//
//  OfflineMapsView.swift
//  RadFaehrte
//

import SwiftUI

/// Eigener Screen für Wege-Graph-Downloads (Offline-Routing-Engine für die "Direkte
/// Fahrrad-Route") - aus `SettingsView` ausgelagert, damit die Haupt-Einstellungen nicht durch
/// viele einzelne Zeilen unübersichtlich lang werden. Generisch über `Region` (`Bundesland` oder
/// `EuropaLand`), damit dieselbe Liste/Download-UI für Deutschland ("Offline-Karten Deutschland")
/// und weitere Länder ("Offline-Karten Europa") wiederverwendet wird, statt zwei fast identische
/// Views zu pflegen.
struct OfflineMapsView<Region: DownloadableRegion>: View {
    @State private var downloadManager: WayGraphDownloadManager<Region>
    private let title: String
    private let footer: String

    init(store: WayGraphStore<Region>, title: String, footer: String) {
        _downloadManager = State(initialValue: WayGraphDownloadManager(store: store))
        self.title = title
        self.footer = footer
    }

    var body: some View {
        Form {
            Section {
                ForEach(Array(Region.allCases)) { region in
                    regionRow(region)
                }
            } footer: {
                Text(footer)
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(region.displayName)
                if let progress = downloadManager.progress[region] {
                    ProgressView(value: progress)
                        .frame(maxWidth: 120)
                } else if downloadManager.isDownloaded(region) {
                    Text("Heruntergeladen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("~\(region.approximateSizeMB) MB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if downloadManager.progress[region] != nil {
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
        OfflineMapsView(
            store: WayGraphStore<Bundesland>(),
            title: "Offline-Karten Deutschland",
            footer: "Für heruntergeladene Bundesländer nutzt \"Direkte Fahrrad-Route\" eine eigene Offline-Engine, die ruhige Wege und Radwege bevorzugt, statt online über Apple zu routen - funktioniert auch ganz ohne Internetverbindung."
        )
    }
}
