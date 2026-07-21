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

        var nodeIndex: [Int64: Int] = [:]
        var adjacency: [[(to: Int, weightMeters: Double)]] = []

        func snapKey(_ c: CLLocationCoordinate2D) -> Int64 {
            let lat = Int64((c.latitude * 100_000).rounded())
            let lon = Int64((c.longitude * 100_000).rounded())
            return lat &* 10_000_000 &+ lon
        }

        func node(for c: CLLocationCoordinate2D) -> Int {
            let key = snapKey(c)
            if let existing = nodeIndex[key] { return existing }
            let index = adjacency.count
            nodeIndex[key] = index
            adjacency.append([])
            return index
        }

        func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
            CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        }

        func addEdge(_ a: Int, _ b: Int, meters distance: Double) {
            guard a != b, distance > 0 else { return }
            adjacency[a].append((b, distance))
            adjacency[b].append((a, distance))
        }

        for line in lines {
            guard line.count >= 2 else { continue }
            var previousNode = node(for: line[0])
            for i in 1..<line.count {
                let currentNode = node(for: line[i])
                addEdge(previousNode, currentNode, meters: meters(line[i - 1], line[i]))
                previousNode = currentNode
            }
        }

        func attach(_ anchor: (coordinate: CLLocationCoordinate2D, distanceKm: Double, segmentStart: CLLocationCoordinate2D, segmentEnd: CLLocationCoordinate2D)) -> Int {
            let projectedNode = node(for: anchor.coordinate)
            addEdge(projectedNode, node(for: anchor.segmentStart), meters: meters(anchor.coordinate, anchor.segmentStart))
            addEdge(projectedNode, node(for: anchor.segmentEnd), meters: meters(anchor.coordinate, anchor.segmentEnd))
            return projectedNode
        }

        guard let startAnchor = nearestPoint(from: from, toLines: lines),
              let endAnchor = nearestPoint(from: to, toLines: lines)
        else { return nil }

        let startNode = attach(startAnchor)
        let endNode = attach(endAnchor)

        guard let shortest = dijkstra(from: startNode, to: endNode, adjacency: adjacency) else { return nil }

        // Kanten des kürzesten Pfads entfernen und erneut suchen, um eine davon unabhängige
        // Alternative zu finden (bei einer Rundstrecke: die andere Richtung).
        var reducedAdjacency = adjacency
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
