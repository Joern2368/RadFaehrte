//
//  ContentView.swift
//  RadFaehrte
//

import SwiftUI
import MapKit

struct ContentView: View {
    @State private var startPlace: SelectedPlace?
    @State private var zielPlace: SelectedPlace?
    @State private var cameraPosition: MapCameraPosition = .region(Self.germanyRegion)

    @State private var matcher = RouteMatcher(repository: RouteRepository())
    @State private var matches: [RouteMatch] = []
    @State private var selectedMatch: RouteMatch?

    @State private var locationManager = LocationManager()
    @State private var isNavigating = false
    @State private var showLocationDeniedAlert = false
    @State private var isResolvingCurrentLocationForStart = false
    @State private var hasCenteredOnInitialLocation = false
    @State private var selectedRouteLines: [[CLLocationCoordinate2D]] = []
    @State private var is3DEnabled = false
    @State private var connectorRouteToStart: MKRoute?
    @State private var connectorRouteToEnd: MKRoute?
    @State private var isDirectRouteSelected = false
    @State private var isLoadingDirectRoute = false
    @State private var directRoute: MKRoute?

    var body: some View {
        VStack(spacing: 12) {
            if !isNavigating {
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 8) {
                        LocationSearchField(
                            label: "Start",
                            selectedPlace: $startPlace,
                            isResolvingCurrentLocation: isResolvingCurrentLocationForStart,
                            onUseCurrentLocation: useCurrentLocationAsStart,
                            biasCoordinate: locationManager.currentLocation?.coordinate
                        )
                        LocationSearchField(
                            label: "Ziel",
                            selectedPlace: $zielPlace,
                            biasCoordinate: startPlace?.coordinate ?? locationManager.currentLocation?.coordinate
                        )
                    }

                    Button {
                        swapStartAndZiel()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                    .accessibilityIdentifier("swapStartZiel")
                }
                .padding(.horizontal)
                .padding(.top)
                .zIndex(1)

                if startPlace != nil && zielPlace != nil {
                    resultsSection
                        .padding(.horizontal)
                }

                if selectedMatch != nil || isDirectRouteSelected {
                    Button {
                        startNavigating()
                    } label: {
                        Label("Los", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                }
            }

            Map(position: $cameraPosition) {
                UserAnnotation()
                if !isNavigating {
                    if let startPlace {
                        Marker(startPlace.title, systemImage: "flag.circle.fill", coordinate: startPlace.coordinate)
                            .tint(.green)
                    }
                    if let zielPlace {
                        Marker(zielPlace.title, systemImage: "flag.checkered.circle.fill", coordinate: zielPlace.coordinate)
                            .tint(.red)
                    }
                }
                routeOverlayContent
            }
            .overlay(alignment: .top) {
                if isNavigating {
                    HStack(spacing: 8) {
                        Button {
                            stopNavigating()
                        } label: {
                            Label("Beenden", systemImage: "xmark.circle.fill")
                                .padding(8)
                                .background(.thinMaterial, in: Capsule())
                        }

                        Button {
                            is3DEnabled.toggle()
                            updateNavigationCamera()
                        } label: {
                            Label(is3DEnabled ? "3D" : "2D", systemImage: "view.3d")
                                .padding(8)
                                .background(.thinMaterial, in: Capsule())
                        }
                        .accessibilityIdentifier("toggle2D3D")
                    }
                    .padding(.top, 8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground))
        .simultaneousGesture(TapGesture().onEnded {
            hideKeyboard()
        })
        .onAppear {
            switch locationManager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                locationManager.startUpdating()
            default:
                break
            }
        }
        .onChange(of: startPlace) { runMatching(); updateCamera() }
        .onChange(of: zielPlace) { runMatching(); updateCamera() }
        .onChange(of: selectedMatch) { _, newValue in
            if newValue != nil {
                isDirectRouteSelected = false
                directRoute = nil
            }
            selectedRouteLines = newValue.map { Self.mergedLines($0.route.lines) } ?? []
            loadConnectorRoute(to: newValue)
        }
        .onChange(of: locationManager.locationUpdateCount) { handleLocationUpdate() }
        .onChange(of: locationManager.headingUpdateCount) { updateNavigationCamera() }
        .alert("Standortzugriff benötigt", isPresented: $showLocationDeniedAlert) {
            Button("Einstellungen öffnen") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Für den Navigationsmodus wird der Standortzugriff benötigt. Bitte in den Einstellungen erlauben.")
        }
    }

    private func startNavigating() {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            showLocationDeniedAlert = true
            return
        default:
            break
        }
        locationManager.requestAuthorization()
        locationManager.startUpdating()
        isNavigating = true
        if let location = locationManager.currentLocation {
            updateNavigationCamera(location: location)
        } else {
            withAnimation {
                cameraPosition = .region(Self.regionToFit(
                    [startPlace?.coordinate, zielPlace?.coordinate].compactMap { $0 }
                ))
            }
        }
    }

    private func stopNavigating() {
        locationManager.stopUpdating()
        isNavigating = false
        updateCamera()
    }

    private func swapStartAndZiel() {
        swap(&startPlace, &zielPlace)
    }

    private func useCurrentLocationAsStart() {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            showLocationDeniedAlert = true
            return
        default:
            break
        }
        isResolvingCurrentLocationForStart = true
        locationManager.requestAuthorization()
        locationManager.startUpdating()
        if let location = locationManager.currentLocation {
            resolveCurrentLocationAsStart(location)
        }
    }

