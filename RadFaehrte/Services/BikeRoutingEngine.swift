//
//  BikeRoutingEngine.swift
//  RadFaehrte
//

import CoreLocation

/// Eigene, offline arbeitende Fahrrad-Routing-Engine über das lokale OSM-Wegenetz
/// (Testregion, siehe `WayGraphRepository`). Bevorzugt Radwege/ruhige Straßen und
/// meidet Hauptstraßen (siehe `WaySegment.costFactor`), anders als Apples
/// MKDirections, das dafür keine öffentliche Stellschraube bietet.
///
/// Lädt nur einen Teilgraphen in einer gepufferten Bounding Box um Start+Ziel
/// (analog zu `RouteMatcher.findMatches`), nicht das gesamte Wegenetz - dadurch
/// reicht ein einfacher A*-Algorithmus ohne Contraction Hierarchies für
/// regionale/städtische Strecken aus.
final class BikeRoutingEngine {
    private let repository: WayGraphRepository

    init(repository: WayGraphRepository) {
        self.repository = repository
    }

    struct Route {
        let coordinates: [CLLocationCoordinate2D]
        let distanceMeters: Double
    }

    /// Berechnet die "ruhigste" Route von `start` zu `end`, oder `nil` falls kein Weg
    /// gefunden wurde (z. B. weil die Region nicht abgedeckt ist oder Start/Ziel isoliert
    /// liegen).
    func route(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Route? {
        routes(from: start, to: end, count: 1).first
    }

    /// Berechnet bis zu `count` Routenalternativen von `start` zu `end`, sortiert von der
    /// "ruhigsten" Route absteigend. Nutzt eine iterative Penalty-Strategie statt eines
    /// vollständigen k-kürzeste-Wege-Algorithmus (z. B. Yen's): nach jeder gefundenen Route
    /// werden ihre Kanten für die nächste Suche stark verteuert (nicht gesperrt, damit auch
    /// bei einem einzigen Zugang zu Start/Ziel noch ein Weg gefunden wird), sodass A* einen
    /// spürbar abweichenden Korridor wählt. Für die überschaubaren Teilgraphen einer
    /// Stadt/Region reicht das aus.
    func routes(
        from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D, count: Int = 4
    ) -> [Route] {
        let latPad = Self.bufferKm / 111.32
        let midLat = (start.latitude + end.latitude) / 2
        let lonPad = Self.bufferKm / (111.32 * max(cos(midLat * .pi / 180), 0.1))

        let minLat = min(start.latitude, end.latitude) - latPad
        let maxLat = max(start.latitude, end.latitude) + latPad
        let minLon = min(start.longitude, end.longitude) - lonPad
        let maxLon = max(start.longitude, end.longitude) + lonPad

        let segments = repository.segmentsOverlapping(
            minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat
        )
        guard !segments.isEmpty else { return [] }

        let graph = Graph(segments: segments)
        guard let startNode = graph.nearestNode(to: start),
              let endNode = graph.nearestNode(to: end) else { return [] }

        var results: [Route] = []
        var seenNodePaths: [[Int64]] = []
        var penalizedEdges: Set<String> = []

        for _ in 0..<count {
            guard let (route, nodePath) = graph.shortestPath(
                from: startNode, to: endNode, avoiding: penalizedEdges
            ) else { break }

            if !seenNodePaths.contains(nodePath) {
                results.append(route)
                seenNodePaths.append(nodePath)
            }
            for i in 1..<nodePath.count {
                penalizedEdges.insert(Graph.edgeKey(nodePath[i - 1], nodePath[i]))
            }
        }
        return results
    }

    /// Bounding-Box-Puffer um Start/Ziel, in denen nach Wegen gesucht wird.
    private static let bufferKm: Double = 2
}

/// In-Memory-Graph für die A*-Suche über einen Teilausschnitt des Wegenetzes.
private final class Graph {
    private struct Edge {
        let toNode: Int64
        let coordinates: [CLLocationCoordinate2D]
        let cost: Double
    }

    private var adjacency: [Int64: [Edge]] = [:]
    private var nodeCoordinate: [Int64: CLLocationCoordinate2D] = [:]

    init(segments: [WaySegment]) {
        for segment in segments {
            guard let first = segment.coordinates.first, let last = segment.coordinates.last else { continue }
            nodeCoordinate[segment.fromNode] = first
            nodeCoordinate[segment.toNode] = last

            let length = segment.lengthMeters
            let cost = length * segment.costFactor

            if segment.oneway >= 0 {
                adjacency[segment.fromNode, default: []].append(
                    Edge(toNode: segment.toNode, coordinates: segment.coordinates, cost: cost)
                )
            }
            if segment.oneway <= 0 {
                adjacency[segment.toNode, default: []].append(
                    Edge(toNode: segment.fromNode, coordinates: segment.coordinates.reversed(), cost: cost)
                )
            }
        }
    }

