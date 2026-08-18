//
//  RecentPlaceStore.swift
//  RadFaehrte
//

import Foundation
import CoreLocation

/// Speichert die zuletzt in der Start-/Ziel-Suche gewählten Ziele (analog "Zuletzt gesucht" bei
/// Google Maps) als eine einzelne JSON-Datei im `Documents`-Ordner - anders als
/// `FavoritePlaceStore` (eine Datei je Favorit) reicht hier eine Datei, da die ganze Liste bei
/// jeder Auswahl ohnehin neu geschrieben wird.
final class RecentPlaceStore {
    /// Mehr als eine Handvoll Zeilen würde die Vorschlagsliste vor jeder Eingabe unübersichtlich
    /// machen - Google Maps zeigt in der Praxis auch nur wenige.
    private static let maxEntries = 6

    private let fileURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("RecentPlaces.json")
    }

    func loadAll() -> [RecentPlace] {
        guard let data = try? Data(contentsOf: fileURL),
              let places = try? JSONDecoder().decode([RecentPlace].self, from: data)
        else { return [] }
        return places.sorted { $0.selectedAt > $1.selectedAt }
    }

    /// Trägt `title` als neuestes Ziel ein - ein bereits vorhandener Eintrag mit demselben Titel
    /// wird dabei aktualisiert (neuer Zeitstempel, an den Anfang gerückt) statt dupliziert.
    func record(title: String, subtitle: String, coordinate: CLLocationCoordinate2D) {
        var places = loadAll()
        places.removeAll { $0.title == title }
        places.insert(RecentPlace(title: title, subtitle: subtitle, coordinate: coordinate), at: 0)
        places = Array(places.prefix(Self.maxEntries))
        guard let data = try? JSONEncoder().encode(places) else { return }
        try? data.write(to: fileURL)
    }

    func delete(_ place: RecentPlace) {
        var places = loadAll()
        places.removeAll { $0.id == place.id }
        guard let data = try? JSONEncoder().encode(places) else { return }
        try? data.write(to: fileURL)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
