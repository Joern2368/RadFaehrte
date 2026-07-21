//
//  ImportedRouteStore.swift
//  RadFaehrte
//

import Foundation

/// Speichert importierte Touren als einzelne JSON-Dateien im `Documents`-Ordner (separat von der
/// read-only `routes.sqlite` im App-Bundle). Für eine Handvoll Nutzer-Routen reicht das locker -
/// kein SwiftData/Core Data nötig.
final class ImportedRouteStore {
    private let directory: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents.appendingPathComponent("ImportedRoutes", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func loadAll() -> [ImportedRoute] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> ImportedRoute? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(ImportedRoute.self, from: data)
            }
            .sorted { $0.importedAt > $1.importedAt }
    }

    func save(_ route: ImportedRoute) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(route) else { return }
        try? data.write(to: fileURL(for: route.id))
    }

    func delete(_ route: ImportedRoute) {
        try? FileManager.default.removeItem(at: fileURL(for: route.id))
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
