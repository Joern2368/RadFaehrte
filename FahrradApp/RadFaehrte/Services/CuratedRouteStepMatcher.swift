//
//  CuratedRouteStepMatcher.swift
//  RadFaehrte
//

import CoreLocation

/// Map-Matching-Versuch (s. ROADMAP.md): ordnet einem Streckenabschnitt einer kuratierten Radroute
/// (z. B. `RouteMatcher.routeSegmentPath`) Straßennamen + Abbiege-Hinweise zu, indem er gegen den
/// lokal heruntergeladenen Wege-Graphen (`WayGraphRepository`, sonst nur für die Offline-Engine
/// `BikeRoutingEngine` genutzt) gestitcht wird.
///
/// ⚠️ **Historie**: Die erste Version routete zwischen alle 300 m abgetasteten Stützpunkten per
/// `BikeRoutingEngine.route` (derselben "ruhigsten Route"-Suche wie die Offline-Engine). Live-
/// Diagnose gegen eine bekannte Referenzstrecke (Bremen Hauptbahnhof -> Bürgerpark) zeigte einen
/// 4-fachen Umweg auf einem einzelnen Hop (298 m Luftlinie -> 1208 m tatsächliche Streckenlänge):
/// `BikeRoutingEngine` optimiert nach "ruhig", nicht nach "tatsächlicher Verlauf" - auf kurzen
/// Hops nimmt sie dafür sichtbare Umwege über Nebenstraßen, statt dem echten (evtl. kurz über eine
/// belebtere Straße führenden) Streckenverlauf zu folgen. Für Map-Matching ist "ruhigste Route
/// zwischen zwei Punkten" das falsche Werkzeug.
///
/// Diese Version snappt stattdessen jeden **Originalpunkt** der kuratierten Route einzeln auf den
/// nächstgelegenen Graph-Knoten (`WayGraphRepository.nearestNode`) und verbindet aufeinander-
/// folgende Knoten möglichst per **direkter Kante** (kein Suchen nötig) - nur wenn zwei Punkte
/// nicht direkt verbunden sind (z. B. weil die Douglas-Peucker-Vereinfachung Zwischenpunkte
/// entfernt hat), überbrückt eine eng begrenzte, rein **distanzbasierte** Dijkstra-Suche die Lücke
/// (`shortestBridge`) - bewusst ohne die "ruhig"-Gewichtung von `BikeRoutingEngine`, damit auch
/// eine kurze Überbrückung dem tatsächlich kürzesten (nicht dem ruhigsten) Weg folgt.
///
/// Die Namens-/Richtungs-Logik selbst kommt unverändert aus `BikeRoutingEngine.buildSteps`, nicht
/// neu implementiert.
enum CuratedRouteStepMatcher {
    /// Wie weit ein Originalpunkt vom nächsten Graph-Knoten entfernt sein darf, um noch als
    /// "getroffen" zu gelten - grober Toleranzwert für Abweichungen zwischen `routes.sqlite` und
    /// dem Wege-Graphen (unterschiedliche OSM-Extraktionen, s. ROADMAP.md) sowie für die
    /// Douglas-Peucker-Vereinfachung der kuratierten Route.
    private static let maxSnapDistanceMeters = 50.0

    /// Obergrenze für die Überbrückungs-Suche zwischen zwei nicht direkt verbundenen Knoten -
    /// sollte für die üblicherweise kurzen Lücken (entfernte Zwischenpunkte einer Vereinfachung)
    /// nie ausgeschöpft werden; verhindert nur ein Ausufern bei einer echten Datenlücke.
    private static let maxBridgeVisitedNodes = 500

    /// Ab welchem Anteil erfolgreich verbundener Punktpaare das Ergebnis überhaupt zurückgegeben
    /// wird. Verläuft eine kuratierte Route überwiegend abseits des heruntergeladenen
    /// Wege-Graphen (z. B. Nachbarregion nicht heruntergeladen, Fährabschnitt), wären lückenhafte
    /// Namen irreführender als gar keine - dann lieber `nil`, die aufrufende Stelle zeigt wie
    /// bisher nichts an.
    private static let minMatchedFraction = 0.5

