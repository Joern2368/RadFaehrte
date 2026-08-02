//
//  OwnRoutesView.swift
//  RadFaehrte
//

import SwiftUI
import UniformTypeIdentifiers

/// Liste der importierten, fertigen Touren (z. B. GPX-Downloads von Zeitungen/Vereinen).
/// "Starten" macht die Tour im Route-Tab zur aktiven Route (siehe `RootTabView`); für den Weg
/// vom aktuellen Standort zum Streckenanfang wird dort dieselbe Wegbeschreibungs-Logik wie bei
/// den DB-Routen wiederverwendet.
struct OwnRoutesView: View {
    let store: ImportedRouteStore
    /// Von `RootTabView` hochgezählt, wenn eine Tour über das Teilen-Menü ("Öffnen mit")
    /// hinzukam - lädt die Liste neu, auch wenn dieser Tab schon sichtbar ist/bleibt.
    let refreshTrigger: Int
    var onStart: (ImportedRoute) -> Void

    @AppStorage(AppSettingsKey.averageSpeedKmh) private var averageSpeedKmh = AppSettingsDefaults.averageSpeedKmh
    @State private var routes: [ImportedRoute] = []
    @State private var isImporterPresented = false
    @State private var importErrorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if routes.isEmpty {
                    ContentUnavailableView(
                        "Noch keine eigenen Routen",
                        systemImage: "square.and.arrow.down.on.square",
                        description: Text("Importiere eine GPX-Datei einer fertigen Tour, um sie hier zu speichern und zu starten.")
                    )
                } else {
                    List {
                        ForEach(routes) { route in
                            routeRow(route)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Eigene Routen")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("GPX importieren", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("importGPX")
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml, .xml, .data],
                onCompletion: handleImportResult
            )
            .alert("Import fehlgeschlagen", isPresented: .constant(importErrorMessage != nil), presenting: importErrorMessage) { _ in
                Button("OK") { importErrorMessage = nil }
            } message: { message in
                Text(message)
            }
        }
        .onAppear { routes = store.loadAll() }
        .onChange(of: refreshTrigger) { routes = store.loadAll() }
    }

    private func routeRow(_ route: ImportedRoute) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                    .font(.subheadline.weight(.medium))
                Text(routeSubtitle(route))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Starten") {
                onStart(route)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("startImportedRoute-\(route.name)")
        }
        .padding(.vertical, 4)
    }

    private func routeSubtitle(_ route: ImportedRoute) -> String {
        var parts = ["\(String(format: "%.1f", route.totalDistanceKm)) km"]
        if let duration = estimatedDurationText(distanceKm: route.totalDistanceKm, speedKmh: averageSpeedKmh) {
            parts.append(duration)
        }
        return parts.joined(separator: " · ")
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            store.delete(routes[index])
        }
        routes.remove(atOffsets: offsets)
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        case .success(let url):
            let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
            defer { if didAccessSecurityScope { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url),
                  let parsed = GPXParser.parse(data: data), parsed.coordinates.count >= 2 else {
                importErrorMessage = "Die Datei enthält keine gültige GPX-Strecke."
                return
            }

            let fallbackName = url.deletingPathExtension().lastPathComponent
            let route = ImportedRoute(
                name: parsed.name?.isEmpty == false ? parsed.name! : fallbackName,
                coordinates: parsed.coordinates
            )
            store.save(route)
            routes = store.loadAll()
        }
    }
}

#Preview {
    OwnRoutesView(store: ImportedRouteStore(), refreshTrigger: 0, onStart: { _ in })
}
