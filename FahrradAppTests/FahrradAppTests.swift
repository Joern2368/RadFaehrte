//
//  FahrradAppTests.swift
//  FahrradAppTests
//
//  Created by Jörn Frankenfeld on 17.07.26.
//

import Testing
import CoreLocation
@testable import FahrradApp

struct FahrradAppTests {

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

}
