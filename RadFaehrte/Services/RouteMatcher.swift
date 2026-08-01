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
    /// Liniensegmenten einer Route ein Netz für Dijkstra-Suchen auf. Punkte innerhalb von
    /// `toleranceMeters` werden per Nachbarschaftssuche (s. `node(for:)`) auf denselben Knoten
    /// dedupliziert; `attach` splict einen beliebigen Punkt (z. B. den nächstgelegenen Punkt zu
    /// Start/Ziel) in die Kante, auf der er projiziert
    /// liegt, statt einen exakten Knotentreffer vorauszusetzen.
    private struct RouteGraph {
        /// Rasterzelle (s. `cellKey`) -> Knoten-Indizes, deren Koordinate in diese Zelle fällt -
        /// mehrere Knoten pro Zelle möglich, anders als bei der früheren reinen
        /// Rundungs-Deduplizierung (s. `node(for:)`).
        private var cellIndex: [Int64: [Int]] = [:]
        private(set) var adjacency: [[(to: Int, weightMeters: Double)]] = []
        /// Knoten-Index -> tatsächliche Koordinate (erste Koordinate, die zu diesem Knoten
        /// geführt hat) - für `routeSegmentPath`, das den per Dijkstra gefundenen Pfad als
        /// Koordinatenliste statt nur als Distanz zurückgeben will, und für den echten
        /// Distanzabgleich in `node(for:)`.
        private(set) var coordinates: [CLLocationCoordinate2D] = []

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

        /// Toleranz (Meter), innerhalb derer zwei Punkte als "derselbe Knoten" gelten. Historie:
        /// ursprünglich ~1,1 m (5 Nachkommastellen), dann ~11 m (0,0001°, wie
        /// `SIMPLIFY_TOLERANCE_DEG` in den Extraktions-Skripten) - Fund 2026-07-30 (Lübeck→Wismar):
        /// Die Douglas-Peucker-Vereinfachung läuft pro OSM-Way einzeln (nicht pro Relation). Liegt
        /// der Punkt, an dem sich zwei benannte Routen kreuzen/berühren, nicht exakt an einem
        /// Way-Anfang/-Ende (die immer erhalten bleiben), sondern mitten in einem Way, können
        /// beide Vereinfachungen ihn unabhängig voneinander um bis zu ~11 m verschieben - im
        /// ungünstigsten Fall in entgegengesetzte Richtungen, macht also bis zu ~22 m möglichen
        /// Gesamtabstand. Auf ~28 m angehoben (kleine Sicherheitsmarge) nach einer bundesweiten
        /// Stichprobe (2026-07-30, Nutzer-Beispiel Brückenradweg Ost-/Westroute Bremen-Osnabrück):
        /// Von 7.018 benannten rcn/ncn/icn-Fernwegen zerfallen 1.243 (17,7 %) intern in mehrere
        /// Komponenten, bei 705 davon (10 % aller Fernwege!) liegt die kleinste Lücke unter 40 m -
        /// also vermutlich derselbe Simplification-Artefakt, kein echter Datenmangel (u. a.
        /// Deutscher Limes-Radweg, Bodensee-Radweg, Rhein-Route, Radfernweg Hamburg-Bremen
        /// betroffen).
        private static let toleranceMeters: Double = 28.0

        /// Rasterzellgröße für die Nachbarschaftssuche in `node(for:)` - **nicht** mehr die
        /// eigentliche Toleranz selbst (die ist jetzt `toleranceMeters`, ein echter
        /// Distanzvergleich), nur zur schnellen Vorauswahl kandidierender Knoten (3×3-Nachbarschaft
        /// muss die volle Toleranz abdecken, sonst werden echte Treffer verpasst).
        /// ⚠️ Fund direkt bei der Erstimplementierung: Ein fester Grad-Wert ist hierfür ungeeignet,
        /// weil sich Meter pro Längengrad mit `cos(Breite)` verkleinert (je nördlicher, desto
        /// schmaler die Zelle in Ost-West-Richtung) - bei 0,0003° und ~28 m Toleranz reichte die
        /// Zelle bei deutschen Breiten (~52-55°N) in Längengrad-Richtung nicht mehr aus (~20-24 m
        /// statt ~28 m), wodurch die ±1-Zellen-Nachbarschaft echte Treffer verpasste (Regression:
        /// Lübeck→Wismar und Brückenradweg-Tests schlugen fehl). Auf 0,001° angehoben - deckt auch
        /// bei den nördlichsten unterstützten Breiten (Schweden, ~69°N, `cos ≈ 0,36`) noch
        /// zuverlässig mehr als `toleranceMeters` pro Zelle ab.
        private static let cellSizeDegrees: Double = 0.001

        private static func cellIndices(_ c: CLLocationCoordinate2D) -> (lat: Int64, lon: Int64) {
            (Int64((c.latitude / cellSizeDegrees).rounded(.down)),
             Int64((c.longitude / cellSizeDegrees).rounded(.down)))
        }

        private static func cellKey(lat: Int64, lon: Int64) -> Int64 {
            lat &* 10_000_000 &+ lon
        }

        /// Fund 2026-07-30 (Brückenradweg Ostroute, Bremen-Osnabrück): Reine Rasterrundung
        /// (`round(x/grid)`) ist nicht robust gegen Grenzfälle - zwei Punkte nur 4 m auseinander
        /// können durch ungünstige Ausrichtung zur Rasterzellen-Grenze trotzdem in
        /// unterschiedliche Zellen fallen und werden dann fälschlich als unverbunden behandelt
        /// (per `shapely`-Nachrechnung mit voller Präzision bestätigt: 4 m echte Distanz, aber
        /// beim reinen Rundungsraster 2 getrennte Komponenten geblieben). Behoben durch
        /// Nachbarschaftssuche: statt nur die eigene Rasterzelle zu prüfen, werden die 3×3
        /// umliegenden Zellen nach vorhandenen Knoten durchsucht und deren **tatsächliche**
        /// Distanz (nicht nur Zellzugehörigkeit) gegen `toleranceMeters` geprüft - das eliminiert
        /// die Empfindlichkeit gegenüber der zufälligen Lage der Rasterzellen-Grenzen.
        mutating func node(for c: CLLocationCoordinate2D) -> Int {
            let cell = Self.cellIndices(c)
            for dLat: Int64 in -1...1 {
                for dLon: Int64 in -1...1 {
                    let key = Self.cellKey(lat: cell.lat + dLat, lon: cell.lon + dLon)
                    guard let candidates = cellIndex[key] else { continue }
                    for candidate in candidates where Self.approxMeters(coordinates[candidate], c) <= Self.toleranceMeters {
                        return candidate
                    }
                }
            }
            let index = adjacency.count
            let ownKey = Self.cellKey(lat: cell.lat, lon: cell.lon)
            cellIndex[ownKey, default: []].append(index)
            adjacency.append([])
            coordinates.append(c)
            return index
        }

        /// Ebene Näherung statt `CLLocation.distance` (echte Geodäten-Berechnung) - für den
        /// Kandidaten-Check in `node(for:)`, der pro eingefügtem Punkt bis zu 9 Zellen mit
        /// mehreren Kandidaten durchsucht und dabei spürbar ins Gewicht fiel (Performance-
        /// Regression beim ersten Testlauf: Berlin->Vreden 22s -> 69s, Berlin->Den Haag lief sogar
        /// in ein leeres Ergebnis, vermutlich weil `maxVisitedRoutes` durch die viel höhere
        /// Rechenlast pro Route effektiv "kleiner" wirkte). Auf dieser Skala (Toleranz ~28 m) ist
        /// der Unterschied zur geodätischen Distanz irrelevant, für die tatsächlichen Kantengewichte
        /// (`addEdge`, potenziell über deutlich größere Distanzen) bleibt `meters` weiterhin exakt.
        private static func approxMeters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
            let metersPerDegreeLat = 111_320.0
            let metersPerDegreeLon = 111_320.0 * cos(a.latitude * .pi / 180)
            let dLat = (a.latitude - b.latitude) * metersPerDegreeLat
            let dLon = (a.longitude - b.longitude) * metersPerDegreeLon
            return (dLat * dLat + dLon * dLon).squareRoot()
        }

        func coordinate(forNode node: Int) -> CLLocationCoordinate2D {
            coordinates[node]
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

    /// Obergrenze (km), wie weit ein "from"/"to"-Punkt von der übergebenen Routen-Geometrie
    /// entfernt sein darf, um noch als Anker auf dieser Route zu gelten. Fund 2026-07-30: Bei
    /// einer ID-Kollision über mehrere Datenbanken hinweg (s. RouteRepository-Header) konnte ein
    /// Punkt, der eigentlich meilenweit von der übergebenen Geometrie entfernt lag (falsche
    /// Länder-Kopie derselben ID), trotzdem stillschweigend auf den nächstgelegenen - aber
    /// bedeutungslosen - Punkt projiziert werden, was eine ~500-km-Distanz fälschlich als ~0 km
    /// auswies. `nearestPoint` selbst kennt keine Obergrenze (für andere Aufrufer wie
    /// `findMatches`, die die Distanz ohnehin selbst gegen `thresholdKm` prüfen, unproblematisch),
    /// `routeSegmentDistance`/`routeSegmentDistances` verlassen sich aber darauf, dass ihre Anker
    /// tatsächlich auf der Route liegen - daher hier zusätzlich abgesichert. 20 km als großzügige
    /// Grenze oberhalb des üblichen `thresholdKm` (8 km), aber weit unterhalb jeder plausiblen
    /// Fehlprojektion.
    private static let maxPlausibleAnchorDistanceKm: Double = 20

    /// Kürzeste (und, falls vorhanden, eine spürbar längere alternative) Verbindung entlang der
    /// Routen-Geometrie zwischen zwei Punkten (üblicherweise die jeweils nächstgelegenen Punkte
    /// zu Start und Ziel einer `RouteMatch`). Die Liniensegmente einer Route liegen in der
    /// Datenbank meist unsortiert vor (einzelne OSM-Way-Fragmente, nicht in Reihenfolge entlang
    /// der Strecke), daher wird ein Netz aus allen Segmenten aufgebaut und per Dijkstra der
    /// kürzeste Pfad gesucht. Für die Alternative werden dessen Kanten entfernt und erneut
    /// gesucht - bei einer Rundstrecke entspricht das der jeweils anderen Richtung.
    /// `nil`, wenn sich kein zusammenhängender Pfad finden lässt (z. B. Lücken im Wegenetz) oder
    /// `from`/`to` zu weit von der Geometrie entfernt liegen (s. `maxPlausibleAnchorDistanceKm`).
    nonisolated static func routeSegmentDistance(
        along lines: [[CLLocationCoordinate2D]], from: CLLocationCoordinate2D, to: CLLocationCoordinate2D
    ) -> RouteSegmentDistance? {
        guard !lines.isEmpty else { return nil }

        var graph = RouteGraph(lines: lines)

        guard let startAnchor = nearestPoint(from: from, toLines: lines),
              startAnchor.distanceKm <= maxPlausibleAnchorDistanceKm,
              let endAnchor = nearestPoint(from: to, toLines: lines),
              endAnchor.distanceKm <= maxPlausibleAnchorDistanceKm
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

    /// Wie `routeSegmentDistance`, liefert aber den tatsächlich befahrenen Streckenverlauf als
    /// Koordinatenliste statt nur die Länge - für die Kartenanzeige einer Etappe innerhalb einer
    /// kombinierten Route (`findCombinedMatches`/`ContentView.selectedRouteLines`). Ohne das würde
    /// die Karte die komplette Geometrie der gesamten benannten Route zeichnen (alle Zweige/
    /// Nebenäste, oft weit über das tatsächlich genutzte Teilstück hinaus) statt nur den Abschnitt
    /// zwischen Ein- und Ausstiegspunkt - bei mehreren gestapelten Etappen entsteht dadurch ein
    /// unübersichtliches Liniengewirr (Nutzer-Beobachtung 2026-07-30, Bremen -> Hannover). `nil`
    /// unter denselben Bedingungen wie `routeSegmentDistance` (keine Verbindung/zu weit entfernt).
    nonisolated static func routeSegmentPath(
        along lines: [[CLLocationCoordinate2D]], from: CLLocationCoordinate2D, to: CLLocationCoordinate2D
    ) -> [CLLocationCoordinate2D]? {
        guard !lines.isEmpty else { return nil }

        var graph = RouteGraph(lines: lines)

        guard let startAnchor = nearestPoint(from: from, toLines: lines),
              startAnchor.distanceKm <= maxPlausibleAnchorDistanceKm,
              let endAnchor = nearestPoint(from: to, toLines: lines),
              endAnchor.distanceKm <= maxPlausibleAnchorDistanceKm
        else { return nil }

        let startNode = graph.attach(startAnchor)
        let endNode = graph.attach(endAnchor)

        guard let shortest = dijkstra(from: startNode, to: endNode, adjacency: graph.adjacency) else { return nil }
        return shortest.path.map { graph.coordinate(forNode: $0) }
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
        guard !lines.isEmpty, let fromAnchor = nearestPoint(from: from, toLines: lines),
              fromAnchor.distanceKm <= maxPlausibleAnchorDistanceKm
        else {
            return targets.map { _ in nil }
        }

        var graph = RouteGraph(lines: lines)
        let fromNode = graph.attach(fromAnchor)
        let targetNodes = targets.map { target -> Int? in
            guard let anchor = nearestPoint(from: target, toLines: lines),
                  anchor.distanceKm <= maxPlausibleAnchorDistanceKm
            else { return nil }
            return graph.attach(anchor)
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

    /// Bezeichnet einen Routennamen als Richtungs-/Teiletappen-Variante (z. B. "Friedensroute
    /// (West)", "100 Schlösser Route (Nord)", "[D9] Weser-Romantische Straße Teil 1") - solche
    /// Varianten werden in `findNearby` von der Ref-Deduplizierung ausgenommen (immer behalten,
    /// nie gegeneinander oder gegen die zusammenfassende Gesamtroute zusammengefasst). Fund
    /// 2026-07-31 (Nutzer-Beobachtung Münster): "Friedensroute (West)" und "Friedensroute (Ost)"
    /// verschwanden hinter der zusammenfassenden "Friedensroute", weil alle drei denselben `ref`
    /// "FR" tragen - anders als etwa beim Brückenradweg, dessen Ost-/Westroute unterschiedliche
    /// `ref`-Werte haben und daher nicht kollidieren. Anhand des `ref`-Tags allein lässt sich eine
    /// echte Mehrfachkartierung derselben Strecke (z. B. "Weser-Radweg" und "Weser Radweg mit
    /// Alternativstrecken", ref "Weser") nicht von einer bewusst benannten Teiletappe
    /// unterscheiden - der Name schon, solche Varianten tragen fast immer einen Richtungs- oder
    /// Etappen-Zusatz.
    private static let subRouteVariantPatterns: [NSRegularExpression] = [
        try! NSRegularExpression(
            pattern: #"\((Ost|West|Nord|Süd|Nordost|Nordwest|Südost|Südwest)\)\s*$"#, options: [.caseInsensitive]
        ),
        try! NSRegularExpression(pattern: #"\b(Teil|Etappe|Part)\s*\d+"#, options: [.caseInsensitive]),
    ]

    private static func isSubRouteVariant(name: String) -> Bool {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return subRouteVariantPatterns.contains { $0.firstMatch(in: name, range: range) != nil }
    }

    /// Radrouten rund um einen einzelnen Punkt, unabhängig von einem Ziel - für die Vorschau
    /// direkt nach der Standortwahl, bevor ein Ziel eingegeben wurde. `distanceToStartKm` und
    /// `distanceToEndKm` sind hier identisch (beide = Distanz zum Punkt), da `RouteMatch`
    /// eigentlich für Start+Ziel-Paare gedacht ist - die UI verwendet für diesen Fall eine eigene
    /// Beschriftung statt `combinedDistanceKm` (siehe `ContentView.nearbySubtitle`).
    ///
    /// Fund 2026-07-31 (Nutzer-Beobachtung Bremen/Osnabrück, Osnabrück/Münster): An Knotenpunkten
    /// vieler sich überlagernder Fernwege (z. B. Bremen, Osnabrück, Münster) drängen zwei
    /// Effekte bekannte Fernwege wie den Brückenradweg oder die Friedensroute aus dem festen
    /// `limit` heraus, obwohl sie in Luftlinie näher liegen als der `searchRadiusKm`-Schwellenwert:
    /// (1) dieselbe Route ist oft mehrfach in der Datenbank vertreten (Land-/Relation-Grenzen,
    /// z. B. "Friedensroute", "Friedensroute (West)", "Friedensroute (Ost)" und "EuroVelo 3 -
    /// Pilgrim's Route - part Germany #5 Friedenroute" - alle mit `ref` "FR"/"EV3"), (2) einzelne
    /// Knotenpunkt-Wegstücke lokaler Netze tauchen als scheinbar eigenständige benannte Route auf
    /// (s. `isNodeToNodeSegment`). Beides zusammen füllt das `limit` mit Varianten derselben oder
    /// bedeutungsloser Routen, bevor der eigentlich gesuchte Fernweg an die Reihe kommt - und das
    /// unterschiedlich stark je nach Endpunkt, wodurch dieselbe Route an einem Ende der Strecke
    /// erscheint, am anderen aber nicht. Behoben durch Ausschluss der Knotenpunkt-Fragmente (wie
    /// bereits in `combinableRoutes`) sowie Deduplizierung nach `ref` (Fallback: Name), jeweils der
    /// nächstgelegene Treffer pro Schlüssel gewinnt - Richtungs-/Teiletappen-Varianten (s.
    /// `isSubRouteVariant`) sind davon ausgenommen und bleiben immer erhalten. `limit` auf 20 (statt
    /// zunächst 15) angehoben, nachdem sich zeigte, dass die Ausnahme für Richtungsvarianten an
    /// Knotenpunkten mit vielen solchen Familien (z. B. Münster: "100 Schlösser Route" plus Nord/
    /// Süd, "Historische Stadtkerne" plus mehrere Etappen) selbst wieder Plätze verbraucht, die
    /// sonst der Friedensroute/dem Brückenradweg fehlten (Nutzer-Beobachtung 2026-07-31: Münster
    /// zeigte zunächst nur die zusammenfassende "Friedensroute", nicht die Teiletappen Ost/West).
    func findNearby(
        around point: CLLocationCoordinate2D, limit: Int = 20, searchRadiusKm: Double = 15
    ) -> [RouteMatch] {
        let latPad = searchRadiusKm / 111.32
        let lonPad = searchRadiusKm / (111.32 * max(cos(point.latitude * .pi / 180), 0.1))

        let candidates = repository.routesOverlapping(
            minLon: point.longitude - lonPad, minLat: point.latitude - latPad,
            maxLon: point.longitude + lonPad, maxLat: point.latitude + latPad
        )

        var nearby: [RouteMatch] = []
        for route in candidates {
            guard let name = route.name, !name.isEmpty, !Self.isNodeToNodeSegment(name: name) else { continue }
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
        nearby.sort { $0.distanceToStartKm < $1.distanceToStartKm }

        var seenKeys: Set<String> = []
        var deduped: [RouteMatch] = []
        for match in nearby {
            let name = match.route.name ?? ""
            guard !Self.isSubRouteVariant(name: name) else {
                deduped.append(match)
                continue
            }
            let key = match.route.ref?.isEmpty == false ? match.route.ref! : name
            guard seenKeys.insert(key).inserted else { continue }
            deduped.append(match)
        }
        return Array(deduped.prefix(limit))
    }

    /// Eine Etappe einer kombinierten Route - eine einzelne benannte Fernwegs-Route, befahren von
    /// `entryPoint` (Nutzer-Start oder Anschluss zur vorigen Etappe) bis `exitPoint` (Anschluss
    /// zur nächsten Etappe oder Nutzer-Ziel).
    struct CombinedRouteLeg: Identifiable {
        let route: BikeRoute
        let entryPoint: CLLocationCoordinate2D
        let exitPoint: CLLocationCoordinate2D
        let distanceKm: Double
        /// Tatsächlich befahrener Streckenverlauf zwischen `entryPoint` und `exitPoint` (per
        /// `routeSegmentPath`) - nachträglich befüllt, erst nachdem eine Kette vollständig
        /// gefunden wurde (s. `findCombinedMatches`), daher zunächst leer. Für die Kartenanzeige
        /// gedacht (`ContentView.selectedRouteLines`) statt der kompletten Routen-Geometrie
        /// (`route.lines`), die auch ungenutzte Zweige/Nebenäste enthalten kann.
        var pathCoordinates: [CLLocationCoordinate2D] = []
        var id: Int64 { route.id }
    }

    /// Ergebnis von `findCombinedMatches`: mehrere benannte Fernwege, die an Anschlussstellen
    /// aneinandergereiht Start und Ziel verbinden, weil keine einzelne Route das allein schafft.
    struct CombinedRouteMatch: Identifiable {
        var legs: [CombinedRouteLeg]
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

    /// A*-Bonus (in km, von der Warteschlangen-Priorität abgezogen) für Etappenwechsel auf eine
    /// Route mit demselben `ref`-Tag (z. B. "EV2" bei EuroVelo 2 diesseits und jenseits einer
    /// Landesgrenze, wo dieselbe Route oft als separate Relation pro Land kartiert ist). 20 km
    /// als moderater Wert: bevorzugt den bekannten Fernweg gegenüber einer nur geringfügig
    /// kürzeren Alternative, ohne bei einer deutlich kürzeren Kette (z. B. bei einer echten
    /// Kartenlücke im bekannten Fernweg) dagegen zu wirken.
    private static let sameRefPriorityBonusKm: Double = 20

    /// Fund 2026-07-31 (Nutzer-Beispiel Bremen -> Münster, "Brückenradweg" + "Friedensroute"):
    /// `findCombinedMatches` finalisierte bisher jede Route-ID **genau einmal**, unabhängig vom
    /// Einstiegspunkt - problematisch bei Routen, deren eigene OSM-Geometrie in mehrere nicht
    /// zusammenhängende Fragmente zerfällt (s. `RouteGraph`, ~10% aller benannten Fernwege
    /// betroffen). Bremen -> Münster: "D7 Pilgerroute" liegt (per reiner Umkreisprüfung, ohne
    /// Pfad-Check) sowohl nahe Bremen als auch nahe Münster und wird deshalb selbst schon als
    /// Direkttreffer *und* als Start-Kandidat der Kombinationssuche verwendet - letzteres mit
    /// Einstiegspunkt bei Bremen. Von dort aus hat die Route aber keinen durchgehenden Pfad zu
    /// ihrer eigenen Anschlussstelle bei Osnabrück (anderes Geometrie-Fragment) - die Route wurde
    /// trotzdem als global "erledigt" markiert und blockierte damit dauerhaft den eigentlich
    /// funktionierenden zweiten Zugang über "Brückenradweg" bei Osnabrück (dieselbe Route-ID,
    /// anderer, gut angebundener Einstiegspunkt), über den "Friedensroute" erreichbar gewesen
    /// wäre. Ersetzt das reine Route-ID-`Set` durch `visitedEntryPoints` - erlaubt bis zu
    /// `maxEntryPointsPerRoute` klar getrennte (≥ `minEntryPointSeparationKm` auseinanderliegende)
    /// Einstiegspunkte pro Route, bevor sie als erschöpft gilt. `maxVisitedRoutes` bleibt die
    /// harte Obergrenze für die Gesamtsuche, daher kein unbegrenztes Blow-up.
    private static let maxEntryPointsPerRoute = 3
    private static let minEntryPointSeparationKm: Double = 5

    /// Viele Regionen taggen ihr lokales Knotenpunkt-Wegenetz (einzelne Abschnitte zwischen
    /// nummerierten Knoten) mit `network=rcn` statt `lcn` - am `network`-Tag allein nicht von
    /// einem echten Fernweg zu unterscheiden. Zwei beobachtete Namensmuster (s. auch
    /// `Scripts/find_route_junctions.py`, das dieselben Muster beim Bau der Anschluss-Tabelle
    /// ausschließt): rein numerisch ("31-32") und Ort+Knotennummer ("Lohne (76) - Dinklage (78)",
    /// über die Hälfte aller benannten rcn/ncn/icn-Routen in Deutschland folgt diesem Muster).
    /// Hier zusätzlich geprüft, damit auch die Start-/Ziel-Kandidatensuche (unabhängig von der
    /// Anschluss-Tabelle) nicht versehentlich so ein Wegstück auswählt.
    ///
    /// Zwei weitere Muster gefunden beim Live-Test Berlin->Den Haag (2026-07-29): "Knotenpunkt-
    /// wegweisung Oberhavel"/"Knotenpunktnetz Landkreis Ostprignitz-Ruppin" (lokale Knotenpunkt-
    /// Netze, am Namen erkennbar, aber von keinem der beiden obigen Muster erfasst) sowie
    /// "71 - Rübehorst (72)" (Mischform aus rein-numerischem und Ort+Nummer-Muster). Ergänzt:
    /// Namen mit "Knotenpunkt" sowie die Mischform "Zahl - Text (Zahl)"/"Text (Zahl) - Zahl".
    private static let nodeToNodeNamePatterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"^\d+\s*-\s*\d+$"#),
        try! NSRegularExpression(pattern: #".*\(\d+\).*-.*\(\d+\).*"#),
        try! NSRegularExpression(pattern: #"^\d+\s*-\s*.+\(\d+\)\s*$"#),
        try! NSRegularExpression(pattern: #"^.+\(\d+\)\s*-\s*\d+$"#),
    ]

    private static func isNodeToNodeSegment(name: String) -> Bool {
        if name.localizedCaseInsensitiveContains("knotenpunkt") { return true }
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

    /// Erkennt "bekannte" internationale/nationale Fernweg-Kennungen (EuroVelo "EV1"-"EV19",
    /// deutsche D-Routen "D1"-"D12") anhand des `ref`-Tags - für `nearbyWellKnownRouteMatches`.
    private static let wellKnownRefPattern = try! NSRegularExpression(pattern: #"^(EV\d{1,2}|D\d{1,2})$"#)

    private static func isWellKnownRef(_ ref: String?) -> Bool {
        guard let ref else { return false }
        let range = NSRange(ref.startIndex..<ref.endIndex, in: ref)
        return wellKnownRefPattern.firstMatch(in: ref, range: range) != nil
    }

    /// Bekannte Fernwege (EuroVelo/D-Route, s. `isWellKnownRef`) in der Nähe von Start oder Ziel,
    /// als vollwertige `RouteMatch`-Einträge - unabhängig davon, ob sie zusätzlich Teil einer
    /// gefundenen Kombination/eines Einzeltreffers wurden (Aufrufer dedupliziert bei Bedarf selbst
    /// per `ref`, s. `ContentView.attemptCombinedThenClosestFallback`). Ursprünglich nur als reiner
    /// Text-Hinweis gezeigt ("... verläuft hier in der Nähe, ist aber nicht durchgehend kartiert")
    /// - Nutzer-Wunsch (2026-07-31, Beispiel Münster -> Köln/EuroVelo 3, aber allgemein gemeint,
    /// nicht nur für diesen einen Fall): "ich möchte trotzdem die Route angezeigt bekommen und
    /// auswählen können". Anders als `findMatches` daher ohne Schwellenwert-Prüfung auf beiden
    /// Seiten (die Route muss nur an einem Ende in der Nähe liegen, s. `combinableRoutes`) - die
    /// tatsächliche (ggf. große) Distanz zum jeweils anderen Ende zeigt dem Nutzer transparent, ob
    /// sich die Route trotzdem lohnt (analog `findClosestMatches`). Fehlt der Route dabei eine
    /// zusammenhängende Geometrie zwischen den beiden Anschlusspunkten (die eigentliche
    /// Kartenlücke), erscheint automatisch der schon bestehende "Kartendaten hier
    /// lückenhaft"-Hinweis (`routeSegmentDistance`, `ContentView.subtitle(for:)`) statt einer
    /// km-Angabe - die Route bleibt trotzdem sicht- und wählbar. Dedupliziert nach `ref`, da z. B.
    /// "Europaroute (D-Route 3)" und "D-Netz Route 3" denselben `ref` tragen können.
    nonisolated func nearbyWellKnownRouteMatches(
        start: CLLocationCoordinate2D, end: CLLocationCoordinate2D, searchRadiusKm: Double = 8
    ) -> [RouteMatch] {
        var seenRefs: Set<String> = []
        var results: [RouteMatch] = []
        let candidates = combinableRoutes(near: start, searchRadiusKm: searchRadiusKm)
            + combinableRoutes(near: end, searchRadiusKm: searchRadiusKm)
        for candidate in candidates {
            guard let ref = candidate.route.ref, Self.isWellKnownRef(ref),
                  seenRefs.insert(ref).inserted
            else { continue }
            guard let toStart = Self.nearestPoint(from: start, toLines: candidate.route.lines),
                  let toEnd = Self.nearestPoint(from: end, toLines: candidate.route.lines)
            else { continue }
            results.append(RouteMatch(
                route: candidate.route,
                distanceToStartKm: toStart.distanceKm,
                distanceToEndKm: toEnd.distanceKm,
                nearestPointToStart: toStart.coordinate,
                nearestPointToEnd: toEnd.coordinate
            ))
        }
        return results
    }

    private struct CombinedSearchEntry {
        let routeId: Int64
        let entryPoint: CLLocationCoordinate2D
        let cumulativeKm: Double
        /// A*-Priorität (`cumulativeKm` + Luftlinie `entryPoint`->Ziel) - bestimmt nur die
        /// Reihenfolge in der Warteschlange, nicht die tatsächliche Streckenlänge (die bleibt
        /// `cumulativeKm`, u. a. für den `maxAllowedKm`-Abbruch und `bestDistanceKm` weiterhin
        /// exakt).
        let priority: Double
        let legs: [CombinedRouteLeg]
    }

    /// Einfache Array-basierte Min-Heap-Warteschlange für `findCombinedMatches`, analog zu
    /// `DijkstraQueue`, aber mit dem größeren `CombinedSearchEntry`-Payload statt nur einer Node-ID -
    /// sortiert nach `priority` (A*), nicht nach der reinen Streckenlänge.
    private struct CombinedSearchQueue {
        private var heap: [CombinedSearchEntry] = []

        mutating func push(_ entry: CombinedSearchEntry) {
            heap.append(entry)
            var i = heap.count - 1
            while i > 0 {
                let parent = (i - 1) / 2
                guard heap[i].priority < heap[parent].priority else { break }
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
                if left < heap.count, heap[left].priority < heap[smallest].priority { smallest = left }
                if right < heap.count, heap[right].priority < heap[smallest].priority { smallest = right }
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
    /// A* über einen impliziten Graphen: Knoten sind (Route, Einstiegspunkt), Kanten die reale
    /// Streckenlänge zu den Anschlusspunkten dieser Route (aus der per
    /// `Scripts/find_route_junctions.py` vorberechneten Sidecar-DB), lazy pro besuchter Route
    /// berechnet über `routeSegmentDistances`. Priorität in der Warteschlange ist Streckenlänge
    /// plus Luftlinie zum Ziel (`CombinedSearchEntry.priority`) statt nur der reinen Streckenlänge
    /// (reiner Dijkstra) - Luftlinie ist als Schätzwert zulässig (kann die reale Reststrecke nie
    /// überschätzen), das Ergebnis bleibt also weiterhin die tatsächlich kürzeste Kette, die Suche
    /// bewegt sich aber gezielter Richtung Ziel statt gleichmäßig in alle Richtungen. Wichtig bei
    /// Städten, in denen sich viele Fernwege überlagern (z. B. Berlin: EuroVelo 2, D-Route 3,
    /// Europaradweg R1, D-Netz Route 3 und weitere verlaufen dort über weite Strecken auf
    /// denselben Wegen und liegen dadurch alle ~0 km voneinander entfernt) - ein reiner Dijkstra
    /// verbraucht dort `maxVisitedRoutes` komplett mit dem Erkunden dieses direkten Umfelds, bevor
    /// er sich überhaupt Richtung Ziel bewegt (beobachtet bei Berlin -> Amsterdam: 500 besuchte
    /// Routen, kumulierte Streckenlänge blieb dabei durchgehend bei 0 km).
    /// Bewusst ohne feste Obergrenze an Etappen (eine längere Strecke wie Bremen -> Leipzig
    /// braucht plausibel mehr als 2-3 Etappen) - stattdessen zwei Sicherheitsgrenzen gegen
    /// ausufernde Suchen: maximal `maxVisitedRoutes` besuchte Routen, und ein Abbruch für Pfade,
    /// die bereits das `maxDistanceMultiplier`-fache der Luftlinie Start-Ziel überschreiten (eine
    /// so uneffiziente Kette wäre ohnehin kein sinnvoller Vorschlag).
    /// `maxVisitedRoutes` ursprünglich 500, auf 2000 angehoben (2026-07-29): Nach Bereinigung der
    /// fälschlich als Fernweg getaggten Knotenpunkt-Netz-Fragmente (s. `isNodeToNodeSegment`)
    /// brauchte der Live-Test Berlin -> Den Haag (echte grenzüberschreitende EuroVelo-2-Kette)
    /// mehr als 500 besuchte Routen, um durchgehend "echte" Fernwege zu finden statt über die
    /// (jetzt ausgeschlossenen) Kurzschluss-Verbindungen der Knotenpunkt-Fragmente zu laufen -
    /// 2000 reichte dafür in Tests zuverlässig (~12s im Simulator).
    /// Leeres Array, wenn keine Kette gefunden wird oder Start/Ziel keine kombinierbare Route in
    /// der Nähe haben. Liefert bis zu `maxAlternatives` verschiedene Ketten (sortiert nach
    /// Gesamtstrecke, kürzeste zuerst) statt nur der einen besten - Nutzer-Wunsch (2026-07-30):
    /// swipebare Alternativen wie beim Wisch-Pager für einzelne Treffer (`matchesPager`), da die
    /// A*-Priorität mit Ref-Bonus nicht immer die subjektiv "richtige" (z. B. bekannteste)
    /// Kombination zuerst findet. Jede zusätzliche Kette endet zwangsläufig über eine andere
    /// letzte Etappen-Route (da `visitedEntryPoints` ein erneutes Verarbeiten desselben
    /// Einstiegspunkts verhindert), Alternativen unterscheiden sich also immer mindestens im
    /// letzten Wegstück.
    /// Rein lesende SQLite-Abfragen + mehrere Pro-Route-Dijkstras - bewusst `nonisolated`, damit
    /// der Aufrufer das abseits des Main-Threads laufen lassen kann (s. `ContentView`).
    nonisolated func findCombinedMatches(
        start: CLLocationCoordinate2D, end: CLLocationCoordinate2D,
        maxVisitedRoutes: Int = 2000, maxDistanceMultiplier: Double = 3, maxAlternatives: Int = 3
    ) -> [CombinedRouteMatch] {
        let startCandidates = combinableRoutes(near: start, searchRadiusKm: thresholdKm)
        let endCandidates = combinableRoutes(near: end, searchRadiusKm: thresholdKm)
        guard !startCandidates.isEmpty, !endCandidates.isEmpty else { return [] }

        var endAnchorByRouteId: [Int64: CLLocationCoordinate2D] = [:]
        for candidate in endCandidates {
            endAnchorByRouteId[candidate.route.id] = candidate.nearestPoint
        }

        let straightLineKm = Self.kilometers(start, end)
        let maxAllowedKm = max(straightLineKm * maxDistanceMultiplier, 30)

        // Bewusst KEIN Cache über die ID allein: Fund 2026-07-30 (Berlin -> Vreden) - "Europaradweg
        // R1" existiert als ID-Kollision sowohl nahe der polnischen als auch der niederländischen
        // Grenze (unterschiedliche Geometrie, s. RouteRepository-Header). War die ID einmal z. B.
        // als Ziel-Kandidat mit der niederländischen Kopie gecacht, nutzte ein späteres
        // Wiederbetreten über eine ganz andere (polnische) Verzweigung fälschlich weiter diese
        // falsche Kopie - `routeSegmentDistances` projizierte den polnischen Einstiegspunkt dabei
        // stillschweigend auf die (Hunderte km entfernte) niederländische Geometrie und wies eine
        // ~500-km-Etappe als ~0 km aus. `route(withId:near:)` löst deshalb bei jedem Zugriff
        // anhand des aktuellen Einstiegspunkts neu auf; `visitedEntryPoints` sorgt ohnehin dafür,
        // dass derselbe Einstiegspunkt höchstens einmal verarbeitet wird, ein Cache über mehrere
        // Aufrufe hinweg würde hier also nichts einsparen, aber genau diesen Fehler ermöglichen.
        func route(withId id: Int64, near point: CLLocationCoordinate2D) -> BikeRoute? {
            let candidates = repository.allRoutes(withId: id)
            guard !candidates.isEmpty else { return nil }
            guard candidates.count > 1 else { return candidates[0] }
            return candidates.min {
                (Self.nearestPoint(from: point, toLines: $0.lines)?.distanceKm ?? .greatestFiniteMagnitude)
                    < (Self.nearestPoint(from: point, toLines: $1.lines)?.distanceKm ?? .greatestFiniteMagnitude)
            }
        }

        // Bereits verarbeitete Einstiegspunkte pro Route-ID (s. `maxEntryPointsPerRoute`-Doku oben:
        // ersetzt das frühere reine Route-ID-`Set`, das eine Route nach dem ersten - ggf. wegen
        // eines Geometrie-Fragments erfolglosen - Einstieg dauerhaft blockierte).
        var visitedEntryPoints: [Int64: [CLLocationCoordinate2D]] = [:]

        func isNewEntryPoint(_ point: CLLocationCoordinate2D, for routeId: Int64) -> Bool {
            (visitedEntryPoints[routeId] ?? []).allSatisfy {
                Self.kilometers($0, point) >= Self.minEntryPointSeparationKm
            }
        }

        var queue = CombinedSearchQueue()
        var results: [CombinedRouteMatch] = []
        var resultRouteIdSets: Set<Set<Int64>> = []
        var seededRouteIds: Set<Int64> = []

        for candidate in startCandidates {
            guard !seededRouteIds.contains(candidate.route.id) else { continue }
            seededRouteIds.insert(candidate.route.id)
            queue.push(CombinedSearchEntry(
                routeId: candidate.route.id, entryPoint: candidate.nearestPoint, cumulativeKm: 0,
                priority: Self.kilometers(candidate.nearestPoint, end), legs: []
            ))
        }

        var visitedCount = 0
        while let current = queue.popMin() {
            // Bricht die Suche vorzeitig ab, wenn der aufrufende `Task` inzwischen abgebrochen
            // wurde (Nutzer-Beobachtung 2026-07-31: schnell hintereinander ausgeführte Suchen
            // wurden langsamer, weil die alte, längst überflüssige Suche einfach bis zum Ende
            // weiterlief und dabei CPU-Zeit verbrauchte - `ContentView.cancelActiveSearchTasks()`
            // ruft jetzt `.cancel()` auf den Task auf, diese Prüfung sorgt dafür, dass die
            // Schleife das auch tatsächlich zeitnah bemerkt, statt bis `maxVisitedRoutes` (2000)
            // weiterzurechnen).
            guard !Task.isCancelled else { break }
            let existingEntries = visitedEntryPoints[current.routeId] ?? []
            guard existingEntries.count < Self.maxEntryPointsPerRoute,
                  isNewEntryPoint(current.entryPoint, for: current.routeId) else { continue }
            visitedEntryPoints[current.routeId, default: []].append(current.entryPoint)

            visitedCount += 1
            guard visitedCount <= maxVisitedRoutes else { break }
            guard current.cumulativeKm <= maxAllowedKm else { continue }
            guard let currentRoute = route(withId: current.routeId, near: current.entryPoint) else { continue }

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
                // Nur als neue Alternative zählen, wenn sich die Menge der genutzten Routen-IDs
                // von allen bisherigen Ergebnissen unterscheidet - verhindert, dass
                // `maxAlternatives` von mehreren, sich nur im genauen Einstiegspunkt
                // unterscheidenden Varianten derselben Routen-Kombination verbraucht wird (Fund
                // 2026-07-31 beim `maxEntryPointsPerRoute`-Fix oben: ohne diese Prüfung konnten
                // z. B. zwei Ketten, die beide zweimal dieselbe stark fragmentierte
                // "EuroVelo 13"-Relation nutzen, allein durch die neu erlaubten Mehrfach-Einstiege
                // alle drei Alternativen-Plätze belegen, bevor eine inhaltlich andere Kette wie
                // "Alte Salzstraße" -> "Ostseeküsten-Radweg" überhaupt in Betracht gezogen wurde).
                let routeIdSet = Set(allLegs.map { $0.route.id })
                if !resultRouteIdSets.contains(routeIdSet) {
                    resultRouteIdSets.insert(routeIdSet)
                    results.append(CombinedRouteMatch(
                        legs: allLegs,
                        distanceToStartKm: Self.kilometers(start, allLegs[0].entryPoint),
                        distanceToEndKm: Self.kilometers(allLegs[allLegs.count - 1].exitPoint, end)
                    ))
                    if results.count >= maxAlternatives { break }
                }
            }

            let neighbors = repository.junctions(forRouteId: current.routeId)
            guard !neighbors.isEmpty else { continue }
            let neighborCoordinates = neighbors.map { $0.coordinate }
            let legDistances = RouteMatcher.routeSegmentDistances(
                along: currentRoute.lines, from: current.entryPoint, to: neighborCoordinates
            )

            let routeIdsUsedSoFar = Set(current.legs.map { $0.route.id }).union([current.routeId])
            for (index, neighbor) in neighbors.enumerated() {
                guard let legDistanceKm = legDistances[index] else { continue }
                let partnerEntries = visitedEntryPoints[neighbor.partnerRouteId] ?? []
                guard partnerEntries.count < Self.maxEntryPointsPerRoute else { continue }
                // Verhindert, dass eine einzelne Kette dieselbe Route zweimal nutzt (z. B. über
                // eine Route verlassen und später an anderer Stelle wieder darauf einsteigen) -
                // geometrisch zwar über je einen echten Pfad abgedeckt (jede Etappe für sich
                // gültig), ergäbe als Nutzer-Vorschlag aber eine verwirrende Zickzack-Route statt
                // einer sinnvollen Verkettung unterschiedlicher Fernwege. `visitedEntryPoints`
                // (mehrere Einstiegspunkte je Route) bleibt trotzdem nötig, damit z. B. eine Route
                // wie "D7 Pilgerroute", deren Bremer Einstieg in eine Sackgasse führt, an anderer
                // Stelle (Osnabrück) noch als Zwischenetappe für eine *andere* Kette nutzbar bleibt
                // (s. `maxEntryPointsPerRoute`-Doku oben) - nur eben nicht zweimal in derselben Kette.
                guard !routeIdsUsedSoFar.contains(neighbor.partnerRouteId) else { continue }
                let newCumulativeKm = current.cumulativeKm + legDistanceKm
                let leg = CombinedRouteLeg(
                    route: currentRoute, entryPoint: current.entryPoint, exitPoint: neighbor.coordinate, distanceKm: legDistanceKm
                )
                // Bonus, wenn die nächste Etappe denselben `ref`-Tag trägt (z. B. "EV2" bei
                // EuroVelo 2 diesseits und jenseits der Grenze) - macht Ketten bevorzugt, die auf
                // demselben bekannten Fernweg bleiben, statt rein nach kürzester Gesamtstrecke zu
                // optimieren. Nur ein Bonus in der Warteschlangen-Priorität, `cumulativeKm` bleibt
                // die echte Streckenlänge - das Ergebnis kann dadurch bewusst von der global
                // kürzesten Kette abweichen (Nutzer-Entscheidung), bleibt aber immer eine
                // tatsächlich befahrbare Verbindung.
                let sameRef = currentRoute.ref.map { !$0.isEmpty } == true
                    && currentRoute.ref == repository.ref(forRouteId: neighbor.partnerRouteId)
                let priority = newCumulativeKm + Self.kilometers(neighbor.coordinate, end)
                    - (sameRef ? Self.sameRefPriorityBonusKm : 0)
                queue.push(CombinedSearchEntry(
                    routeId: neighbor.partnerRouteId, entryPoint: neighbor.coordinate,
                    cumulativeKm: newCumulativeKm,
                    priority: priority,
                    legs: current.legs + [leg]
                ))
            }
        }
        var sortedResults = results.sorted { $0.totalDistanceKm < $1.totalDistanceKm }
        // Tatsächlichen Streckenverlauf je Etappe erst jetzt nachträglich berechnen (statt während
        // der Suche für jeden erkundeten Kandidaten) - hält die eigentliche A*-Suche unverändert
        // schnell, da nur für die am Ende tatsächlich zurückgegebenen Ketten (`maxAlternatives`,
        // Standard 3) zusätzliche Dijkstra-Läufe mit Pfad-Rekonstruktion nötig sind.
        for i in sortedResults.indices {
            for j in sortedResults[i].legs.indices {
                let leg = sortedResults[i].legs[j]
                sortedResults[i].legs[j].pathCoordinates = Self.routeSegmentPath(
                    along: leg.route.lines, from: leg.entryPoint, to: leg.exitPoint
                ) ?? []
            }
        }
        return sortedResults
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
