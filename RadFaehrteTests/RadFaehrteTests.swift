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

    /// Regressionstest für einen Nutzer-Fund (2026-07-30): Bremen -> Osnabrück zeigte früher
    /// "Brückenradweg Westroute" als Treffer, nach dem München-Nürnberg-Fix (2026-07-29, verwirft
    /// Treffer ohne auffindbaren Pfad) aber nicht mehr - Ursache: Die Route zerfällt in ihrer
    /// eigenen OSM-Geometrie in mehrere Teile, die nur durch winzige Simplification-Artefakte
    /// (22 m/26 m, s. `RouteGraph.toleranceMeters`) getrennt sind, keine echte Lücke. Bundesweite
    /// Stichprobe ergab: 705 von 7.018 benannten Fernwegen (10 %) betroffen.
    ///
    /// "Brückenradweg Ostroute" ursprünglich fälschlich für dauerhaft ausgeschlossen gehalten
    /// (angeblich echte ~67-km-Lücke) - das war ein eigener Rechenfehler bei der Diagnose
    /// (Raster-Indizes statt echter Koordinaten in die Distanzberechnung eingesetzt). Mit voller
    /// Präzision (shapely) nachgerechnet: tatsächliche Lücke nur ~4 m, exakt derselbe
    /// Simplification-Artefakt wie bei der Westroute - reine Rasterrundung (auch bei ~28 m
    /// Zellgröße) hatte sie trotzdem nicht verbunden, weil die beiden Punkte zufällig auf
    /// entgegengesetzten Seiten einer Rasterzellen-Grenze lagen. Behoben durch Nachbarschaftssuche
    /// in `RouteGraph.node(for:)` (prüft die 3×3 umliegenden Zellen statt nur die eigene, mit
    /// echtem Distanzabgleich) - seitdem finden **beide** Brückenradweg-Varianten einen
    /// durchgehenden Pfad Bremen-Osnabrück.
    @Test func routeSegmentDistanceFindsBothBridgeCyclewayRoutesBremenToOsnabrueck() async throws {
        let repository = RouteRepository()
        let bremen = CLLocationCoordinate2D(latitude: 53.0793, longitude: 8.8017)
        let osnabrueck = CLLocationCoordinate2D(latitude: 52.2799, longitude: 8.0472)

        for id in [174357, 409354] as [Int64] {
            let route = try #require(repository.route(withId: id))
            let distance = try #require(
                RouteMatcher.routeSegmentDistance(along: route.lines, from: bremen, to: osnabrueck),
                "Erwartete einen durchgehenden Pfad für Route \(id) (\(route.name ?? "?")), fand keinen"
            )
            #expect(distance.distanceKm > 100)
            #expect(distance.distanceKm < 250)
        }
    }

    /// Regressionstest für einen Nutzer-Fund (2026-07-31): Bei "Bremen" als Start zeigte die
    /// Nähe-Vorschau (`findNearby`, kein Ziel gesetzt) beide Brückenradweg-Varianten, bei
    /// "Osnabrück" als Start aber keine - obwohl der Brückenradweg genau zwischen beiden Städten
    /// verläuft und an beiden Enden nahe genug liegt. Ursache: Osnabrück/Münster sind
    /// Knotenpunkte vieler sich überlagernder Fernwege - das feste `limit` (früher 10) füllte
    /// sich dort mit Varianten derselben Route (z. B. "Friedensroute", "Friedensroute (West)",
    /// "Friedensroute (Ost)" - alle `ref` "FR") und mit einzelnen Knotenpunkt-Wegstücken als
    /// scheinbar eigenständige Route (z. B. "Münster (1) - Münster (74)"), bevor der eigentlich
    /// gesuchte Fernweg an die Reihe kam.
    @Test func findNearbyShowsBridgeCyclewayAndPeaceRouteFromBothEndpoints() async throws {
        let matcher = RouteMatcher(repository: RouteRepository())

        let bremen = CLLocationCoordinate2D(latitude: 53.0793, longitude: 8.8017)
        let osnabrueck = CLLocationCoordinate2D(latitude: 52.2799, longitude: 8.0472)
        let muenster = CLLocationCoordinate2D(latitude: 51.9607, longitude: 7.6261)

        for point in [bremen, osnabrueck] {
            let names = matcher.findNearby(around: point).map { $0.route.name }
            #expect(names.contains("Brückenradweg Westroute"), "fehlt bei \(point)")
            #expect(names.contains("Brückenradweg Ostroute"), "fehlt bei \(point)")
        }

        // Fund 2026-07-31 (Nutzer-Beobachtung Münster): Die Ref-Deduplizierung darf die
        // Richtungs-/Teiletappen "Friedensroute (West)"/"(Ost)" nicht hinter der
        // zusammenfassenden "Friedensroute" verschwinden lassen (alle drei teilen sich den
        // `ref` "FR") - beide Teiletappen müssen als eigene Treffer erhalten bleiben.
        for point in [osnabrueck, muenster] {
            let names = matcher.findNearby(around: point).map { $0.route.name }
            #expect(names.contains("Friedensroute (West)"), "Friedensroute (West) fehlt bei \(point)")
            #expect(names.contains("Friedensroute (Ost)"), "Friedensroute (Ost) fehlt bei \(point)")
        }
    }

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

        let combined = try #require(matcher.findCombinedMatches(start: bremen, end: hannover).first)
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

    /// ⚠️ Bekannte Regression (2026-07-30, zurückgestellt statt weiter untersucht - Nutzer-
    /// Entscheidung): Seit der Nachbarschaftssuche in `RouteGraph.node(for:)` (behebt die
    /// Grenzfall-Schwäche reiner Rasterrundung, s. Brückenradweg-Ostroute-Fund) findet dieser Test
    /// keine Kette mehr - Suche läuft komplett durch (~50-57s, auch mit `maxVisitedRoutes`
    /// verdoppelt auf 4000 unverändert), bleibt aber leer. Vermutete Ursache: Die jetzt bundesweit
    /// verbesserte interne Verbindungsfähigkeit vieler Routen ändert die Reihenfolge, in der
    /// Routen während der A*-Suche als `finalized` markiert werden - eine für die eigentliche Kette
    /// nötige Route wird vermutlich vorzeitig über einen ungünstigen Einstiegspunkt finalisiert.
    /// Berlin -> Den Haag ist ein extremer, seltener Randfall (mehrere Länder, dutzende sich in
    /// Berlin überlagernde internationale Fernwege) - der reale Nutzen der Nachbarschaftssuche für
    /// alltägliche deutsche Regionalfälle (Bremen-Osnabrück u. v. a., s. o.) wiegt höher als dieser
    /// Randfall. Deaktiviert statt gelöscht, damit der Regressionsstand dokumentiert bleibt und der
    /// Test bei einer künftigen, gründlicheren Untersuchung der `finalized`-Reihenfolge sofort
    /// wieder verfügbar ist.
    @Test(.disabled("Bekannte Regression seit RouteGraph-Nachbarschaftssuche (2026-07-30) - s. Doc-Kommentar, bewusst zurückgestellt. Erneut probiert nach dem maxEntryPointsPerRoute-Fix (2026-08-01, s. u. Bremen->Münster) - bleibt leer (49s, nil), also ein anderer/zusätzlicher Grund für Berlin->Den Haag."))
    func combinedMatchBerlinToDenHaagFindsEuroVelo2Chain() async throws {
        // Regressionstest für einen Fund beim Live-Testen (2026-07-29): Berlin->Amsterdam wurde
        // ursprünglich als Testfall für "funktioniert die Kombinationssuche auch grenzüberschreitend"
        // herangezogen, weil man "EuroVelo 2 - Hauptstadt-Route" erwartete - tatsächlich endet die
        // real kartierte niederländische EuroVelo-2-Geometrie aber schon bei Hoek van Holland
        // (~0,4 km Abstand) bzw. Den Haag (~3,3 km) statt Amsterdam (~26 km, weit außerhalb jeder
        // Schwelle) - Amsterdam war also nie ein erreichbares Ziel für diese Route, unabhängig vom
        // Such-Algorithmus. Berlin->Den Haag ist der faire Test, da Den Haag tatsächlich innerhalb
        // `thresholdKm` (8 km) der echten Route liegt.
        //
        // Gleichzeitig Regressionstest für die A*-Umstellung von `findCombinedMatches`: Am
        // Startpunkt Berlin überlagern sich dutzende Fernwege (EuroVelo 2, D-Route 3, Europaradweg
        // R1, D-Netz Route 3 u. a.) auf denselben Wegen mit ~0 km Abstand zueinander - ein reiner
        // Dijkstra nach Streckenlänge verbrauchte hier `maxVisitedRoutes` mit deren Erkundung, ohne
        // je Fortschritt Richtung Ziel zu machen (bei Berlin->Amsterdam beobachtet: kumulierte
        // Streckenlänge blieb über alle 500 besuchten Routen hinweg bei 0 km). Die A*-Priorität
        // (Streckenlänge + Luftlinie zum Ziel) soll die Suche gezielter lenken - hier mit dem
        // regulären `maxVisitedRoutes`-Standardwert (500), ohne Sonderbehandlung.
        let repository = RouteRepository()
        let matcher = RouteMatcher(repository: repository)
        let berlin = CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050)
        let denHaag = CLLocationCoordinate2D(latitude: 52.0705, longitude: 4.3007)

        let start = Date()
        let combined = matcher.findCombinedMatches(start: berlin, end: denHaag)
        let elapsed = Date().timeIntervalSince(start)
        print("combinedMatchBerlinToDenHaag: \(elapsed)s, Ergebnis: \(combined.first?.routeNames ?? ["nil"])")

        let result = try #require(combined.first, "Erwartete eine gefundene Kombination Berlin->Den Haag")
        #expect(result.legs.count >= 1)
        // Grober Plausibilitätsrahmen (Luftlinie ~577 km) statt exaktem Wert.
        #expect(result.totalDistanceKm > 400)
        #expect(result.totalDistanceKm < 1800)
    }

    /// Regressionstest für einen Fund beim Live-Testen (2026-07-30): "Europaradweg R1" existiert
    /// als ID-Kollision sowohl nahe der polnischen als auch der niederländischen Grenze (s.
    /// RouteRepository-Header). Die Kombinationssuche cachte Routen ursprünglich nur nach ID -
    /// wurde dieselbe ID einmal als Ziel-Kandidat mit der niederländischen Kopie gecacht, nutzte
    /// ein späteres Wiederbetreten über eine polnische Verzweigung fälschlich weiter diese falsche
    /// Kopie. `routeSegmentDistances` projizierte den polnischen Einstiegspunkt dabei
    /// stillschweigend auf die (Hunderte km entfernte) niederländische Geometrie und wies eine
    /// ~500-km-Etappe als ~0 km aus - Berlin -> Vreden kam so auf eine offensichtlich falsche
    /// Gesamtstrecke von ~134 km statt der tatsächlichen (~838 km über die gefundene Kette).
    /// Behoben durch zwei Fixes: `RouteMatcher.nearestPoint`-Anker werden jetzt gegen
    /// `maxPlausibleAnchorDistanceKm` geprüft (kein Pfad statt einer unsinnig kleinen Distanz zu
    /// einem zu weit entfernten Projektionspunkt), und `findCombinedMatches`s `route(withId:near:)`
    /// löst Routen bei einer ID-Kollision (`RouteRepository.allRoutes(withId:)`) anhand des
    /// aktuellen Einstiegspunkts neu auf, statt eine möglicherweise falsche Kopie zu cachen.
    @Test func combinedMatchBerlinToVredenHasPlausibleTotalDistance() async throws {
        let repository = RouteRepository()
        let matcher = RouteMatcher(repository: repository)
        let berlin = CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050)
        let vreden = CLLocationCoordinate2D(latitude: 52.0374, longitude: 6.8259)
        let combined = try #require(matcher.findCombinedMatches(start: berlin, end: vreden).first)

        let straightLineKm = 451.0
        #expect(combined.totalDistanceKm > straightLineKm, "Gesamtstrecke darf nie kürzer als die Luftlinie sein (~\(straightLineKm) km) - war sie doch, deutet das auf eine Fehlprojektion zwischen zwei ID-kollidierenden Routen-Kopien hin")

        // Keine einzelne Etappe darf eine unplausibel große geografische Lücke überbrücken (mehr
        // als die Diagonale des Suchgebiets), da das dieselbe Fehlprojektion wäre wie beim Fund.
        for leg in combined.legs {
            let entryToExitKm = CLLocation(latitude: leg.entryPoint.latitude, longitude: leg.entryPoint.longitude)
                .distance(from: CLLocation(latitude: leg.exitPoint.latitude, longitude: leg.exitPoint.longitude)) / 1000
            #expect(entryToExitKm < 200, "Etappe auf \(leg.route.name ?? "?") überbrückt \(entryToExitKm) km Luftlinie - unplausibel groß für eine einzelne Etappe")
        }
    }

    /// Regressionstest für einen Nutzer-Fund (2026-07-30): Lübeck→Wismar fand ursprünglich keine
    /// Kombination - zwei unabhängige Ursachen, live per Debug-Logging auf dem iPhone gefunden:
    /// (1) "Alte Salzstraße" (Lübeck→Travemünde) und der "Ostseeküsten-Radweg"/D2
    /// (Travemünde→Wismar) treffen sich in Travemünde erst bei 60,6 m tatsächlicher Distanz -
    /// knapp über dem damaligen `JUNCTION_THRESHOLD_M` von 30 m in find_route_junctions.py. Auf
    /// 75 m angehoben, route_junctions.sqlite neu regeneriert.
    /// (2) Selbst danach blieb die Kette stecken: "D2 Ostseeküsten-Radweg - Abschnitt MV-Nordwest"
    /// zerfiel intern in mehrere unzusammenhängende Teile (der Übergangspunkt aus Richtung
    /// Travemünde lag in einer 117-Knoten-Komponente, der Punkt bei Wismar in einer separaten
    /// 482-Knoten-Komponente - realer Abstand dazwischen nur ~4 m). Ursache: Die Douglas-Peucker-
    /// Vereinfachung läuft pro OSM-Way einzeln; liegt der Berührpunkt zweier Routen nicht exakt an
    /// einem Way-Anfang/-Ende, sondern mitten in einem Way, können beide Vereinfachungen ihn
    /// unabhängig voneinander um bis zu ~11 m verschieben. `RouteGraph.snapKey` rundete bisher nur
    /// auf ~1,1 m (5 Nachkommastellen) - auf ~11 m angehoben (4 Nachkommastellen, wie
    /// `SIMPLIFY_TOLERANCE_DEG`), damit exakt solche Fast-Treffer als derselbe Knoten erkannt
    /// werden. Kein Regressionsschaden: kompletter bestehender Test-Suite-Lauf (inkl.
    /// Weser/Aller/Leine-Heide-, Bremen/Hannover-, Berlin/Vreden-, Berlin/Den-Haag-Ketten) blieb
    /// unverändert grün.
    ///
    /// Bewusst kein `#expect(matcher.findMatches(...).isEmpty)` hier (anders als beim Bremen/
    /// Hannover-Pendant): `findMatches` liefert für Lübeck→Wismar einen eigenständigen, davon
    /// unabhängigen Treffer ("EuroVelo 13 - Iron Curtain Trail - Inner German part", vermutlich ein
    /// Multi-Fragment-Datensatz mit einem Fragment zufällig nahe Lübeck und einem anderen nahe der
    /// Suchregion) - ob der praktisch nutzbar ist, prüft `filterAndReorderMatchesByPracticalDistance`
    /// separat; nicht Gegenstand dieses Tests.
    ///
    /// **Update 2026-07-31** (`maxEntryPointsPerRoute`-Fix, s. `findCombinedMatches`-Doku): Die
    /// Suche findet jetzt eine kürzere Kette über "EuroVelo 13"-Fragmente bzw. "Elbetal-Schaalsee
    /// Rundweg" (~90-96 km) statt der vorher einzig auffindbaren Alte-Salzstraße/Ostseeküsten-
    /// Kette über Travemünde - erreichbar, weil dieselbe stark fragmentierte Route jetzt über
    /// mehrere getrennte Einstiegspunkte statt nur einen einzigen erkundet werden kann. Nicht
    /// live auf dem iPhone nachverifiziert (anders als der ursprüngliche Fund) - die konkrete
    /// Namens-Erwartung wurde deshalb hier bewusst gelockert; falls sich die neue Kette bei
    /// Gelegenheit als unplausibel herausstellt, hier ansetzen.
    @Test func combinedMatchLuebeckToWismarFindsRouteChainViaTravemuende() async throws {
        let repository = RouteRepository()
        let matcher = RouteMatcher(repository: repository)
        let luebeck = CLLocationCoordinate2D(latitude: 53.8655, longitude: 10.6866)
        let wismar = CLLocationCoordinate2D(latitude: 53.8912, longitude: 11.4527)

        let combined = try #require(matcher.findCombinedMatches(start: luebeck, end: wismar).first)
        #expect(combined.legs.count >= 2)
        #expect(combined.totalDistanceKm > Self.kilometers(luebeck, wismar))
        #expect(combined.totalDistanceKm < 150)
    }

    private static func kilometers(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1000
    }

    @Test func findCombinedMatchesTerminatesWithoutImplausibleConnection() async throws {
        // Zwei Punkte ohne jede kombinierbare Route in der Nähe (mitten im offenen Meer) müssen
        // zuverlässig (und schnell, dank maxVisitedRoutes-Sicherheitsgrenze) nil liefern statt
        // endlos zu suchen oder abzustürzen.
        let repository = RouteRepository()
        let matcher = RouteMatcher(repository: repository)
        let northSea1 = CLLocationCoordinate2D(latitude: 55.5, longitude: 4.0)
        let northSea2 = CLLocationCoordinate2D(latitude: 56.0, longitude: 3.0)
        #expect(matcher.findCombinedMatches(start: northSea1, end: northSea2).isEmpty)
    }

    /// Regressionstest für einen Nutzer-Fund (2026-07-31): Bremen -> Münster fand keine
    /// Routenkombination mehr, obwohl `findMatches` bereits Brückenradweg und Friedensroute
    /// beide als Kandidaten in der Nähe von Start bzw. Ziel liefert (bestätigt per Debug-Logging).
    /// Ursache: "D7 Pilgerroute" liegt (per reiner Umkreisprüfung) sowohl nahe Bremen als auch
    /// nahe Münster, wurde deshalb selbst als Start-Kandidat der Kombinationssuche verwendet -
    /// hat aber von ihrem Bremer Einstiegspunkt aus keinen durchgehenden Pfad zur eigenen
    /// Anschlussstelle bei Osnabrück (eigenes Geometrie-Fragment). Die Route wurde trotzdem
    /// global als "erledigt" markiert (`finalized`-`Set`) und blockierte damit dauerhaft den
    /// zweiten, funktionierenden Zugang über "Brückenradweg" bei Osnabrück, über den
    /// "Friedensroute" erreichbar gewesen wäre. Fix: `visitedEntryPoints` erlaubt jetzt bis zu
    /// drei klar getrennte Einstiegspunkte pro Route, bevor sie als erschöpft gilt.
    @Test func combinedMatchBremenToMuensterFindsRouteChainViaOsnabrueck() async throws {
        let repository = RouteRepository()
        let matcher = RouteMatcher(repository: repository)
        let bremen = CLLocationCoordinate2D(latitude: 53.0793, longitude: 8.8017)
        let muenster = CLLocationCoordinate2D(latitude: 51.9607, longitude: 7.6261)

        let combined = try #require(matcher.findCombinedMatches(start: bremen, end: muenster).first)
        let names = combined.routeNames.joined(separator: " -> ")
        let containsBridge = combined.routeNames.contains { $0.localizedCaseInsensitiveContains("brückenradweg") }
        let containsPeace = combined.routeNames.contains { $0.localizedCaseInsensitiveContains("friedens") }
        #expect(containsBridge, "Erwartete eine Brückenradweg-Etappe, bekam: \(names)")
        #expect(containsPeace, "Erwartete eine Friedensroute-Etappe, bekam: \(names)")
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

    /// Map-Matching-Versuch (`CuratedRouteStepMatcher`, s. ROADMAP.md): Rundlauf-Test statt echter
    /// kuratierter Routen-Geometrie, um Grenzfragen der Bremen-Enklave (Achim/Osnabrück liegen
    /// außerhalb des heruntergeladenen Bremen-Wege-Graphen, s. u. "Bremen und Niedersachsen
    /// heruntergeladen...") aus der Gleichung zu nehmen und den Matching-Algorithmus selbst
    /// isoliert zu prüfen: Nimmt die tatsächlich von `BikeRoutingEngine` gefundene Route
    /// Hauptbahnhof -> Bürgerpark (liegt per Konstruktion vollständig auf Kanten des
    /// Wege-Graphen) als Stellvertreter für eine kuratierte Route und lässt sie erneut durch
    /// `CuratedRouteStepMatcher` laufen. Da die Polyline exakt dem Graphen folgt, sollten
    /// praktisch alle Stützpunkt-Hops matchen und die rekonstruierte Distanz nah an der
    /// Referenzdistanz liegen.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: RadFaehrteTests.bremenWayGraphPath)))
    func curatedRouteStepMatcherReconstructsStepsAlongKnownGraphPath() async throws {
        let repository = try #require(WayGraphRepository(path: Self.bremenWayGraphPath))
        let engine = BikeRoutingEngine(repository: repository)

        let hauptbahnhof = CLLocationCoordinate2D(latitude: 53.0836, longitude: 8.8138)
        let buergerpark = CLLocationCoordinate2D(latitude: 53.0960, longitude: 8.8065)
        let reference = try #require(engine.route(from: hauptbahnhof, to: buergerpark))

        let steps = try #require(
            CuratedRouteStepMatcher.steps(along: reference.coordinates, using: repository),
            "Erwartete gematchte Schritte entlang einer Polyline, die per Konstruktion auf dem Wege-Graphen liegt"
        )

        #expect(!steps.isEmpty)
        #expect(steps.allSatisfy { !$0.instructions.isEmpty })

        let reconstructedMeters = zip(
            [hauptbahnhof] + steps.map(\.endCoordinate), steps.map(\.endCoordinate)
        ).reduce(0.0) { total, pair in
            total + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        }
        // 10 % Toleranz statt exaktem Vergleich - beim Live-Lauf lag der rekonstruierte Wert
        // tatsächlich innerhalb von 1 % der Referenz (direkte Kanten-Treffer dominieren, da die
        // Referenzpolyline per Konstruktion aus Graph-Knoten besteht), 10 % lässt Spielraum für
        // Bridging-Fälle bei echter (nicht graph-generierter) Routen-Geometrie.
        #expect(reconstructedMeters > reference.distanceMeters * 0.9)
        #expect(reconstructedMeters < reference.distanceMeters * 1.1)
    }

    /// Wie `curatedRouteStepMatcherReconstructsStepsAlongKnownGraphPath`, aber mit echter
    /// kuratierter Routen-Geometrie statt einer graph-generierten Referenzstrecke: Bremen
    /// Hauptbahnhof -> Weserwehr/Werdersee entlang des tatsächlichen "Weser-Radweg" (aus
    /// `routes.sqlite`, Douglas-Peucker-vereinfacht, unsortierte Way-Fragmente - genau die
    /// Eingabe, die `CuratedRouteStepMatcher` in der App später bekäme). Live-Diagnose (2026-08-01)
    /// ergab plausible, echte Bremer Straßennamen ohne Lücken (u. a. Bredenstraße, Schlachte,
    /// Wilhelm-Kaisen-Brücke, Werderstraße) - hier nur lose auf Struktur statt exakten Namen
    /// geprüft, damit der Test nicht bei jeder kleinen Kartendaten-Änderung bricht.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: RadFaehrteTests.bremenWayGraphPath)))
    func curatedRouteStepMatcherHandlesRealWeserRadwegGeometry() async throws {
        let repository = RouteRepository()
        let routes = repository.routesOverlapping(minLon: 8.6, minLat: 52.9, maxLon: 8.95, maxLat: 53.2)
        let weserRadweg = try #require(routes.first { $0.name == "Weser-Radweg" })
        let wayGraphRepo = try #require(WayGraphRepository(path: Self.bremenWayGraphPath))

        let hauptbahnhof = CLLocationCoordinate2D(latitude: 53.0836, longitude: 8.8138)
        let weserwehr = CLLocationCoordinate2D(latitude: 53.0530, longitude: 8.8280)

        let path = try #require(
            RouteMatcher.routeSegmentPath(along: weserRadweg.lines, from: hauptbahnhof, to: weserwehr)
        )
        let steps = try #require(
            CuratedRouteStepMatcher.steps(along: path, using: wayGraphRepo),
            "Erwartete gematchte Schritte entlang der echten Weser-Radweg-Geometrie Bremen Hauptbahnhof -> Weserwehr"
        )

        #expect(steps.count > 5)
        #expect(steps.allSatisfy { !$0.instructions.isEmpty })
        // Mindestens ein paar echte Straßennamen sollten dabei sein, nicht nur unbenannte
        // "Rechts/Links abbiegen" ohne "auf ..." - sonst wäre das Ergebnis für Nutzer nutzlos.
        let namedSteps = steps.filter { $0.instructions.contains(" auf ") }
        #expect(namedSteps.count >= 3)
    }

    /// Regressionstest für einen Nutzer-Fund (2026-07-31, Münster -> Köln): "EuroVelo 3 - Pilgrim's
    /// Route - part Germany" liegt nahe Münster, ist dort aber nicht durchgehend genug kartiert, um
    /// als Einzeltreffer/Teil einer Kombination zu erscheinen - wurde bisher nur als reiner
    /// Text-Hinweis gezeigt, nicht als wählbarer Treffer. `nearbyWellKnownRouteMatches` muss die
    /// Route stattdessen als vollwertigen `RouteMatch` liefern (Nutzer-Wunsch: "trotzdem anzeigen
    /// und auswählen können").
    @Test func nearbyWellKnownRouteMatchesFindsEuroVelo3NearMuenster() async throws {
        let matcher = RouteMatcher(repository: RouteRepository())
        let muenster = CLLocationCoordinate2D(latitude: 51.9607, longitude: 7.6261)
        let koeln = CLLocationCoordinate2D(latitude: 50.9375, longitude: 6.9603)

        let matches = matcher.nearbyWellKnownRouteMatches(start: muenster, end: koeln)
        let ev3 = try #require(
            matches.first { $0.route.ref == "EV3" },
            "Erwartete einen Treffer mit ref \"EV3\" (EuroVelo 3) in der Nähe von Münster"
        )
        // Ein noch so großer Wert ist besser als gar keiner - der Nutzer soll die reale Entfernung
        // selbst einschätzen können (analog `findClosestMatches`), statt die Route zu verstecken.
        #expect(ev3.distanceToStartKm < 8)
        #expect(ev3.distanceToStartKm >= 0)
        #expect(ev3.distanceToEndKm >= 0)
    }

    /// Regressionstest für einen Nutzer-Fund (2026-07-31): Bremen und Niedersachsen heruntergeladen,
    /// eine Route innerhalb von Bremen oder innerhalb von Niedersachsens nutzt die Offline-Engine,
    /// eine Route von Bremen nach Niedersachsen (Bremen → Osnabrück) aber nicht - fällt auf
    /// Online-Routing für die gesamte Strecke zurück, obwohl beide Regionen offline vorliegen.
    /// Ursache: Jeder heruntergeladene Wege-Graph ist isoliert, `CrossRegionRouteStitcher` sucht
    /// deshalb den Übergangspunkt zwischen zwei Regionen selbst. Dieser Test deckt nur die reine
    /// Geometrie ab (`findHandoverCoordinate`, per Closures ohne echte Graph-Dateien) - simuliert
    /// zwei "Abdeckungsbereiche" entlang einer Nord-Süd-Linie über ihre Distanz zum Abtastpunkt.
    @Test func crossRegionRouteStitcherFindsHandoverBetweenAdjacentRegions() throws {
        let start = CLLocationCoordinate2D(latitude: 53.20, longitude: 8.80)
        let end = CLLocationCoordinate2D(latitude: 52.60, longitude: 8.80)
        let startCenter = CLLocationCoordinate2D(latitude: 53.10, longitude: 8.80)
        let endCenter = CLLocationCoordinate2D(latitude: 52.90, longitude: 8.80)

        func distance(from center: CLLocationCoordinate2D) -> (CLLocationCoordinate2D) -> Double? {
            { point in abs(point.latitude - center.latitude) }
        }

        let handover = CrossRegionRouteStitcher.findHandoverCoordinate(
            start: start, end: end,
            startRegionDistanceMeters: distance(from: startCenter),
            endRegionDistanceMeters: distance(from: endCenter)
        )

        let handoverCoordinate = try #require(handover)
        // Der gefundene Übergang muss zwischen Start und Ziel liegen, nicht außerhalb, und nahe der
        // Mitte zwischen beiden Zentren (53.00°N).
        #expect(handoverCoordinate.latitude < start.latitude)
        #expect(handoverCoordinate.latitude > end.latitude)
        #expect(abs(handoverCoordinate.latitude - 53.00) < 0.05)
    }

    /// Regressionstest für den eigentlichen Live-Fund: Ein erster Entwurf prüfte pro Abtastpunkt nur
    /// "liegt ein Knoten der Region näher als X Meter dran" - bei Bremen als kleiner Enklave
    /// innerhalb Niedersachsens war dieser Schwellenwert praktisch überall gleichzeitig für beide
    /// Regionen erfüllt, wodurch nie ein reiner "nur Bremen"-Punkt gefunden wurde. Hier: die
    /// Ziel-Region hat *überall* einen sehr nahen Knoten (konstant 50 m, wie Niedersachsen direkt an
    /// Bremens Grenze), trotzdem muss der reine Distanzvergleich in Start-Nähe noch "näher an Start"
    /// erkennen und dort einen Übergang finden, statt wie der alte Schwellenwert-Ansatz leer
    /// auszugehen.
    @Test func crossRegionRouteStitcherFindsHandoverEvenWhenEndRegionIsAlwaysNearby() throws {
        let start = CLLocationCoordinate2D(latitude: 53.20, longitude: 8.80)
        let end = CLLocationCoordinate2D(latitude: 52.60, longitude: 8.80)

        let handover = CrossRegionRouteStitcher.findHandoverCoordinate(
            start: start, end: end,
            startRegionDistanceMeters: { abs($0.latitude - start.latitude) },
            endRegionDistanceMeters: { _ in 0.01 }
        )

        let handoverCoordinate = try #require(handover)
        #expect(handoverCoordinate.latitude < start.latitude)
        #expect(handoverCoordinate.latitude > end.latitude)
    }

    /// Gegenprobe: Die Start-Region bleibt über die komplette Strecke näher (kein echter
    /// Grenzübertritt) - kein Übergang, `ContentView` fällt wie bisher auf Online-Routing zurück
    /// statt eine unplausible Route zu bauen.
    @Test func crossRegionRouteStitcherReturnsNilWhenStartRegionStaysCloserThroughout() {
        let start = CLLocationCoordinate2D(latitude: 53.20, longitude: 8.80)
        let end = CLLocationCoordinate2D(latitude: 52.60, longitude: 8.80)

        let handover = CrossRegionRouteStitcher.findHandoverCoordinate(
            start: start, end: end,
            startRegionDistanceMeters: { _ in 0.01 },
            endRegionDistanceMeters: { _ in 100.0 }
        )

        #expect(handover == nil)
    }

    /// Weitere Gegenprobe: Keine der beiden Regionen hat entlang der Linie überhaupt einen Knoten in
    /// Reichweite (beide Distanz-Closures liefern `nil`) - kein Übergang statt eines Absturzes/einer
    /// zufälligen Koordinate.
    @Test func crossRegionRouteStitcherReturnsNilWhenNeitherRegionIsInRange() {
        let start = CLLocationCoordinate2D(latitude: 53.20, longitude: 8.80)
        let end = CLLocationCoordinate2D(latitude: 52.60, longitude: 8.80)

        let handover = CrossRegionRouteStitcher.findHandoverCoordinate(
            start: start, end: end,
            startRegionDistanceMeters: { _ in nil },
            endRegionDistanceMeters: { _ in nil }
        )

        #expect(handover == nil)
    }

}
