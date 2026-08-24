//
//  RestStopsOfflineView.swift
//  RadFaehrte
//

import SwiftUI

/// Eigener, kleiner Screen für Rastplatz-Downloads (alle 16 Bundesländer, s.
/// `restStopSupportedRegions`) - bewusst kein weiterer Aufruf von `OfflineMapsView<Region>` (das
/// generische UI für die Wege-Graphen), damit dieses Feature vollständig unabhängig von der
/// bestehenden Offline-Karten-UI bleibt.
struct RestStopsOfflineView: View {
    @State private var downloadManager: RestStopDownloadManager

    init(store: RestStopStore) {
        _downloadManager = State(initialValue: RestStopDownloadManager(store: store))
    }

    private var regions: [Bundesland] {
        restStopSupportedRegions.sorted {
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
        .navigationTitle("POIs")
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
    private func regionRow(_ region: Bundesland) -> some View {
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
        RestStopsOfflineView(store: RestStopStore())
    }
}
