//
//  BikeRoute.swift
//  FahrradApp
//

import CoreLocation

struct BikeRoute: Identifiable {
    let id: Int64
    let name: String?
    let network: String?
    let ref: String?
    let distanceKm: Double?
    let operatorName: String?
    /// Eine Route kann aus mehreren nicht zusammenhängenden Liniensegmenten bestehen.
    let lines: [[CLLocationCoordinate2D]]
}
