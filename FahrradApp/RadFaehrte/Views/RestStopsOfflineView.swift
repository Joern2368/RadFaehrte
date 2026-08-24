//
//  RestStopsOfflineView.swift
//  RadFaehrte
//

import SwiftUI

/// Eigener, kleiner Screen für Rastplatz-Downloads - bewusst kein weiterer Aufruf von
/// `OfflineMapsView<Region>` (das generische UI für die Wege-Graphen), damit dieses Feature
/// vollständig unabhängig von der bestehenden Offline-Karten-UI bleibt. Generisch über
/// `Region: RestStopDownloadableRegion` seit Luxemburg als zweitem unterstützten Land (2026-08-24),
/// analog `RestStopStore<Region>`. Anders als `OfflineMapsView<Region>` bekommt diese View die
/// unterstützten Regionen explizit übergeben statt `Region.allCases` zu verwenden - nicht jede
/// `Bundesland`-/`EuropaLand`-Ausprägung hat automatisch eine gebaute POI-Datei (s.
/// `restStopSupportedRegions`/`restStopSupportedEuropaLands`).
struct RestStopsOfflineView<Region: RestStopDownloadableRegion>: View {
    @State private var downloadManager: RestStopDownloadManager<Region>
    private let title: String
    private let regions: [Region]

    init(store: RestStopStore<Region>, title: String, regions: [Region]) {
        _downloadManager = State(initialValue: RestStopDownloadManager(store: store, supportedRegions: regions))
        self.title = title
        self.regions = regions.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(regions) { region in
                    regionRow(region)
                }
            } footer: {
                Text("Trinkwasser, Cafés, Aussichtspunkte, Fahrrad-Reparaturstationen, Bänke, Biergärten, Toiletten, E-Bike-Ladestationen und Bäckereien aus OpenStreetMap.")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Fehler", isPresented: .constant(downloadManager.errorMessage != nil),
            presenting: downloadManager.errorMessage
        ) { _ in
            Button("OK") { downloadManager.errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    @ViewBuilder
    private func regionRow(_ region: Region) -> some View {
        let isDeleting = downloadManager.deletingRegions.contains(region)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(region.displayName)
                if let progress = downloadManager.progress[region] {
                    ProgressView(value: progress)
                        .frame(maxWidth: 120)
                } else if isDeleting {
                    Text("Wird gelöscht …")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if downloadManager.isDownloaded(region) {
                    Text("Heruntergeladen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(downloadManager.approximateSizeDisplay(region))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isDeleting {
                ProgressView()
            } else if downloadManager.progress[region] != nil {
                Button("Abbrechen", role: .destructive) {
                    downloadManager.cancel(region)
                }
            } else {
                if downloadManager.isDownloaded(region) {
                    Button("Löschen", role: .destructive) {
                        downloadManager.delete(region)
                    }
                } else {
                    Button("Herunterladen") {
                        downloadManager.download(region)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RestStopsOfflineView(store: RestStopStore(), title: "POIs Deutschland", regions: restStopSupportedRegions)
    }
}
