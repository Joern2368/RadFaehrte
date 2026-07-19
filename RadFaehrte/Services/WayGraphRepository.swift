//
//  WayGraphRepository.swift
//  RadFaehrte
//

import CoreLocation
import SQLite3

/// Liest die im App-Bundle mitgelieferte Straßen-/Wegegraph-Datenbank (read-only).
/// Erste Version deckt nur die Testregion Bremen ab (`ways_bremen.sqlite`).
final class WayGraphRepository {

    private var db: OpaquePointer?

    init(resourceName: String = "ways_bremen") {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "sqlite") else {
            assertionFailure("\(resourceName).sqlite fehlt im App-Bundle")
            return
        }
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            assertionFailure("Konnte \(resourceName).sqlite nicht öffnen: \(String(cString: sqlite3_errmsg(db)))")
            db = nil
        }
    }

    deinit {
        sqlite3_close(db)
    }

    /// Alle Kanten, deren Bounding Box das übergebene Rechteck überschneidet.
    func segmentsOverlapping(
        minLon: Double, minLat: Double, maxLon: Double, maxLat: Double
    ) -> [WaySegment] {
        guard let db else { return [] }

        let sql = """
            SELECT id, from_node, to_node, highway, cycleway, surface, oneway, name, geometry
            FROM way_segments
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

        var results: [WaySegment] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let fromNode = sqlite3_column_int64(statement, 1)
            let toNode = sqlite3_column_int64(statement, 2)
            let highway = textColumn(statement, 3)
            let cycleway = textColumn(statement, 4)
            let surface = textColumn(statement, 5)
            let oneway = Int(sqlite3_column_int(statement, 6))
            let name = textColumn(statement, 7)

            guard let blobPointer = sqlite3_column_blob(statement, 8) else { continue }
            let blobLength = Int(sqlite3_column_bytes(statement, 8))
            let data = Data(bytes: blobPointer, count: blobLength)
            let lines = Self.decodeGeometry(data)
            guard let coordinates = lines.first else { continue }

            results.append(WaySegment(
                id: id, fromNode: fromNode, toNode: toNode,
                highway: highway, cycleway: cycleway, surface: surface,
                oneway: oneway, name: name, coordinates: coordinates
            ))
        }
        return results
    }

    private func textColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    /// Gleiches Binärformat wie routes.geometry: UInt32 numLines, je Line UInt32 numPoints,
    /// dann numPoints * (Float32 lon, Float32 lat), little-endian. Kanten haben immer genau
    /// eine Line.
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
