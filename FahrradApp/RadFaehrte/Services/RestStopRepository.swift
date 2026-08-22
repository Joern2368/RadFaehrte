//
//  RestStopRepository.swift
//  RadFaehrte
//

import Foundation
import SQLite3

/// Liest eine heruntergeladene Rastplatz-Datenbank (s. `Scripts/build_rest_stops.py`,
/// `RestStopStore`) von einem Dateisystempfad - anders als `WayGraphRepository` (kompletter Graph
/// wird beim Laden in Swift-Arrays kopiert) bleibt die Datei hier offen und wird pro
/// Kartenausschnitt live per indizierter Bbox-Abfrage angefragt, analog `RouteRepository`, da
/// Rastplätze Punktdaten sind, keine zu traversierende Graphstruktur.
nonisolated final class RestStopRepository {
    private var db: OpaquePointer?

    /// Schützt SQLite-Zugriffe vor gleichzeitiger Nutzung durch mehrere Threads - siehe
    /// Doc-Kommentar an `RouteRepository.lock` (dort per Live-Crash begründet).
    private let lock = NSLock()

    init?(path: String) {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let handle else {
            return nil
        }
        db = handle
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    /// Rastplätze innerhalb der übergebenen Bbox, gedeckelt durch `limit` als Sicherheitsdeckel
    /// (analog `RouteRepository.routeSummaries(..., limit:)`) gegen eine Pin-Flut bei zu
    /// niedrigem Zoom.
    func restStops(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double, limit: Int = 500) -> [RestStop] {
        lock.lock()
        defer { lock.unlock() }

        let sql = "SELECT id, kind, name, opening_hours, lat, lon FROM rest_stops WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ? LIMIT ?"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            // Bewusst kein `assertionFailure` (crasht in Debug-Builds) wie bei `RouteRepository`:
            // dort sind die Datenbanken fest gebündelt, ein Schema-Mismatch wäre ein echter Bug.
            // Hier werden die Dateien dagegen zur Laufzeit heruntergeladen und können durch ein
            // Schema-Update zwischenzeitlich veraltet sein (Live-Fund 2026-08-19: ein noch nicht
            // neu hochgeladenes Bundesland ohne die `opening_hours`-Spalte brachte die App beim
            // Start der Navigation zum Absturz) - lieber diese eine Region kommentarlos ohne Pins
            // lassen als die ganze App abschießen.
            print("RestStopRepository: SQL prepare fehlgeschlagen: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }

        sqlite3_bind_double(statement, 1, minLat)
        sqlite3_bind_double(statement, 2, maxLat)
        sqlite3_bind_double(statement, 3, minLon)
        sqlite3_bind_double(statement, 4, maxLon)
        sqlite3_bind_int(statement, 5, Int32(limit))

        var results: [RestStop] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let stop = decodeRestStop(from: statement) {
                results.append(stop)
            }
        }
        return results
    }

    private func decodeRestStop(from statement: OpaquePointer?) -> RestStop? {
        let id = sqlite3_column_int64(statement, 0)
        guard let kind = RestStop.Kind(rawKindValue: sqlite3_column_int(statement, 1)) else { return nil }
        let name = textColumn(statement, 2)
        let openingHours = textColumn(statement, 3)
        let lat = sqlite3_column_double(statement, 4)
        let lon = sqlite3_column_double(statement, 5)
        return RestStop(id: id, kind: kind, title: name, openingHours: openingHours, coordinate: .init(latitude: lat, longitude: lon))
    }

    private func textColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }
}

/// Wandelt den in `Scripts/build_rest_stops.py` (`KIND_*`-Konstanten) vergebenen Integer-Code der
/// `kind`-Spalte in den passenden Fall um - Reihenfolge muss mit dem Python-Skript übereinstimmen.
/// Reihenfolge/Werte müssen mit `KIND_*` in `Scripts/build_rest_stops.py` übereinstimmen.
private extension RestStop.Kind {
    init?(rawKindValue: Int32) {
        switch rawKindValue {
        case 0: self = .drinkingWater
        case 1: self = .cafe
        case 2: self = .viewpoint
        case 3: self = .bicycleRepairStation
        case 4: self = .bench
        case 5: self = .beerGarden
        case 6: self = .toilets
        default: return nil
        }
    }
}
