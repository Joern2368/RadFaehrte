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

    @Test func routeSegmentDistanceComputesPlausiblePathAlongUnorderedGeometry() async throws {
        // "Weser Radweg mit Alternativstrecken" hat keine distance_km in der DB und ihre
        // Geometrie liegt (wie bei den meisten OSM-Routenrelationen) als viele einzelne,
        // ungeordnete Way-Fragmente vor statt als eine durchgehende Linie.
        let repository = RouteRepository()
        let routes = repository.routesOverlapping(minLon: 8.6, minLat: 52.9, maxLon: 8.95, maxLat: 53.2)
        let route = try #require(routes.first { $0.name == "Weser Radweg mit Alternativstrecken" })

        let matcher = RouteMatcher(repository: repository)
        let bremen = CLLocationCoordinate2D(latitude: 53.0793, longitude: 8.8017)
        let achim = CLLocationCoordinate2D(latitude: 53.0158, longitude: 8.9525)
        let matches = matcher.findMatches(start: bremen, end: achim)
        let match = try #require(matches.first { $0.route.id == route.id })

        let directDistanceKm = CLLocation(latitude: match.nearestPointToStart.latitude, longitude: match.nearestPointToStart.longitude)
            .distance(from: CLLocation(latitude: match.nearestPointToEnd.latitude, longitude: match.nearestPointToEnd.longitude)) / 1000

        let segment = try #require(RouteMatcher.routeSegmentDistance(
            along: route.lines, from: match.nearestPointToStart, to: match.nearestPointToEnd
        ))

        // Die Strecke entlang der Route muss mindestens der Luftlinie entsprechen. Diese Route
        // macht über ihre Alternativstrecke real einen großen Schlenker weit südlich von Achim,
        // daher ist ein deutliches Vielfaches der Luftlinie hier tatsächlich korrekt (keine
        // Schleife durchs restliche Streckennetz quer durch Deutschland als grobe Obergrenze).
        #expect(segment.distanceKm >= directDistanceKm - 0.1)
        #expect(segment.distanceKm < directDistanceKm * 10)

        // Zwischen diesen exakten Ankerpunkten gibt es (verifiziert) keinen redundanten
        // zweiten Pfad in der Geometrie dieser Route - die Alternativstrecken liegen an
        // anderer Stelle im Netz. Sofern doch eine gefunden wird, muss sie länger sein
        // als der kürzeste Pfad (Dijkstra über die um dessen Kanten reduzierte Kopie).
        if let alternateKm = segment.alternateDistanceKm {
            #expect(alternateKm > segment.distanceKm)
        }
    }

    @Test func gpxParserExtractsNameAndTrackPoints() async throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Test">
          <trk>
            <name>Sonntagsrunde Bremen</name>
            <trkseg>
              <trkpt lat="53.0793" lon="8.8017"></trkpt>
              <trkpt lat="53.0700" lon="8.8100"></trkpt>
              <trkpt lat="53.0600" lon="8.8300"></trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let data = try #require(gpx.data(using: .utf8))

        let parsed = try #require(GPXParser.parse(data: data))
        #expect(parsed.name == "Sonntagsrunde Bremen")
        #expect(parsed.coordinates.count == 3)
        #expect(parsed.coordinates.first?.latitude == 53.0793)
        #expect(parsed.coordinates.last?.longitude == 8.83)
    }

    @Test func gpxParserIgnoresWaypointsAndReturnsNilForEmptyTrack() async throws {
        let gpxWithOnlyWaypoint = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Test">
          <wpt lat="53.0" lon="8.8"><name>Rastplatz</name></wpt>
        </gpx>
        """
        let data = try #require(gpxWithOnlyWaypoint.data(using: .utf8))
        #expect(GPXParser.parse(data: data) == nil)
    }

    @Test func importedRouteComputesSequentialDistance() async throws {
        // Drei Punkte auf einem Breitengrad, je ca. 0.01° Längengrad auseinander (~0.67 km bei
        // dieser Breite) - Reihenfolge ist bei GPX-Tracks bereits gegeben, daher einfache Summe
        // statt Graph-Suche.
        let coordinates = [
            CLLocationCoordinate2D(latitude: 53.0, longitude: 8.80),
            CLLocationCoordinate2D(latitude: 53.0, longitude: 8.81),
            CLLocationCoordinate2D(latitude: 53.0, longitude: 8.82)
        ]
        let route = ImportedRoute(name: "Test-Tour", coordinates: coordinates)

        let expectedMeters = zip(coordinates, coordinates.dropFirst()).reduce(0.0) { total, pair in
            total + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        }

        #expect(abs(route.totalDistanceKm - expectedMeters / 1000) < 0.001)
    }

}