    /// Nächstgelegener Graph-Knoten zu einem beliebigen Punkt (einfache lineare Suche,
    /// ausreichend für die wenigen tausend Knoten im geladenen Teilgraphen).
    func nearestNode(to point: CLLocationCoordinate2D) -> Int64? {
        let target = CLLocation(latitude: point.latitude, longitude: point.longitude)
        var best: (id: Int64, distance: CLLocationDistance)?
        for (id, coordinate) in nodeCoordinate {
            let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude).distance(from: target)
            if best == nil || distance < best!.distance {
                best = (id, distance)
            }
        }
        return best?.id
    }

    /// Kanten, deren Schlüssel (siehe `edgeKey`) in `penalizedEdges` enthalten ist, werden
    /// stark verteuert statt komplett gesperrt - so bleibt auch dann noch ein (längerer) Weg
    /// auffindbar, wenn eine bereits gefundene Route den einzigen Zugang zu Start oder Ziel
    /// darstellt.
    func shortestPath(
        from start: Int64, to end: Int64, avoiding penalizedEdges: Set<String> = []
    ) -> (route: BikeRoutingEngine.Route, nodePath: [Int64])? {
        var gScore: [Int64: Double] = [start: 0]
        var cameFrom: [Int64: (node: Int64, coordinates: [CLLocationCoordinate2D])] = [:]
        var visited: Set<Int64> = []
        var openSet = MinHeap<Int64>()
        openSet.insert(start, priority: heuristic(start, end))

        while let current = openSet.extractMin() {
            if current == end {
                return reconstructPath(cameFrom: cameFrom, end: end)
            }
            guard !visited.contains(current) else { continue }
            visited.insert(current)

            for edge in adjacency[current] ?? [] {
                guard !visited.contains(edge.toNode) else { continue }
                var edgeCost = edge.cost
                if penalizedEdges.contains(Self.edgeKey(current, edge.toNode)) {
                    edgeCost *= 6
                }
                let tentativeGScore = (gScore[current] ?? .infinity) + edgeCost
                if tentativeGScore < (gScore[edge.toNode] ?? .infinity) {
                    gScore[edge.toNode] = tentativeGScore
                    cameFrom[edge.toNode] = (current, edge.coordinates)
                    openSet.insert(edge.toNode, priority: tentativeGScore + heuristic(edge.toNode, end))
                }
            }
        }
        return nil
    }

    static func edgeKey(_ a: Int64, _ b: Int64) -> String {
        a < b ? "\(a)_\(b)" : "\(b)_\(a)"
    }

    private func heuristic(_ node: Int64, _ end: Int64) -> Double {
        guard let a = nodeCoordinate[node], let b = nodeCoordinate[end] else { return 0 }
        return CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    private func reconstructPath(
        cameFrom: [Int64: (node: Int64, coordinates: [CLLocationCoordinate2D])],
        end: Int64
    ) -> (route: BikeRoutingEngine.Route, nodePath: [Int64]) {
        var coordinates: [CLLocationCoordinate2D] = []
        var nodePath: [Int64] = [end]
        var current = end
        while let step = cameFrom[current] {
            coordinates.append(contentsOf: step.coordinates.reversed())
            current = step.node
            nodePath.append(current)
        }
        coordinates.reverse()
        nodePath.reverse()

        var distance = 0.0
        for i in 1..<max(coordinates.count, 1) where i < coordinates.count {
            distance += CLLocation(latitude: coordinates[i - 1].latitude, longitude: coordinates[i - 1].longitude)
                .distance(from: CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude))
        }
        return (BikeRoutingEngine.Route(coordinates: coordinates, distanceMeters: distance), nodePath)
    }
}

/// Einfache Binär-Heap-Priority-Queue für A* (O(log n) statt O(n log n) pro Schritt
/// bei einer vollständigen Sortierung des offenen Sets).
private struct MinHeap<Element> {
    private var items: [(element: Element, priority: Double)] = []

    var isEmpty: Bool { items.isEmpty }

    mutating func insert(_ element: Element, priority: Double) {
        items.append((element, priority))
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            guard items[i].priority < items[parent].priority else { break }
            items.swapAt(i, parent)
            i = parent
        }
    }

    mutating func extractMin() -> Element? {
        guard !items.isEmpty else { return nil }
        let min = items[0]
        items[0] = items[items.count - 1]
        items.removeLast()

        var i = 0
        while true {
            let left = 2 * i + 1, right = 2 * i + 2
            var smallest = i
            if left < items.count && items[left].priority < items[smallest].priority { smallest = left }
            if right < items.count && items[right].priority < items[smallest].priority { smallest = right }
            guard smallest != i else { break }
            items.swapAt(i, smallest)
            i = smallest
        }
        return min.element
    }
}
