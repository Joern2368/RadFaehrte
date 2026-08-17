//
//  BikeRoutingEngine.swift
//  RadFaehrte
//

import CoreLocation

/// A*-Routing über den Wege-Graphen eines heruntergeladenen Bundeslands (`WayGraphRepository`),
/// das ruhige Wege/Radwege bevorzugt statt nur die kürzeste Verbindung zu suchen (das leistet
/// bereits Apples MKDirections für die "Direkte Fahrrad-Route" online).
nonisolated final class BikeRoutingEngine {
    /// Kleinstmöglicher Gewichtungsfaktor aus `Scripts/build_way_graph.py`
    /// (HIGHWAY_WEIGHTS["cycleway"] * CYCLE_INFRA_BONUS = 0.6 * 0.7 = 0.42) als konservative
    /// Untergrenze für die A*-Heuristik, damit sie nie die tatsächlichen Restkosten überschätzt
    /// (sonst wäre die gefundene Route nicht mehr garantiert die günstigste). Muss angepasst
    /// werden, falls sich die Gewichtung dort ändert.
    private static let minWeightMultiplier = 0.4

    /// Seitlicher Versatz für Kanten mit `cycleway=track/lane` (siehe `offsetSide` in
    /// `WayGraphRepository.Edge`): Diese Radwege sind in OSM nur als Attribut an der
    /// Straßen-Mittellinie vermerkt, nicht als eigene Geometrie gezeichnet. Ohne Versatz würde
    /// die Route optisch auf der Fahrbahn statt auf dem tatsächlich danebenliegenden Radweg
    /// verlaufen. 3,5 m ist eine grobe Schätzung für den typischen Abstand eines baulich
    /// getrennten Radwegs zur Fahrbahnmitte, keine echte Vermessung.
    private static let cycleOffsetMeters = 3.5

    /// Maximale Länge (Meter) einer Lücke ohne eindeutige Versatz-Seite (`offsetSide == 0`), die
    /// noch überbrückt wird, wenn die Abschnitte davor und danach dieselbe eindeutige Seite haben
    /// (s. `smoothedOffsetSides`). Grund: Ein und dieselbe reale Straße ist in OSM oft an
    /// Kreuzungen/Haltestellen in mehrere kurze Way-Segmente zerschnitten, die uneinheitlich
    /// getaggt sind - z. B. `cycleway:right=track` (eindeutige Seite) vor einer Kreuzung, dann ein
    /// paar Meter mit `cycleway:both=track` oder unqualifiziertem `cycleway=track` (keine
    /// eindeutige Seite, s. `offset_side` in `build_way_graph.py`), danach wieder
    /// `cycleway:right=track`. Ohne Überbrückung springt die Linie dort kurz auf die
    /// Fahrbahnmitte zurück und wieder heraus, obwohl der reale Radweg durchgängig ist
    /// (Nutzer-Meldung 2026-08-06, Kreuzung Bei den Drei Pfählen/Stader Straße, Bremen - per
    /// Overpass-Abfrage bestätigt: 30 m langes `cycleway:both=track`-Zwischenstück zwischen zwei
    /// `cycleway:right=track`-Abschnitten). 50 m ist eine grobe Schätzung (deutlich mehr als
    /// typische Kreuzungsbreiten, aber klein genug, um eine wirklich längere Lücke ohne
    /// Seitenangabe nicht fälschlich zu überbrücken) - nicht gegen viele echte Fälle kalibriert.
    private static let maxSmoothedGapMeters = 50.0

    /// Obergrenze für besuchte Knoten pro Suche - ohne sie würde eine erfolglose Suche (z. B. weil
    /// `start`/`end` zwar auf einen Knoten snappen, aber keine sinnvolle Verbindung dazwischen
    /// existiert) im schlimmsten Fall den kompletten Graphen durchlaufen, bevor sie aufgibt. Bei
    /// den ursprünglichen, kleinen Bundesländern (Bremen, Saarland) unkritisch, bei ganzen Ländern
    /// wie den Niederlanden (9,6 Mio. Knoten) oder Polen (31 Mio.) aber ein reales Problem: eine
    /// erfolglose Suche über Minuten und mit stark wachsendem Speicherverbrauch (`gScore`/
    /// `cameFrom`/`visited` wachsen mit jedem besuchten Knoten) - beobachtet als scheinbarer
    /// App-Absturz beim Live-Test in Rotterdam (2026-07-26). Bricht die Suche stattdessen früh ab
    /// und liefert `nil` zurück, `routes(from:to:)` fällt dann wie bei "kein Pfad gefunden" auf
    /// Online-Routing zurück (s. `ContentView.offlineGraphCandidatePaths`). 300.000 ist grob
    /// geschätzt (deutlich mehr als eine normale lokale Stadt-Route je berühren sollte, aber
    /// klein genug, um im ungünstigen Fall in wenigen Sekunden statt Minuten abzubrechen) - noch
    /// nicht gegen echte Grenzfälle kalibriert.
    private static let maxVisitedNodes = 300_000

    /// Anzahl der tatsächlich per A* probierten Ausweich-Kandidaten für Start/Ziel in
    /// `routes(from:to:)`, falls der jeweils nächstgelegene Knoten auf einer isolierten Graph-Insel
    /// liegt (s. `isolatedIslandVisitedNodeThreshold`) - 4 statt 1, damit ein einzelner ungünstig
    /// gesnappter Punkt (typischerweise eine private Zufahrt/Sackgasse direkt neben der eigentlich
    /// gemeinten Straße) nicht die ganze Suche scheitern lässt, aber klein genug, um im Normalfall
    /// (Insel nur beim allerersten Kandidaten) keine spürbaren zusätzlichen Suchen zu verursachen.
    private static let endpointCandidateCount = 4

    /// Anzahl der Knoten, die `nearestNodes` liefert, **bevor** `wellConnectedCandidates` filtert -
    /// deutlich größer als `endpointCandidateCount` (die eigentliche A*-Versuchsanzahl), da eine
    /// isolierte Graph-Insel selbst mehr als eine Handvoll Knoten enthalten kann (Live-Fund
    /// 2026-08-06: 321 Knoten auf der Kehdingen-Halbinsel). Mit nur 4 abgefragten Rohkandidaten
    /// wären bei so einer größeren Insel alle 4 nächstgelegenen Knoten selbst Teil der Insel
    /// gewesen, der tatsächlich gut angebundene nächste Knoten (knapp 4,6 km entfernt) hätte den
    /// Filter also nie erreicht. 40 ist grob geschätzt (deutlich mehr als die bisher beobachteten
    /// Inseln, aber klein genug, um pro `wellConnectedCandidates`-Aufruf nicht spürbar mehr Zeit als
    /// die eigentliche A*-Suche zu kosten).
    private static let nearestNodesPoolSize = 40

    /// Obergrenze für die schnelle Vorab-Erreichbarkeitsprüfung in `wellConnectedCandidates` - klein
    /// genug, um pro Kandidat nur einige hundert statt Millionen Knoten zu besuchen, aber deutlich
    /// größer als die bisher beobachteten Inseln (2 bzw. 321 Knoten, s. dort), sodass eine echte, gut
    /// angebundene Straße den Cap zuverlässig erreicht und als "gut angebunden" gilt.
    private static let localConnectivityProbeCap = 600

    /// Standard-Suchradius für `nearestNodes`-Kandidaten in `routes(from:to:)` (deckt sich mit
    /// `WayGraphRepository.nearestNode`s eigenem Standard) - für die tatsächlichen Start-/
    /// Zielpunkte einer Route (Nutzer-Standort/-Adresse) bewusst eng, damit nicht kilometerweit
    /// entfernt gesnappt wird. `CrossRegionRouteStitcher` übergibt für die berechneten
    /// Übergangspunkte zwischen zwei Regionen bewusst einen größeren Wert (`handoverSnapMeters`) -
    /// anders als ein echter Start-/Zielpunkt ist so ein Übergangspunkt nur eine grobe geometrische
    /// Näherung, keine reale Adresse, und darf deshalb weiter zu einem tatsächlich gut angebundenen
    /// Knoten wandern (Live-Fund 2026-08-06: der geometrisch nächstgelegene Übergangspunkt bei
    /// Stade/Buxtehude lag auf der vom übrigen Netz abgeschnittenen Kehdingen-Halbinsel - der
    /// nächste gut angebundene Knoten lag knapp 4,6 km weiter westlich, außerhalb dieses
    /// Standardradius).
    static let defaultEndpointMaxDistanceMeters = 2000.0

    /// Zusätzliches Sicherheitsnetz neben `wellConnectedCandidates` (s. dort): Bricht eine Suche mit
    /// weniger als dieser Anzahl besuchter Knoten ab (Warteschlange leer, `maxVisitedNodes` nicht
    /// erreicht), gilt das in `routes(from:to:)` als Symptom einer kleinen, vom übrigen Netz
    /// abgeschnittenen Graph-Insel statt eines echten "kein Pfad vorhanden" - reale Städte-/
    /// Land-Strecken berühren selbst im ungünstigsten Fall deutlich mehr Knoten. 50 ist grob
    /// geschätzt (deutlich mehr als die ursprünglich beobachteten 2 besuchten Knoten bei Cuxhaven,
    /// aber klein genug, um eine echte, nur zufällig kurze erfolglose Suche nicht fälschlich als
    /// Insel zu werten). ⚠️ Greift nur, wenn die Suche selbst auf der Insel beginnt/endet und dort
    /// schnell aufgibt - deckt **nicht** den Fall ab, dass eine gut angebundene große Seite
    /// vergeblich versucht, eine isolierte Insel zu erreichen (dabei läuft die Warteschlange nicht
    /// leer, sondern die Suche erreicht `maxVisitedNodes`, weil sie fast den kompletten
    /// zusammenhängenden Graphen durchsucht - Live-Fund 2026-08-06, Übergangspunkt
    /// Bremen/Niedersachsen → Schleswig-Holstein bei Stade/Buxtehude landete auf einer nur
    /// 321-Knoten-Insel und ließ eine Suche von Bremen aus selbst mit 3 Mio. Knoten Limit
    /// scheitern). Für genau diesen Fall filtert `wellConnectedCandidates` die Kandidaten schon
    /// *vor* der teuren A*-Suche.
    private static let isolatedIslandVisitedNodeThreshold = 50

    /// Ab welcher Kursänderung (Grad) `stepDetails` überhaupt eine Abbiegung ausgibt (Text,
    /// Pfeil-Icon, Watch-Haptik-Trigger über `isTurnInstruction` in `ContentView`) statt "Weiter
    /// auf ...". Ursprünglich 20° - führte laut Live-Test zu Fehlalarmen bei sanften
    /// Straßenschwenks, die keine echte Abbiegung sind. Auf 30° angehoben, um das zu reduzieren;
    /// weiterhin eine grobe Schätzung, nicht gegen echte Kreuzungen kalibriert - Kehrseite eines zu
    /// hohen Werts wäre eine tatsächliche, aber sanfte Abbiegung, die stillschweigend übergangen
    /// wird (deutlich harmloser als eine falsche Ansage).
    private static let turnAngleThresholdDegrees = 30.0

    /// Ab welcher Kursänderung (Grad) eine Abbiegung als "scharf" (statt normal) angesagt wird.
    private static let sharpTurnAngleThresholdDegrees = 120.0

    /// Zusätzliche Kosten (Meter-Äquivalent, addiert auf `gScore`) pro Grad Richtungsänderung an
    /// einem Knoten. Ohne diesen Malus bewertet die Suche Kanten rein nach `edge.weight`
    /// (Distanz × Straßentyp-Faktor inkl. Radweg-Bonus) - ein kurzer, separat kartierter
    /// Radweg-/Querungsabschnitt (z. B. eine Ampel-Aufstellfläche seitlich der eigentlichen
    /// Kreuzung) kann dadurch trotz unnötigem kleinem Schlenker günstiger wirken als einfach
    /// geradeaus weiterzufahren (Nutzer-Meldung 2026-08-06: Route schlägt an einer Kreuzung einen
    /// kleinen Rechts-Schlenker zur Ampel vor, obwohl es geradeaus weitergeht). Grobe Schätzung,
    /// nicht gegen echte Kreuzungen kalibriert: zu niedrig verhindert den Effekt nicht, zu hoch
    /// drängt die Route von echten, sinnvollen Abbiegungen auf ruhigere Wege weg - Zielkonflikt
    /// mit dem eigentlichen Zweck der Engine. Ändert nichts an der A*-Korrektheit: `heuristic(_:)`
    /// bleibt eine gültige Unterschätzung, da sie ausschließlich auf der Luftlinien-Distanz
    /// beruht und der Malus die tatsächlichen Kosten nur erhöht, nie verringert.
    private static let turnPenaltyMetersPerDegree = 1.0

    private let repository: WayGraphRepository

    init(repository: WayGraphRepository) {
        self.repository = repository
    }

    struct Result {
        struct Step {
            enum Direction {
                case straight, left, right
            }

            let instructions: String
            let endCoordinate: CLLocationCoordinate2D
            let direction: Direction
        }

        let coordinates: [CLLocationCoordinate2D]
        let distanceMeters: Double
        /// Abschnitte nach Straßenname gruppiert, mit grob aus dem Abbiege-Winkel geschätzter
        /// Richtungsangabe (siehe `instructions(incomingBearing:outgoingBearing:name:)`) - analog
        /// zu `MKRoute.steps` bei der Online-Route, nur ohne Apples Kreuzungs-Heuristiken. Leer,
        /// wenn der Wege-Graph keine Namen enthält (altes Datenformat vor `WayGraphRepository`s
        /// `wayNames`) oder kein Pfad gefunden wurde.
        let steps: [Step]
        /// Gefahrene Meter je `WayGraphRepository.WayCategory` (Radweg/Ruhige Straße/Landstraße/
        /// Unbefestigter Weg/Sonstiger Weg) für die Wegearten-Anzeige ("X km Landstraße" usw.).
        /// Summe über alle Werte entspricht `distanceMeters` (bis auf Rundung).
        let metersByCategory: [WayGraphRepository.WayCategory: Double]
    }

    /// Knoten werden als dichte 0-basierte Array-Indizes referenziert (siehe
    /// `WayGraphRepository`), nicht die ursprünglichen OSM-IDs.
    private struct EdgeKey: Hashable {
        let from: Int
        let to: Int
    }

    /// Einzelne "ruhigste" Route zwischen zwei Punkten - Kurzform von
    /// `routes(from:to:maxAlternatives:)` ohne Alternativen. `maxVisitedNodes`/
    /// `startMaxDistanceMeters`/`endMaxDistanceMeters` s. dort.
    func route(
        from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D,
        maxVisitedNodes: Int = BikeRoutingEngine.maxVisitedNodes,
        startMaxDistanceMeters: Double = BikeRoutingEngine.defaultEndpointMaxDistanceMeters,
        endMaxDistanceMeters: Double = BikeRoutingEngine.defaultEndpointMaxDistanceMeters
    ) -> Result? {
        routes(
            from: start, to: end, maxAlternatives: 0, maxVisitedNodes: maxVisitedNodes,
            startMaxDistanceMeters: startMaxDistanceMeters, endMaxDistanceMeters: endMaxDistanceMeters
        ).first
    }

    /// Berechnet die "ruhigste" Route sowie bis zu `maxAlternatives` weitere, spürbar andere
    /// Alternativen - analog zu `RouteMatcher.routeSegmentDistance`s Alternativstrecken-Suche:
    /// Kanten der bereits gefundenen Pfade ausschließen und erneut suchen. Liefert weniger als
    /// `maxAlternatives + 1` Ergebnisse, sobald sich keine trennbare Alternative mehr finden
    /// lässt; leeres Array, wenn kein Knoten in der Nähe von `start`/`end` liegt (außerhalb des
    /// heruntergeladenen Bundeslands) oder gar kein Pfad existiert.
    ///
    /// `maxVisitedNodes` überschreibt `Self.maxVisitedNodes` (s. dort) für diesen Aufruf -
    /// `CrossRegionRouteStitcher` braucht für seine Teilstrecken ein höheres Limit, da eine Etappe
    /// quer durch ein großes Bundesland (z. B. Bremen → Osnabrück: ~97 km allein im
    /// Niedersachsen-Abschnitt) mehr Knoten berührt als die für lokale Städte-Routen kalibrierten
    /// 300.000 (Live-Fund 2026-07-31: `leg2` schlug mit dem Standardwert fehl, obwohl ein Pfad
    /// existierte).
    func routes(
        from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D, maxAlternatives: Int = 2,
        maxVisitedNodes: Int = BikeRoutingEngine.maxVisitedNodes,
        startMaxDistanceMeters: Double = BikeRoutingEngine.defaultEndpointMaxDistanceMeters,
        endMaxDistanceMeters: Double = BikeRoutingEngine.defaultEndpointMaxDistanceMeters
    ) -> [Result] {
        let rawStartCandidates = repository.nearestNodes(
            to: start, maxDistanceMeters: startMaxDistanceMeters, limit: Self.nearestNodesPoolSize)
        let rawEndCandidates = repository.nearestNodes(
            to: end, maxDistanceMeters: endMaxDistanceMeters, limit: Self.nearestNodesPoolSize)
        guard !rawStartCandidates.isEmpty, !rawEndCandidates.isEmpty else { return [] }
        let filteredStartCandidates = wellConnectedCandidates(rawStartCandidates)
        let filteredEndCandidates = wellConnectedCandidates(rawEndCandidates)
        let startCandidates = Array((filteredStartCandidates.isEmpty ? rawStartCandidates : filteredStartCandidates).prefix(Self.endpointCandidateCount))
        let endCandidates = Array((filteredEndCandidates.isEmpty ? rawEndCandidates : filteredEndCandidates).prefix(Self.endpointCandidateCount))

        var results: [Result] = []
        var excludedEdges: Set<EdgeKey> = []
        var startNode = startCandidates[0]
        var endNode = endCandidates[0]

        // Erste Suche: bei einer isolierten Insel der Reihe nach erst weitere Start-, dann weitere
        // Ziel-Kandidaten probieren (s. Doku an `endpointCandidateCount`). Ein echtes "kein Pfad"
        // oder ein Abbruch am `maxVisitedNodes`-Limit bricht sofort ab, ohne weitere Kandidaten zu
        // probieren - beides würde durch einen leicht verschobenen Start-/Zielknoten nicht besser.
        var firstOutcome: SearchOutcome = .queueExhausted(visitedCount: 0)
        candidateSearch: for startCandidate in startCandidates {
            for endCandidate in endCandidates {
                firstOutcome = search(from: startCandidate, to: endCandidate, excluding: [], maxVisitedNodes: maxVisitedNodes)
                if case .queueExhausted(let visitedCount) = firstOutcome,
                   visitedCount < Self.isolatedIslandVisitedNodeThreshold {
                    continue
                }
                startNode = startCandidate
                endNode = endCandidate
                break candidateSearch
            }
        }

        guard case .found(let result, let path) = firstOutcome else { return [] }
        results.append(result)
        for i in 1..<path.count {
            excludedEdges.insert(EdgeKey(from: path[i - 1], to: path[i]))
        }

        for _ in 0..<maxAlternatives {
            guard case .found(let result, let path) = search(from: startNode, to: endNode, excluding: excludedEdges, maxVisitedNodes: maxVisitedNodes)
            else { break }
            results.append(result)
            for i in 1..<path.count {
                excludedEdges.insert(EdgeKey(from: path[i - 1], to: path[i]))
            }
        }
        return results
    }

    /// Filtert `candidates` (Reihenfolge bleibt erhalten, nächstgelegener zuerst) auf Knoten mit
    /// ausreichender lokaler Anbindung: eine per `edges(from:)` begrenzte Breitensuche (Obergrenze
    /// `localConnectivityProbeCap`) muss diesen Cap erreichen, statt vorher auf einer isolierten
    /// Graph-Insel (private Zufahrt, Sackgasse, unangebundener Weg - eine normale Eigenschaft realer
    /// OSM-Daten) auszulaufen. Deutlich billiger als der volle A*-Versuch, der bei einer Insel auf
    /// der GROSSEN Seite fast den kompletten zusammenhängenden Graphen durchsucht, bevor er am
    /// `maxVisitedNodes`-Limit aufgibt statt schnell mit wenigen besuchten Knoten zu scheitern (s.
    /// Doku an `isolatedIslandVisitedNodeThreshold`). Leer, wenn kein Kandidat besteht - Aufrufer
    /// fallen dann bewusst auf die ungefilterte Liste zurück, statt ganz aufzugeben.
    private func wellConnectedCandidates(_ candidates: [Int]) -> [Int] {
        candidates.filter { candidate in
            var visited: Set<Int> = [candidate]
            var queue = [candidate]
            var head = 0
            while head < queue.count, visited.count < Self.localConnectivityProbeCap {
                let node = queue[head]
                head += 1
                for edge in repository.edges(from: node) {
                    if visited.insert(Int(edge.toNode)).inserted {
                        queue.append(Int(edge.toNode))
                    }
                }
            }
            return visited.count >= Self.localConnectivityProbeCap
        }
    }

    /// Ergebnis von `search` - unterscheidet (anders als ein einfaches Optional) zwei
    /// unterschiedliche Fehlerursachen, damit `routes(from:to:)` gezielt nur auf eine davon mit
    /// Ausweich-Kandidaten reagieren kann (s. `endpointCandidateCount`).
    private enum SearchOutcome {
        case found(Result, [Int])
        /// Warteschlange lief leer, ohne dass `maxVisitedNodes` erreicht wurde. Bei kleinem
        /// `visitedCount` typisches Symptom einer isolierten Graph-Insel (s.
        /// `isolatedIslandVisitedNodeThreshold`); bei großem `visitedCount` ein echtes "zwischen
        /// diesen beiden Knoten existiert kein Pfad".
        case queueExhausted(visitedCount: Int)
        /// `maxVisitedNodes` erreicht, bevor die Suche von selbst fertig wurde - ein anderer
        /// Start-/Zielkandidat in unmittelbarer Nähe würde daran nichts ändern.
        case nodeLimitExceeded
    }

    /// Dictionaries statt Arrays über die volle Knotenzahl, obwohl Knoten dichte Indizes haben:
    /// eine A*-Suche berührt bei einem großen Bundesland (Millionen Knoten) typischerweise nur
    /// einen kleinen, lokalen Ausschnitt - Arrays in Graphgröße vorzuallozieren wäre für jede
    /// einzelne Suche unnötig speicherhungrig.
    private func search(
        from startNode: Int, to endNode: Int, excluding excludedEdges: Set<EdgeKey>, maxVisitedNodes: Int
    ) -> SearchOutcome {
        guard endNode < repository.nodeLocations.count else { return .queueExhausted(visitedCount: 0) }
        let endLocation = repository.nodeLocations[endNode]
        let endCLLocation = CLLocation(latitude: endLocation.latitude, longitude: endLocation.longitude)
        func heuristic(_ nodeId: Int) -> Double {
            let location = repository.nodeLocations[nodeId]
            return CLLocation(latitude: location.latitude, longitude: location.longitude)
                .distance(from: endCLLocation) * Self.minWeightMultiplier
        }

        var gScore: [Int: Double] = [startNode: 0]
        var realDistance: [Int: Double] = [startNode: 0]
        var cameFrom: [Int: Int] = [:]
        // Versatz-Seite der Kante, über die ein Knoten auf dem bisher besten Pfad erreicht
        // wurde - nötig, um beim Rekonstruieren des Pfads (unten) die Anzeige-Koordinaten pro
        // Kante statt pro Knoten seitlich zu verschieben.
        var cameFromOffsetSide: [Int: Int] = [:]
        // Straßenname der Kante, über die ein Knoten erreicht wurde - für die Schritt-Erzeugung
        // (`buildSteps`), analog zu `cameFromOffsetSide`.
        var cameFromNameIndex: [Int: UInt32] = [:]
        // Wegeart der Kante, über die ein Knoten erreicht wurde - für die Wegearten-Aggregation
        // unten, analog zu `cameFromOffsetSide`.
        var cameFromCategory: [Int: WayGraphRepository.WayCategory] = [:]
        var visited: Set<Int> = []
        var queue = AStarQueue()
        queue.push(priority: heuristic(startNode), node: startNode)

        while let current = queue.popMin() {
            guard !visited.contains(current.node) else { continue }
            visited.insert(current.node)
            if current.node == endNode { break }
            guard visited.count < maxVisitedNodes else { return .nodeLimitExceeded }

            // Peilung der Kante, über die `current.node` erreicht wurde - `nil` beim Startknoten,
            // da es dort noch keine vorherige Fahrtrichtung gibt, mit der sich ein Abbiegen
            // vergleichen ließe (analog `stepDetails`s `incomingBearing`).
            let incomingBearing = cameFrom[current.node].map {
                Self.bearingDegrees(from: repository.nodeLocations[$0], to: repository.nodeLocations[current.node])
            }

            for edge in repository.edges(from: current.node) {
                let toNode = Int(edge.toNode)
                guard !visited.contains(toNode),
                      !excludedEdges.contains(EdgeKey(from: current.node, to: toNode))
                else { continue }
                var turnPenalty = 0.0
                if let incomingBearing {
                    let outgoingBearing = Self.bearingDegrees(
                        from: repository.nodeLocations[current.node], to: repository.nodeLocations[toNode])
                    var delta = outgoingBearing - incomingBearing
                    while delta > 180 { delta -= 360 }
                    while delta < -180 { delta += 360 }
                    turnPenalty = abs(delta) * Self.turnPenaltyMetersPerDegree
                }
                let tentativeG = (gScore[current.node] ?? .greatestFiniteMagnitude) + Double(edge.weight) + turnPenalty
                if tentativeG < (gScore[toNode] ?? .greatestFiniteMagnitude) {
                    gScore[toNode] = tentativeG
                    realDistance[toNode] = (realDistance[current.node] ?? 0) + Double(edge.distanceMeters)
                    cameFrom[toNode] = current.node
                    cameFromOffsetSide[toNode] = Int(edge.offsetSide)
                    cameFromNameIndex[toNode] = edge.nameIndex
                    cameFromCategory[toNode] = edge.wayCategory
                    queue.push(priority: tentativeG + heuristic(toNode), node: toNode)
                }
            }
        }

        guard gScore[endNode] != nil else { return .queueExhausted(visitedCount: visited.count) }

        var path = [endNode]
        var node = endNode
        while let prev = cameFrom[node] {
            path.append(prev)
            node = prev
        }
        path.reverse()

        // Kanten-Länge pro Hop aus der Differenz der (entlang des Pfads monoton steigenden)
        // kumulierten `realDistance`-Werte statt einer eigenen dritten `cameFrom*`-Tabelle -
        // spart eine weitere Dictionary-Allokation pro Suche.
        var metersByCategory: [WayGraphRepository.WayCategory: Double] = [:]
        for toNode in path.dropFirst() {
            guard let category = cameFromCategory[toNode], let fromNode = cameFrom[toNode] else { continue }
            let edgeMeters = (realDistance[toNode] ?? 0) - (realDistance[fromNode] ?? 0)
            metersByCategory[category, default: 0] += edgeMeters
        }

        let result = Result(
            coordinates: Self.displayCoordinates(for: path, offsetSide: cameFromOffsetSide, repository: repository),
            distanceMeters: realDistance[endNode] ?? 0,
            steps: Self.buildSteps(path: path, nameIndex: cameFromNameIndex, repository: repository),
            metersByCategory: metersByCategory
        )
        return .found(result, path)
    }

    /// Mindest-Distanz (Meter) für `windowedBearing`s Rückwärts-/Vorwärts-Fenster an einer
    /// Namensgruppen-Grenze, statt nur der einen angrenzenden Kante. Grund: Direkt an
    /// Namenswechseln liegen im Wege-Graph gelegentlich sehr kurze Kanten (wenige Meter,
    /// OSM-Digitalisierungsdetail statt echter Kreuzung) - deren Einzel-Peilung kann stark von
    /// der über die Strecke gemittelten tatsächlichen Fahrtrichtung abweichen und einen
    /// Fehlalarm auslösen (Nutzer-Meldung 2026-08-07, per echter GPS-Aufzeichnung aus dem
    /// "Verlauf" nachvollzogen: ein unbenannter ~800 m Verbindungsweg zwischen "Am Schwarzen
    /// Meer" und "Am Hulsberg" löste an beiden Enden "Rechts abbiegen" aus, obwohl der Weg dort
    /// nur sanft geschwenkt war - die Kante direkt an einer der beiden Grenzen war nur 2,4 m
    /// kurz). 15 m ist eine grobe Schätzung (deutlich mehr als die beobachtete Störkante, aber
    /// klein genug, um eine tatsächliche Abbiegung direkt nach einer kurzen Einfahrt nicht zu
    /// verschlucken) - nicht gegen viele echte Kreuzungen kalibriert.
    private static let turnBearingWindowMeters = 15.0

    /// Gruppiert den Pfad in Abschnitte mit demselben Straßennamen (`WayGraphRepository.Edge.
    /// nameIndex`) - ein neuer Schritt beginnt, sobald sich der Name ändert (auch von/zu
    /// unbenannt). Für jeden Übergang wird aus der Winkeländerung zwischen der Peilung kurz vor
    /// dem vorherigen und kurz nach dem neuen Abschnitt (s. `windowedBearing`/
    /// `turnBearingWindowMeters`) grob eine Abbiege-Richtung geschätzt - ohne die
    /// Kreuzungs-/Namensänderungs-Heuristiken echter Navigations-Engines, kann also bei sanften
    /// Straßenschwenks gelegentlich daneben liegen (Live-Test/Kalibrierung nötig).
    ///
    /// Bewusst nicht `private` (wie der Rest der A*-Interna dieser Klasse): `CuratedRouteStepMatcher`
    /// baut Knotenpfade auf andere Weise auf (Map-Matching statt A*-Suche), nutzt für die
    /// eigentliche Namens-/Richtungs-Aufbereitung aber dieselbe Logik statt sie zu duplizieren.
    static func buildSteps(
        path: [Int], nameIndex: [Int: UInt32], repository: WayGraphRepository
    ) -> [Result.Step] {
        guard path.count >= 2 else { return [] }

        var steps: [Result.Step] = []
        var groupStart = 1
        var groupNameIndex = nameIndex[path[1]] ?? WayGraphRepository.noNameIndex

        func closeGroup(end: Int) {
            let incomingBearing = groupStart > 1
                ? windowedBearing(endingAt: groupStart - 1, path: path, repository: repository, minMeters: turnBearingWindowMeters)
                : nil
            let outgoingBearing = windowedBearing(
                startingAt: groupStart, path: path, repository: repository, minMeters: turnBearingWindowMeters)
            let name = repository.wayName(forIndex: groupNameIndex)
            let (text, direction) = stepDetails(incomingBearing: incomingBearing, outgoingBearing: outgoingBearing, name: name)
            steps.append(Result.Step(instructions: text, endCoordinate: repository.nodeLocations[path[end]], direction: direction))
        }

        for edgeEnd in 2..<path.count {
            let currentNameIndex = nameIndex[path[edgeEnd]] ?? WayGraphRepository.noNameIndex
            if currentNameIndex != groupNameIndex {
                closeGroup(end: edgeEnd - 1)
                groupStart = edgeEnd
                groupNameIndex = currentNameIndex
            }
        }
        closeGroup(end: path.count - 1)
        return steps
    }

    /// Peilung rückwärts entlang `path` endend bei `path[index]`: läuft von `index` aus zurück,
    /// bis mindestens `minMeters` Distanz akkumuliert sind (oder der Pfadanfang erreicht ist),
    /// und misst die Peilung von dort direkt zu `path[index]` - eine Sehne über das Fenster
    /// statt des Mittels einzelner Kanten-Peilungen, aber für die paar Meter typischer
    /// Fenstergröße ausreichend nah dran und deutlich einfacher. S. `turnBearingWindowMeters` für
    /// den Hintergrund, wieso eine einzelne angrenzende Kante nicht reicht.
    private static func windowedBearing(
        endingAt index: Int, path: [Int], repository: WayGraphRepository, minMeters: Double
    ) -> Double {
        let endLocation = repository.nodeLocations[path[index]]
        var i = index
        var accumulated = 0.0
        while i > 0, accumulated < minMeters {
            let from = CLLocation(
                latitude: repository.nodeLocations[path[i - 1]].latitude,
                longitude: repository.nodeLocations[path[i - 1]].longitude)
            let to = CLLocation(
                latitude: repository.nodeLocations[path[i]].latitude,
                longitude: repository.nodeLocations[path[i]].longitude)
            accumulated += from.distance(from: to)
            i -= 1
        }
        return bearingDegrees(from: repository.nodeLocations[path[i]], to: endLocation)
    }

    /// Vorwärts-Gegenstück zu `windowedBearing(endingAt:...)`, s. dort.
    private static func windowedBearing(
        startingAt index: Int, path: [Int], repository: WayGraphRepository, minMeters: Double
    ) -> Double {
        let startLocation = repository.nodeLocations[path[index]]
        var i = index
        var accumulated = 0.0
        while i < path.count - 1, accumulated < minMeters {
            let from = CLLocation(
                latitude: repository.nodeLocations[path[i]].latitude,
                longitude: repository.nodeLocations[path[i]].longitude)
            let to = CLLocation(
                latitude: repository.nodeLocations[path[i + 1]].latitude,
                longitude: repository.nodeLocations[path[i + 1]].longitude)
            accumulated += from.distance(from: to)
            i += 1
        }
        return bearingDegrees(from: startLocation, to: repository.nodeLocations[path[i]])
    }

    /// Anfangs-Peilung (0–360°, 0 = Norden) von `a` nach `b`.
    private static func bearingDegrees(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let bearing = atan2(y, x) * 180 / .pi
        return bearing < 0 ? bearing + 360 : bearing
    }

    /// Formuliert die Anweisung für einen neuen Abschnitt und die grobe Richtung fürs Pfeil-Icon
    /// in der Navigations-Kopfzeile. `incomingBearing == nil` beim allerersten Abschnitt der
    /// Route - dort gibt es noch keine vorherige Fahrtrichtung, mit der sich ein Abbiegen
    /// vergleichen ließe. Schwellenwerte s. `turnAngleThresholdDegrees`/
    /// `sharpTurnAngleThresholdDegrees`.
    private static func stepDetails(
        incomingBearing: Double?, outgoingBearing: Double, name: String?
    ) -> (text: String, direction: Result.Step.Direction) {
        guard let incomingBearing else {
            return (name.map { "Weiter auf \($0)" } ?? "Route folgen", .straight)
        }
        var delta = outgoingBearing - incomingBearing
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        let magnitude = abs(delta)
        guard magnitude >= turnAngleThresholdDegrees else {
            return (name.map { "Weiter auf \($0)" } ?? "Route folgen", .straight)
        }
        let isRight = delta > 0
        let turn = magnitude >= sharpTurnAngleThresholdDegrees
            ? (isRight ? "Scharf rechts abbiegen" : "Scharf links abbiegen")
            : (isRight ? "Rechts abbiegen" : "Links abbiegen")
        let text = name.map { "\(turn) auf \($0)" } ?? turn
        return (text, isRight ? .right : .left)
    }

    /// Baut die Anzeige-Koordinaten kantenweise statt einfach `path.map { nodeLocations[$0] }`,
    /// damit Kanten mit `cycleway=track/lane` (siehe `WayGraphRepository.Edge.offsetSide`)
    /// seitlich versetzt dargestellt werden. An Übergängen zwischen versetzten und
    /// nicht-versetzten Kanten entstehen dadurch kleine Sprünge in der Linie - das ist
    /// gewollt, da der reale Radweg dort tatsächlich beginnt bzw. endet.
    private static func displayCoordinates(
        for path: [Int], offsetSide: [Int: Int], repository: WayGraphRepository
    ) -> [CLLocationCoordinate2D] {
        guard path.count >= 2 else {
            return path.map { repository.nodeLocations[$0] }
        }
        let sides = smoothedOffsetSides(for: path, offsetSide: offsetSide, repository: repository)
        var coordinates: [CLLocationCoordinate2D] = []
        for i in 1..<path.count {
            let from = repository.nodeLocations[path[i - 1]]
            let to = repository.nodeLocations[path[i]]
            let (offsetFrom, offsetTo) = offsetPoint(from: from, to: to, side: sides[i - 1], meters: cycleOffsetMeters)
            if coordinates.isEmpty {
                coordinates.append(offsetFrom)
            }
            coordinates.append(offsetTo)
        }
        return coordinates
    }

    /// Versatz-Seite je Kante entlang `path` (Index `k` = Kante `path[k] -> path[k+1]`), mit
    /// überbrückten kurzen Lücken ohne eindeutige Seite - s. `maxSmoothedGapMeters` für den
    /// Hintergrund. Eine Lücke wird nur überbrückt, wenn sie auf beiden Seiten an eine eindeutige,
    /// **übereinstimmende** Seite grenzt (an Streckenanfang/-ende oder bei widersprüchlichen
    /// Seiten links/rechts bleibt es bei "keine Seite behaupten", analog `offset_side`s
    /// Begründung, wieso hier bewusst nicht geraten wird).
    private static func smoothedOffsetSides(
        for path: [Int], offsetSide: [Int: Int], repository: WayGraphRepository
    ) -> [Int] {
        var sides = (1..<path.count).map { offsetSide[path[$0]] ?? 0 }
        var i = 0
        while i < sides.count {
            guard sides[i] == 0 else { i += 1; continue }
            var gapEnd = i
            while gapEnd < sides.count, sides[gapEnd] == 0 { gapEnd += 1 }
            if i > 0, gapEnd < sides.count, sides[i - 1] != 0, sides[i - 1] == sides[gapEnd] {
                var gapMeters = 0.0
                for k in i..<gapEnd {
                    let from = CLLocation(latitude: repository.nodeLocations[path[k]].latitude, longitude: repository.nodeLocations[path[k]].longitude)
                    let to = CLLocation(latitude: repository.nodeLocations[path[k + 1]].latitude, longitude: repository.nodeLocations[path[k + 1]].longitude)
                    gapMeters += from.distance(from: to)
                }
                if gapMeters <= maxSmoothedGapMeters {
                    for k in i..<gapEnd { sides[k] = sides[i - 1] }
                }
            }
            i = gapEnd
        }
        return sides
    }

    /// Verschiebt eine Strecke `from -> to` senkrecht zu ihrer Richtung um `meters`, nach rechts
    /// (`side == 1`) oder links (`side == 2`); `side == 0` gibt die Punkte unverändert zurück.
    /// Rechnet lokal in Metern (kurze Distanz, Erdkrümmung vernachlässigbar) statt mit echter
    /// geodätischer Projektion - für wenige Meter Versatz ausreichend genau.
    private static func offsetPoint(
        from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, side: Int, meters: Double
    ) -> (CLLocationCoordinate2D, CLLocationCoordinate2D) {
        guard side == 1 || side == 2 else { return (from, to) }
        let metersPerDegreeLat = 111_320.0
        let midLatRad = (from.latitude + to.latitude) / 2 * .pi / 180
        let metersPerDegreeLon = metersPerDegreeLat * max(cos(midLatRad), 0.1)
        let dxMeters = (to.longitude - from.longitude) * metersPerDegreeLon
        let dyMeters = (to.latitude - from.latitude) * metersPerDegreeLat
        let length = (dxMeters * dxMeters + dyMeters * dyMeters).squareRoot()
        guard length > 0 else { return (from, to) }
        // Rechts der Richtung (from -> to) in Nord-oben-Kartenorientierung: (dy, -dx) normiert.
        let (px, py) = side == 1 ? (dyMeters / length, -dxMeters / length) : (-dyMeters / length, dxMeters / length)
        let offsetLon = (px * meters) / metersPerDegreeLon
        let offsetLat = (py * meters) / metersPerDegreeLat
        let offsetFrom = CLLocationCoordinate2D(latitude: from.latitude + offsetLat, longitude: from.longitude + offsetLon)
        let offsetTo = CLLocationCoordinate2D(latitude: to.latitude + offsetLat, longitude: to.longitude + offsetLon)
        return (offsetFrom, offsetTo)
    }
}

/// Binärer Min-Heap für A*, geordnet nach Priorität (f-Score). Analog `DijkstraQueue` in
/// `RouteMatcher.swift`.
private nonisolated struct AStarQueue {
    private var elements: [(priority: Double, node: Int)] = []

    mutating func push(priority: Double, node: Int) {
        elements.append((priority, node))
        var i = elements.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            guard elements[parent].priority > elements[i].priority else { break }
            elements.swapAt(parent, i)
            i = parent
        }
    }

    mutating func popMin() -> (priority: Double, node: Int)? {
        guard !elements.isEmpty else { return nil }
        let result = elements[0]
        let last = elements.removeLast()
        if !elements.isEmpty {
            elements[0] = last
            var i = 0
            while true {
                let left = 2 * i + 1, right = 2 * i + 2
                var smallest = i
                if left < elements.count, elements[left].priority < elements[smallest].priority { smallest = left }
                if right < elements.count, elements[right].priority < elements[smallest].priority { smallest = right }
                guard smallest != i else { break }
                elements.swapAt(i, smallest)
                i = smallest
            }
        }
        return result
    }
}