    /// Straßennamen + Abbiege-Hinweise für `coordinates` (ein Streckenabschnitt aus
    /// `RouteMatcher.routeSegmentPath`), oder `nil` bei zu vielen nicht verbundenen Punkten (s.
    /// `minMatchedFraction`) oder wenn `coordinates` zu kurz ist. Rein lesend/rechnend, bewusst
    /// `nonisolated` wie `BikeRoutingEngine`/`WayGraphRepository` - Aufrufer sind für die
    /// Hintergrund-Ausführung verantwortlich.
    nonisolated static func steps(
        along coordinates: [CLLocationCoordinate2D], using repository: WayGraphRepository
    ) -> [BikeRoutingEngine.Result.Step]? {
        guard coordinates.count >= 2,
              let firstNode = repository.nearestNode(to: coordinates[0], maxDistanceMeters: maxSnapDistanceMeters)
        else { return nil }

        var nodePath: [Int] = [firstNode]
        // ⚠️ Wie `BikeRoutingEngine.search`s `cameFromNameIndex` nach Knoten-ID indiziert, nicht
        // nach Position im Pfad - bei einer Route, die denselben Knoten zweimal durchläuft (z. B.
        // Kreisverkehr, Sackgassen-Stichweg hin und zurück), überschreibt der zweite Durchlauf den
        // Namen des ersten. Für die praktisch immer vorwärtslaufende, kurze Prüfstrecke hier
        // vernachlässigbar, bei sehr langen Fernrouten mit echten Schleifen ein bekanntes,
        // akzeptiertes Limit (dieselbe Einschränkung hat `BikeRoutingEngine` selbst schon).
        var nameIndexByNode: [Int: UInt32] = [:]
        var previousNode = firstNode
        var matchedSegments = 0
        let totalSegments = coordinates.count - 1

        for i in 1..<coordinates.count {
            guard let node = repository.nearestNode(to: coordinates[i], maxDistanceMeters: maxSnapDistanceMeters),
                  node != previousNode
            else { continue }

            if let nameIndex = directEdgeNameIndex(from: previousNode, to: node, repository: repository) {
                nodePath.append(node)
                nameIndexByNode[node] = nameIndex
                matchedSegments += 1
            } else if let bridge = shortestBridge(from: previousNode, to: node, repository: repository) {
                for bridgedNode in bridge.path.dropFirst() {
                    nodePath.append(bridgedNode)
                    nameIndexByNode[bridgedNode] = bridge.nameIndexByNode[bridgedNode]
                }
                matchedSegments += 1
            }
            previousNode = node
        }

        guard nodePath.count >= 2, Double(matchedSegments) / Double(totalSegments) >= minMatchedFraction else {
            return nil
        }
        return BikeRoutingEngine.buildSteps(path: nodePath, nameIndex: nameIndexByNode, repository: repository)
    }

    /// Straßenname der direkten Kante `from -> to`, falls vorhanden - `edges(from:)` liefert
    /// typischerweise nur eine Handvoll Kanten pro Knoten, ein linearer Scan ist hier also
    /// billiger als eine eigene Kanten-Lookup-Struktur.
    private static func directEdgeNameIndex(
        from: Int, to: Int, repository: WayGraphRepository
    ) -> UInt32? {
        repository.edges(from: from).first { $0.toNode == Int32(to) }?.nameIndex
    }

    /// Rein distanzbasierte (nicht "ruhig"-gewichtete, anders als `BikeRoutingEngine.search`)
    /// Dijkstra-Suche zwischen zwei Knoten, die nicht direkt durch eine Kante verbunden sind -
    /// für kurze Lücken durch von der Vereinfachung entfernte Zwischenpunkte. `nil`, wenn keine
    /// Verbindung innerhalb von `maxBridgeVisitedNodes` besuchten Knoten gefunden wird.
    private static func shortestBridge(
        from start: Int, to end: Int, repository: WayGraphRepository
    ) -> (path: [Int], nameIndexByNode: [Int: UInt32])? {
        var distances: [Int: Double] = [start: 0]
        var cameFrom: [Int: Int] = [:]
        var cameFromNameIndex: [Int: UInt32] = [:]
        var visited: Set<Int> = []
        var queue = BridgeQueue()
        queue.push(priority: 0, node: start)

        while let current = queue.popMin() {
            guard !visited.contains(current.node) else { continue }
            visited.insert(current.node)
            if current.node == end { break }
            guard visited.count < maxBridgeVisitedNodes else { return nil }

            for edge in repository.edges(from: current.node) {
                let toNode = Int(edge.toNode)
                guard !visited.contains(toNode) else { continue }
                let tentative = (distances[current.node] ?? .greatestFiniteMagnitude) + Double(edge.distanceMeters)
                if tentative < (distances[toNode] ?? .greatestFiniteMagnitude) {
                    distances[toNode] = tentative
                    cameFrom[toNode] = current.node
                    cameFromNameIndex[toNode] = edge.nameIndex
                    queue.push(priority: tentative, node: toNode)
                }
            }
        }

        guard distances[end] != nil else { return nil }
        var path = [end]
        var node = end
        while let prev = cameFrom[node] {
            path.append(prev)
            node = prev
        }
        path.reverse()
        return (path, cameFromNameIndex)
    }
}

/// Binärer Min-Heap für `shortestBridge`, analog `AStarQueue` in `BikeRoutingEngine.swift`.
private struct BridgeQueue {
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
