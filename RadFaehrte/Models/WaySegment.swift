//
//  WaySegment.swift
//  RadFaehrte
//

import CoreLocation

/// Eine Kante im lokalen Straßen-/Wegegraphen, zwischen zwei echten Kreuzungen
/// (OSM-Knoten, die von mehreren Ways geteilt werden, oder Way-Endpunkten).
struct WaySegment {
    let id: Int64
    let fromNode: Int64
    let toNode: Int64
    let highway: String?
    let cycleway: String?
    let surface: String?
    /// 0 = beide Richtungen befahrbar, 1 = nur from→to, -1 = nur to→from
    let oneway: Int
    let name: String?
    let coordinates: [CLLocationCoordinate2D]

    var lengthMeters: Double {
        var total = 0.0
        for i in 1..<coordinates.count {
            let a = CLLocation(latitude: coordinates[i - 1].latitude, longitude: coordinates[i - 1].longitude)
            let b = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
            total += a.distance(from: b)
        }
        return total
    }

    /// Gewichtungsfaktor gegenüber der reinen Distanz: niedriger = bevorzugt.
    /// Radwege/ruhige Straßen werden bevorzugt, Hauptstraßen gemieden.
    var costFactor: Double {
        var factor: Double
        if let cycleway, !cycleway.isEmpty, cycleway != "no" {
            factor = 0.7
        } else if highway == "cycleway" {
            factor = 0.7
        } else {
            switch highway {
            case "residential", "living_street", "path", "track", "service", "pedestrian", "unclassified":
                factor = 1.0
            case "tertiary", "tertiary_link":
                factor = 1.3
            case "secondary", "secondary_link":
                factor = 1.6
            case "primary", "primary_link":
                factor = 3.0
            default:
                factor = 1.4
            }
        }
        if let surface, ["unpaved", "gravel", "ground", "sand", "grass"].contains(surface) {
            factor *= 1.2
        }
        return factor
    }
}
