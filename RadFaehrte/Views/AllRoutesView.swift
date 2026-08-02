//
//  AllRoutesView.swift
//  RadFaehrte
//

import SwiftUI
import CoreLocation
import MapKit

/// Übersicht/Suche über den kompletten Routenbestand (~13.800 benannte Routen über alle
/// gebündelten Länder-Datenbanken hinweg) - beantwortet die Frage "kennt die App die mir
/// bekannten lokalen Radwege?". Eine reine alphabetische Liste wäre bei dieser Menge unbrauchbar
/// (man weiß ja gerade nicht, unter welchem Buchstaben eine lokale Route steht), deshalb zwei
/// Sucharten: Umkreissuche um einen Ort (nutzt dieselbe Bbox-Überlappung wie die Navigations-
/// Kernfunktion) und Namenssuche für den Fall, dass man einen konkreten Namen kennt.
struct AllRoutesView: View {
    private enum SearchMode: String, CaseIterable, Identifiable {
        case nearby
        case byName

        var id: String { rawValue }

        var label: String {
            switch self {
            case .nearby: return "In der Nähe"
            case .byName: return "Nach Name"
            }
        }
    }

    /// Deckelt sowohl die Ergebnismenge als auch die Laufzeit der Namenssuche, die mangels Index
    /// auf `name` (s. `RouteRepository`) einen vollen Tabellenscan macht.
    private static let resultLimit = 300
    /// Kantenlänge (Grad) der Bbox um einen gesuchten Ort - grobe ~30 km-Umkreissuche, ausreichend
    /// um lokale und regionale Routen um eine Stadt herum zu finden.
    private static let nearbySpanDegrees = 0.3

    @State private var repository = RouteRepository()
    @State private var searchMode: SearchMode = .nearby

    @State private var selectedPlace: SelectedPlace?
    @State private var locationManager = LocationManager()
    @State private var isResolvingCurrentLocation = false
    @State private var showLocationDeniedAlert = false

    @State private var nameQuery = ""

    @State private var results: [RouteSummary] = []
    @State private var isLoading = false
    @State private var hasSearched = false

