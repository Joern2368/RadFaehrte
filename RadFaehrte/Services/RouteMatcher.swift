//
//  RouteMatcher.swift
//  RadFaehrte
//

import CoreLocation

struct RouteMatch: Identifiable {
    let route: BikeRoute
    let distanceToStartKm: Double
    let distanceToEndKm: Double

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
            guard let distanceToStart = Self.minDistanceKm(from: start, toLines: route.lines),
                  let distanceToEnd = Self.minDistanceKm(from: end, toLines: route.lines) else { continue }
            if distanceToStart <= thresholdKm && distanceToEnd <= thresholdKm {
                matches.append(RouteMatch(
                    route: route,
                    distanceToStartKm: distanceToStart,
                    distanceToEndKm: distanceToEnd
                ))
            }
        }
        return matches.sorted { $0.combinedDistanceKm < $1.combinedDistanceKm }
    }

    /// Kürzeste Distanz von einem Punkt zu einer Liniengeometrie, in km.
    /// Rechnet lokal in einer ebenen Näherung um den Punkt (ausreichend genau
    /// auf der hier relevanten Skala von wenigen Kilometern).
    private static func minDistanceKm(
        from point: CLLocationCoordinate2D, toLines lines: [[CLLocationCoordinate2D]]
    ) -> Double? {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * max(cos(point.latitude * .pi / 180), 0.1)

        func toLocal(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            (
                (c.longitude - point.longitude) * metersPerDegreeLon,
                (c.latitude - point.latitude) * metersPerDegreeLat
            )
        }

        let origin = (x: 0.0, y: 0.0)
        var best = Double.greatestFiniteMagnitude

        for line in lines {
            guard line.count >= 2 else { continue }
            var prev = toLocal(line[0])
            for i in 1..<line.count {
                let curr = toLocal(line[i])
                let d = distanceToSegmentMeters(point: origin, a: prev, b: curr)
                if d < best { best = d }
                prev = curr
            }
        }
        guard best.isFinite else { return nil }
        return best / 1000
    }

    private static func distanceToSegmentMeters(
        point p: (x: Double, y: Double), a: (x: Double, y: Double), b: (x: Double, y: Double)
    ) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy

        if lengthSquared == 0 {
            let ex = p.x - a.x, ey = p.y - a.y
            return (ex * ex + ey * ey).squareRoot()
        }

        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        let ex = p.x - projX, ey = p.y - projY
        return (ex * ex + ey * ey).squareRoot()
    }
}
