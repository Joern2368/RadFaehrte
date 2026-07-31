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
    private static let maxHandoverGapMeters = 1500.0

    /// Höheres `BikeRoutingEngine.maxVisitedNodes`-Limit für die beiden Teilstrecken (Start →
    /// Übergang, Übergang → Ziel) als der sonstige Standard (300.000, kalibriert für lokale
    /// Städte-Routen). Eine Teilstrecke quer durch ein großes Bundesland kann leicht 50-100 km lang
    /// sein (z. B. Bremen → Osnabrück: ~97 km allein im Niedersachsen-Abschnitt) und dabei mehr
    /// Knoten berühren als der Standard erlaubt - live auf dem Gerät als stiller Fehlschlag der
    /// zweiten Teilstrecke beobachtet (2026-07-31), obwohl ein Pfad existierte.
    private static let legMaxVisitedNodes = 1_500_000

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

        guard let leg1 = BikeRoutingEngine(repository: startRepository).route(from: start, to: handoverInStart, maxVisitedNodes: legMaxVisitedNodes),
              let leg2 = BikeRoutingEngine(repository: endRepository).route(from: handoverInEnd, to: end, maxVisitedNodes: legMaxVisitedNodes)
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
}
