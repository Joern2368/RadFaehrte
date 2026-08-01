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
    }

    /// Knoten werden als dichte 0-basierte Array-Indizes referenziert (siehe
    /// `WayGraphRepository`), nicht die ursprünglichen OSM-IDs.
    private struct EdgeKey: Hashable {
        let from: Int
        let to: Int
    }

    /// Einzelne "ruhigste" Route zwischen zwei Punkten - Kurzform von
    /// `routes(from:to:maxAlternatives:)` ohne Alternativen. `maxVisitedNodes` s. dort.
    func route(
        from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D,
        maxVisitedNodes: Int = BikeRoutingEngine.maxVisitedNodes
    ) -> Result? {
        routes(from: start, to: end, maxAlternatives: 0, maxVisitedNodes: maxVisitedNodes).first
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
        maxVisitedNodes: Int = BikeRoutingEngine.maxVisitedNodes
    ) -> [Result] {
        guard let startNode = repository.nearestNode(to: start),
              let endNode = repository.nearestNode(to: end)
        else { return [] }

        var results: [Result] = []
        var excludedEdges: Set<EdgeKey> = []

        for _ in 0...maxAlternatives {
            guard let (result, path) = search(from: startNode, to: endNode, excluding: excludedEdges, maxVisitedNodes: maxVisitedNodes)
            else { break }
            results.append(result)
            for i in 1..<path.count {
                excludedEdges.insert(EdgeKey(from: path[i - 1], to: path[i]))
            }
        }
        return results
    }

    /// Dictionaries statt Arrays über die volle Knotenzahl, obwohl Knoten dichte Indizes haben:
    /// eine A*-Suche berührt bei einem großen Bundesland (Millionen Knoten) typischerweise nur
    /// einen kleinen, lokalen Ausschnitt - Arrays in Graphgröße vorzuallozieren wäre für jede
    /// einzelne Suche unnötig speicherhungrig.
    private func search(
        from startNode: Int, to endNode: Int, excluding excludedEdges: Set<EdgeKey>, maxVisitedNodes: Int
    ) -> (Result, [Int])? {
        guard endNode < repository.nodeLocations.count else { return nil }
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
        var visited: Set<Int> = []
        var queue = AStarQueue()
        queue.push(priority: heuristic(startNode), node: startNode)

        while let current = queue.popMin() {
            guard !visited.contains(current.node) else { continue }
            visited.insert(current.node)
            if current.node == endNode { break }
            guard visited.count < maxVisitedNodes else { return nil }

            for edge in repository.edges(from: current.node) {
                let toNode = Int(edge.toNode)
                guard !visited.contains(toNode),
                      !excludedEdges.contains(EdgeKey(from: current.node, to: toNode))
                else { continue }
                let tentativeG = (gScore[current.node] ?? .greatestFiniteMagnitude) + Double(edge.weight)
                if tentativeG < (gScore[toNode] ?? .greatestFiniteMagnitude) {
                    gScore[toNode] = tentativeG
                    realDistance[toNode] = (realDistance[current.node] ?? 0) + Double(edge.distanceMeters)
                    cameFrom[toNode] = current.node
                    cameFromOffsetSide[toNode] = Int(edge.offsetSide)
                    cameFromNameIndex[toNode] = edge.nameIndex
                    queue.push(priority: tentativeG + heuristic(toNode), node: toNode)
                }
            }
        }

        guard gScore[endNode] != nil else { return nil }

        var path = [endNode]
        var node = endNode
        while let prev = cameFrom[node] {
            path.append(prev)
            node = prev
        }
        path.reverse()

        let result = Result(
            coordinates: Self.displayCoordinates(for: path, offsetSide: cameFromOffsetSide, repository: repository),
            distanceMeters: realDistance[endNode] ?? 0,
            steps: Self.buildSteps(path: path, nameIndex: cameFromNameIndex, repository: repository)
        )
        return (result, path)
    }

    /// Gruppiert den Pfad in Abschnitte mit demselben Straßennamen (`WayGraphRepository.Edge.
    /// nameIndex`) - ein neuer Schritt beginnt, sobald sich der Name ändert (auch von/zu
    /// unbenannt). Für jeden Übergang wird aus der Winkeländerung zwischen der letzten Kante des
    /// vorherigen und der ersten Kante des neuen Abschnitts grob eine Abbiege-Richtung geschätzt -
    /// ohne die Kreuzungs-/Namensänderungs-Heuristiken echter Navigations-Engines, kann also bei
    /// sanften Straßenschwenks gelegentlich daneben liegen (Live-Test/Kalibrierung nötig).
    ///
    /// Bewusst nicht `private` (wie der Rest der A*-Interna dieser Klasse): `CuratedRouteStepMatcher`
    /// baut Knotenpfade auf andere Weise auf (Map-Matching statt A*-Suche), nutzt für die
    /// eigentliche Namens-/Richtungs-Aufbereitung aber dieselbe Logik statt sie zu duplizieren.
    static func buildSteps(
        path: [Int], nameIndex: [Int: UInt32], repository: WayGraphRepository
    ) -> [Result.Step] {
        guard path.count >= 2 else { return [] }

        func bearing(ofEdgeEndingAt edgeEnd: Int) -> Double {
            bearingDegrees(
                from: repository.nodeLocations[path[edgeEnd - 1]],
                to: repository.nodeLocations[path[edgeEnd]]
            )
        }

        var steps: [Result.Step] = []
        var groupStart = 1
        var groupNameIndex = nameIndex[path[1]] ?? WayGraphRepository.noNameIndex

        func closeGroup(end: Int) {
            let incomingBearing = groupStart > 1 ? bearing(ofEdgeEndingAt: groupStart - 1) : nil
            let outgoingBearing = bearing(ofEdgeEndingAt: groupStart)
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
    /// vergleichen ließe. Schwellenwerte (20°/120°) grob geschätzt, nicht gegen echte Kreuzungen
    /// kalibriert.
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
        guard magnitude >= 20 else {
            return (name.map { "Weiter auf \($0)" } ?? "Route folgen", .straight)
        }
        let isRight = delta > 0
        let turn = magnitude >= 120
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
        var coordinates: [CLLocationCoordinate2D] = []
        for i in 1..<path.count {
            let from = repository.nodeLocations[path[i - 1]]
            let to = repository.nodeLocations[path[i]]
            let side = offsetSide[path[i]] ?? 0
            let (offsetFrom, offsetTo) = offsetPoint(from: from, to: to, side: side, meters: cycleOffsetMeters)
            if coordinates.isEmpty {
                coordinates.append(offsetFrom)
            }
            coordinates.append(offsetTo)
        }
        return coordinates
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
