//
//  DrivenTourStore.swift
//  RadFaehrte
//

import Foundation

/// Speichert abgeschlossene Fahrten als einzelne JSON-Dateien im `Documents`-Ordner, analog zu
/// `ImportedRouteStore` - getrennter Unterordner, da inhaltlich ein anderes Konzept (aufgezeichnete
/// statt importierte Strecke).
final class DrivenTourStore {
    private let directory: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents.appendingPathComponent("DrivenTours", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func loadAll() -> [DrivenTour] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> DrivenTour? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(DrivenTour.self, from: data)
            }
            .sorted { $0.date > $1.date }
    }

    func save(_ tour: DrivenTour) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(tour) else { return }
        try? data.write(to: fileURL(for: tour.id))
    }

    func delete(_ tour: DrivenTour) {
        try? FileManager.default.removeItem(at: fileURL(for: tour.id))
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
