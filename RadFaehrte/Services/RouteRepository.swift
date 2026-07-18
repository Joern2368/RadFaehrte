//
//  RouteRepository.swift
//  RadFaehrte
//

import CoreLocation
import SQLite3

/// Liest die im App-Bundle mitgelieferte Radrouten-Datenbank (read-only).
final class RouteRepository {

    private var db: OpaquePointer?

    init() {
        guard let url = Bundle.main.url(forResource: "routes", withExtension: "sqlite") else {
            assertionFailure("routes.sqlite fehlt im App-Bundle")
            return
        }
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            assertionFailure("Konnte routes.sqlite nicht öffnen: \(String(cString: sqlite3_errmsg(db)))")
            db = nil
        }
    }

    deinit {
        sqlite3_close(db)
    }

    /// Alle Routen, deren Bounding Box das übergebene Rechteck überschneidet.
    func routesOverlapping(
        minLon: Double, minLat: Double, maxLon: Double, maxLat: Double
    ) -> [BikeRoute] {
        guard let db else { return [] }

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
            let id = sqlite3_column_int64(statement, 0)
            let name = textColumn(statement, 1)
            let network = textColumn(statement, 2)
            let ref = textColumn(statement, 3)
            let distanceKm: Double? = sqlite3_column_type(statement, 4) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 4)
            let operatorName = textColumn(statement, 5)

            guard let blobPointer = sqlite3_column_blob(statement, 6) else { continue }
            let blobLength = Int(sqlite3_column_bytes(statement, 6))
            let data = Data(bytes: blobPointer, count: blobLength)
            let lines = Self.decodeGeometry(data)

            results.append(BikeRoute(
                id: id,
                name: name,
                network: network,
                ref: ref,
                distanceKm: distanceKm,
                operatorName: operatorName,
                lines: lines
            ))
        }
        return results
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
