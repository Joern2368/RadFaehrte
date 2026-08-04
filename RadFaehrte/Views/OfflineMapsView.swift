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
///
/// Regionen erscheinen alphabetisch nach `displayName` sortiert (Nutzerwunsch) statt in
/// Deklarationsreihenfolge des jeweiligen Enums - bei `Bundesland` deckt sich das zufällig
/// (Fallnamen dort schon alphabetisch angelegt), bei `EuropaLand`/`FranceRegion` nicht (Fallnamen
/// dort englisch/französisch, `displayName` aber Deutsch, s. z. B. `.austria` vs. "Österreich").
///
/// `extraRows` (optional, Standard leer) hängt zusätzliche Zeilen in die alphabetisch
/// einsortierte Regionsliste ein - genutzt in der Europa-Liste für "Frankreich"/"Italien", die
/// (statt selbst herunterladbar zu sein) zu den separaten `FranceRegion`-/`ItalyRegion`-Listen
/// weiterleiten, da beide Länder als Ganzes für den Wege-Graph-Bau zu groß sind und stattdessen
/// in Regionen aufgeteilt wurden (Nutzerwunsch, s. ROADMAP.md). `AnyView` statt eines generischen
/// Parameters, da es potenziell mehrere unterschiedlich aussehende Extra-Zeilen gleichzeitig sein
/// können (anders als der frühere Einzel-`trailingContent`-Versuch, der nur "Frankreich" allein
/// korrekt einsortieren konnte) - bei einer Handvoll Zeilen in einer Einstellungen-Liste keine
/// spürbare Kostenfrage. Jede Zeile trägt ein `label` nur für die Einsortierungs-Position
/// (Vergleich mit den `displayName`s), nicht für die tatsächliche Darstellung.
struct OfflineMapsView<Region: DownloadableRegion>: View where Region.ID == String {
    struct ExtraRow {
        let label: String
        let content: AnyView

        init(label: String, @ViewBuilder content: () -> some View) {
            self.label = label
            self.content = AnyView(content())
        }
    }

    private struct Row: Identifiable {
        enum Kind {
            case region(Region)
            case extra(AnyView)
        }
        let id: String
        let kind: Kind
    }

    @State private var downloadManager: WayGraphDownloadManager<Region>
    private let title: String
    private let footer: String
    private let extraRows: [ExtraRow]

    init(
        store: WayGraphStore<Region>, title: String, footer: String,
        extraRows: [ExtraRow] = []
    ) {
        _downloadManager = State(initialValue: WayGraphDownloadManager(store: store))
        self.title = title
        self.footer = footer
        self.extraRows = extraRows
    }

    private var rows: [Row] {
        var result = Region.allCases
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            .map { Row(id: $0.id, kind: .region($0)) }
        for (index, extra) in extraRows.enumerated() {
            let insertIndex = result.firstIndex {
                guard case let .region(region) = $0.kind else { return false }
                return extra.label.localizedStandardCompare(region.displayName) == .orderedAscending
            } ?? result.count
            result.insert(Row(id: "extra-\(index)", kind: .extra(extra.content)), at: insertIndex)
        }
        return result
    }

    var body: some View {
        Form {
            Section {
                ForEach(rows) { row in
                    switch row.kind {
                    case .region(let region):
                        regionRow(region)
                    case .extra(let view):
                        view
                    }
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
                    Text("~\(region.approximateSizeMB) MB")
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
        OfflineMapsView(
            store: WayGraphStore<Bundesland>(),
            title: "Offline-Karten Deutschland",
            footer: "Für heruntergeladene Bundesländer nutzt \"Direkte Fahrrad-Route\" eine eigene Offline-Engine, die ruhige Wege und Radwege bevorzugt, statt online über Apple zu routen - funktioniert auch ganz ohne Internetverbindung."
        )
    }
}