    /// Angetippte Route, deren Geometrie noch geladen wird bzw. die als Kartenausschnitt gezeigt
    /// wird - `RouteDetailSheet` fragt dafür die volle `BikeRoute` (mit Geometrie) nach, die
    /// `RouteSummary` bewusst nicht enthält (s. `RouteRepository.routeSummaries`).
    @State private var selectedSummary: RouteSummary?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Suchart", selection: $searchMode) {
                ForEach(SearchMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            Group {
                switch searchMode {
                case .nearby:
                    LocationSearchField(
                        label: "Ort, z. B. Frankfurt am Main",
                        selectedPlace: $selectedPlace,
                        isResolvingCurrentLocation: isResolvingCurrentLocation,
                        onUseCurrentLocation: useCurrentLocation
                    )
                case .byName:
                    TextField("Routenname, z. B. Weser-Radweg", text: $nameQuery)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            resultsList
        }
        .navigationTitle("Alle Routen")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: searchMode) { _, _ in
            results = []
            hasSearched = false
            isLoading = false
        }
        .onChange(of: selectedPlace) { _, newValue in
            if let newValue { search(nearby: newValue.coordinate) }
        }
        .onChange(of: locationManager.locationUpdateCount) {
            if isResolvingCurrentLocation, let location = locationManager.currentLocation {
                resolveCurrentLocation(location)
            }
        }
        .task(id: nameQuery) {
            guard searchMode == .byName else { return }
            let trimmed = nameQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else {
                results = []
                hasSearched = false
                return
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await search(matchingName: trimmed)
        }
        .alert("Standortzugriff benötigt", isPresented: $showLocationDeniedAlert) {
            Button("Einstellungen öffnen") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Um Routen in deiner Nähe zu finden, wird der Standortzugriff benötigt. Bitte in den Einstellungen erlauben.")
        }
        .sheet(item: $selectedSummary) { summary in
            RouteDetailSheet(repository: repository, summary: summary)
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if isLoading {
            Spacer()
            ProgressView()
            Spacer()
        } else if !hasSearched {
            ContentUnavailableView(
                "Route suchen",
                systemImage: "list.bullet",
                description: Text(
                    searchMode == .nearby
                        ? "Gib einen Ort ein oder nutze deine aktuelle Position, um Routen in der Nähe zu finden."
                        : "Gib mindestens 2 Zeichen eines Routennamens ein."
                )
            )
            Spacer()
        } else if results.isEmpty {
            ContentUnavailableView.search
            Spacer()
        } else {
            List {
                Section {
                    ForEach(results) { summary in
                        Button {
                            selectedSummary = summary
                        } label: {
                            routeRow(summary)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    if results.count >= Self.resultLimit {
                        Text("Zeigt die ersten \(Self.resultLimit) Treffer – Suche eingrenzen.")
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func routeRow(_ summary: RouteSummary) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.name)
                    .font(.subheadline.weight(.medium))
                if let subtitle = subtitle(for: summary) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let label = summary.networkLabel {
                Text(label)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func subtitle(for summary: RouteSummary) -> String? {
        var parts: [String] = []
        if let ref = summary.ref, !ref.isEmpty { parts.append(ref) }
        if let distanceKm = summary.distanceKm { parts.append("\(Int(distanceKm)) km") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func useCurrentLocation() {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            showLocationDeniedAlert = true
            return
        default:
            break
        }
        isResolvingCurrentLocation = true
        locationManager.requestAuthorization()
        locationManager.startUpdating()
        if let location = locationManager.currentLocation {
            resolveCurrentLocation(location)
        }
    }

    private func resolveCurrentLocation(_ location: CLLocation) {
        isResolvingCurrentLocation = false
        locationManager.stopUpdating()
        selectedPlace = SelectedPlace(title: "Aktueller Standort", subtitle: "", coordinate: location.coordinate)
    }

    private func search(nearby coordinate: CLLocationCoordinate2D) {
        isLoading = true
        hasSearched = true
        let half = Self.nearbySpanDegrees / 2
        let minLon = coordinate.longitude - half
        let maxLon = coordinate.longitude + half
        let minLat = coordinate.latitude - half
        let maxLat = coordinate.latitude + half
        let repository = repository
        Task.detached(priority: .userInitiated) {
            let summaries = repository.routeSummaries(
                minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat, limit: Self.resultLimit
            )
            await MainActor.run {
                results = summaries.sorted { $0.name < $1.name }
                isLoading = false
            }
        }
    }

    private func search(matchingName query: String) async {
        isLoading = true
        hasSearched = true
        let repository = repository
        let summaries = await Task.detached(priority: .userInitiated) {
            repository.routeSummaries(matchingName: query, limit: Self.resultLimit)
        }.value
        results = summaries.sorted { $0.name < $1.name }
        isLoading = false
    }
}

/// Kartenansicht einer angetippten Route aus der Ergebnisliste - lädt die volle Geometrie erst
/// bei Bedarf nach (`RouteSummary` enthält sie bewusst nicht, s. `RouteRepository.routeSummaries`),
/// analog dem Verlauf-Tab (`HistoryView.tourDetail`).
private struct RouteDetailSheet: View {
    let repository: RouteRepository
    let summary: RouteSummary

    @State private var route: BikeRoute?
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettingsKey.averageSpeedKmh) private var averageSpeedKmh = AppSettingsDefaults.averageSpeedKmh

    var body: some View {
        NavigationStack {
            Group {
                if let route, !route.lines.isEmpty {
                    Map(initialPosition: .region(route.region())) {
                        ForEach(Array(route.lines.enumerated()), id: \.offset) { _, line in
                            MapPolyline(coordinates: line)
                                .stroke(.blue, lineWidth: 4)
                        }
                    }
                } else if isLoading {
                    ProgressView()
                } else {
                    ContentUnavailableView(
                        "Kein Streckenverlauf",
                        systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                        description: Text("Für diese Route liegt keine kartierte Geometrie vor.")
                    )
                }
            }
            .navigationTitle(summary.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.bar)
                }
            }
        }
        .task {
            let id = summary.id
            let fetched = await Task.detached(priority: .userInitiated) {
                repository.route(withId: id)
            }.value
            route = fetched
            isLoading = false
        }
    }

    private var subtitleText: String? {
        var parts: [String] = []
        if let ref = summary.ref, !ref.isEmpty { parts.append(ref) }
        if let distanceKm = summary.distanceKm { parts.append("\(Int(distanceKm)) km") }
        if let duration = estimatedDurationText(distanceKm: summary.distanceKm, speedKmh: averageSpeedKmh) { parts.append(duration) }
        if let label = summary.networkLabel { parts.append(label) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        AllRoutesView()
    }
}
