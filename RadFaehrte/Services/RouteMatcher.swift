//
//  RouteMatcher.swift
//  RadFaehrte
//

import CoreLocation

struct RouteMatch: Identifiable {
    let route: BikeRoute
    let distanceToStartKm: Double
    let distanceToEndKm: Double
    /// Der Punkt auf der Routen-Geometrie, der dem Start am nächsten liegt.
    let nearestPointToStart: CLLocationCoordinate2D
    /// Der Punkt auf der Routen-Geometrie, der dem Ziel am nächsten liegt.
    let nearestPointToEnd: CLLocationCoordinate2D

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

    /// Streckenlänge entlang einer Route zwischen zwei Punkten. `distanceKm` ist stets die
    /// kürzeste Verbindung; `alternateDistanceKm` die Länge einer davon spürbar verschiedenen,
    /// längeren Alternative im selben Streckennetz (z. B. die andere Richtung bei einer
    /// Rundstrecke oder eine kartierte Alternativstrecke), falls vorhanden.
    struct RouteSegmentDistance {
        let distanceKm: Double
        let alternateDistanceKm: Double?
    }

    /// Baut aus den (üblicherweise unsortierten, aus einzelnen OSM-Way-Fragmenten bestehenden)
    /// Liniensegmenten einer Route ein Netz für Dijkstra-Suchen auf. Punkte werden per gerundeter
    /// Koordinate (`snapKey`) auf denselben Knoten dedupliziert; `attach` splict einen beliebigen
    /// Punkt (z. B. den nächstgelegenen Punkt zu Start/Ziel) in die Kante, auf der er projiziert
    /// liegt, statt einen exakten Knotentreffer vorauszusetzen.
    private struct RouteGraph {
        private(set) var nodeIndex: [Int64: Int] = [:]
        private(set) var adjacency: [[(to: Int, weightMeters: Double)]] = []

        init(lines: [[CLLocationCoordinate2D]]) {
            for line in lines {
                guard line.count >= 2 else { continue }
                var previousNode = node(for: line[0])
                for i in 1..<line.count {
                    let currentNode = node(for: line[i])
                    addEdge(previousNode, currentNode, meters: Self.meters(line[i - 1], line[i]))
                    previousNode = currentNode
                }
            }
        }

        private static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
            CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        }

        private static func snapKey(_ c: CLLocationCoordinate2D) -> Int64 {
            let lat = Int64((c.latitude * 100_000).rounded())
            let lon = Int64((c.longitude * 100_000).rounded())
            return lat &* 10_000_000 &+ lon
        }

        mutating func node(for c: CLLocationCoordinate2D) -> Int {
            let key = Self.snapKey(c)
            if let existing = nodeIndex[key] { return existing }
            let index = adjacency.count
            nodeIndex[key] = index
            adjacency.append([])
            return index
        }

        mutating func addEdge(_ a: Int, _ b: Int, meters distance: Double) {
            guard a != b, distance > 0 else { return }
            adjacency[a].append((b, distance))
            adjacency[b].append((a, distance))
        }

