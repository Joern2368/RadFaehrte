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
