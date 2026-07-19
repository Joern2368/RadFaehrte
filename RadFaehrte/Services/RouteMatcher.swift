//
//  RouteMatcher.swift
//  RadFaehrte
//

import CoreLocation

struct RouteMatch: Identifiable {
    let route: BikeRoute
    let distanceToStartKm: Double
    let distanceToEndKm: Double
    /// Der Punkt auf der Routen-Geometrie, der dem Start am nächsten liegt.
    let nearestPointToStart: CLLocationCoordinate2D
    /// Der Punkt auf der Routen-Geometrie, der dem Ziel am nächsten liegt.
    let nearestPointToEnd: CLLocationCoordinate2D

    var id: Int64 { route.id }
    var combinedDistanceKm: Double { distanceToStartKm + distanceToEndKm }
}

/// Findet Radfernwege/-routen, die sowohl in der Nähe von Start als auch Ziel verlaufen.
final class RouteMatcher {
    private let repository: RouteRepository
    private let thresholdKm: Double

    init(repository: RouteRepository, thresholdKm: Double = 8) {
        self.repository = repository
        self.thresholdKm = thresholdKm
    }

    func findMatches(start: CLLocationCoordinate2D, end: CLLocationCoordinate2D) -> [RouteMatch] {
        let minLat = min(start.latitude, end.latitude)
        let maxLat = max(start.latitude, end.latitude)
        let minLon = min(start.longitude, end.longitude)
        let maxLon = max(start.longitude, end.longitude)

        let latPad = thresholdKm / 111.32
        let midLat = (minLat + maxLat) / 2
        let lonPad = thresholdKm / (111.32 * max(cos(midLat * .pi / 180), 0.1))

        let candidates = repository.routesOverlapping(
            minLon: minLon - lonPad, minLat: minLat - latPad,
            maxLon: maxLon + lonPad, maxLat: maxLat + latPad
        )

        var matches: [RouteMatch] = []
        for route in candidates {
            // Unbenannte Routen sind meist Fragmente lokaler Knotenpunkt-Netze (network=lcn),
            // die in OSM oft als viele einzelne, kurze Wegabschnitte statt als eine
            // durchgehende Route kartiert sind - für den Nutzer keine sinnvoll folgbare Route.
            guard let name = route.name, !name.isEmpty else { continue }
            guard let toStart = Self.nearestPoint(from: start, toLines: route.lines),
                  let toEnd = Self.nearestPoint(from: end, toLines: route.lines) else { continue }
            if toStart.distanceKm <= thresholdKm && toEnd.distanceKm <= thresholdKm {
                matches.append(RouteMatch(
                    route: route,
                    distanceToStartKm: toStart.distanceKm,
                    distanceToEndKm: toEnd.distanceKm,
                    nearestPointToStart: toStart.coordinate,
                    nearestPointToEnd: toEnd.coordinate
                ))
            }
        }
        return matches.sorted { $0.combinedDistanceKm < $1.combinedDistanceKm }
    }

    /// Nächstgelegener Punkt auf einer Liniengeometrie zu einem Punkt, mit Distanz in km.
    /// Rechnet lokal in einer ebenen Näherung um den Punkt (ausreichend genau
    /// auf der hier relevanten Skala von wenigen Kilometern).
    private static func nearestPoint(
        from point: CLLocationCoordinate2D, toLines lines: [[CLLocationCoordinate2D]]
    ) -> (coordinate: CLLocationCoordinate2D, distanceKm: Double)? {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * max(cos(point.latitude * .pi / 180), 0.1)

        func toLocal(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            (
                (c.longitude - point.longitude) * metersPerDegreeLon,
                (c.latitude - point.latitude) * metersPerDegreeLat
            )
        }
        func toCoordinate(_ p: (x: Double, y: Double)) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(
                latitude: point.latitude + p.y / metersPerDegreeLat,
                longitude: point.longitude + p.x / metersPerDegreeLon
            )
        }

        let origin = (x: 0.0, y: 0.0)
        var bestDistance = Double.greatestFiniteMagnitude
        var bestPoint: (x: Double, y: Double)?

        for line in lines {
            guard line.count >= 2 else { continue }
            var prev = toLocal(line[0])
            for i in 1..<line.count {
                let curr = toLocal(line[i])
                let (distance, projected) = closestPointOnSegmentMeters(point: origin, a: prev, b: curr)
                if distance < bestDistance {
                    bestDistance = distance
                    bestPoint = projected
                }
                prev = curr
            }
        }
        guard let bestPoint, bestDistance.isFinite else { return nil }
        return (toCoordinate(bestPoint), bestDistance / 1000)
    }

    private static func closestPointOnSegmentMeters(
        point p: (x: Double, y: Double), a: (x: Double, y: Double), b: (x: Double, y: Double)
    ) -> (distance: Double, point: (x: Double, y: Double)) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy

        if lengthSquared == 0 {
            let ex = p.x - a.x, ey = p.y - a.y
            return ((ex * ex + ey * ey).squareRoot(), a)
        }

        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        let ex = p.x - projX, ey = p.y - projY
        return ((ex * ex + ey * ey).squareRoot(), (projX, projY))
    }
}
