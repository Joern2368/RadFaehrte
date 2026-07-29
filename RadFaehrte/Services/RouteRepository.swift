//
//  RouteRepository.swift
//  RadFaehrte
//

import CoreLocation
import SQLite3

/// Liest die im App-Bundle mitgelieferten Radrouten-Datenbanken (read-only). Deutschland
/// (`routes.sqlite`) ist Pflicht, weitere Länder (z. B. `netherlands.sqlite`) werden nur
/// eingebunden, wenn die jeweilige Datei tatsächlich im Bundle liegt - alle Datenbanken teilen
/// sich dasselbe Schema, Ergebnisse werden einfach zusammengeführt. OSM-Relations-IDs sind
/// global eindeutig (planetweiter Namensraum), daher keine Kollisionsgefahr zwischen Ländern.
nonisolated final class RouteRepository {

    private static let bundledResourceNames = ["routes", "netherlands", "poland", "sweden"]

    private var databases: [OpaquePointer] = []

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
        databases.flatMap {
            routesOverlapping(in: $0, minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat)
        }
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

    /// Eine einzelne Route anhand ihrer OSM-Relations-ID (z. B. für die Kombinationssuche, die
    /// per Junction-Tabelle nur IDs kennt und die volle Geometrie nachladen muss). Fragt die
    /// Datenbanken der Reihe nach ab, bis eine einen Treffer liefert.
    func route(withId id: Int64) -> BikeRoute? {
        for db in databases {
            if let route = route(withId: id, in: db) {
                return route
            }
        }
        return nil
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

    /// Alle Anschlussstellen einer Route zu anderen benannten Fernwegen (aus der per
    /// `Scripts/find_route_junctions.py` vorab berechneten Sidecar-DB). Leeres Array, wenn die
    /// Sidecar-Datei fehlt oder die Route keine Anschlüsse hat - kein Crash in beiden Fällen.
    func junctions(forRouteId id: Int64) -> [(partnerRouteId: Int64, coordinate: CLLocationCoordinate2D)] {
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
