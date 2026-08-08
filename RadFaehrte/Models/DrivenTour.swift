//
//  DrivenTour.swift
//  RadFaehrte
//

import CoreLocation
import MapKit

/// Eine tatsächlich gefahrene Tour (Aufzeichnung aus dem Navigationsmodus), fürs Verlauf-Tab.
/// Anders als `ImportedRoute` (eine vom Nutzer importierte Ziel-Tour) ist das hier ein
/// nachträgliches Protokoll einer abgeschlossenen Fahrt.
struct DrivenTour: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    /// Vom Nutzer vergebener Name (Umbenennen im Verlauf-Tab), `nil` solange keiner gesetzt wurde -
    /// dann zeigt die UI stattdessen das Datum an. Optional statt mit Default-Wert, damit ältere,
    /// bereits gespeicherte Touren (JSON ohne dieses Feld) weiterhin klaglos decodiert werden.
    var name: String?
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
        id: UUID = UUID(), date: Date = Date(), name: String? = nil, distanceKm: Double, duration: TimeInterval,
        averageSpeedKmh: Double, coordinates: [CLLocationCoordinate2D]
    ) {
        self.id = id
        self.date = date
        self.name = name
        self.distanceKm = distanceKm
        self.duration = duration
        self.averageSpeedKmh = averageSpeedKmh
        self.coordinates = coordinates.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var clCoordinates: [CLLocationCoordinate2D] {
        coordinates.map { $0.clLocationCoordinate }
    }

    private static let fallbackNameDateFormat = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Locale(identifier: "de_DE"))

    /// Name für Kontexte, die zwingend einen (nicht-leeren) Titel brauchen - z. B. das Ziel-Feld
    /// beim Direkt-Starten aus dem Verlauf. Fällt auf einen datumsbasierten Titel zurück, falls
    /// der Nutzer die Tour nicht umbenannt hat.
    var displayName: String {
        if let name, !name.isEmpty { return name }
        return "Fahrt vom \(Self.fallbackNameDateFormat.format(date))"
    }

    /// Kartenregion, die die komplette aufgezeichnete Strecke mit etwas Rand umfasst - genutzt
    /// sowohl für die Detailkarte im Verlauf (`HistoryView`) als auch für die kleinen
    /// Routen-Vorschaubilder (`TourMapSnapshotCache`).
    func region(padding: Double = 1.3) -> MKCoordinateRegion {
        let coords = clCoordinates
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * padding),
            longitudeDelta: max(0.01, (maxLon - minLon) * padding)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

/// Gemeinsame Dauer-Formatierung für Touren (Navigations-Zusammenfassung und Verlauf).
func formattedTourDuration(_ interval: TimeInterval) -> String {
    let totalMinutes = Int(interval / 60)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    return hours > 0 ? "\(hours) Std. \(minutes) Min." : "\(minutes) Min."
}
