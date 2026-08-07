//
//  RouteRepository.swift
//  RadFaehrte
//

import CoreLocation
import Foundation
import SQLite3

/// Liest die im App-Bundle mitgelieferten Radrouten-Datenbanken (read-only). Deutschland
/// (`routes.sqlite`) ist Pflicht, weitere Länder (z. B. `netherlands.sqlite`) werden nur
/// eingebunden, wenn die jeweilige Datei tatsächlich im Bundle liegt - alle Datenbanken teilen
/// sich dasselbe Schema, Ergebnisse werden einfach zusammengeführt. OSM-Relations-IDs sind zwar
/// planetweit eindeutig, grenzüberschreitende Relations tauchen aber in den Geofabrik-Extrakten
/// mehrerer Länder auf (mit dort jeweils unterschiedlich zugeschnittener Geometrie) - `id` ist
/// daher über die vier Datenbanken hinweg **nicht** kollisionsfrei. `routesOverlapping(...)`
/// dedupliziert deshalb per ID, erster Treffer gewinnt (dieselbe Reihenfolge/Priorität wie
/// `route(withId:)`).
nonisolated final class RouteRepository {

    private static let bundledResourceNames = ["routes", "netherlands", "poland", "sweden", "denmark", "belgium", "luxembourg", "switzerland", "france", "austria", "czechia", "slovakia", "albania", "italy", "spain", "portugal", "malta", "andorra", "liechtenstein", "macedonia", "kosovo", "montenegro", "bosnia-herzegovina", "serbia", "croatia", "slovenia", "bulgaria", "hungary", "romania", "greece"]

    private var databases: [OpaquePointer] = []

    /// Schützt alle SQLite-Zugriffe unten vor gleichzeitiger Nutzung durch mehrere Threads.
    /// Live-Crash gefunden (2026-08-03): `ContentView` startet die Kombinationssuche über
    /// `Task.detached` (mehrfach überlappend möglich, da eine zuvor als veraltet erkannte Suche
    /// erst nach ihrem synchronen SQLite-Teil auf `Task.isCancelled` prüft) - zwei Threads, die
    /// gleichzeitig dieselbe `OpaquePointer`-Verbindung verwenden, führten zu einem
    /// `EXC_BAD_ACCESS` mitten in `libsqlite3.dylib`. Ein einfaches `NSLock` um jede öffentliche
    /// Methode serialisiert den Zugriff, unabhängig davon, in welchem SQLite-Threading-Modus die
    /// Systembibliothek tatsächlich läuft.
    private let lock = NSLock()

    /// Separate, optionale Sidecar-DB mit Anschlussstellen zwischen benannten Fernwegen
    /// (`Scripts/find_route_junctions.py`), fürs Kombinieren mehrerer Routen. Anderes Schema als
    /// `routes.sqlite`, deshalb kein Teil von `databases`. Fehlt die Datei (z. B. bevor sie im
    /// Zuge dieser Umsetzung ins Bundle aufgenommen wurde), bewusst kein `assertionFailure` -
    /// anders als `routes.sqlite` ist sie nicht zwingend für die Grundfunktion der App.
    private var junctionsDatabase: OpaquePointer?

    init() {
        for name in Self.bundledResourceNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "sqlite") else {
                if name == "routes" {
                    assertionFailure("routes.sqlite fehlt im App-Bundle")
                }
                continue
            }
            var handle: OpaquePointer?
            guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
                  let handle else {
                assertionFailure("Konnte \(name).sqlite nicht öffnen: \(String(cString: sqlite3_errmsg(handle)))")
                continue
            }
            databases.append(handle)
        }

        if let url = Bundle.main.url(forResource: "route_junctions", withExtension: "sqlite") {
            var handle: OpaquePointer?
            if sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
                junctionsDatabase = handle
            }
        }
    }

    deinit {
        for db in databases {
            sqlite3_close(db)
        }
        if let junctionsDatabase {
            sqlite3_close(junctionsDatabase)
        }
    }

    /// Alle Routen, deren Bounding Box das übergebene Rechteck überschneidet.
    func routesOverlapping(
        minLon: Double, minLat: Double, maxLon: Double, maxLat: Double
    ) -> [BikeRoute] {
        lock.lock()
        defer { lock.unlock() }
        var seenIds: Set<Int64> = []
        var results: [BikeRoute] = []
        for db in databases {
            for route in routesOverlapping(in: db, minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat) {
                if seenIds.insert(route.id).inserted {
                    results.append(route)
                }
            }
        }
        return results
    }

    private func routesOverlapping(
        in db: OpaquePointer, minLon: Double, minLat: Double, maxLon: Double, maxLat: Double
    ) -> [BikeRoute] {
        let sql = """
            SELECT id, name, network, ref, distance_km, operator, geometry
            FROM routes
            WHERE min_lon <= ? AND max_lon >= ? AND min_lat <= ? AND max_lat >= ?
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            assertionFailure("SQL prepare fehlgeschlagen: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }

        sqlite3_bind_double(statement, 1, maxLon)
        sqlite3_bind_double(statement, 2, minLon)
        sqlite3_bind_double(statement, 3, maxLat)
        sqlite3_bind_double(statement, 4, minLat)

        var results: [BikeRoute] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let route = decodeRoute(from: statement) {
                results.append(route)
            }
        }
        return results
    }

    /// Route-Zusammenfassungen (ohne Geometrie) für alle Routen, deren Bounding Box das
    /// übergebene Rechteck überschneidet - für die "Alle Routen"-Übersicht, die pro Region
    /// potenziell hunderte Treffer auflisten muss und dafür nicht wie `routesOverlapping` jedes
    /// Mal die volle (u. U. tausende Punkte lange) Geometrie dekodieren soll. `limit` begrenzt
    /// sowohl das Gesamtergebnis als auch jede einzelne Datenbankabfrage.
    ///
    /// Beide Query-Varianten filtern Namen im Muster `"<Zahl>-<Zahl>"` (z. B. "43-94") heraus -
    /// das sind keine echten Radrouten, sondern einzelne Segmente des Knotenpunkt-Wegenetzes
    /// (jede Verbindung zwischen zwei nummerierten Knoten ist in OSM eine eigene `name`/`ref`-
    /// gleiche Relation, network=rcn). Live-Test bestätigt (Nutzer, 2026-08-01, Umkreis Bremen):
    /// ohne Filter 134 von 205 Treffern solche Segmente, die durch alphabetisches Sortieren
    /// (Zahlen vor Buchstaben) außerdem die komplette sichtbare Liste vor den echten Routen
    /// füllten.
    func routeSummaries(
        minLon: Double, minLat: Double, maxLon: Double, maxLat: Double, limit: Int
    ) -> [RouteSummary] {
        lock.lock()
        defer { lock.unlock() }
        var seenIds: Set<Int64> = []
        var results: [RouteSummary] = []
        for db in databases {
            for summary in routeSummaries(in: db, minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat, limit: limit) {
                if seenIds.insert(summary.id).inserted {
                    results.append(summary)
                    if results.count >= limit { return results }
                }
            }
        }
        return results
    }

    private func routeSummaries(
        in db: OpaquePointer, minLon: Double, minLat: Double, maxLon: Double, maxLat: Double, limit: Int
    ) -> [RouteSummary] {
        let sql = """
            SELECT id, name, network, ref, distance_km, operator
            FROM routes
            WHERE name IS NOT NULL AND name != '' AND name NOT GLOB '[0-9]*-[0-9]*'
                AND min_lon <= ? AND max_lon >= ? AND min_lat <= ? AND max_lat >= ?
            LIMIT ?
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            assertionFailure("SQL prepare fehlgeschlagen: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }

        sqlite3_bind_double(statement, 1, maxLon)
        sqlite3_bind_double(statement, 2, minLon)
        sqlite3_bind_double(statement, 3, maxLat)
        sqlite3_bind_double(statement, 4, minLat)
        sqlite3_bind_int(statement, 5, Int32(limit))

        var results: [RouteSummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let summary = decodeSummary(from: statement) {
                results.append(summary)
            }
        }
        return results
    }

    /// Route-Zusammenfassungen (ohne Geometrie) aller Routen, deren Name den Suchtext enthält
    /// (case-insensitiv). Es gibt keinen Index auf `name`, ein voller Tabellenscan über die
    /// ~50.000 Zeilen ist für eine gedebouncte Texteingabe (kein Query pro Tastendruck) aber
    /// unproblematisch; `limit` deckelt zusätzlich die Laufzeit.
    func routeSummaries(matchingName query: String, limit: Int) -> [RouteSummary] {
        lock.lock()
        defer { lock.unlock() }
        var seenIds: Set<Int64> = []
        var results: [RouteSummary] = []
        for db in databases {
            for summary in routeSummaries(in: db, matchingName: query, limit: limit) {
                if seenIds.insert(summary.id).inserted {
                    results.append(summary)
                    if results.count >= limit { return results }
                }
            }
        }
        return results
    }

    private func routeSummaries(in db: OpaquePointer, matchingName query: String, limit: Int) -> [RouteSummary] {
        let sql = """
            SELECT id, name, network, ref, distance_km, operator
            FROM routes
            WHERE name LIKE ? COLLATE NOCASE AND name NOT GLOB '[0-9]*-[0-9]*'
            LIMIT ?
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            assertionFailure("SQL prepare fehlgeschlagen: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }

        sqlite3_bind_text(statement, 1, "%\(query)%", -1, Self.sqliteTransient)
        sqlite3_bind_int(statement, 2, Int32(limit))

        var results: [RouteSummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let summary = decodeSummary(from: statement) {
                results.append(summary)
            }
        }
        return results
    }

    /// Dekodiert eine Ergebniszeile im Schema `id, name, network, ref, distance_km, operator`
    /// (ohne Geometrie-Spalte, anders als `decodeRoute(from:)`) zu einer `RouteSummary`. `nil`
    /// nur bei fehlendem Namen (sollte durch die `WHERE`-Klauseln oben nie vorkommen).
    private func decodeSummary(from statement: OpaquePointer?) -> RouteSummary? {
        guard let name = textColumn(statement, 1) else { return nil }
        let id = sqlite3_column_int64(statement, 0)
        let network = textColumn(statement, 2)
        let ref = textColumn(statement, 3)
        let distanceKm: Double? = sqlite3_column_type(statement, 4) == SQLITE_NULL
            ? nil : sqlite3_column_double(statement, 4)
        let operatorName = textColumn(statement, 5)

        return RouteSummary(
            id: id,
            name: name,
            network: network,
            ref: ref,
            distanceKm: distanceKm,
            operatorName: operatorName
        )
    }

    /// Konstante für `sqlite3_bind_text`, die SQLite anweist, den String selbst zu kopieren
    /// (statt eines Zeigers, der schon ungültig sein könnte, bis die Query läuft) - Standard-
    /// Idiom für den C-SQLite-Wrapper in Swift, da `SQLITE_TRANSIENT` als Makro nicht importiert
    /// wird.
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Eine einzelne Route anhand ihrer OSM-Relations-ID (z. B. für die Kombinationssuche, die
    /// per Junction-Tabelle nur IDs kennt und die volle Geometrie nachladen muss). Fragt die
    /// Datenbanken der Reihe nach ab, bis eine einen Treffer liefert. Bei einer ID-Kollision über
    /// mehrere Datenbanken hinweg (s. Klassen-Header) also bewusst "erster Treffer gewinnt" -
    /// für Aufrufer, die selbst anhand eines geografischen Kontexts die passende Kopie auswählen
    /// müssen, stattdessen `allRoutes(withId:)` verwenden (s. `RouteMatcher.findCombinedMatches`).
    func route(withId id: Int64) -> BikeRoute? {
        lock.lock()
        defer { lock.unlock() }
        for db in databases {
            if let route = route(withId: id, in: db) {
                return route
            }
        }
        return nil
    }

    /// Alle Kopien einer Route über alle vier Datenbanken hinweg - im Regelfall nur eine, bei
    /// einer ID-Kollision an einer Ländergrenze (s. Klassen-Header) aber mehrere mit
    /// unterschiedlicher Geometrie. Für Aufrufer, die (anders als `route(withId:)`s blindes
    /// "erster Treffer gewinnt") selbst die geografisch passende Kopie auswählen müssen - z. B.
    /// die Kombinationssuche, die dieselbe ID aus unterschiedlichen Richtungen/Ländern erreichen
    /// kann und je nach Einstiegspunkt eine andere Kopie braucht.
    func allRoutes(withId id: Int64) -> [BikeRoute] {
        lock.lock()
        defer { lock.unlock() }
        return databases.compactMap { route(withId: id, in: $0) }
    }

    private func route(withId id: Int64, in db: OpaquePointer) -> BikeRoute? {
        let sql = """
            SELECT id, name, network, ref, distance_km, operator, geometry
            FROM routes
            WHERE id = ?
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            assertionFailure("SQL prepare fehlgeschlagen: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }

        sqlite3_bind_int64(statement, 1, id)

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return decodeRoute(from: statement)
    }

    /// Nur das `ref`-Tag einer Route (z. B. "EV2", "D3") anhand ihrer ID, ohne die Geometrie zu
    /// dekodieren - für die Kombinationssuche, die beim Erweitern der Warteschlange (potenziell
    /// viele Nachbar-Kandidaten pro besuchter Route) nur wissen muss, ob zwei Routen zum selben
    /// Fernweg gehören, aber nicht sofort deren volle (u. U. tausende Punkte lange) Geometrie
    /// braucht - die wird ohnehin erst bei tatsächlichem Besuch über `route(withId:)` geladen und
    /// gecacht. `nil`, wenn die ID in keiner Datenbank existiert oder kein `ref`-Tag gesetzt ist.
    func ref(forRouteId id: Int64) -> String? {
        lock.lock()
        defer { lock.unlock() }
        for db in databases {
            let sql = "SELECT ref FROM routes WHERE id = ?"
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                assertionFailure("SQL prepare fehlgeschlagen: \(String(cString: sqlite3_errmsg(db)))")
                continue
            }
            sqlite3_bind_int64(statement, 1, id)
            guard sqlite3_step(statement) == SQLITE_ROW else { continue }
            return textColumn(statement, 0)
        }
        return nil
    }

    /// Alle Anschlussstellen einer Route zu anderen benannten Fernwegen (aus der per
    /// `Scripts/find_route_junctions.py` vorab berechneten Sidecar-DB). Leeres Array, wenn die
    /// Sidecar-Datei fehlt oder die Route keine Anschlüsse hat - kein Crash in beiden Fällen.
    func junctions(forRouteId id: Int64) -> [(partnerRouteId: Int64, coordinate: CLLocationCoordinate2D)] {
        lock.lock()
        defer { lock.unlock() }
        guard let junctionsDatabase else { return [] }

        let sql = "SELECT route_b, lon, lat FROM junctions WHERE route_a = ?"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(junctionsDatabase, sql, -1, &statement, nil) == SQLITE_OK else {
            assertionFailure("SQL prepare fehlgeschlagen: \(String(cString: sqlite3_errmsg(junctionsDatabase)))")
            return []
        }

        sqlite3_bind_int64(statement, 1, id)

        var results: [(partnerRouteId: Int64, coordinate: CLLocationCoordinate2D)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let partnerRouteId = sqlite3_column_int64(statement, 0)
            let lon = sqlite3_column_double(statement, 1)
            let lat = sqlite3_column_double(statement, 2)
            results.append((partnerRouteId, CLLocationCoordinate2D(latitude: lat, longitude: lon)))
        }
        return results
    }

    /// Dekodiert eine Ergebniszeile im Schema `id, name, network, ref, distance_km, operator,
    /// geometry` (Spaltenreihenfolge/-indizes wie in den `SELECT`s oben) zu einer `BikeRoute`.
    private func decodeRoute(from statement: OpaquePointer?) -> BikeRoute? {
        let id = sqlite3_column_int64(statement, 0)
        let name = textColumn(statement, 1)
        let network = textColumn(statement, 2)
        let ref = textColumn(statement, 3)
        let distanceKm: Double? = sqlite3_column_type(statement, 4) == SQLITE_NULL
            ? nil : sqlite3_column_double(statement, 4)
        let operatorName = textColumn(statement, 5)

        guard let blobPointer = sqlite3_column_blob(statement, 6) else { return nil }
        let blobLength = Int(sqlite3_column_bytes(statement, 6))
        let data = Data(bytes: blobPointer, count: blobLength)
        let lines = Self.decodeGeometry(data)

        return BikeRoute(
            id: id,
            name: name,
            network: network,
            ref: ref,
            distanceKm: distanceKm,
            operatorName: operatorName,
            lines: lines
        )
    }

    private func textColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    /// Dekodiert das Binärformat: UInt32 numLines, je Line UInt32 numPoints
    /// gefolgt von numPoints * (Float32 lon, Float32 lat), little-endian.
    private static func decodeGeometry(_ data: Data) -> [[CLLocationCoordinate2D]] {
        var offset = 0

        func readUInt32() -> UInt32 {
            let value = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes {
                $0.loadUnaligned(as: UInt32.self)
            }
            offset += 4
            return UInt32(littleEndian: value)
        }

        func readFloat32() -> Float {
            let bits = readUInt32()
            return Float(bitPattern: bits)
        }

        let numLines = readUInt32()
        var lines: [[CLLocationCoordinate2D]] = []
        lines.reserveCapacity(Int(numLines))

        for _ in 0..<numLines {
            let numPoints = readUInt32()
            var coordinates: [CLLocationCoordinate2D] = []
            coordinates.reserveCapacity(Int(numPoints))
            for _ in 0..<numPoints {
                let lon = Double(readFloat32())
                let lat = Double(readFloat32())
                coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
            lines.append(coordinates)
        }
        return lines
    }
}
