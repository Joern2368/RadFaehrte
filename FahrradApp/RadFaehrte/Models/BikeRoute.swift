//
//  BikeRoute.swift
//  RadFaehrte
//

import CoreLocation
import MapKit

struct BikeRoute: Identifiable {
    let id: Int64
    let name: String?
    let network: String?
    let ref: String?
    let distanceKm: Double?
    let operatorName: String?
    /// Eine Route kann aus mehreren nicht zusammenhängenden Liniensegmenten bestehen.
    let lines: [[CLLocationCoordinate2D]]

    /// Streckenlänge direkt aus der Geometrie aufsummiert (alle Liniensegmente einzeln, dann
    /// addiert) - Fallback für Routen ohne `distance`-Tag in den OSM-Daten (`distanceKm == nil`,
    /// z. B. beim Ammerseeradweg beobachtet: viele auch bekannte, lange Routen sind schlicht nicht
    /// mit einer Gesamtlänge getaggt). Kann bei Kartendaten, die an einer Regionsgrenze
    /// abgeschnitten sind, etwas unter der tatsächlichen Streckenlänge liegen - aber immer noch
    /// deutlich näher an der Wahrheit als `0`.
    var geometryLengthKm: Double {
        lines.reduce(0) { total, line in
            guard line.count > 1 else { return total }
            var lineLengthMeters = 0.0
            for index in 1..<line.count {
                let a = CLLocation(latitude: line[index - 1].latitude, longitude: line[index - 1].longitude)
                let b = CLLocation(latitude: line[index].latitude, longitude: line[index].longitude)
                lineLengthMeters += a.distance(from: b)
            }
            return total + lineLengthMeters / 1000
        }
    }

    /// Kartenregion, die alle Liniensegmente mit etwas Rand umfasst - analog
    /// `DrivenTour.region(padding:)`, für die Detailkarte in `AllRoutesView`.
    func region(padding: Double = 1.3) -> MKCoordinateRegion {
        let coords = lines.flatMap { $0 }
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
