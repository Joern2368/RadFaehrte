//
//  RadFaehrteTests.swift
//  RadFaehrteTests
//
//  Created by Jörn Frankenfeld on 17.07.26.
//

import Testing
import CoreLocation
@testable import RadFaehrte

struct RadFaehrteTests {

    @Test func routeRepositoryFindsWeserRadwegNearBremen() async throws {
        let repository = RouteRepository()

        // Grobe Bounding Box um Bremen
        let routes = repository.routesOverlapping(
            minLon: 8.6, minLat: 52.9, maxLon: 8.95, maxLat: 53.2
        )

        #expect(!routes.isEmpty)
        #expect(routes.contains { $0.name == "Weser-Radweg" })

        let weserRadweg = routes.first { $0.name == "Weser-Radweg" }
        #expect(weserRadweg?.network == "rcn")
        #expect(weserRadweg?.lines.isEmpty == false)
    }

    @Test func routeMatcherFindsWeserRadwegForBremenAchim() async throws {
        let matcher = RouteMatcher(repository: RouteRepository())

        // Das Motivationsbeispiel aus der Spezifikation
        let bremen = CLLocationCoordinate2D(latitude: 53.0793, longitude: 8.8017)
        let achim = CLLocationCoordinate2D(latitude: 53.0158, longitude: 8.9525)

        let matches = matcher.findMatches(start: bremen, end: achim)

        #expect(!matches.isEmpty)
        #expect(matches.contains { $0.route.name == "Weser-Radweg" })

        if let weserRadweg = matches.first(where: { $0.route.name == "Weser-Radweg" }) {
            #expect(weserRadweg.distanceToStartKm < 8)
            #expect(weserRadweg.distanceToEndKm < 8)
        }
    }

    @Test func waySegmentCostFactorPrefersCyclewayOverPrimaryRoad() async throws {
        let cycleway = WaySegment(
            id: 1, fromNode: 1, toNode: 2, highway: "cycleway", cycleway: nil, surface: nil,
            oneway: 0, name: nil,
            coordinates: [CLLocationCoordinate2D(latitude: 53.08, longitude: 8.80)]
        )
        let residential = WaySegment(
            id: 2, fromNode: 1, toNode: 2, highway: "residential", cycleway: nil, surface: nil,
            oneway: 0, name: nil,
            coordinates: [CLLocationCoordinate2D(latitude: 53.08, longitude: 8.80)]
        )
        let primary = WaySegment(
            id: 3, fromNode: 1, toNode: 2, highway: "primary", cycleway: nil, surface: nil,
            oneway: 0, name: nil,
            coordinates: [CLLocationCoordinate2D(latitude: 53.08, longitude: 8.80)]
        )

        #expect(cycleway.costFactor < residential.costFactor)
        #expect(residential.costFactor < primary.costFactor)
    }

    @Test func bikeRoutingEngineFindsRouteBetweenTwoBremenPoints() async throws {
        let engine = BikeRoutingEngine(repository: WayGraphRepository())

        // Zwei reale Punkte im Bremer Wohngebiet, ca. 1.4 km auseinander
        let start = CLLocationCoordinate2D(latitude: 53.0999, longitude: 8.7905)
        let end = CLLocationCoordinate2D(latitude: 53.0872, longitude: 8.7901)

        let route = engine.route(from: start, to: end)

        #expect(route != nil)
        if let route {
            #expect(route.coordinates.count > 1)
            // Direkte Distanz liegt bei ~1.4 km; die Route entlang des Wegenetzes darf
            // etwas länger sein, aber nicht unrealistisch (z. B. nicht > 5x Luftlinie).
            let straightLineKm = CLLocation(latitude: start.latitude, longitude: start.longitude)
                .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude)) / 1000
            #expect(route.distanceMeters / 1000 < straightLineKm * 5)
        }
    }

    @Test func bikeRoutingEngineReturnsMultipleDistinctAlternates() async throws {
        let engine = BikeRoutingEngine(repository: WayGraphRepository())

        let start = CLLocationCoordinate2D(latitude: 53.0999, longitude: 8.7905)
        let end = CLLocationCoordinate2D(latitude: 53.0872, longitude: 8.7901)

        let routes = engine.routes(from: start, to: end, count: 4)

        #expect(!routes.isEmpty)
        #expect(routes.count <= 4)
        // Alternativen sollen sich spürbar unterscheiden (Penalty-Strategie), nicht dieselbe
        // Route mehrfach liefern.
        if routes.count > 1 {
            func signature(_ route: BikeRoutingEngine.Route) -> String {
                route.coordinates.map { "\($0.latitude),\($0.longitude)" }.joined()
            }
            #expect(signature(routes[0]) != signature(routes[1]))
        }
    }

}
