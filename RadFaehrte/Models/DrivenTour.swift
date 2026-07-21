//
//  DrivenTour.swift
//  RadFaehrte
//

import CoreLocation

/// Eine tatsächlich gefahrene Tour (Aufzeichnung aus dem Navigationsmodus), fürs Verlauf-Tab.
/// Anders als `ImportedRoute` (eine vom Nutzer importierte Ziel-Tour) ist das hier ein
/// nachträgliches Protokoll einer abgeschlossenen Fahrt.
struct DrivenTour: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let distanceKm: Double
    let duration: TimeInterval
    let averageSpeedKmh: Double
    let coordinates: [Coordinate]

    struct Coordinate: Codable, Equatable {
        let latitude: Double
        let longitude: Double

        var clLocationCoordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    init(
        id: UUID = UUID(), date: Date = Date(), distanceKm: Double, duration: TimeInterval,
        averageSpeedKmh: Double, coordinates: [CLLocationCoordinate2D]
    ) {
        self.id = id
        self.date = date
        self.distanceKm = distanceKm
        self.duration = duration
        self.averageSpeedKmh = averageSpeedKmh
        self.coordinates = coordinates.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var clCoordinates: [CLLocationCoordinate2D] {
        coordinates.map { $0.clLocationCoordinate }
    }
}

/// Gemeinsame Dauer-Formatierung für Touren (Navigations-Zusammenfassung und Verlauf).
func formattedTourDuration(_ interval: TimeInterval) -> String {
    let totalMinutes = Int(interval / 60)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    return hours > 0 ? "\(hours) Std. \(minutes) Min." : "\(minutes) Min."
}
