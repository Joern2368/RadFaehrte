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
    @State private var routingEngine = BikeRoutingEngine(repository: WayGraphRepository())
    @State private var isDirectRouteMode = false
    @State private var isLoadingDirectRoute = false
    @State private var directRoutes: [BikeRoutingEngine.Route] = []
    @State private var selectedDirectRouteIndex = 0
    @State private var isFollowingUser = true
    @State private var isProgrammaticCameraUpdate = false
    @State private var directRouteMapSelection: Int?
    @State private var tourStartTime: Date?
    @State private var tourDistanceMeters: Double = 0
    @State private var lastTourLocation: CLLocation?
    @State private var tourSummary: TourSummary?

    var body: some View {
        VStack(spacing: 12) {
            if isNavigating {
                navigationHeaderSection
            }
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

                if selectedMatch != nil || isDirectRouteMode {
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

            Map(position: $cameraPosition, selection: $directRouteMapSelection) {
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
            .onMapCameraChange(frequency: .onEnd, handleMapCameraChange)
            .overlay(alignment: .topTrailing) {
                if isNavigating {
                    VStack(spacing: 10) {
                        compassBadge
                        navigationControlsOverlay
                    }
                    .padding()
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
                isDirectRouteMode = false
                directRoutes = []
            }
            selectedRouteLines = newValue.map { Self.mergedLines($0.route.lines) } ?? []
            loadConnectorRoute(to: newValue)
        }
        .onChange(of: locationManager.locationUpdateCount) { handleLocationUpdate() }
        .onChange(of: locationManager.headingUpdateCount) { updateNavigationCamera() }
        .onChange(of: directRouteMapSelection) { _, newValue in
            if let newValue, directRoutes.indices.contains(newValue) {
                selectedDirectRouteIndex = newValue
            }
            directRouteMapSelection = nil
        }
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
        .sheet(item: $tourSummary) { summary in
            tourSummarySheet(summary)
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
        isFollowingUser = true
        tourStartTime = Date()
        tourDistanceMeters = 0
        lastTourLocation = locationManager.currentLocation
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
        if let tourStartTime {
            let duration = Date().timeIntervalSince(tourStartTime)
            let distanceKm = tourDistanceMeters / 1000
            tourSummary = TourSummary(
                distanceKm: distanceKm,
                duration: duration,
                averageSpeedKmh: duration > 0 ? distanceKm / (duration / 3600) : 0
            )
        }
        self.tourStartTime = nil
        lastTourLocation = nil
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
            if let location = locationManager.currentLocation {
                accumulateTourDistance(location)
            }
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

    private func accumulateTourDistance(_ location: CLLocation) {
        if let lastTourLocation {
            tourDistanceMeters += location.distance(from: lastTourLocation)
        }
        lastTourLocation = location
    }

    private func resolveCurrentLocationAsStart(_ location: CLLocation) {
        isResolvingCurrentLocationForStart = false
        locationManager.stopUpdating()
        startPlace = SelectedPlace(title: "Aktueller Standort", subtitle: "", coordinate: location.coordinate)
    }

    private func updateNavigationCamera(location: CLLocation? = nil) {
        guard isNavigating, isFollowingUser, let location = location ?? locationManager.currentLocation else { return }
        isProgrammaticCameraUpdate = true
        withAnimation {
            cameraPosition = .camera(MapCamera(
                centerCoordinate: location.coordinate,
                distance: 300,
                heading: locationManager.currentHeading ?? 0,
                pitch: is3DEnabled ? 60 : 0
            ))
        }
    }

    /// `MapCameraUpdateContext` hat in diesem SDK kein Feld, das eigene (programmatische)
    /// Kamera-Updates von Nutzer-Gesten unterscheidet. Stattdessen wird vor jedem eigenen
    /// Kamera-Update ein Flag gesetzt, das hier konsumiert wird - bleibt es unbeachtet
    /// (Flag war nicht gesetzt), kam die Änderung von einer Nutzer-Geste (Pan/Zoom).
    private func handleMapCameraChange(_ context: MapCameraUpdateContext) {
        if isProgrammaticCameraUpdate {
            isProgrammaticCameraUpdate = false
        } else if isNavigating {
            isFollowingUser = false
        }
    }

    /// Kopfzeile im Navigationsmodus mit Richtungspfeil, aktueller Anweisung und Statistik-
    /// Leiste (Tempo/Strecke/Zielentfernung), angelehnt an gängige Rad-Navigations-Apps.
    /// Weder offizielle Radrouten noch die eigene Routing-Engine liefern Straßennamen pro
    /// Wegabschnitt, daher hier nur eine generische "Route folgen"-Anzeige mit Routennamen.
    private var navigationHeaderSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(navigationInstructionTitle)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text(navigationInstructionSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.24, green: 0.29, blue: 0.16))

            HStack(spacing: 0) {
                navigationStat(value: String(format: "%.1f", currentSpeedKmh), unit: "km/h", label: "Aktuell")
                Divider().frame(height: 32)
                navigationStat(value: String(format: "%.1f", tourDistanceMeters / 1000), unit: "km", label: "Strecke")
                if let distanceToDestinationKm {
                    Divider().frame(height: 32)
                    navigationStat(value: String(format: "%.1f", distanceToDestinationKm), unit: "km", label: "Ziel")
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.background)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top)
    }

    private func navigationStat(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value) \(unit)")
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var navigationInstructionTitle: String {
        "Route folgen"
    }

    private var navigationInstructionSubtitle: String {
        if isDirectRouteMode {
            return "Direkte Route (ruhige Wege)"
        }
        return selectedMatch?.route.name ?? "Radroute"
    }

    private var currentSpeedKmh: Double {
        guard let speed = locationManager.currentLocation?.speed, speed >= 0 else { return 0 }
        return speed * 3.6
    }

    private var distanceToDestinationKm: Double? {
        guard let location = locationManager.currentLocation, let ziel = zielPlace?.coordinate else { return nil }
        return location.distance(from: CLLocation(latitude: ziel.latitude, longitude: ziel.longitude)) / 1000
    }

    private var compassBadge: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.85))
            Image(systemName: "location.north.fill")
                .font(.system(size: 16))
                .foregroundStyle(.red)
                .rotationEffect(.degrees(-(locationManager.currentHeading ?? 0)))
        }
        .frame(width: 40, height: 40)
    }

    @ViewBuilder
    private var navigationControlsOverlay: some View {
        if isNavigating {
            VStack(spacing: 10) {
                Button {
                    stopNavigating()
                } label: {
                    navigationIconButtonLabel("xmark")
                }
                .accessibilityLabel("Beenden")

                Button {
                    is3DEnabled.toggle()
                    isFollowingUser = true
                    updateNavigationCamera()
                } label: {
                    navigationIconButtonLabel("view.3d")
                }
                .accessibilityIdentifier("toggle2D3D")
                .accessibilityLabel(is3DEnabled ? "3D" : "2D")

                if !isFollowingUser {
                    Button {
                        isFollowingUser = true
                        updateNavigationCamera()
                    } label: {
                        navigationIconButtonLabel("location.fill")
                    }
                    .accessibilityIdentifier("recenterOnUser")
                    .accessibilityLabel("Standort")
                }
            }
        }
    }

    private func navigationIconButtonLabel(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 40, height: 40)
            .background(.thinMaterial, in: Circle())
    }

    @MapContentBuilder
    private var routeOverlayContent: some MapContent {
        if isDirectRouteMode {
            ForEach(Array(directRoutes.enumerated()), id: \.offset) { index, route in
                if index != selectedDirectRouteIndex {
                    MapPolyline(coordinates: route.coordinates)
                        .stroke(Color.gray.opacity(0.7), lineWidth: 4)
                        .tag(index)
                }
            }
            if directRoutes.indices.contains(selectedDirectRouteIndex) {
                MapPolyline(coordinates: directRoutes[selectedDirectRouteIndex].coordinates)
                    .stroke(.purple, lineWidth: 5)
                    .tag(selectedDirectRouteIndex)
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

    /// Berechnet eine direkte Fahrrad-Route von Start zu Ziel über die eigene, offline
    /// arbeitende Routing-Engine (siehe `BikeRoutingEngine`), die gezielt Radwege bevorzugt
    /// und Hauptstraßen meidet - unabhängig vom importierten Radroutennetz. Deckt ganz
    /// Deutschland ab (siehe `WayGraphRepository`). Liefert bis zu 4 Routenalternativen
    /// zur Auswahl (wie in Karten-Apps üblich).
    private func selectDirectRoute() {
        selectedMatch = nil
        isDirectRouteMode = true
        loadDirectRoute()
    }

    private func loadDirectRoute() {
        directRoutes = []
        selectedDirectRouteIndex = 0
        guard let start = startPlace?.coordinate, let ziel = zielPlace?.coordinate else { return }
        isLoadingDirectRoute = true
        Task {
            let routes = routingEngine.routes(from: start, to: ziel)
            isLoadingDirectRoute = false
            if isDirectRouteMode { directRoutes = routes }
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
                if let route = await Self.directions(from: start, to: match.nearestPointToStart).first {
                    if match.id == selectedMatch?.id { connectorRouteToStart = route }
                }
            }
        }
        if let ziel = zielPlace?.coordinate, match.distanceToEndKm > 0.05 {
            Task {
                if let route = await Self.directions(from: match.nearestPointToEnd, to: ziel).first {
                    if match.id == selectedMatch?.id { connectorRouteToEnd = route }
                }
            }
        }
    }

    private static func directions(
        from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D
    ) async -> [MKRoute] {
        let sourceItem = MKMapItem(placemark: MKPlacemark(coordinate: source))
        let destinationItem = MKMapItem(placemark: MKPlacemark(coordinate: destination))

        let cyclingRequest = MKDirections.Request()
        cyclingRequest.source = sourceItem
        cyclingRequest.destination = destinationItem
        cyclingRequest.transportType = .cycling

        if let routes = try? await MKDirections(request: cyclingRequest).calculate().routes, !routes.isEmpty {
            return routes
        }

        let walkingRequest = MKDirections.Request()
        walkingRequest.source = sourceItem
        walkingRequest.destination = destinationItem
        walkingRequest.transportType = .walking

        return (try? await MKDirections(request: walkingRequest).calculate().routes) ?? []
    }

    private func tourSummarySheet(_ summary: TourSummary) -> some View {
        VStack(spacing: 24) {
            Text("Tour beendet")
                .font(.title2.bold())
                .padding(.top, 24)

            HStack(spacing: 32) {
                VStack(spacing: 4) {
                    Text(String(format: "%.1f km", summary.distanceKm))
                        .font(.title3.bold())
                    Text("Strecke")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 4) {
                    Text(formattedTourDuration(summary.duration))
                        .font(.title3.bold())
                    Text("Dauer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 4) {
                    Text(String(format: "%.1f km/h", summary.averageSpeedKmh))
                        .font(.title3.bold())
                    Text("⌀ Tempo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Fertig") {
                tourSummary = nil
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 24)
        }
        .padding(.horizontal)
        .presentationDetents([.height(220)])
    }

    @ViewBuilder
    private var resultsSection: some View {
        VStack(spacing: 0) {
            directRouteSection

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

    /// Einzelne Zeile für die direkte Fahrrad-Route. Bei mehreren Alternativen können diese
    /// direkt auf der Karte per Antippen gewählt werden (siehe `routeOverlayContent`/
    /// `directRouteMapSelection`) - das funktioniert aber nur zuverlässig dort, wo sich die
    /// Routen sichtbar unterscheiden; überlappen sie sich (häufig bei ähnlichen Alternativen),
    /// liegt die hervorgehobene Route optisch/beim Antippen über den anderen. Der Stepper
    /// daneben bietet deshalb einen immer funktionierenden zweiten Weg zum Durchschalten.
    @ViewBuilder
    private var directRouteSection: some View {
        HStack(spacing: 4) {
            Button {
                selectDirectRoute()
            } label: {
                if isDirectRouteMode, directRoutes.indices.contains(selectedDirectRouteIndex) {
                    directRouteRow(directRoutes[selectedDirectRouteIndex])
                } else if isDirectRouteMode, !isLoadingDirectRoute {
                    directRouteUnavailableRow
                } else {
                    directRoutePlaceholderRow
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("selectDirectRoute")

            if isDirectRouteMode && directRoutes.count > 1 {
                directRouteAlternatesStepper
            }
        }
        Divider()
    }

    private var directRouteAlternatesStepper: some View {
        HStack(spacing: 2) {
            Button {
                cycleDirectRoute(by: -1)
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            .accessibilityIdentifier("previousDirectRoute")

            Text("\(selectedDirectRouteIndex + 1)/\(directRoutes.count)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button {
                cycleDirectRoute(by: 1)
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            .accessibilityIdentifier("nextDirectRoute")
        }
        .buttonStyle(.plain)
        .padding(.trailing, 8)
    }

    private func cycleDirectRoute(by delta: Int) {
        guard directRoutes.count > 1 else { return }
        let count = directRoutes.count
        selectedDirectRouteIndex = ((selectedDirectRouteIndex + delta) % count + count) % count
    }

    private func directRouteRow(_ route: BikeRoutingEngine.Route) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Direkte Route (ruhige Wege)")
                    .font(.subheadline.weight(.medium))
                Text(directRouteSubtitle(for: route))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.purple)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    /// Die Engine liefert keine Fahrzeit; grob geschätzt über eine mittlere Reisegeschwindigkeit
    /// von 15 km/h (typisches Alltagsrad-Tempo), analog zur bisherigen Apple-Anzeige.
    private func directRouteSubtitle(for route: BikeRoutingEngine.Route) -> String {
        let distanceKm = route.distanceMeters / 1000
        var parts = [
            "\(String(format: "%.1f", distanceKm)) km",
            "ca. \(Int(distanceKm / 15 * 60)) Min.",
            "bevorzugt Radwege, meidet Hauptstraßen"
        ]
        if directRoutes.count > 1 {
            parts.append("\(directRoutes.count) Routen – auf Karte wählbar")
        }
        return parts.joined(separator: " · ")
    }

    private var directRoutePlaceholderRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Direkte Route (ruhige Wege)")
                    .font(.subheadline.weight(.medium))
                Text("Bevorzugt Radwege, meidet Hauptstraßen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLoadingDirectRoute {
                ProgressView()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private var directRouteUnavailableRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Direkte Route (ruhige Wege)")
                    .font(.subheadline.weight(.medium))
                Text("Keine Route gefunden")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
        isDirectRouteMode = false
        directRoutes = []
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

struct TourSummary: Identifiable {
    let id = UUID()
    let distanceKm: Double
    let duration: TimeInterval
    let averageSpeedKmh: Double
}

private func formattedTourDuration(_ interval: TimeInterval) -> String {
    let totalMinutes = Int(interval / 60)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    return hours > 0 ? "\(hours) Std. \(minutes) Min." : "\(minutes) Min."
}

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

private func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

#Preview {
    ContentView()
}
