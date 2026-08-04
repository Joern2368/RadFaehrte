//
//  RecentPlace.swift
//  RadFaehrte
//

import CoreLocation

/// Ein zuletzt in der Start-/Ziel-Suche gewähltes Ziel (analog "Zuletzt gesucht" bei Google Maps) -
/// anders als `FavoritePlace` nicht bewusst gespeichert, sondern automatisch bei jeder
/// Adressauswahl mitgeschrieben (s. `RecentPlaceStore.record`).
struct RecentPlace: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String
    let coordinate: Coordinate
    /// Zeitpunkt der letzten Auswahl - bestimmt die Sortierung (neueste zuerst) und wird beim
    /// erneuten Wählen desselben Ziels aktualisiert statt einen zweiten Eintrag anzulegen.
    var selectedAt: Date

    struct Coordinate: Codable, Equatable {
        let latitude: Double
        let longitude: Double

        var clLocationCoordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    init(
        id: UUID = UUID(), title: String, subtitle: String,
        coordinate: CLLocationCoordinate2D, selectedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.coordinate = Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        self.selectedAt = selectedAt
    }

    var clCoordinate: CLLocationCoordinate2D {
        coordinate.clLocationCoordinate
    }
}
