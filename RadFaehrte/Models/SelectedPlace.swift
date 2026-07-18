//
//  SelectedPlace.swift
//  RadFaehrte
//

import CoreLocation

struct SelectedPlace: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: SelectedPlace, rhs: SelectedPlace) -> Bool {
        lhs.id == rhs.id
    }
}
