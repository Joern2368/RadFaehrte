//
//  OfflineMapsView.swift
//  RadFaehrte
//

import SwiftUI

/// Eigener Screen für die Bundesländer-Downloads (Offline-Routing-Engine für die "Direkte
/// Fahrrad-Route") - aus `SettingsView` ausgelagert, damit die Haupt-Einstellungen nicht durch
/// 16 einzelne Zeilen unübersichtlich lang werden.
struct OfflineMapsView: View {
    @State private var downloadManager: WayGraphDownloadManager

    init(wayGraphStore: WayGraphStore = WayGraphStore()) {
        _downloadManager = State(initialValue: WayGraphDownloadManager(store: wayGraphStore))
    }

    var body: some View {
        Form {
            Section {
                ForEach(Bundesland.allCases) { bundesland in
                    bundeslandRow(bundesland)
                }
            } footer: {
                Text("Für heruntergeladene Bundesländer nutzt \"Direkte Fahrrad-Route\" eine eigene Offline-Engine, die ruhige Wege und Radwege bevorzugt, statt online über Apple zu routen - funktioniert auch ganz ohne Internetverbindung.")
            }
        }
        .navigationTitle("Offline-Karten")
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
    private func bundeslandRow(_ bundesland: Bundesland) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(bundesland.displayName)
                if let progress = downloadManager.progress[bundesland] {
                    ProgressView(value: progress)
                        .frame(maxWidth: 120)
                } else if downloadManager.isDownloaded(bundesland) {
                    Text("Heruntergeladen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("~\(bundesland.approximateSizeMB) MB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if downloadManager.progress[bundesland] == nil {
                if downloadManager.isDownloaded(bundesland) {
                    Button("Löschen", role: .destructive) {
                        downloadManager.delete(bundesland)
                    }
                } else {
                    Button("Herunterladen") {
                        downloadManager.download(bundesland)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        OfflineMapsView()
    }
}
