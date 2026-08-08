//
//  ImportedRoute.swift
//  RadFaehrte
//

import CoreLocation

/// Eine vom Nutzer importierte, fertige Tour (z. B. von einer GPX-Datei einer Zeitung/eines
/// Vereins). Anders als die Routen aus `routes.sqlite` liegen die Punkte bereits in der
/// richtigen Reihenfolge vor - die Streckenlänge ergibt sich daher durch simples Aufsummieren
/// statt (wie bei den unsortierten OSM-Fragmenten) über einen Graphen + Dijkstra.
struct ImportedRoute: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let importedAt: Date
    let coordinates: [Coordinate]

    struct Coordinate: Codable, Equatable {
        let latitude: Double
        let longitude: Double

        var clLocationCoordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    init(id: UUID = UUID(), name: String, importedAt: Date = Date(), coordinates: [CLLocationCoordinate2D]) {
        self.id = id
        self.name = name
        self.importedAt = importedAt
        self.coordinates = coordinates.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var clCoordinates: [CLLocationCoordinate2D] {
        coordinates.map { $0.clLocationCoordinate }
    }

    var totalDistanceKm: Double {
        guard coordinates.count >= 2 else { return 0 }
        var meters = 0.0
        for i in 1..<coordinates.count {
            let a = CLLocation(latitude: coordinates[i - 1].latitude, longitude: coordinates[i - 1].longitude)
            let b = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
            meters += a.distance(from: b)
        }
        return meters / 1000
    }
}
