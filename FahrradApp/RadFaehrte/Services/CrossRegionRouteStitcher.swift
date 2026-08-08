//
//  CrossRegionRouteStitcher.swift
//  RadFaehrte
//

import CoreLocation

/// Verbindet zwei Offline-Wege-Graphen (`WayGraphRepository`) unterschiedlicher heruntergeladener
/// Regionen (Bundesländer/Länder) zu einer durchgehenden Route, wenn Start und Ziel in
/// unterschiedlichen Regionen liegen. Jeder heruntergeladene Graph ist ein eigenständiger,
/// isolierter Knoten-/Kanten-Raum ohne jede Verbindung zum Nachbargraphen an der Landesgrenze (s.
/// `WayGraphRepository`-Typ-Dokumentation) - `BikeRoutingEngine.routes` findet deshalb nie einen
/// Pfad, wenn `start` und `end` nicht im selben Graphen liegen, und `ContentView` fiel bisher in
/// diesem Fall komplett auf Online-Routing für die gesamte Strecke zurück, statt beide Abschnitte
/// weiterhin offline zu berechnen (s. ROADMAP.md, "Ruhige-Wege-Offline-Routing pro Bundesland").
///
/// Statt die beiden Graphen echt zu verschmelzen (Knoten aus unabhängig zugeschnittenen
/// Geofabrik-Extrakten müssten dafür anhand ihrer Koordinaten am Rand einander zugeordnet werden -
/// deutlich aufwendiger, für unklaren Zusatznutzen), sucht dieser Typ näherungsweise die Stelle, an
/// der die Luftlinie zwischen Start und Ziel von der einen in die andere Region übertritt, snappt
/// dort unabhängig in beiden Graphen auf den nächstgelegenen Knoten und lässt `BikeRoutingEngine`
/// zwei unabhängige Teilrouten (Start → Übergang, Übergang → Ziel) berechnen, die anschließend
/// aneinandergereiht werden. Die kleine Lücke zwischen den beiden unabhängig gesnappten
/// Übergangspunkten bleibt eine kurze Luftlinie (auf einer echten Grenzstraße typischerweise
/// deutlich unter 100 m) - analog zu den bereits an anderer Stelle akzeptierten kleinen Sprüngen an
/// Kanten-Übergängen (s. `BikeRoutingEngine.displayCoordinates`).
///
/// ⚠️ Bewusst **kein** fester "Abdeckungsradius" (z. B. "liegt ein Knoten der Region X innerhalb von
/// 5 km?"): Erster Entwurf funktionierte genau am Auslöse-Fall nicht (Bremen → Osnabrück, Live-Test
/// 2026-07-31) - Bremen ist als Stadtstaat so klein (~20 km Durchmesser), dass praktisch jeder Punkt
/// darin bereits innerhalb jedes plausiblen Radius auch "von Niedersachsen abgedeckt" war (Bremen
/// ist eine Enklave, Niedersachsen grenzt auf allen Seiten direkt an) - es gab dadurch nie einen
/// Abtastpunkt, der *nur* zu Bremen gehörte, und die Suche ging leer aus (→ stiller Fallback auf
/// Online-Routing). Robuster: pro Abtastpunkt nicht "ist Region X nah genug", sondern "welche der
/// beiden Regionen hat den näheren Knoten" - der Übergang ist die Stelle, an der sich das entlang
/// der Linie erstmals umdreht. Funktioniert unabhängig davon, wie stark sich die Abdeckungsbereiche
/// beider Regionen überlappen.
nonisolated enum CrossRegionRouteStitcher {
    /// Anzahl Abtastpunkte entlang der Luftlinie zwischen Start und Ziel - grob genug für
    /// Städte-Distanzen (wenige km bis wenige hundert km), ohne dass die Gesamtkosten (jeder Punkt
    /// kostet einen `nearestNode`-Scan in beiden Graphen) spürbar ausufern.
    private static let sampleCount = 60

    /// Suchradius beim Abtasten der Luftlinie (s. `findHandoverCoordinate`) - großzügig, damit für
    /// jeden Abtastpunkt in der Nähe der tatsächlichen Grenze ein Knoten in beiden Graphen gefunden
    /// wird (bestimmt hier nur, *wie weit* ein Knoten entfernt sein darf, nicht ob ein Punkt "zu"
    /// einer Region gehört - das übernimmt der direkte Distanzvergleich, s. Typ-Dokumentation).
    private static let sampleSearchRadiusMeters = 20_000.0

    /// Suchradius für das abschließende Snappen des gefundenen Übergangspunkts auf einen echten
    /// Graph-Knoten - enger als `sampleSearchRadiusMeters`, da hier tatsächlich ein nahes
    /// Straßenstück gebraucht wird, kein bloßer Distanzvergleich.
    private static let handoverSnapMeters = 5000.0

    /// Maximal akzeptierte Lücke zwischen den beiden unabhängig gesnappten Übergangspunkten. Größere
    /// Lücken deuten darauf hin, dass die abgetastete Übergangsstelle nicht in der Nähe einer
    /// echten, beide Regionen verbindenden Straße lag (z. B. Feld/Wald ohne Wegedaten) - in dem Fall
    /// lieber sauber auf Online-Routing zurückfallen als eine hässliche lange Luftlinie anzuzeigen.
    /// Testweise auf 2500 m angehoben und live geprüft (2026-08-02, Cuxhaven -> Hamburg, Übergang
    /// Niedersachsen -> Schleswig-Holstein an der Elbe mit 2016 m) - dabei aber festgestellt, dass
    /// die eigentliche Blockade dort gar nicht der Gap war, sondern ein davon unabhängiger
    /// Wege-Graph-Fehler (s. ROADMAP.md, "Wege-Graph Niedersachsen: Cuxhaven vom Rest der Region
    /// getrennt"). Ohne live bestätigten Nutzen für einen größeren Wert deshalb zurück auf den
    /// ursprünglichen, gegen den Bremen/Osnabrück-Fall kalibrierten Wert.
    private static let maxHandoverGapMeters = 1500.0

    /// Höheres `BikeRoutingEngine.maxVisitedNodes`-Limit für die beiden Teilstrecken (Start →
    /// Übergang, Übergang → Ziel) als der sonstige Standard (300.000, kalibriert für lokale
    /// Städte-Routen). Eine Teilstrecke quer durch ein großes Bundesland kann leicht 50-100 km lang
    /// sein (z. B. Bremen → Osnabrück: ~97 km allein im Niedersachsen-Abschnitt) und dabei mehr
    /// Knoten berühren als der Standard erlaubt - live auf dem Gerät als stiller Fehlschlag der
    /// zweiten Teilstrecke beobachtet (2026-07-31), obwohl ein Pfad existierte.
    ///
    /// Von 1.500.000 auf 3.000.000 angehoben (Live-Fund 2026-08-06, Bremen → Neumünster über
    /// Niedersachsen → Schleswig-Holstein): Per Debug-Ausgabe bestätigt, dass die längere der beiden
    /// `chainedRoute`-Teilstrecken (durch einen Großteil Niedersachsens, 6,5 Mio. Knoten insgesamt)
    /// exakt am alten Limit abbrach (`SearchOutcome.nodeLimitExceeded`, nicht die zunächst vermutete
    /// Graph-Insel - deren BFS-Verifikation stand bereits vorher fest, s. ROADMAP.md "Isolierte
    /// Graph-Inseln... beheben").
    private static let legMaxVisitedNodes = 3_000_000

    /// Findet näherungsweise die Koordinate, an der die Luftlinie von `start` nach `end` erstmals von
    /// "Start-Region ist näher" zu "Ziel-Region ist näher" wechselt. `startRegionDistanceMeters`/
    /// `endRegionDistanceMeters` sind bewusst Closures statt konkreter `WayGraphRepository`-
    /// Parameter - hält die eigentliche Such-Logik als reine, unabhängig testbare Geometrie (s.
    /// `RadFaehrteTests`), unabhängig davon, wie die Distanz tatsächlich ermittelt wird (in
    /// `combinedRoute` per `nearestNode`). `nil` für einen Abtastpunkt bedeutet "diese Region hat
    /// dort gar keinen Knoten in Reichweite".
    ///
    /// `nil`, wenn entlang der Linie kein solcher Wechsel gefunden wird (z. B. weil die Regionen dort
    /// gar nicht aneinandergrenzen).
    static func findHandoverCoordinate(
        start: CLLocationCoordinate2D, end: CLLocationCoordinate2D,
        startRegionDistanceMeters: (CLLocationCoordinate2D) -> Double?,
        endRegionDistanceMeters: (CLLocationCoordinate2D) -> Double?
    ) -> CLLocationCoordinate2D? {
        var previousSample: CLLocationCoordinate2D?
        var previousCloserToStart: Bool?

        for i in 0...sampleCount {
            let t = Double(i) / Double(sampleCount)
            let sample = CLLocationCoordinate2D(
                latitude: start.latitude + (end.latitude - start.latitude) * t,
                longitude: start.longitude + (end.longitude - start.longitude) * t
            )

            let closerToStart: Bool
            switch (startRegionDistanceMeters(sample), endRegionDistanceMeters(sample)) {
            case let (.some(startDistance), .some(endDistance)): closerToStart = startDistance <= endDistance
            case (.some, nil): closerToStart = true
            case (nil, .some): closerToStart = false
            case (nil, nil): continue // Keine der beiden Regionen hat hier überhaupt einen Knoten in Reichweite.
            }

            if previousCloserToStart == true, !closerToStart, let previousSample {
                return CLLocationCoordinate2D(
                    latitude: (previousSample.latitude + sample.latitude) / 2,
                    longitude: (previousSample.longitude + sample.longitude) / 2
                )
            }
            previousCloserToStart = closerToStart
            previousSample = sample
        }
        return nil
    }

    /// Höchste akzeptierte Kettenlänge für `findHandoverSequence`/`chainedRoute` - eine Strecke, die
    /// laut Luftlinien-Abtastung mehr als sechs verschiedene Regionen durchquert, ist entweder eine
    /// geografisch extreme Ausnahme (quer durchs ganze Land) oder ein Zeichen einer instabilen
    /// Abtastung an mehreren wackligen Grenzen - in beiden Fällen lieber sauber auf Online-Routing
    /// zurückfallen als sechs oder mehr Teilrouten zu je bis zu `legMaxVisitedNodes` Knoten zu
    /// berechnen.
    private static let maxChainLength = 6

    /// Wie `findHandoverCoordinate`, aber für Ketten aus beliebig vielen (statt nur zwei) Regionen -
    /// z. B. eine Strecke, die zwischen Start und Ziel eine dritte Region mittig durchquert, ohne
    /// dass diese selbst Start oder Ziel enthält (Live-Fund 2026-08-02: Cuxhaven -> Hamburg verläuft
    /// über Niedersachsen -> Schleswig-Holstein -> Hamburg). Ermittelt für jeden Abtastpunkt entlang
    /// der Luftlinie, welche der `regionDistanceMeters`-Closures (ein Eintrag je Kandidatenregion,
    /// Reihenfolge frei wählbar, vom Aufrufer über den zurückgegebenen Index wieder aufzulösen) dort
    /// den nächsten Knoten liefert, und fasst aufeinanderfolgende gleiche Regionen zu einer
    /// geordneten Kette von Regions-Indizes zusammen. Reine, unabhängig testbare Geometrie (s.
    /// Typ-Dokumentation) - das tatsächliche Snappen der Übergänge/Berechnen der Teilrouten
    /// übernimmt `chainedRoute`.
    ///
    /// Mindestanzahl aufeinanderfolgender Abtastpunkte, die dieselbe Region "gewinnen" muss, bevor
    /// `findHandoverSequence` das als echten Regionswechsel zählt statt als Rauschen. Live-Fund
    /// (Cuxhaven -> Hamburg, 2026-08-02): An der stark verwinkelten Grenze zwischen Schleswig-
    /// Holstein und Hamburg (Wedel/Rissen) kippte ein einzelner Abtastpunkt zurück zu
    /// Schleswig-Holstein, nachdem die Kette schon zu Hamburg gewechselt war - ohne Entprellung
    /// erschien Schleswig-Holstein dadurch zweimal in der rohen Kette (`[Niedersachsen,
    /// Schleswig-Holstein, Hamburg, Schleswig-Holstein, Hamburg]`) und wurde komplett verworfen,
    /// obwohl die eigentliche Kette (Niedersachsen -> Schleswig-Holstein -> Hamburg) korrekt war.
    private static let minRunLength = 2

    /// `nil`, wenn die (entprellte) Kette weniger als drei Regionen umfasst (der einfachere
    /// Zwei-Regionen-Fall deckt `findHandoverCoordinate`/`combinedRoute` bereits ab), länger als
    /// `maxChainLength` ist, oder eine Region trotz Entprellung mehrfach auftaucht (Zeichen einer
    /// tatsächlich instabilen Abtastung, nicht nur eines einzelnen Ausreißers - ein falscher
    /// Zwischen-Hop wäre schlimmer als der bestehende Online-Fallback).
    static func findHandoverSequence(
        start: CLLocationCoordinate2D, end: CLLocationCoordinate2D,
        regionDistanceMeters: [(CLLocationCoordinate2D) -> Double?]
    ) -> [Int]? {
        guard regionDistanceMeters.count >= 2 else { return nil }

        var perSample: [Int] = []
        for i in 0...sampleCount {
            let t = Double(i) / Double(sampleCount)
            let sample = CLLocationCoordinate2D(
                latitude: start.latitude + (end.latitude - start.latitude) * t,
                longitude: start.longitude + (end.longitude - start.longitude) * t
            )

            var bestIndex: Int?
            var bestDistance = Double.infinity
            for (index, distanceMeters) in regionDistanceMeters.enumerated() {
                guard let candidateDistance = distanceMeters(sample), candidateDistance < bestDistance else { continue }
                bestDistance = candidateDistance
                bestIndex = index
            }
            guard let bestIndex else { continue } // Keine Region hat hier überhaupt einen Knoten in Reichweite.
            perSample.append(bestIndex)
        }

        struct Run { var region: Int; var length: Int }
        var runs: [Run] = []
        for region in perSample {
            if runs.last?.region == region { runs[runs.count - 1].length += 1 } else { runs.append(Run(region: region, length: 1)) }
        }

        // Kurze Zwischen-Läufe (< minRunLength Abtastpunkte) sind Rauschen an einer verwinkelten
        // Grenze, kein echter Regionswechsel - werden in einen Nachbarlauf verschmolzen (bevorzugt
        // den vorherigen, sonst den nachfolgenden), bis keine kurzen Läufe mehr übrig sind. Jeder
        // Durchlauf entfernt mindestens einen Lauf, terminiert also spätestens nach `runs.count`
        // Durchläufen.
        while runs.count > 1, let shortIndex = runs.firstIndex(where: { $0.length < minRunLength }) {
            let mergeInto = shortIndex > 0 ? shortIndex - 1 : shortIndex + 1
            runs[mergeInto].length += runs[shortIndex].length
            runs.remove(at: shortIndex)
            // Direkt benachbarte gleiche Regionen nach dem Verschmelzen wieder zusammenfassen (kann
            // durch das Entfernen entstehen, s. Typ-Dokumentation).
            var i = 0
            while i + 1 < runs.count {
                if runs[i].region == runs[i + 1].region {
                    runs[i].length += runs[i + 1].length
                    runs.remove(at: i + 1)
                } else {
                    i += 1
                }
            }
        }

        let chain = runs.map(\.region)
        guard chain.count >= 3, chain.count <= maxChainLength, Set(chain).count == chain.count else { return nil }
        return chain
    }

    /// Berechnet eine durchgehende Offline-Route von `start` (in `startRepository`) nach `end` (in
    /// `endRepository`) über einen gemeinsamen Übergangspunkt. `nil`, wenn kein plausibler Übergang
    /// gefunden wird, dort keiner der beiden Graphen einen nahen Knoten hat, die gesnappten Punkte zu
    /// weit auseinanderliegen, oder eine der beiden Teilrouten selbst fehlschlägt - `ContentView`
    /// fällt in all diesen Fällen wie bisher auf Online-Routing zurück.
    static func combinedRoute(
        start: CLLocationCoordinate2D, end: CLLocationCoordinate2D,
        startRepository: WayGraphRepository, endRepository: WayGraphRepository,
        endRegionDisplayName: String
    ) -> BikeRoutingEngine.Result? {
        func distance(in repository: WayGraphRepository, to coordinate: CLLocationCoordinate2D) -> Double? {
            guard let node = repository.nearestNode(to: coordinate, maxDistanceMeters: sampleSearchRadiusMeters) else { return nil }
            let location = repository.nodeLocations[node]
            return CLLocation(latitude: location.latitude, longitude: location.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }

        guard let handover = findHandoverCoordinate(
            start: start, end: end,
            startRegionDistanceMeters: { distance(in: startRepository, to: $0) },
            endRegionDistanceMeters: { distance(in: endRepository, to: $0) }
        ) else { return nil }

        guard let startNode = startRepository.nearestNode(to: handover, maxDistanceMeters: handoverSnapMeters),
              let endNode = endRepository.nearestNode(to: handover, maxDistanceMeters: handoverSnapMeters)
        else { return nil }

        let handoverInStart = startRepository.nodeLocations[startNode]
        let handoverInEnd = endRepository.nodeLocations[endNode]
        let gap = CLLocation(latitude: handoverInStart.latitude, longitude: handoverInStart.longitude)
            .distance(from: CLLocation(latitude: handoverInEnd.latitude, longitude: handoverInEnd.longitude))
        guard gap < maxHandoverGapMeters else { return nil }

        // `endMaxDistanceMeters`/`startMaxDistanceMeters` auf `handoverSnapMeters` statt dem engeren
        // Standard: Der Übergangspunkt ist nur eine grobe geometrische Näherung, keine reale
        // Adresse, und darf deshalb weiter zu einem tatsächlich gut angebundenen Knoten wandern (s.
        // Doku an `BikeRoutingEngine.defaultEndpointMaxDistanceMeters`) - `start`/`end` selbst
        // bleiben beim engen Standardradius.
        guard let leg1 = BikeRoutingEngine(repository: startRepository).route(
                from: start, to: handoverInStart, maxVisitedNodes: legMaxVisitedNodes,
                endMaxDistanceMeters: handoverSnapMeters),
              let leg2 = BikeRoutingEngine(repository: endRepository).route(
                from: handoverInEnd, to: end, maxVisitedNodes: legMaxVisitedNodes,
                startMaxDistanceMeters: handoverSnapMeters)
        else { return nil }

        let transitionStep = BikeRoutingEngine.Result.Step(
            instructions: "Weiter in \(endRegionDisplayName)", endCoordinate: handoverInEnd, direction: .straight
        )
        return BikeRoutingEngine.Result(
            coordinates: leg1.coordinates + leg2.coordinates,
            distanceMeters: leg1.distanceMeters + gap + leg2.distanceMeters,
            steps: leg1.steps + [transitionStep] + leg2.steps
        )
    }

    /// Wie `combinedRoute`, aber für Ketten aus drei oder mehr Regionen (s. `findHandoverSequence`) -
    /// wird von `ContentView.crossRegionOfflineDirectRoute` erst versucht, nachdem der einfachere
    /// Zwei-Regionen-Versuch (`combinedRoute`) für jedes Start-/Ziel-Regionspaar fehlgeschlagen ist.
    /// `candidates` sind alle für die Berechnung geladenen Regionen (nicht nur die, die Start/Ziel
    /// selbst enthalten - eine mittig durchquerte Region wie Schleswig-Holstein bei Cuxhaven ->
    /// Hamburg enthält keinen von beiden). Ermittelt zunächst per `findHandoverSequence` die
    /// durchquerte Regionenkette, dann für jeden benachbarten Kettenübergang per
    /// `findHandoverCoordinate` (wiederverwendet, auf genau die zwei angrenzenden Regionen
    /// beschränkt) den jeweiligen Übergangspunkt, snappt ihn wie bei `combinedRoute` unabhängig in
    /// beiden angrenzenden Graphen und reiht die so entstehenden Teilrouten aneinander. `nil`, wenn
    /// keine Kette gefunden wird, ein Übergang nicht plausibel snappt (zu große Lücke, s.
    /// `maxHandoverGapMeters`) oder eine Teilroute selbst fehlschlägt - `ContentView` fällt dann wie
    /// bisher auf Online-Routing zurück.
    static func chainedRoute(
        start: CLLocationCoordinate2D, end: CLLocationCoordinate2D,
        candidates: [(repository: WayGraphRepository, displayName: String)]
    ) -> BikeRoutingEngine.Result? {
        func distance(in repository: WayGraphRepository, to coordinate: CLLocationCoordinate2D) -> Double? {
            guard let node = repository.nearestNode(to: coordinate, maxDistanceMeters: sampleSearchRadiusMeters) else { return nil }
            let location = repository.nodeLocations[node]
            return CLLocation(latitude: location.latitude, longitude: location.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        let distanceClosures = candidates.map { candidate in
            { (coordinate: CLLocationCoordinate2D) -> Double? in distance(in: candidate.repository, to: coordinate) }
        }

        guard let chain = findHandoverSequence(start: start, end: end, regionDistanceMeters: distanceClosures)
        else { return nil }

        // Übergangspunkt je benachbartem Kettenpaar - dieselbe Zwei-Regionen-Suche wie
        // `combinedRoute`, hier auf die beiden angrenzenden Kandidaten der Kette beschränkt.
        var handovers: [CLLocationCoordinate2D] = []
        for i in 0..<(chain.count - 1) {
            guard let handover = findHandoverCoordinate(
                start: start, end: end,
                startRegionDistanceMeters: distanceClosures[chain[i]],
                endRegionDistanceMeters: distanceClosures[chain[i + 1]]
            ) else { return nil }
            handovers.append(handover)
        }

        // Jeden Übergang unabhängig in beiden angrenzenden Graphen snappen (analog `combinedRoute`) -
        // liefert je Übergang einen Endpunkt fürs vorherige und einen Startpunkt fürs nächste Leg.
        var legStarts = [start]
        var legEnds: [CLLocationCoordinate2D] = []
        var gaps: [Double] = []
        for (i, handover) in handovers.enumerated() {
            let fromRepository = candidates[chain[i]].repository
            let toRepository = candidates[chain[i + 1]].repository
            guard let fromNode = fromRepository.nearestNode(to: handover, maxDistanceMeters: handoverSnapMeters),
                  let toNode = toRepository.nearestNode(to: handover, maxDistanceMeters: handoverSnapMeters)
            else { return nil }
            let fromLocation = fromRepository.nodeLocations[fromNode]
            let toLocation = toRepository.nodeLocations[toNode]
            let gap = CLLocation(latitude: fromLocation.latitude, longitude: fromLocation.longitude)
                .distance(from: CLLocation(latitude: toLocation.latitude, longitude: toLocation.longitude))
            guard gap < maxHandoverGapMeters else { return nil }
            legEnds.append(fromLocation)
            legStarts.append(toLocation)
            gaps.append(gap)
        }
        legEnds.append(end)

        var coordinates: [CLLocationCoordinate2D] = []
        var steps: [BikeRoutingEngine.Result.Step] = []
        var totalDistanceMeters = 0.0
        for i in 0..<chain.count {
            let repository = candidates[chain[i]].repository
            // Wie bei `combinedRoute`: nur die echten Start-/Zielpunkte (erstes/letztes Leg) bleiben
            // beim engen Standardradius, alle dazwischenliegenden Übergangspunkte dürfen weiter zu
            // einem tatsächlich gut angebundenen Knoten wandern (`handoverSnapMeters`).
            let startMaxDistanceMeters = i == 0 ? BikeRoutingEngine.defaultEndpointMaxDistanceMeters : Self.handoverSnapMeters
            let endMaxDistanceMeters = i == chain.count - 1 ? BikeRoutingEngine.defaultEndpointMaxDistanceMeters : Self.handoverSnapMeters
            guard let leg = BikeRoutingEngine(repository: repository).route(
                from: legStarts[i], to: legEnds[i], maxVisitedNodes: legMaxVisitedNodes,
                startMaxDistanceMeters: startMaxDistanceMeters, endMaxDistanceMeters: endMaxDistanceMeters
            ) else { return nil }

            coordinates.append(contentsOf: leg.coordinates)
            totalDistanceMeters += leg.distanceMeters
            steps.append(contentsOf: leg.steps)

            if i < chain.count - 1 {
                totalDistanceMeters += gaps[i]
                steps.append(BikeRoutingEngine.Result.Step(
                    instructions: "Weiter in \(candidates[chain[i + 1]].displayName)",
                    endCoordinate: legStarts[i + 1], direction: .straight
                ))
            }
        }

        return BikeRoutingEngine.Result(coordinates: coordinates, distanceMeters: totalDistanceMeters, steps: steps)
    }
}
