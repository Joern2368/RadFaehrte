//
//  WayGraphRepository.swift
//  RadFaehrte
//

import CoreLocation
import Foundation
import SQLite3

/// Liest den Wege-Graphen eines heruntergeladenen Bundeslands/Landes für die "ruhige Wege"-
/// Offline-Routing-Engine (`BikeRoutingEngine`). Unterstützt zwei Dateiformate, per Magic-Bytes am
/// Dateianfang automatisch erkannt (`init?`):
///
/// **Format v1** (`Scripts/build_way_graph.py`, aktuell alle 16 Bundesländer + Polen): SQLite-Datei
/// mit einer einzelnen Zeile in `graph`, zwei Blobs (`nodes`, `edges`) - siehe Kommentare in
/// `parseLegacy`. Wird komplett gelesen und in eigene Swift-Arrays (`nodeLocations`, CSR-`edges`)
/// umgewandelt (Knoten dichte 0-basierte Indizes statt OSM-IDs).
///
/// **Format v2** (`Scripts/build_way_graph_v2.py`, Pilotversuch Niederlande, 2026-07-27): reine
/// Flachdatei ohne SQLite-Container, Kanten liegen **bereits auf der Platte** nach `fromNode`
/// sortiert vor (CSR-Layout schon beim Bauen in Python hergestellt, nicht erst zur Laufzeit in
/// Swift). Wird per `mmap` geöffnet (`Data(contentsOf:options:.alwaysMapped)`) - `edges(from:)`
/// dekodiert die Kanten eines Knotens dann **on-demand** direkt aus den gemappten Bytes, statt
/// beim Laden den kompletten Graphen in ein eigenes Array zu kopieren. Für eine lokale Route (z. B.
/// eine Stadt) berührt A* nur einen winzigen Bruchteil aller Knoten - Format v2 muss dafür auch nur
/// einen winzigen Bruchteil der Datei tatsächlich lesen/dekodieren, statt beim Laden immer den
/// gesamten Graphen zu verarbeiten. Layout (little-endian):
/// - Header (16 Byte): `"RFG3"` (4 Byte Magic) + `UInt32 nodeCount` + `UInt32 edgeCount` +
///   `UInt32 nameCount`
/// - Nodes-Sektion (`nodeCount * 8` Byte): je `Float32 lat, Float32 lon`
/// - EdgeOffsets-Sektion (`(nodeCount + 1) * 4` Byte): je `UInt32` - direkt aus der Datei gelesen,
///   keine eigene Berechnung mehr nötig (im Gegensatz zu v1)
/// - Edges-Sektion (`edgeCount * 18` Byte), nach `fromNode` sortiert: je `UInt32 toNode,
///   Float32 distanceMeters, Float32 weight, UInt8 offsetSide, UInt32 nameIndex, UInt8 wayCategory`
///   (kein `fromNode`-Feld mehr - die Position im sortierten Array codiert es bereits, 18 statt 21
///   Byte/Kante)
/// - Names-Sektion (`nameCount` Einträge): je `UInt16 byteLength` + UTF-8-Bytes
///
/// Beide Formate teilen sich `nameIndex`/`noNameIndex`/`offsetSide`-Semantik (siehe
/// `offset_side()`/`name_index_for()` in den jeweiligen Python-Skripten).
///
/// ⚠️ **`wayCategory`** (grobe Wegeart wie "Radweg"/"Landstraße"/"Unbefestigter Weg", s.
/// `WayCategory` unten und `way_category()` in `Scripts/build_way_graph.py`) existiert **nur in
/// Format v2** (ab Magic `"RFG3"`) - Format v1 kennt das Feld nicht, dort liefert `Edge.wayCategory`
/// immer `WayCategory.other.rawValue` als neutralen Platzhalter, s. `parseLegacy`. Das alte
/// `"RFG2"`-Layout (ohne dieses Feld, 17 Byte/Kante) wird bewusst nicht mehr unterstützt - beim
/// Formatwechsel wurde `wayGraphFormatVersion` in `WayGraphStore.swift` hochgezählt, wodurch alte
/// lokal heruntergeladene Dateien automatisch verworfen werden.
///
/// ⚠️ **Historie (Format v1)**: Ursprünglich ein `[[Edge]]` pro Knoten (`adjacency`) - führte beim
/// Live-Test mit dem Niederlande-Graphen (9,6 Mio. Knoten) zu einem Speicher-Kill durch iOS
/// (`App terminated due to signal 9`) durch den Buffer-Overhead von Millionen einzelner
/// Array-Allokationen. Auf ein flaches, nach `fromNode` gruppiertes `edges`-Array plus
/// `edgeOffsets` (CSR) umgestellt, `Edge`-Felder auf Disk-Format-Größe verkleinert
/// (`Int32`/`Float`/`UInt8`/`UInt32` statt `Int`/`Double`) - ca. 60 % weniger Speicher. Format v2
/// geht darüber hinaus: Es baut für große Länder gar nicht erst ein komplettes `edges`-Array auf.
nonisolated final class WayGraphRepository {
    /// Sentinel für "kein `name`-Tag".
    static let noNameIndex: UInt32 = .max

    private static let v2Magic = Data("RFG3".utf8)
    private static let v1EdgeRecordSize = 21
    private static let v2EdgeRecordSize = 18
    private static let v2HeaderSize = 16

    /// Grobe Wegeart-Kategorie einer Kante für die Nutzer-Anzeige ("X km Landstraße" usw.), s.
    /// `way_category()`/`WAY_CATEGORY_*` in `Scripts/build_way_graph.py` (Rohwert dort und hier
    /// muss übereinstimmen). Nur in Format v2 vorhanden, s. Typ-Dokumentation.
    enum WayCategory: UInt8 {
        case cycleway = 0
        case quietRoad = 1
        case mainRoad = 2
        case unpaved = 3
        case other = 4
        /// Radweg, der laut `MainRoadIndex`/`NEARBY_MAIN_ROAD_METERS` in `build_way_graph.py`
        /// innerhalb von ~15 m einer Landstraßen-Kante liegt - Nutzer-Wunsch 2026-08-17, um einen
        /// straßenbegleitenden Radweg von einem freistehenden (`cycleway`, Nebenstraße/freies
        /// Feld) zu unterscheiden. Reine Content-Änderung, kein Format-Bruch (weiterhin `UInt8`) -
        /// deshalb kein `wayGraphFormatVersion`-Bump nötig, nur ein Neu-Bau der Regionsdateien.
        case cyclewayNearMainRoad = 5

        var displayName: String {
            switch self {
            case .cycleway: return "Radweg"
            case .quietRoad: return "Ruhige Straße"
            case .mainRoad: return "Landstraße"
            case .unpaved: return "Unbefestigter Weg"
            case .other: return "Sonstiger Weg"
            case .cyclewayNearMainRoad: return "Radweg an Landstraße"
            }
        }
    }

    struct Edge {
        /// Dichter 0-basierter Knoten-Index, `Int32` statt `Int` - spart bei Millionen Kanten
        /// spürbar Speicher, Graphen mit >2,1 Mrd. Knoten sind ohnehin unrealistisch.
        let toNode: Int32
        let distanceMeters: Float
        let weight: Float
        /// 0 = kein Versatz, 1 = rechts, 2 = links (siehe `BikeRoutingEngine.offsetPoint`).
        let offsetSide: UInt8
        /// Index in `wayNames`, oder `noNameIndex` für unbenannte Wege.
        let nameIndex: UInt32
        /// Rohwert von `WayCategory` - `WayCategory.other.rawValue` (neutraler Platzhalter) bei
        /// Format v1, das dieses Feld nicht kennt (s. Typ-Dokumentation).
        let wayCategoryRaw: UInt8

        var wayCategory: WayCategory {
            WayCategory(rawValue: wayCategoryRaw) ?? .other
        }
    }

    private(set) var nodeLocations: [CLLocationCoordinate2D] = []
    /// Startindex pro Knoten in die Kanten (Länge `nodeLocations.count + 1`,
    /// `edgeOffsets[i]..<edgeOffsets[i+1]` sind die Kanten von Knoten `i`). Bei v1 selbst
    /// berechnet, bei v2 direkt aus der Datei gelesen. Siehe `edges(from:)`.
    private var edgeOffsets: [Int32] = []
    /// **Format v1 only**: alle Kanten flach in einem eigenen Array (CSR-Layout, s.
    /// Typ-Dokumentation) - bei v2 stattdessen `mappedFile`/`edgesSectionByteOffset`, keine
    /// eigene Kopie im Speicher.
    private var eagerEdges: [Edge] = []
    /// **Format v2 only**: die per `mmap` geöffnete Datei, bleibt für die Lebensdauer dieser
    /// Instanz bestehen - `edges(from:)` dekodiert direkt daraus statt aus einem eigenen Array.
    private var mappedFile: Data?
    private var v2EdgesSectionByteOffset = 0
    /// Straßennamen in Index-Reihenfolge - siehe `Edge.nameIndex`/`wayName(forIndex:)`.
    private(set) var wayNames: [String] = []

    /// Grobes Raster über `nodeLocations` (Zellgröße `gridCellSizeDegrees`, ~1,1 km), einmalig beim
    /// Laden aufgebaut - beschleunigt `nearestNode` von einem linearen Scan über alle Knoten (bei
    /// großen Bundesländern/Ländern mehrere Millionen) auf eine Suche in den wenigen Zellen rund um
    /// die Zielkoordinate. Für eine einzelne Route (2 Aufrufe) kaum spürbar, aber
    /// `CrossRegionRouteStitcher` ruft `nearestNode` beim Abtasten der Luftlinie über hundert Mal
    /// auf - ohne Raster live auf dem Gerät als Hänger von >40 s beobachtet (Nutzer-Fund,
    /// 2026-07-31), da jeder Aufruf für sich den kompletten Knoten-Array linear durchsuchte.
    private struct GridKey: Hashable {
        let lat: Int32
        let lon: Int32
    }
    private static let gridCellSizeDegrees = 0.01
    private var spatialGrid: [GridKey: [Int32]] = [:]

    init?(path: String) {
        guard let fileHandle = FileHandle(forReadingAtPath: path) else { return nil }
        let magic = fileHandle.readData(ofLength: 4)
        fileHandle.closeFile()

        if magic == Self.v2Magic {
            guard parseV2(path: path) else { return nil }
        } else {
            guard parseLegacy(path: path) else { return nil }
        }
        buildSpatialGrid()
    }

    private static func gridCell(for coordinate: CLLocationCoordinate2D) -> GridKey {
        GridKey(
            lat: Int32(floor(coordinate.latitude / gridCellSizeDegrees)),
            lon: Int32(floor(coordinate.longitude / gridCellSizeDegrees))
        )
    }

    private func buildSpatialGrid() {
        spatialGrid.reserveCapacity(nodeLocations.count / 4)
        for (index, location) in nodeLocations.enumerated() {
            spatialGrid[Self.gridCell(for: location), default: []].append(Int32(index))
        }
    }

    /// Format v2: Datei per `mmap` öffnen, Header + `nodeLocations` + `edgeOffsets` eagerly lesen
    /// (zusammen klein, z. B. bei den Niederlanden ~190 MB von 380 MB Gesamtgröße), die Kanten
    /// selbst aber **nicht** - die bleiben in `mappedFile` und werden erst in `edges(from:)`
    /// on-demand dekodiert (s. Typ-Dokumentation).
    private func parseV2(path: String) -> Bool {
        guard let data = try? Data(
            contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped
        ) else { return false }
        guard data.count >= Self.v2HeaderSize else { return false }

        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            let nodeCount = Int(raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
            let edgeCount = Int(raw.loadUnaligned(fromByteOffset: 8, as: UInt32.self))
            let nameCount = Int(raw.loadUnaligned(fromByteOffset: 12, as: UInt32.self))

            let nodesSectionOffset = Self.v2HeaderSize
            let edgeOffsetsSectionOffset = nodesSectionOffset + nodeCount * 8
            let edgesSectionOffset = edgeOffsetsSectionOffset + (nodeCount + 1) * 4
            let namesSectionOffset = edgesSectionOffset + edgeCount * Self.v2EdgeRecordSize
            guard namesSectionOffset <= raw.count else { return false }

            nodeLocations.reserveCapacity(nodeCount)
            for i in 0..<nodeCount {
                let offset = nodesSectionOffset + i * 8
                let lat = Double(raw.loadUnaligned(fromByteOffset: offset, as: Float32.self))
                let lon = Double(raw.loadUnaligned(fromByteOffset: offset + 4, as: Float32.self))
                nodeLocations.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }

            edgeOffsets = [Int32](repeating: 0, count: nodeCount + 1)
            for i in 0..<(nodeCount + 1) {
                edgeOffsets[i] = Int32(bitPattern: raw.loadUnaligned(
                    fromByteOffset: edgeOffsetsSectionOffset + i * 4, as: UInt32.self
                ))
            }

            v2EdgesSectionByteOffset = edgesSectionOffset
            mappedFile = data

            wayNames.reserveCapacity(nameCount)
            var offset = namesSectionOffset
            for _ in 0..<nameCount {
                guard offset + 2 <= raw.count else { break }
                let length = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                offset += 2
                guard offset + length <= raw.count else { break }
                let bytes = Data(bytes: raw.baseAddress!.advanced(by: offset), count: length)
                wayNames.append(String(decoding: bytes, as: UTF8.self))
                offset += length
            }
            return true
        }
    }

    /// Format v1: siehe Scripts/build_way_graph.py und die ausführliche Historie in der
    /// Typ-Dokumentation (CSR-Aufbau zur Laufzeit, da auf der Platte unsortiert vorliegend).
    private func parseLegacy(path: String) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return false
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            db, "SELECT node_count, edge_count, nodes, edges, name_count, names FROM graph", -1, &statement, nil
        ) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW
        else {
            sqlite3_finalize(statement)
            return false
        }
        defer { sqlite3_finalize(statement) }

        let nodeCount = Int(sqlite3_column_int64(statement, 0))
        let edgeCount = Int(sqlite3_column_int64(statement, 1))
        let nameCount = Int(sqlite3_column_int64(statement, 4))

        // Direkt mit dem von SQLite gelieferten Rohzeiger arbeiten statt ihn erst in ein eigenes
        // `Data` zu kopieren (der Zeiger bleibt gültig, solange `statement` lebt, also für den
        // kompletten restlichen Aufruf, da `sqlite3_finalize` erst am Ende via `defer` läuft).
        guard let nodesPointer = sqlite3_column_blob(statement, 2) else { return false }
        let nodesBuffer = UnsafeRawBufferPointer(start: nodesPointer, count: Int(sqlite3_column_bytes(statement, 2)))

        guard let edgesPointer = sqlite3_column_blob(statement, 3) else { return false }
        let edgesBuffer = UnsafeRawBufferPointer(start: edgesPointer, count: Int(sqlite3_column_bytes(statement, 3)))

        // Leere Namenstabelle (nameCount == 0) ist gültig - `sqlite3_column_blob` liefert für ein
        // leeres BLOB `nil` zurück, das darf hier also nicht als Fehler gewertet werden.
        let namesBuffer: UnsafeRawBufferPointer
        if let namesPointer = sqlite3_column_blob(statement, 5) {
            namesBuffer = UnsafeRawBufferPointer(start: namesPointer, count: Int(sqlite3_column_bytes(statement, 5)))
        } else {
            namesBuffer = UnsafeRawBufferPointer(start: nil, count: 0)
        }

        nodeLocations.reserveCapacity(nodeCount)
        for i in 0..<nodeCount {
            let lat = Double(nodesBuffer.loadUnaligned(fromByteOffset: i * 8, as: Float32.self))
            let lon = Double(nodesBuffer.loadUnaligned(fromByteOffset: i * 8 + 4, as: Float32.self))
            nodeLocations.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        // CSR-Aufbau in zwei Durchläufen: erst pro Knoten die Anzahl ausgehender Kanten zählen
        // (Präfixsumme für `edgeOffsets`), danach die Kanten an ihre endgültige Position im
        // flachen `eagerEdges`-Array schreiben (`writeCursor` verfolgt pro Knoten, wie viele
        // seiner Kanten schon platziert wurden).
        var outDegree = [Int32](repeating: 0, count: nodeCount)
        for i in 0..<edgeCount {
            let from = Int(edgesBuffer.loadUnaligned(fromByteOffset: i * Self.v1EdgeRecordSize, as: UInt32.self))
            guard from < nodeCount else { continue }
            outDegree[from] += 1
        }

        edgeOffsets = [Int32](repeating: 0, count: nodeCount + 1)
        for i in 0..<nodeCount {
            edgeOffsets[i + 1] = edgeOffsets[i] + outDegree[i]
        }

        let placeholder = Edge(
            toNode: 0, distanceMeters: 0, weight: 0, offsetSide: 0, nameIndex: Self.noNameIndex,
            wayCategoryRaw: WayCategory.other.rawValue
        )
        eagerEdges = [Edge](repeating: placeholder, count: edgeCount)
        var writeCursor = edgeOffsets
        for i in 0..<edgeCount {
            let offset = i * Self.v1EdgeRecordSize
            let from = Int(edgesBuffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            guard from < nodeCount else { continue }
            let to = edgesBuffer.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self)
            let distance = edgesBuffer.loadUnaligned(fromByteOffset: offset + 8, as: Float32.self)
            let weight = edgesBuffer.loadUnaligned(fromByteOffset: offset + 12, as: Float32.self)
            let side = edgesBuffer.loadUnaligned(fromByteOffset: offset + 16, as: UInt8.self)
            let nameIndex = edgesBuffer.loadUnaligned(fromByteOffset: offset + 17, as: UInt32.self)

            let position = Int(writeCursor[from])
            eagerEdges[position] = Edge(
                toNode: Int32(bitPattern: to), distanceMeters: distance, weight: weight,
                offsetSide: side, nameIndex: nameIndex, wayCategoryRaw: WayCategory.other.rawValue
            )
            writeCursor[from] += 1
        }

        wayNames.reserveCapacity(nameCount)
        var offset = 0
        for _ in 0..<nameCount {
            guard offset + 2 <= namesBuffer.count else { break }
            let length = Int(namesBuffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
            offset += 2
            guard offset + length <= namesBuffer.count else { break }
            let bytes = Data(bytes: namesBuffer.baseAddress!.advanced(by: offset), count: length)
            wayNames.append(String(decoding: bytes, as: UTF8.self))
            offset += length
        }
        return true
    }

    /// Straßenname für `Edge.nameIndex`, oder `nil` für unbenannte Wege/ungültigen Index.
    func wayName(forIndex index: UInt32) -> String? {
        guard index != Self.noNameIndex, wayNames.indices.contains(Int(index)) else { return nil }
        return wayNames[Int(index)]
    }

    /// Alle ausgehenden Kanten eines Knotens. Bei Format v1 ein Ausschnitt aus dem bereits
    /// vollständig geladenen `eagerEdges`-Array; bei Format v2 werden die (typischerweise nur
    /// eine Handvoll) Kanten dieses einen Knotens gerade erst jetzt aus der gemappten Datei
    /// dekodiert (s. Typ-Dokumentation) - für eine A*-Suche über wenige tausend besuchte Knoten
    /// insgesamt eine sehr kleine, günstige Zusatzarbeit pro Aufruf.
    func edges(from node: Int) -> [Edge] {
        guard node >= 0, node + 1 < edgeOffsets.count else { return [] }
        let start = Int(edgeOffsets[node])
        let end = Int(edgeOffsets[node + 1])
        guard end > start else { return [] }

        if let mappedFile {
            var result: [Edge] = []
            result.reserveCapacity(end - start)
            mappedFile.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                for i in start..<end {
                    let offset = v2EdgesSectionByteOffset + i * Self.v2EdgeRecordSize
                    let to = raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
                    let distance = raw.loadUnaligned(fromByteOffset: offset + 4, as: Float32.self)
                    let weight = raw.loadUnaligned(fromByteOffset: offset + 8, as: Float32.self)
                    let side = raw.loadUnaligned(fromByteOffset: offset + 12, as: UInt8.self)
                    let nameIndex = raw.loadUnaligned(fromByteOffset: offset + 13, as: UInt32.self)
                    let category = raw.loadUnaligned(fromByteOffset: offset + 17, as: UInt8.self)
                    result.append(Edge(
                        toNode: Int32(bitPattern: to), distanceMeters: distance, weight: weight,
                        offsetSide: side, nameIndex: nameIndex, wayCategoryRaw: category
                    ))
                }
            }
            return result
        }

        return Array(eagerEdges[start..<end])
    }

    /// Nächstgelegener Graph-Knoten (als dichter Index, siehe oben) zu einer Koordinate, oder
    /// `nil`, wenn keiner innerhalb von `maxDistanceMeters` liegt. Kurzform von
    /// `nearestNodes(to:maxDistanceMeters:limit:1)` für die (deutlich häufigeren) Aufrufer, die nur
    /// den einen nächsten Knoten brauchen (z. B. `CrossRegionRouteStitcher`s
    /// Luftlinien-Abtastung).
    func nearestNode(
        to coordinate: CLLocationCoordinate2D, maxDistanceMeters: Double = 2000
    ) -> Int? {
        nearestNodes(to: coordinate, maxDistanceMeters: maxDistanceMeters, limit: 1).first
    }

    /// Die bis zu `limit` nächstgelegenen Graph-Knoten zu einer Koordinate, aufsteigend nach
    /// Distanz sortiert (leeres Array, wenn keiner innerhalb von `maxDistanceMeters` liegt).
    /// Rechnet lokal in einer ebenen Näherung um `coordinate` (analog `RouteMatcher.nearestPoint`)
    /// statt mit `CLLocation.distance(from:)`. Durchsucht dank `spatialGrid` nur die Zellen, die
    /// `maxDistanceMeters` überhaupt abdecken können, statt aller Knoten - vergleicht außerdem nur
    /// quadrierte Distanzen (kein `sqrt` pro Knoten nötig, da nur die Reihenfolge zählt).
    ///
    /// `limit > 1` existiert für `BikeRoutingEngine.routes(from:to:)`: reale Wege-Graphen enthalten
    /// durch echte OSM-Lücken (Sackgassen, private Zufahrten, Inseln) immer einen kleinen Anteil
    /// Knoten, die zwar existieren, aber vom übrigen, großen Netz abgeschnitten sind (Live-Fund
    /// 2026-08-02/06, Cuxhaven in Niedersachsen und Stuttgart in Baden-Württemberg - beide Male kein
    /// Bug in der Wege-Graph-Erstellung selbst, sondern eine per BFS bestätigte, winzige echte
    /// Graph-Insel um genau den nächstgelegenen Knoten). Snappt die einfache `nearestNode`-Variante
    /// zufällig auf so einen Insel-Knoten, scheitert die A*-Suche fast sofort und die App fällt
    /// still auf Online-Routing zurück, obwohl der nur wenige Meter entfernte, tatsächlich verbundene
    /// Knoten problemlos gereicht hätte.
    func nearestNodes(
        to coordinate: CLLocationCoordinate2D, maxDistanceMeters: Double = 2000, limit: Int = 1
    ) -> [Int] {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = metersPerDegreeLat * max(cos(coordinate.latitude * .pi / 180), 0.1)

        let latCellMeters = Self.gridCellSizeDegrees * metersPerDegreeLat
        let lonCellMeters = Self.gridCellSizeDegrees * metersPerDegreeLon
        let latRadius = Int32(ceil(maxDistanceMeters / latCellMeters)) + 1
        let lonRadius = Int32(ceil(maxDistanceMeters / lonCellMeters)) + 1

        let center = Self.gridCell(for: coordinate)
        let maxDistanceSquared = maxDistanceMeters * maxDistanceMeters
        // Kleine, nach Distanz sortierte Kandidatenliste (Länge <= `limit`) statt eines echten
        // Sortier-Schritts am Ende - bei den hier verwendeten `limit`-Größen (einstellig) schneller
        // und einfacher als jeden Kandidaten erst zu sammeln und dann zu sortieren.
        var best: [(index: Int, distanceSquared: Double)] = []

        for latOffset in -latRadius...latRadius {
            for lonOffset in -lonRadius...lonRadius {
                let key = GridKey(lat: center.lat + latOffset, lon: center.lon + lonOffset)
                guard let candidates = spatialGrid[key] else { continue }
                for candidate in candidates {
                    let location = nodeLocations[Int(candidate)]
                    let dy = (location.latitude - coordinate.latitude) * metersPerDegreeLat
                    let dx = (location.longitude - coordinate.longitude) * metersPerDegreeLon
                    let distanceSquared = dx * dx + dy * dy
                    guard distanceSquared < maxDistanceSquared else { continue }
                    guard best.count < limit || distanceSquared < best[best.count - 1].distanceSquared
                    else { continue }
                    let insertAt = best.firstIndex { distanceSquared < $0.distanceSquared } ?? best.count
                    best.insert((Int(candidate), distanceSquared), at: insertAt)
                    if best.count > limit { best.removeLast() }
                }
            }
        }
        return best.map(\.index)
    }
}
