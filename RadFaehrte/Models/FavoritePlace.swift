//
//  FavoritePlace.swift
//  RadFaehrte
//

import CoreLocation

/// Ein gespeicherter Ort fürs schnelle Auswählen als Start/Ziel (analog "Zuhause"/"Arbeit" bei
/// Google Maps), unabhängig von der automatischen "Zuletzt gefahren"-Verlaufsliste.
struct FavoritePlace: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: Kind
    /// Nur bei `kind == .custom` gesetzt - bei `.home`/`.work` ergibt sich der Anzeigename aus der
    /// Art (s. `displayName`), es gibt je nur einen Favoriten dieser Art (durchgesetzt in
    /// `FavoritePlaceStore.save`).
    var customName: String?
    let title: String
    let subtitle: String
    let coordinate: Coordinate

    enum Kind: String, Codable {
        case home, work, custom
    }

    struct Coordinate: Codable, Equatable {
        let latitude: Double
        let longitude: Double

        var clLocationCoordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    init(
        id: UUID = UUID(), kind: Kind, customName: String? = nil,
        title: String, subtitle: String, coordinate: CLLocationCoordinate2D
    ) {
        self.id = id
        self.kind = kind
        self.customName = customName
        self.title = title
        self.subtitle = subtitle
        self.coordinate = Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var displayName: String {
        switch kind {
        case .home: return "Zuhause"
        case .work: return "Arbeit"
        case .custom: return customName?.isEmpty == false ? customName! : title
        }
    }

    var icon: String {
        switch kind {
        case .home: return "house.fill"
        case .work: return "briefcase.fill"
        case .custom: return "star.fill"
        }
    }

    var clCoordinate: CLLocationCoordinate2D {
        coordinate.clLocationCoordinate
    }
}
