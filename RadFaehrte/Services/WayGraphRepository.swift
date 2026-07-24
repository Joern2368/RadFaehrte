//
//  WayGraphRepository.swift
//  RadFaehrte
//

import CoreLocation
import Foundation
import SQLite3

/// Liest den Wege-Graphen eines heruntergeladenen Bundeslands (siehe `Scripts/build_way_graph.py`)
/// für die "ruhige Wege"-Offline-Routing-Engine (`BikeRoutingEngine`). Anders als
/// `RouteRepository` (das pro Bounding-Box gezielt nachfragt, weil nur wenige Routen relevant
/// sind) lädt dieses Repository Knoten und Kanten einmalig komplett in den Speicher - A* besucht
/// beim Suchen potenziell tausende Knoten, wiederholte SQL-Anfragen pro Knoten wären spürbar
/// langsamer als Array-Lookups.
///
/// Speicherformat (siehe `Scripts/build_way_graph.py`): eine einzelne Zeile in `graph` mit zwei
/// Binär-Blobs statt einer Zeile pro Knoten/Kante mit SQL-Indizes - letzteres kostete bei
/// Baden-Württemberg allein ~700 MB von 1,8 GB, obwohl die App nie indiziert abfragt, sondern
/// immer den kompletten Graphen lädt. Knoten werden über dichte 0-basierte Indizes (nicht die
/// langen OSM-IDs) referenziert:
/// - `nodes`-Blob: pro Knoten (in Index-Reihenfolge) `Float32 lat, Float32 lon`
/// - `edges`-Blob: pro Kante `UInt32 fromIndex, UInt32 toIndex, Float32 distanceMeters,
///   Float32 weight, UInt8 offsetSide` (0 = kein Versatz, 1 = rechts, 2 = links, bezogen auf
///   die Richtung fromIndex -> toIndex dieser Kante - siehe `offset_side()` in
///   `Scripts/build_way_graph.py`)
final class WayGraphRepository {
    struct Edge {
        let toNode: Int
        let distanceMeters: Double
        let weight: Double
        /// 0 = kein Versatz, 1 = rechts, 2 = links (siehe `BikeRoutingEngine.offsetPoint`).
        let offsetSide: Int
    }

    private(set) var nodeLocations: [CLLocationCoordinate2D] = []
    private(set) var adjacency: [[Edge]] = []

    init?(path: String) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return nil
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT node_count, edge_count, nodes, edges FROM graph", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW
        else {
            sqlite3_finalize(statement)
            return nil
        }
        defer { sqlite3_finalize(statement) }

        let nodeCount = Int(sqlite3_column_int64(statement, 0))
        let edgeCount = Int(sqlite3_column_int64(statement, 1))

        guard let nodesPointer = sqlite3_column_blob(statement, 2) else { return nil }
        let nodesLength = Int(sqlite3_column_bytes(statement, 2))
        let nodesData = Data(bytes: nodesPointer, count: nodesLength)

        guard let edgesPointer = sqlite3_column_blob(statement, 3) else { return nil }
        let edgesLength = Int(sqlite3_column_bytes(statement, 3))
        let edgesData = Data(bytes: edgesPointer, count: edgesLength)

        nodeLocations.reserveCapacity(nodeCount)
        nodesData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<nodeCount {
                let lat = Double(raw.loadUnaligned(fromByteOffset: i * 8, as: Float32.self))
                let lon = Double(raw.loadUnaligned(fromByteOffset: i * 8 + 4, as: Float32.self))
                nodeLocations.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }

        adjacency = [[Edge]](repeating: [], count: nodeCount)
        edgesData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<edgeCount {
                let offset = i * 17
                let from = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                let to = Int(raw.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))
                let distance = Double(raw.loadUnaligned(fromByteOffset: offset + 8, as: Float32.self))
                let weight = Double(raw.loadUnaligned(fromByteOffset: offset + 12, as: Float32.self))
                let side = Int(raw.loadUnaligned(fromByteOffset: offset + 16, as: UInt8.self))
                guard from < adjacency.count else { continue }
                adjacency[from].append(Edge(toNode: to, distanceMeters: distance, weight: weight, offsetSide: side))
            }
        }
    }

    /// Nächstgelegener Graph-Knoten (als dichter Index, siehe oben) zu einer Koordinate, oder
    /// `nil`, wenn keiner innerhalb von `maxDistanceMeters` liegt (z. B. weil die Koordinate
    /// außerhalb des heruntergeladenen Bundeslands liegt).
    func nearestNode(
        to coordinate: CLLocationCoordinate2D, maxDistanceMeters: Double = 2000
    ) -> Int? {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var bestIndex: Int?
        var bestDistance = maxDistanceMeters
        for (index, location) in nodeLocations.enumerated() {
            let distance = target.distance(
                from: CLLocation(latitude: location.latitude, longitude: location.longitude)
            )
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }
}