        mutating func attach(_ anchor: (coordinate: CLLocationCoordinate2D, distanceKm: Double, segmentStart: CLLocationCoordinate2D, segmentEnd: CLLocationCoordinate2D)) -> Int {
            let projectedNode = node(for: anchor.coordinate)
            addEdge(projectedNode, node(for: anchor.segmentStart), meters: Self.meters(anchor.coordinate, anchor.segmentStart))
            addEdge(projectedNode, node(for: anchor.segmentEnd), meters: Self.meters(anchor.coordinate, anchor.segmentEnd))
            return projectedNode
        }
    }

    /// Kürzeste (und, falls vorhanden, eine spürbar längere alternative) Verbindung entlang der
    /// Routen-Geometrie zwischen zwei Punkten (üblicherweise die jeweils nächstgelegenen Punkte
    /// zu Start und Ziel einer `RouteMatch`). Die Liniensegmente einer Route liegen in der
    /// Datenbank meist unsortiert vor (einzelne OSM-Way-Fragmente, nicht in Reihenfolge entlang
    /// der Strecke), daher wird ein Netz aus allen Segmenten aufgebaut und per Dijkstra der
    /// kürzeste Pfad gesucht. Für die Alternative werden dessen Kanten entfernt und erneut
    /// gesucht - bei einer Rundstrecke entspricht das der jeweils anderen Richtung.
    /// `nil`, wenn sich kein zusammenhängender Pfad finden lässt (z. B. Lücken im Wegenetz).
    nonisolated static func routeSegmentDistance(
        along lines: [[CLLocationCoordinate2D]], from: CLLocationCoordinate2D, to: CLLocationCoordinate2D
    ) -> RouteSegmentDistance? {
        guard !lines.isEmpty else { return nil }

        var graph = RouteGraph(lines: lines)

        guard let startAnchor = nearestPoint(from: from, toLines: lines),
              let endAnchor = nearestPoint(from: to, toLines: lines)
        else { return nil }

        let startNode = graph.attach(startAnchor)
        let endNode = graph.attach(endAnchor)

        guard let shortest = dijkstra(from: startNode, to: endNode, adjacency: graph.adjacency) else { return nil }

        // Kanten des kürzesten Pfads entfernen und erneut suchen, um eine davon unabhängige
        // Alternative zu finden (bei einer Rundstrecke: die andere Richtung).
        var reducedAdjacency = graph.adjacency
        for i in 1..<shortest.path.count {
            let a = shortest.path[i - 1], b = shortest.path[i]
            reducedAdjacency[a].removeAll { $0.to == b }
            reducedAdjacency[b].removeAll { $0.to == a }
        }
        let alternate = dijkstra(from: startNode, to: endNode, adjacency: reducedAdjacency)

        let distanceKm = shortest.distanceMeters / 1000
        let alternateKm = alternate.map { $0.distanceMeters / 1000 }
        // Nur als eigenständige Alternative ausweisen, wenn sie sich spürbar vom kürzesten
        // Pfad unterscheidet (sonst z. B. nur eine winzige Umfahrung um ein einzelnes Hindernis).
        let meaningfulAlternateKm = alternateKm.flatMap { abs($0 - distanceKm) > 0.3 ? $0 : nil }

        return RouteSegmentDistance(distanceKm: distanceKm, alternateDistanceKm: meaningfulAlternateKm)
    }

    /// Distanzen (Meter) von einem Punkt zu mehreren Zielen entlang derselben Routen-Geometrie -
    /// baut das Netz nur einmal auf und läuft mit einem einzigen Dijkstra-Durchlauf zu allen
    /// Zielen gleichzeitig, statt `routeSegmentDistance` pro Ziel einzeln aufzurufen. Genutzt von
    /// der Kombinationssuche (`findCombinedMatches`), um von einem Einstiegspunkt aus in einem
    /// Rutsch die Distanzen zu allen Anschlussstellen einer Route zu holen. `nil` je Ziel, wenn
    /// `from` sich nicht auf die Geometrie projizieren lässt oder das jeweilige Ziel unerreichbar
    /// ist (z. B. Lücke im Wegenetz).
    nonisolated static func routeSegmentDistances(
        along lines: [[CLLocationCoordinate2D]],
        from: CLLocationCoordinate2D,
        to targets: [CLLocationCoordinate2D]
    ) -> [Double?] {
        guard !lines.isEmpty, let fromAnchor = nearestPoint(from: from, toLines: lines) else {
            return targets.map { _ in nil }
        }

        var graph = RouteGraph(lines: lines)
        let fromNode = graph.attach(fromAnchor)
        let targetNodes = targets.map { target in
            nearestPoint(from: target, toLines: lines).map { graph.attach($0) }
        }

        let distances = dijkstraDistances(from: fromNode, adjacency: graph.adjacency)
        return targetNodes.map { node in
            guard let node, distances[node] < .greatestFiniteMagnitude else { return nil }
            return distances[node] / 1000
        }
    }

    private nonisolated static func dijkstra(
        from start: Int, to end: Int, adjacency: [[(to: Int, weightMeters: Double)]]
    ) -> (distanceMeters: Double, path: [Int])? {
        guard start != end else { return (0, [start]) }
        var bestDistance = [Double](repeating: .greatestFiniteMagnitude, count: adjacency.count)
        var predecessor = [Int](repeating: -1, count: adjacency.count)
        var visited = [Bool](repeating: false, count: adjacency.count)
        bestDistance[start] = 0
        var queue = DijkstraQueue()
        queue.push(distance: 0, node: start)

        while let current = queue.popMin() {
            guard !visited[current.node] else { continue }
            visited[current.node] = true
            if current.node == end {
                var path = [end]
                var node = end
                while node != start {
                    node = predecessor[node]
                    path.append(node)
                }
                return (current.distance, path.reversed())
            }
            for edge in adjacency[current.node] where !visited[edge.to] {
                let candidate = current.distance + edge.weightMeters
                if candidate < bestDistance[edge.to] {
                    bestDistance[edge.to] = candidate
                    predecessor[edge.to] = current.node
                    queue.push(distance: candidate, node: edge.to)
                }
            }
        }
        return nil
    }

    /// Wie `dijkstra(from:to:adjacency:)`, aber ohne festes Ziel: liefert die Distanz (Meter) zu
    /// JEDEM erreichbaren Knoten (`.greatestFiniteMagnitude` für unerreichbare), statt bei einem
    /// einzelnen Ziel früh abzubrechen und einen Pfad zu rekonstruieren. Für einen einzelnen
    /// Start-Knoten mit vielen Zielen (s. `routeSegmentDistances`) günstiger als `dijkstra` pro
    /// Ziel einzeln aufzurufen.
    private nonisolated static func dijkstraDistances(
        from start: Int, adjacency: [[(to: Int, weightMeters: Double)]]
    ) -> [Double] {
        var bestDistance = [Double](repeating: .greatestFiniteMagnitude, count: adjacency.count)
        var visited = [Bool](repeating: false, count: adjacency.count)
        bestDistance[start] = 0
        var queue = DijkstraQueue()
        queue.push(distance: 0, node: start)

        while let current = queue.popMin() {
            guard !visited[current.node] else { continue }
            visited[current.node] = true
            for edge in adjacency[current.node] where !visited[edge.to] {
                let candidate = current.distance + edge.weightMeters
                if candidate < bestDistance[edge.to] {
                    bestDistance[edge.to] = candidate
                    queue.push(distance: candidate, node: edge.to)
                }
            }
        }
        return bestDistance
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
            // Unbenannte Routen sind meist Fragmente lokaler Knotenpunkt-Netze (network=lcn),
            // die in OSM oft als viele einzelne, kurze Wegabschnitte statt als eine
            // durchgehende Route kartiert sind - für den Nutzer keine sinnvoll folgbare Route.
            guard let name = route.name, !name.isEmpty else { continue }
            guard let toStart = Self.nearestPoint(from: start, toLines: route.lines),
                  let toEnd = Self.nearestPoint(from: end, toLines: route.lines) else { continue }
            if toStart.distanceKm <= thresholdKm && toEnd.distanceKm <= thresholdKm {
                matches.append(RouteMatch(
                    route: route,
                    distanceToStartKm: toStart.distanceKm,
                    distanceToEndKm: toEnd.distanceKm,
                    nearestPointToStart: toStart.coordinate,
                    nearestPointToEnd: toEnd.coordinate
                ))
            }
        }
        return matches.sorted { $0.combinedDistanceKm < $1.combinedDistanceKm }
    }

    /// Fällt zurück auf die nächstgelegenen benannten Routen, falls `findMatches` nichts innerhalb
    /// des Schwellenwerts findet (z. B. weil Start oder Ziel abseits jedes kartierten Radfernwegs
    /// liegen). Anders als `findMatches` filtert diese Methode nicht nach `thresholdKm`, sondern
    /// gibt schlicht die `limit` nächstgelegenen Treffer zurück - anhand der angezeigten Entfernung
    /// (siehe `subtitle(for:)` in ContentView) erkennt der Nutzer selbst, ob sich die Anfahrt lohnt.
    func findClosestMatches(
        start: CLLocationCoordinate2D, end: CLLocationCoordinate2D,
        limit: Int = 3, searchRadiusKm: Double = 50
    ) -> [RouteMatch] {
        let minLat = min(start.latitude, end.latitude)
        let maxLat = max(start.latitude, end.latitude)
        let minLon = min(start.longitude, end.longitude)
        let maxLon = max(start.longitude, end.longitude)

        let latPad = searchRadiusKm / 111.32
        let midLat = (minLat + maxLat) / 2
        let lonPad = searchRadiusKm / (111.32 * max(cos(midLat * .pi / 180), 0.1))

        let candidates = repository.routesOverlapping(
            minLon: minLon - lonPad, minLat: minLat - latPad,
            maxLon: maxLon + lonPad, maxLat: maxLat + latPad
        )

        var matches: [RouteMatch] = []
        for route in candidates {
            guard let name = route.name, !name.isEmpty else { continue }
            guard let toStart = Self.nearestPoint(from: start, toLines: route.lines),
                  let toEnd = Self.nearestPoint(from: end, toLines: route.lines) else { continue }
            matches.append(RouteMatch(
                route: route,
                distanceToStartKm: toStart.distanceKm,
                distanceToEndKm: toEnd.distanceKm,
                nearestPointToStart: toStart.coordinate,
                nearestPointToEnd: toEnd.coordinate
            ))
        }
        return Array(matches.sorted { $0.combinedDistanceKm < $1.combinedDistanceKm }.prefix(limit))
    }

    /// Radrouten rund um einen einzelnen Punkt, unabhängig von einem Ziel - für die Vorschau
    /// direkt nach der Standortwahl, bevor ein Ziel eingegeben wurde. `distanceToStartKm` und
    /// `distanceToEndKm` sind hier identisch (beide = Distanz zum Punkt), da `RouteMatch`
    /// eigentlich für Start+Ziel-Paare gedacht ist - die UI verwendet für diesen Fall eine eigene
    /// Beschriftung statt `combinedDistanceKm` (siehe `ContentView.nearbySubtitle`).
    func findNearby(
        around point: CLLocationCoordinate2D, limit: Int = 10, searchRadiusKm: Double = 15
    ) -> [RouteMatch] {
        let latPad = searchRadiusKm / 111.32
        let lonPad = searchRadiusKm / (111.32 * max(cos(point.latitude * .pi / 180), 0.1))

        let candidates = repository.routesOverlapping(
            minLon: point.longitude - lonPad, minLat: point.latitude - latPad,
            maxLon: point.longitude + lonPad, maxLat: point.latitude + latPad
        )

        var nearby: [RouteMatch] = []
        for route in candidates {
            guard let name = route.name, !name.isEmpty else { continue }
            guard let nearest = Self.nearestPoint(from: point, toLines: route.lines),
                  nearest.distanceKm <= searchRadiusKm else { continue }
            nearby.append(RouteMatch(
                route: route,
                distanceToStartKm: nearest.distanceKm,
                distanceToEndKm: nearest.distanceKm,
                nearestPointToStart: nearest.coordinate,
                nearestPointToEnd: nearest.coordinate
            ))
        }
        return Array(nearby.sorted { $0.distanceToStartKm < $1.distanceToStartKm }.prefix(limit))
    }

    /// Eine Etappe einer kombinierten Route - eine einzelne benannte Fernwegs-Route, befahren von
    /// `entryPoint` (Nutzer-Start oder Anschluss zur vorigen Etappe) bis `exitPoint` (Anschluss
    /// zur nächsten Etappe oder Nutzer-Ziel).
    struct CombinedRouteLeg: Identifiable {
        let route: BikeRoute
        let entryPoint: CLLocationCoordinate2D
        let exitPoint: CLLocationCoordinate2D
        let distanceKm: Double
        var id: Int64 { route.id }
    }

    /// Ergebnis von `findCombinedMatches`: mehrere benannte Fernwege, die an Anschlussstellen
    /// aneinandergereiht Start und Ziel verbinden, weil keine einzelne Route das allein schafft.
    struct CombinedRouteMatch: Identifiable {
        let legs: [CombinedRouteLeg]
        /// Luftlinie vom Nutzer-Start zum Einstiegspunkt der ersten Etappe.
        let distanceToStartKm: Double
        /// Luftlinie vom Ausstiegspunkt der letzten Etappe zum Nutzer-Ziel.
        let distanceToEndKm: Double

        var id: String { legs.map { String($0.id) }.joined(separator: "-") }
        var totalDistanceKm: Double { legs.reduce(0) { $0 + $1.distanceKm } }
        var routeNames: [String] { legs.map { $0.route.name ?? "Unbenannte Route" } }
    }

    /// Nur `rcn`/`ncn`/`icn` (regionale/nationale/internationale Fernwege) kommen für eine
    /// Kombination infrage - die deutlich zahlreicheren lokalen `lcn`-Knotenpunktnetz-Fragmente
    /// sind dafür zu kleinteilig/unübersichtlich (s. Machbarkeitsanalyse: 7.018 rcn/ncn/icn-Routen,
    /// 99% davon mit mind. einer Anschlussstelle).
    private static let combinableNetworks: Set<String> = ["rcn", "ncn", "icn"]

    /// Viele Regionen taggen ihr lokales Knotenpunkt-Wegenetz (einzelne Abschnitte zwischen
    /// nummerierten Knoten) mit `network=rcn` statt `lcn` - am `network`-Tag allein nicht von
    /// einem echten Fernweg zu unterscheiden. Zwei beobachtete Namensmuster (s. auch
    /// `Scripts/find_route_junctions.py`, das dieselben Muster beim Bau der Anschluss-Tabelle
    /// ausschließt): rein numerisch ("31-32") und Ort+Knotennummer ("Lohne (76) - Dinklage (78)",
    /// über die Hälfte aller benannten rcn/ncn/icn-Routen in Deutschland folgt diesem Muster).
    /// Hier zusätzlich geprüft, damit auch die Start-/Ziel-Kandidatensuche (unabhängig von der
    /// Anschluss-Tabelle) nicht versehentlich so ein Wegstück auswählt.
    private static let nodeToNodeNamePatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"^\d+\s*-\s*\d+$"#),
        try! NSRegularExpression(pattern: #".*\(\d+\).*-.*\(\d+\).*"#),
    ]

    private static func isNodeToNodeSegment(name: String) -> Bool {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return nodeToNodeNamePatterns.contains { $0.firstMatch(in: name, range: range) != nil }
    }

    private struct CombinableRouteCandidate {
        let route: BikeRoute
        let nearestPoint: CLLocationCoordinate2D
    }

    private nonisolated func combinableRoutes(
        near point: CLLocationCoordinate2D, searchRadiusKm: Double
    ) -> [CombinableRouteCandidate] {
        let latPad = searchRadiusKm / 111.32
        let lonPad = searchRadiusKm / (111.32 * max(cos(point.latitude * .pi / 180), 0.1))

        let candidates = repository.routesOverlapping(
            minLon: point.longitude - lonPad, minLat: point.latitude - latPad,
            maxLon: point.longitude + lonPad, maxLat: point.latitude + latPad
        )

        var results: [CombinableRouteCandidate] = []
        for route in candidates {
            guard let name = route.name, !name.isEmpty, !Self.isNodeToNodeSegment(name: name) else { continue }
            guard let network = route.network, Self.combinableNetworks.contains(network) else { continue }
            guard let nearest = Self.nearestPoint(from: point, toLines: route.lines),
                  nearest.distanceKm <= searchRadiusKm else { continue }
            results.append(CombinableRouteCandidate(route: route, nearestPoint: nearest.coordinate))
        }
        return results
    }

    private struct CombinedSearchEntry {
        let routeId: Int64
        let entryPoint: CLLocationCoordinate2D
        let cumulativeKm: Double
        let legs: [CombinedRouteLeg]
    }

    /// Einfache Array-basierte Min-Heap-Warteschlange für `findCombinedMatches`, analog zu
    /// `DijkstraQueue`, aber mit dem größeren `CombinedSearchEntry`-Payload statt nur einer Node-ID.
    private struct CombinedSearchQueue {
        private var heap: [CombinedSearchEntry] = []

        mutating func push(_ entry: CombinedSearchEntry) {
            heap.append(entry)
            var i = heap.count - 1
            while i > 0 {
                let parent = (i - 1) / 2
                guard heap[i].cumulativeKm < heap[parent].cumulativeKm else { break }
                heap.swapAt(i, parent)
                i = parent
            }
        }

        mutating func popMin() -> CombinedSearchEntry? {
            guard !heap.isEmpty else { return nil }
            heap.swapAt(0, heap.count - 1)
            let result = heap.removeLast()
            var i = 0
            while true {
                let left = 2 * i + 1, right = 2 * i + 2
                var smallest = i
                if left < heap.count, heap[left].cumulativeKm < heap[smallest].cumulativeKm { smallest = left }
                if right < heap.count, heap[right].cumulativeKm < heap[smallest].cumulativeKm { smallest = right }
                guard smallest != i else { break }
                heap.swapAt(i, smallest)
                i = smallest
            }
            return result
        }
    }

    /// Sucht eine Kette aus mehreren benannten Fernwegen, die zusammen Start und Ziel verbinden -
    /// gedacht als Fallback, wenn `findMatches` keine einzelne passende Route findet (z. B.
    /// Bremen -> Hannover über Weser-Radweg -> Aller-Radweg -> Leine-Heide-Radweg). Läuft als
    /// gewichteter Dijkstra über einen impliziten Graphen: Knoten sind (Route, Einstiegspunkt),
    /// Kanten die reale Streckenlänge zu den Anschlusspunkten dieser Route (aus der per
    /// `Scripts/find_route_junctions.py` vorberechneten Sidecar-DB), lazy pro besuchter Route
    /// berechnet über `routeSegmentDistances`. Bewusst ohne feste Obergrenze an Etappen (eine
    /// längere Strecke wie Bremen -> Leipzig braucht plausibel mehr als 2-3 Etappen) - stattdessen
    /// zwei Sicherheitsgrenzen gegen ausufernde Suchen: maximal `maxVisitedRoutes` besuchte Routen,
    /// und ein Abbruch für Pfade, die bereits das `maxDistanceMultiplier`-fache der Luftlinie
    /// Start-Ziel überschreiten (eine so uneffiziente Kette wäre ohnehin kein sinnvoller Vorschlag).
    /// `nil`, wenn keine Kette gefunden wird oder Start/Ziel keine kombinierbare Route in der Nähe
    /// haben. Rein lesende SQLite-Abfragen + mehrere Pro-Route-Dijkstras - bewusst `nonisolated`,
    /// damit der Aufrufer das abseits des Main-Threads laufen lassen kann (s. `ContentView`).
    nonisolated func findCombinedMatches(
        start: CLLocationCoordinate2D, end: CLLocationCoordinate2D,
        maxVisitedRoutes: Int = 500, maxDistanceMultiplier: Double = 3
    ) -> CombinedRouteMatch? {
        let startCandidates = combinableRoutes(near: start, searchRadiusKm: thresholdKm)
        let endCandidates = combinableRoutes(near: end, searchRadiusKm: thresholdKm)
        guard !startCandidates.isEmpty, !endCandidates.isEmpty else { return nil }

        var endAnchorByRouteId: [Int64: CLLocationCoordinate2D] = [:]
        for candidate in endCandidates {
            endAnchorByRouteId[candidate.route.id] = candidate.nearestPoint
        }

        let straightLineKm = Self.kilometers(start, end)
        let maxAllowedKm = max(straightLineKm * maxDistanceMultiplier, 30)

        var routeCache: [Int64: BikeRoute] = [:]
        for candidate in startCandidates { routeCache[candidate.route.id] = candidate.route }
        for candidate in endCandidates { routeCache[candidate.route.id] = candidate.route }

        func route(withId id: Int64) -> BikeRoute? {
            if let cached = routeCache[id] { return cached }
            guard let fetched = repository.route(withId: id) else { return nil }
            routeCache[id] = fetched
            return fetched
        }

        var bestDistanceKm: [Int64: Double] = [:]
        var finalized: Set<Int64> = []
        var queue = CombinedSearchQueue()

        for candidate in startCandidates {
            guard bestDistanceKm[candidate.route.id] == nil else { continue }
            bestDistanceKm[candidate.route.id] = 0
            queue.push(CombinedSearchEntry(
                routeId: candidate.route.id, entryPoint: candidate.nearestPoint, cumulativeKm: 0, legs: []
            ))
        }

        var visitedCount = 0
        while let current = queue.popMin() {
            guard !finalized.contains(current.routeId) else { continue }
            finalized.insert(current.routeId)

            visitedCount += 1
            guard visitedCount <= maxVisitedRoutes else { return nil }
            guard current.cumulativeKm <= maxAllowedKm else { continue }
            guard let currentRoute = route(withId: current.routeId) else { continue }

            // Ziel schon erreicht? (Kann bei der allerersten Etappe nicht zutreffen - sonst
            // hätte `findMatches` diese Route bereits als Direkttreffer gefunden.)
            if !current.legs.isEmpty, let endAnchor = endAnchorByRouteId[current.routeId],
               let finishKm = RouteMatcher.routeSegmentDistances(
                   along: currentRoute.lines, from: current.entryPoint, to: [endAnchor]
               ).first, let finishKmValue = finishKm {
                let finalLeg = CombinedRouteLeg(
                    route: currentRoute, entryPoint: current.entryPoint, exitPoint: endAnchor, distanceKm: finishKmValue
                )
                let allLegs = current.legs + [finalLeg]
                return CombinedRouteMatch(
                    legs: allLegs,
                    distanceToStartKm: Self.kilometers(start, allLegs[0].entryPoint),
                    distanceToEndKm: Self.kilometers(allLegs[allLegs.count - 1].exitPoint, end)
                )
            }

            let neighbors = repository.junctions(forRouteId: current.routeId)
            guard !neighbors.isEmpty else { continue }
            let neighborCoordinates = neighbors.map { $0.coordinate }
            let legDistances = RouteMatcher.routeSegmentDistances(
                along: currentRoute.lines, from: current.entryPoint, to: neighborCoordinates
            )

            for (index, neighbor) in neighbors.enumerated() {
                guard !finalized.contains(neighbor.partnerRouteId),
                      let legDistanceKm = legDistances[index] else { continue }
                let newCumulativeKm = current.cumulativeKm + legDistanceKm
                if let known = bestDistanceKm[neighbor.partnerRouteId], known <= newCumulativeKm { continue }
                bestDistanceKm[neighbor.partnerRouteId] = newCumulativeKm
                let leg = CombinedRouteLeg(
                    route: currentRoute, entryPoint: current.entryPoint, exitPoint: neighbor.coordinate, distanceKm: legDistanceKm
                )
                queue.push(CombinedSearchEntry(
                    routeId: neighbor.partnerRouteId, entryPoint: neighbor.coordinate,
                    cumulativeKm: newCumulativeKm, legs: current.legs + [leg]
                ))
            }
        }
        return nil
    }

    private nonisolated static func kilometers(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1000
    }

    /// Nächstgelegener Punkt auf einer Liniengeometrie zu einem Punkt, mit Distanz in km.
    /// Rechnet lokal in einer ebenen Näherung um den Punkt (ausreichend genau
    /// auf der hier relevanten Skala von wenigen Kilometern).
    nonisolated static func nearestPoint(
        from point: CLLocationCoordinate2D, toLines lines: [[CLLocationCoordinate2D]]
    ) -> (coordinate: CLLocationCoordinate2D, distanceKm: Double, segmentStart: CLLocationCoordinate2D, segmentEnd: CLLocationCoordinate2D)? {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * max(cos(point.latitude * .pi / 180), 0.1)

        func toLocal(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            (
                (c.longitude - point.longitude) * metersPerDegreeLon,
                (c.latitude - point.latitude) * metersPerDegreeLat
            )
        }
        func toCoordinate(_ p: (x: Double, y: Double)) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(
                latitude: point.latitude + p.y / metersPerDegreeLat,
                longitude: point.longitude + p.x / metersPerDegreeLon
            )
        }

        let origin = (x: 0.0, y: 0.0)
        var bestDistance = Double.greatestFiniteMagnitude
        var bestPoint: (x: Double, y: Double)?
        var bestSegment: (start: CLLocationCoordinate2D, end: CLLocationCoordinate2D)?

        for line in lines {
            guard line.count >= 2 else { continue }
            var prev = toLocal(line[0])
            for i in 1..<line.count {
                let curr = toLocal(line[i])
                let (distance, projected) = closestPointOnSegmentMeters(point: origin, a: prev, b: curr)
                if distance < bestDistance {
                    bestDistance = distance
                    bestPoint = projected
                    bestSegment = (line[i - 1], line[i])
                }
                prev = curr
            }
        }
        guard let bestPoint, let bestSegment, bestDistance.isFinite else { return nil }
        return (toCoordinate(bestPoint), bestDistance / 1000, bestSegment.start, bestSegment.end)
    }

    /// Projiziert einen Punkt auf ein einzelnes, vorgegebenes Liniensegment statt auf die
    /// komplette Routen-Geometrie - für die Trägheit beim Einrasten in
    /// `ContentView.snapToActiveRoute` (bevorzugt das zuletzt genutzte Segment, um Zickzack an
    /// Kurven/Ecken zu vermeiden).
    nonisolated static func nearestPoint(
        from point: CLLocationCoordinate2D,
        onSegment segmentStart: CLLocationCoordinate2D,
        _ segmentEnd: CLLocationCoordinate2D
    ) -> (coordinate: CLLocationCoordinate2D, distanceKm: Double) {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * max(cos(point.latitude * .pi / 180), 0.1)

        func toLocal(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            (
                (c.longitude - point.longitude) * metersPerDegreeLon,
                (c.latitude - point.latitude) * metersPerDegreeLat
            )
        }
        func toCoordinate(_ p: (x: Double, y: Double)) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(
                latitude: point.latitude + p.y / metersPerDegreeLat,
                longitude: point.longitude + p.x / metersPerDegreeLon
            )
        }

        let (distance, projected) = closestPointOnSegmentMeters(
            point: (x: 0, y: 0), a: toLocal(segmentStart), b: toLocal(segmentEnd)
        )
        return (toCoordinate(projected), distance / 1000)
    }

    private nonisolated static func closestPointOnSegmentMeters(
        point p: (x: Double, y: Double), a: (x: Double, y: Double), b: (x: Double, y: Double)
    ) -> (distance: Double, point: (x: Double, y: Double)) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy

        if lengthSquared == 0 {
            let ex = p.x - a.x, ey = p.y - a.y
            return ((ex * ex + ey * ey).squareRoot(), a)
        }

        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        let ex = p.x - projX, ey = p.y - projY
        return ((ex * ex + ey * ey).squareRoot(), (projX, projY))
    }
}

/// Binärer Min-Heap für Dijkstra, geordnet nach Distanz.
private nonisolated struct DijkstraQueue {
    private var elements: [(distance: Double, node: Int)] = []

    mutating func push(distance: Double, node: Int) {
        elements.append((distance, node))
        var i = elements.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            guard elements[parent].distance > elements[i].distance else { break }
            elements.swapAt(parent, i)
            i = parent
        }
    }

    mutating func popMin() -> (distance: Double, node: Int)? {
        guard !elements.isEmpty else { return nil }
        let result = elements[0]
        let last = elements.removeLast()
        if !elements.isEmpty {
            elements[0] = last
            var i = 0
            while true {
                let left = 2 * i + 1, right = 2 * i + 2
                var smallest = i
                if left < elements.count, elements[left].distance < elements[smallest].distance { smallest = left }
                if right < elements.count, elements[right].distance < elements[smallest].distance { smallest = right }
                guard smallest != i else { break }
                elements.swapAt(i, smallest)
                i = smallest
            }
        }
        return result
    }
}