    private func handleLocationUpdate() {
        if isNavigating {
            updateNavigationCamera()
        } else if isResolvingCurrentLocationForStart, let location = locationManager.currentLocation {
            resolveCurrentLocationAsStart(location)
        } else if !hasCenteredOnInitialLocation, startPlace == nil, zielPlace == nil,
                  let location = locationManager.currentLocation {
            hasCenteredOnInitialLocation = true
            locationManager.stopUpdating()
            withAnimation {
                cameraPosition = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
        }
    }

    private func resolveCurrentLocationAsStart(_ location: CLLocation) {
        isResolvingCurrentLocationForStart = false
        locationManager.stopUpdating()
        startPlace = SelectedPlace(title: "Aktueller Standort", subtitle: "", coordinate: location.coordinate)
    }

    private func updateNavigationCamera(location: CLLocation? = nil) {
        guard isNavigating, let location = location ?? locationManager.currentLocation else { return }
        withAnimation {
            cameraPosition = .camera(MapCamera(
                centerCoordinate: location.coordinate,
                distance: 300,
                heading: locationManager.currentHeading ?? 0,
                pitch: is3DEnabled ? 60 : 0
            ))
        }
    }

    @MapContentBuilder
    private var routeOverlayContent: some MapContent {
        if isDirectRouteSelected {
            if let directRoute {
                MapPolyline(directRoute.polyline)
                    .stroke(.blue, lineWidth: 4)
            }
        } else {
            ForEach(Array(selectedRouteLines.enumerated()), id: \.offset) { _, line in
                MapPolyline(coordinates: line)
                    .stroke(.blue, lineWidth: 4)
            }
            if let connectorRouteToStart {
                MapPolyline(connectorRouteToStart.polyline)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
            }
            if let connectorRouteToEnd {
                MapPolyline(connectorRouteToEnd.polyline)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
            }
        }
    }

    /// Berechnet eine direkte Fahrrad-Wegbeschreibung von Start zu Ziel, unabhängig vom
    /// importierten Radroutennetz. Für Ziele außerhalb der Reichweite bestehender
    /// Radfernwege/-netze (oder wenn schlicht keine gefunden wurden).
    private func selectDirectRoute() {
        selectedMatch = nil
        isDirectRouteSelected = true
        loadDirectRoute()
    }

    private func loadDirectRoute() {
        directRoute = nil
        guard let start = startPlace?.coordinate, let ziel = zielPlace?.coordinate else { return }
        isLoadingDirectRoute = true
        Task {
            let route = await Self.directions(from: start, to: ziel)
            isLoadingDirectRoute = false
            if isDirectRouteSelected { directRoute = route }
        }
    }

    /// Zeigt Wegbeschreibungen zwischen Start/Ziel und dem jeweils nächstgelegenen Punkt der
    /// ausgewählten Route, falls dieser spürbar entfernt liegt (z. B. wenn der Radweg nicht
    /// direkt am Start- oder Zielpunkt beginnt/endet). Nutzt Fahrrad-Wegbeschreibung mit
    /// Fallback auf Fußweg, falls Radrouting für die Region nicht verfügbar ist.
    private func loadConnectorRoute(to match: RouteMatch?) {
        connectorRouteToStart = nil
        connectorRouteToEnd = nil
        guard let match else { return }

        if let start = startPlace?.coordinate, match.distanceToStartKm > 0.05 {
            Task {
                if let route = await Self.directions(from: start, to: match.nearestPointToStart) {
                    if match.id == selectedMatch?.id { connectorRouteToStart = route }
                }
            }
        }
        if let ziel = zielPlace?.coordinate, match.distanceToEndKm > 0.05 {
            Task {
                if let route = await Self.directions(from: match.nearestPointToEnd, to: ziel) {
                    if match.id == selectedMatch?.id { connectorRouteToEnd = route }
                }
            }
        }
    }

    private static func directions(
        from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D
    ) async -> MKRoute? {
        let sourceItem = MKMapItem(placemark: MKPlacemark(coordinate: source))
        let destinationItem = MKMapItem(placemark: MKPlacemark(coordinate: destination))

        let cyclingRequest = MKDirections.Request()
        cyclingRequest.source = sourceItem
        cyclingRequest.destination = destinationItem
        cyclingRequest.transportType = .cycling

        if let route = try? await MKDirections(request: cyclingRequest).calculate().routes.first {
            return route
        }

        let walkingRequest = MKDirections.Request()
        walkingRequest.source = sourceItem
        walkingRequest.destination = destinationItem
        walkingRequest.transportType = .walking

        return try? await MKDirections(request: walkingRequest).calculate().routes.first
    }

    @ViewBuilder
    private var resultsSection: some View {
        VStack(spacing: 0) {
            Button {
                selectDirectRoute()
            } label: {
                directRouteRow
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("selectDirectRoute")

            if matches.isEmpty {
                Divider()
                Text("Keine passende Radroute in der Nähe gefunden")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
            } else {
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(matches) { match in
                            Button {
                                selectedMatch = match
                            } label: {
                                matchRow(match)
                            }
                            .buttonStyle(.plain)
                            if match.id != matches.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var directRouteRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Direkte Fahrrad-Route")
                    .font(.subheadline.weight(.medium))
                Text("Berechnete Route außerhalb des Radroutennetzes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLoadingDirectRoute {
                ProgressView()
            } else if isDirectRouteSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private func matchRow(_ match: RouteMatch) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(match.route.name ?? "Unbenannte Route")
                    .font(.subheadline.weight(.medium))
                Text(subtitle(for: match))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if match.id == selectedMatch?.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private func subtitle(for match: RouteMatch) -> String {
        var parts: [String] = []
        if let network = match.route.network {
            parts.append(network)
        }
        if let distanceKm = match.route.distanceKm {
            parts.append("\(Int(distanceKm)) km Gesamtlänge")
        }
        parts.append("~\(String(format: "%.1f", match.combinedDistanceKm)) km Entfernung zur Route")
        return parts.joined(separator: " · ")
    }

    private func runMatching() {
        isDirectRouteSelected = false
        directRoute = nil
        guard let start = startPlace?.coordinate, let end = zielPlace?.coordinate else {
            matches = []
            selectedMatch = nil
            return
        }
        matches = matcher.findMatches(start: start, end: end)
        selectedMatch = matches.first
    }

    private func updateCamera() {
        let coordinates = [startPlace?.coordinate, zielPlace?.coordinate].compactMap { $0 }
        withAnimation {
            cameraPosition = .region(Self.regionToFit(coordinates))
        }
    }

    /// Manche Routen (v.a. regionale Netz-Relationen wie "Radverkehrsnetz Bayern") haben
    /// zehntausende Geometriepunkte; MapKit braucht dafür beim Anzeigen spürbar lange
    /// (>1s), da das Rendern synchron beim View-Update passiert. Für die Darstellung reicht
    /// eine grobe Ausdünnung, die Matching-Logik nutzt weiterhin die volle Auflösung.
    private static func decimated(_ line: [CLLocationCoordinate2D], maxPoints: Int = 500) -> [CLLocationCoordinate2D] {
        guard line.count > maxPoints else { return line }
        let step = max(1, line.count / maxPoints)
        var indices = Swift.stride(from: 0, to: line.count, by: step).map { $0 }
        if indices.last != line.count - 1 {
            indices.append(line.count - 1)
        }
        return indices.map { line[$0] }
    }

    /// Manche Routen bestehen aus tausenden einzelnen, meist sehr kurzen Liniensegmenten
    /// (z. B. "Weser - Romantische Straße": 5256 Segmente, obwohl geometrisch lückenlos
    /// aneinander anschließend). Ein separates `MapPolyline` pro Segment lässt MapKit beim
    /// Hinzufügen der Overlays spürbar hängen (mehrere Sekunden). Hier werden Segmente, die
    /// einen gemeinsamen Endpunkt haben, zu durchgehenden Linien verkettet, um die Anzahl
    /// der Overlays drastisch zu reduzieren. Die Matching-Logik bleibt davon unberührt.
    private static func mergedLines(
        _ lines: [[CLLocationCoordinate2D]], epsilon: Double = 1e-5
    ) -> [[CLLocationCoordinate2D]] {
        func key(_ c: CLLocationCoordinate2D) -> String {
            "\(Int((c.latitude / epsilon).rounded())):\(Int((c.longitude / epsilon).rounded()))"
        }

        var endpointIndex: [String: [(line: Int, atStart: Bool)]] = [:]
        for (i, line) in lines.enumerated() where line.count >= 2 {
            endpointIndex[key(line.first!), default: []].append((i, true))
            endpointIndex[key(line.last!), default: []].append((i, false))
        }

        var used = Array(repeating: false, count: lines.count)

        func unusedNeighbor(at point: CLLocationCoordinate2D) -> (line: Int, atStart: Bool)? {
            endpointIndex[key(point)]?.first { !used[$0.line] }
        }

        var merged: [[CLLocationCoordinate2D]] = []
        for start in 0..<lines.count {
            guard !used[start], lines[start].count >= 2 else { continue }
            used[start] = true
            var chain = lines[start]

            while let next = unusedNeighbor(at: chain.last!) {
                used[next.line] = true
                var nextLine = lines[next.line]
                if !next.atStart { nextLine.reverse() }
                chain.append(contentsOf: nextLine.dropFirst())
            }
            while let prev = unusedNeighbor(at: chain.first!) {
                used[prev.line] = true
                var prevLine = lines[prev.line]
                if prev.atStart { prevLine.reverse() }
                chain.insert(contentsOf: prevLine.dropLast(), at: 0)
            }

            merged.append(decimated(chain))
        }
        return merged
    }

    private static let germanyRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.1657, longitude: 10.4515),
        span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
    )

    private static func regionToFit(_ coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else { return germanyRegion }

        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let minLat = lats.min()!
        let maxLat = lats.max()!
        let minLon = lons.min()!
        let maxLon = lons.max()!

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.05),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.05)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

extension RouteMatch: Equatable {
    static func == (lhs: RouteMatch, rhs: RouteMatch) -> Bool {
        lhs.id == rhs.id
    }
}

private func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

#Preview {
    ContentView()
}
