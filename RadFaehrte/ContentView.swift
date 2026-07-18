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

    var body: some View {
        VStack(spacing: 12) {
            if !isNavigating {
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 8) {
                        LocationSearchField(
                            label: "Start",
                            selectedPlace: $startPlace,
                            isResolvingCurrentLocation: isResolvingCurrentLocationForStart,
                            onUseCurrentLocation: useCurrentLocationAsStart
                        )
                        LocationSearchField(label: "Ziel", selectedPlace: $zielPlace)
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

                if selectedMatch != nil {
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
                if let selectedMatch {
                    ForEach(Array(selectedMatch.route.lines.enumerated()), id: \.offset) { _, line in
                        MapPolyline(coordinates: Self.decimated(line))
                            .stroke(.blue, lineWidth: 4)
                    }
                }
            }
            .overlay(alignment: .top) {
                if isNavigating {
                    Button {
                        stopNavigating()
                    } label: {
                        Label("Beenden", systemImage: "xmark.circle.fill")
                            .padding(8)
                            .background(.thinMaterial, in: Capsule())
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
                pitch: 60
            ))
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if matches.isEmpty {
            Text("Keine passende Radroute in der Nähe gefunden")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
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
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
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
