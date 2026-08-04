//
//  FavoritePlaceStore.swift
//  RadFaehrte
//

import Foundation

/// Speichert Favoriten-Orte als einzelne JSON-Dateien im `Documents`-Ordner (analog
/// `ImportedRouteStore`/`DrivenTourStore`) - für eine Handvoll gespeicherter Orte reicht das
/// locker, kein SwiftData/Core Data nötig.
final class FavoritePlaceStore {
    private let directory: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents.appendingPathComponent("FavoritePlaces", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Sortiert Zuhause/Arbeit immer an den Anfang (in dieser Reihenfolge), da sie in der
    /// Vorschlagsliste als feste, wiedererkennbare Zeilen erscheinen sollen - eigene Favoriten
    /// danach alphabetisch.
    func loadAll() -> [FavoritePlace] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }

        let places = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> FavoritePlace? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(FavoritePlace.self, from: data)
            }
        return places.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind.sortOrder < rhs.kind.sortOrder }
            return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
        }
    }

    /// Speichert `place` - für `.home`/`.work` wird zuvor ein eventuell schon vorhandener
    /// Favorit derselben Art gelöscht, da es davon jeweils nur einen geben soll (neuer Ort
    /// ersetzt den alten, statt eine zweite "Zuhause"-Zeile anzulegen).
    func save(_ place: FavoritePlace) {
        if place.kind != .custom {
            for existing in loadAll() where existing.kind == place.kind && existing.id != place.id {
                delete(existing)
            }
        }
        guard let data = try? JSONEncoder().encode(place) else { return }
        try? data.write(to: fileURL(for: place.id))
    }

    func delete(_ place: FavoritePlace) {
        try? FileManager.default.removeItem(at: fileURL(for: place.id))
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}

private extension FavoritePlace.Kind {
    var sortOrder: Int {
        switch self {
        case .home: return 0
        case .work: return 1
        case .custom: return 2
        }
    }
}
