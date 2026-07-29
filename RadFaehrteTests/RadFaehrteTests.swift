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

    @Test func routeRepositoryFindsEuroVeloRouteNearRotterdam() async throws {
        // Regressionstest für die zusätzliche Niederlande-Datenbank (netherlands.sqlite,
        // s. ROADMAP.md) - stellt sicher, dass RouteRepository sie neben routes.sqlite lädt und
        // ihre Treffer korrekt dekodiert.
        let repository = RouteRepository()

        let routes = repository.routesOverlapping(
            minLon: 4.35, minLat: 51.85, maxLon: 4.65, maxLat: 52.0
        )

        #expect(!routes.isEmpty)
        #expect(routes.contains { $0.name?.contains("EuroVelo 15") == true })

        let euroVelo15 = routes.first { $0.name?.contains("EuroVelo 15") == true }
        #expect(euroVelo15?.lines.isEmpty == false)
    }

    @Test func routeRepositoryFindsEuroVeloRouteNearKrakow() async throws {
        // Regressionstest für die zusätzliche Polen-Datenbank (poland.sqlite, s. ROADMAP.md) -
        // analog zum Niederlande-Test oben.
        let repository = RouteRepository()

        let routes = repository.routesOverlapping(
            minLon: 19.75, minLat: 49.9, maxLon: 20.15, maxLat: 50.15
        )

        #expect(!routes.isEmpty)
        #expect(routes.contains { $0.name?.contains("EuroVelo 4") == true })

        let euroVelo4 = routes.first { $0.name?.contains("EuroVelo 4") == true }
        #expect(euroVelo4?.lines.isEmpty == false)
    }

    @Test func routeRepositoryFindsEuroVeloRouteNearStockholm() async throws {
        // Regressionstest für die zusätzliche Schweden-Datenbank (sweden.sqlite, s. ROADMAP.md) -
        // analog zu den Niederlande-/Polen-Tests oben.
        let repository = RouteRepository()

        let routes = repository.routesOverlapping(
            minLon: 17.9, minLat: 59.2, maxLon: 18.3, maxLat: 59.45
        )

        #expect(!routes.isEmpty)
        #expect(routes.contains { $0.name?.contains("EuroVelo 10") == true })

        let euroVelo10 = routes.first { $0.name?.contains("EuroVelo 10") == true }
        #expect(euroVelo10?.lines.isEmpty == false)
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

    @Test func routeSegmentDistancesMatchesSingleTargetVersion() async throws {
        // routeSegmentDistances(along:from:to:) baut denselben Streckengraphen wie
        // routeSegmentDistance(along:from:to:), löst aber mehrere Ziele in einem Dijkstra-
        // Durchlauf statt einem separaten Aufruf pro Ziel. Für ein einzelnes Ziel muss beides
        // exakt dieselbe Distanz liefern - das ist der Vertrauensanker für die neue,
        // ungetestete Mehrfachziel-Funktion, bevor sie in die Kombinationssuche einfließt.
        let repository = RouteRepository()
        let routes = repository.routesOverlapping(minLon: 8.6, minLat: 52.9, maxLon: 8.95, maxLat: 53.2)
        let route = try #require(routes.first { $0.name == "Weser-Radweg" })

        let bremen = CLLocationCoordinate2D(latitude: 53.0793, longitude: 8.8017)
        let achim = CLLocationCoordinate2D(latitude: 53.0158, longitude: 8.9525)

        let single = try #require(RouteMatcher.routeSegmentDistance(along: route.lines, from: bremen, to: achim))
        let multi = RouteMatcher.routeSegmentDistances(along: route.lines, from: bremen, to: [achim])

        #expect(multi.count == 1)
        let multiDistance = try #require(multi.first ?? nil)
        #expect(abs(multiDistance - single.distanceKm) < 0.001)

        // Zwei völlig unverbundene Liniensegmente (keine gemeinsamen Endpunkte) simulieren eine
        // echte Netzlücke - das Ziel auf dem zweiten Segment darf dann nicht erreichbar sein.
        let disconnectedLines: [[CLLocationCoordinate2D]] = [
            [
                CLLocationCoordinate2D(latitude: 53.0, longitude: 8.8),
                CLLocationCoordinate2D(latitude: 53.01, longitude: 8.81),
            ],
            [
                CLLocationCoordinate2D(latitude: 54.0, longitude: 9.8),
                CLLocationCoordinate2D(latitude: 54.01, longitude: 9.81),
            ],
        ]
        let fromOnFirstSegment = CLLocationCoordinate2D(latitude: 53.0, longitude: 8.8)
        let targetOnSecondSegment = CLLocationCoordinate2D(latitude: 54.0, longitude: 9.8)
        let withGap = RouteMatcher.routeSegmentDistances(
            along: disconnectedLines, from: fromOnFirstSegment, to: [targetOnSecondSegment]
        )
        #expect(withGap.count == 1)
        #expect(withGap[0] == nil)
    }

    @Test func junctionSidecarConnectsWeserAllerLeineHeide() async throws {
        // Schützt vor stillem Veralten von route_junctions.sqlite (manuell zu regenerierendes
        // Derivat, s. Scripts/find_route_junctions.py) - pinnt das bereits real gefahrene, per
        // Analyse bestätigte Nutzerbeispiel: Weser-Radweg <-> Aller-Radweg bei Verden,
        // Aller-Radweg <-> Leine-Heide-Radweg bei Hannover.
        let repository = RouteRepository()
        let weserRoutes = repository.routesOverlapping(minLon: 8.6, minLat: 52.9, maxLon: 8.95, maxLat: 53.2)
        let weserRadweg = try #require(weserRoutes.first { $0.name == "Weser-Radweg" })

        let allerRoutes = repository.routesOverlapping(minLon: 9.0, minLat: 52.8, maxLon: 9.3, maxLat: 53.0)
        let allerRadweg = try #require(allerRoutes.first { $0.name == "Aller-Radweg" })

        let leineRoutes = repository.routesOverlapping(minLon: 9.4, minLat: 52.6, maxLon: 9.9, maxLat: 52.9)
        let leineHeideRadweg = try #require(leineRoutes.first { $0.name == "Leine-Heide-Radweg" })

        let weserJunctions = repository.junctions(forRouteId: weserRadweg.id)
        #expect(weserJunctions.contains { $0.partnerRouteId == allerRadweg.id })

        let allerJunctions = repository.junctions(forRouteId: allerRadweg.id)
        #expect(allerJunctions.contains { $0.partnerRouteId == leineHeideRadweg.id })
    }

    @Test func combinedMatchBremenToHannoverFindsRouteChain() async throws {
        let repository = RouteRepository()
        let matcher = RouteMatcher(repository: repository)
        let bremen = CLLocationCoordinate2D(latitude: 53.0793, longitude: 8.8017)
        let hannover = CLLocationCoordinate2D(latitude: 52.3759, longitude: 9.7320)

        // Vorbedingung: keine einzelne Route deckt Bremen->Hannover direkt ab - genau der Fall,
        // in dem ContentView.runMatching() auf die Kombinationssuche zurückfällt.
        #expect(matcher.findMatches(start: bremen, end: hannover).isEmpty)

        let combined = try #require(matcher.findCombinedMatches(start: bremen, end: hannover))
        #expect(combined.legs.count >= 2)

        // Reale Rad-Distanz Bremen-Hannover über diese Fernwege liegt bei ca. 120-130 km -
        // großzügiger Plausibilitätsrahmen statt exaktem Wert (Routenwahl/OSM-Daten können sich
        // ändern), analog zu den bestehenden routeSegmentDistance-Tests.
        #expect(combined.totalDistanceKm > 80)
        #expect(combined.totalDistanceKm < 250)

        let names = combined.routeNames.joined(separator: " -> ")
        let containsExpectedRoute = combined.routeNames.contains {
            $0.localizedCaseInsensitiveContains("weser")
                || $0.localizedCaseInsensitiveContains("aller")
                || $0.localizedCaseInsensitiveContains("leine")
        }
        #expect(containsExpectedRoute, "Erwartete Weser/Aller/Leine-Radweg-Kette, bekam: \(names)")
    }

    @Test func findCombinedMatchesTerminatesWithoutImplausibleConnection() async throws {
        // Zwei Punkte ohne jede kombinierbare Route in der Nähe (mitten im offenen Meer) müssen
        // zuverlässig (und schnell, dank maxVisitedRoutes-Sicherheitsgrenze) nil liefern statt
        // endlos zu suchen oder abzustürzen.
        let repository = RouteRepository()
        let matcher = RouteMatcher(repository: repository)
        let northSea1 = CLLocationCoordinate2D(latitude: 55.5, longitude: 4.0)
        let northSea2 = CLLocationCoordinate2D(latitude: 56.0, longitude: 3.0)
        #expect(matcher.findCombinedMatches(start: northSea1, end: northSea2) == nil)
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

    /// Pfad zum lokal per `Scripts/build_way_graph.py` erzeugten Bremen-Wegegraphen. Diese Datei
    /// ist bewusst nicht Teil des Repos (großer, generierter Downloadartikel - siehe
    /// `Scripts/.gitignore`), daher wird der Test übersprungen, wenn sie fehlt (z. B. auf einem
    /// frischen Checkout ohne lokal ausgeführte Pipeline).
    private static var bremenWayGraphPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/data/bremen_ways.sqlite")
            .path
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: RadFaehrteTests.bremenWayGraphPath)))
    func bikeRoutingEnginePrefersQuietPathsOverShortestDistance() async throws {
        let repository = try #require(WayGraphRepository(path: Self.bremenWayGraphPath))
        let engine = BikeRoutingEngine(repository: repository)

        // Bremen Hauptbahnhof -> Bürgerpark (~2,5 km Luftlinie)
        let hauptbahnhof = CLLocationCoordinate2D(latitude: 53.0836, longitude: 8.8138)
        let buergerpark = CLLocationCoordinate2D(latitude: 53.0960, longitude: 8.8065)

        let result = try #require(engine.route(from: hauptbahnhof, to: buergerpark))
        let beelineMeters = CLLocation(latitude: hauptbahnhof.latitude, longitude: hauptbahnhof.longitude)
            .distance(from: CLLocation(latitude: buergerpark.latitude, longitude: buergerpark.longitude))

        #expect(result.coordinates.count > 2)
        // Die "ruhige" Route darf länger sein als die Luftlinie (normal für Straßennetze), aber
        // nicht komplett ausufern - grobe Plausibilitätsgrenze statt exaktem Vergleich, da sich
        // die Gewichtung noch feinjustieren lässt.
        #expect(result.distanceMeters >= beelineMeters)
        #expect(result.distanceMeters < beelineMeters * 2.5)
    }

}
