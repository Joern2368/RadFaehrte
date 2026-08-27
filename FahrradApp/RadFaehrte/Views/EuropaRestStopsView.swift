//
//  EuropaRestStopsView.swift
//  RadFaehrte
//

import SwiftUI

/// Eine Zeile in der vereinten "POIs Europa"-Liste - unabhängig vom konkreten `Region`-Typ
/// (`EuropaLand` oder einem der Ganz-Land-Typen `FranceCountry`/`SpainCountry`/`ItalyCountry`/
/// `NorwayCountry`/`GreatBritainCountry`). Nötig, weil `RestStopsOfflineView<Region>` (s. dort)
/// über genau einen `Region`-Typ generisch ist - für eine gemeinsame, alphabetisch sortierte Liste
/// über mehrere Typen hinweg (Nutzerwunsch 2026-08-27: "Frankreich/Spanien/Italien/Norwegen zu
/// Europa packen", Großbritannien direkt nach demselben Muster ergänzt statt eigener Zeile)
/// braucht SwiftUI eine gemeinsame, typ-unabhängige Zeilen-Art statt getrennter Listen.
private struct EuropaPOIRow: Identifiable {
    let id: String
    let displayName: String
    let isDownloaded: Bool
    let isDeleting: Bool
    let progress: Double?
    let sizeDisplay: String
    let download: () -> Void
    let cancel: () -> Void
    let delete: () -> Void
}

/// Zeigt POI-Downloads für alle Länder außerhalb Deutschlands in einer einzigen, alphabetisch
/// sortierten Liste - `EuropaLand`-Länder und die vier Ganz-Land-Typen zusammen (s. `EuropaPOIRow`-
/// Doc-Kommentar). Hält dafür fünf getrennte `RestStopDownloadManager`-Instanzen (eine pro
/// `Region`-Typ, da jeder Typ eigene Dateien/Release-Tags hat), mischt deren Zeilen aber in der
/// Anzeige zusammen.
struct EuropaRestStopsView: View {
    @State private var europaManager: RestStopDownloadManager<EuropaLand>
    @State private var franceManager: RestStopDownloadManager<FranceCountry>
    @State private var spainManager: RestStopDownloadManager<SpainCountry>
    @State private var italyManager: RestStopDownloadManager<ItalyCountry>
    @State private var norwayManager: RestStopDownloadManager<NorwayCountry>
    @State private var greatBritainManager: RestStopDownloadManager<GreatBritainCountry>

    init(
        europaStore: RestStopStore<EuropaLand>,
        franceStore: RestStopStore<FranceCountry>,
        spainStore: RestStopStore<SpainCountry>,
        italyStore: RestStopStore<ItalyCountry>,
        norwayStore: RestStopStore<NorwayCountry>,
        greatBritainStore: RestStopStore<GreatBritainCountry>
    ) {
        _europaManager = State(initialValue: RestStopDownloadManager(store: europaStore, supportedRegions: restStopSupportedEuropaLands))
        _franceManager = State(initialValue: RestStopDownloadManager(store: franceStore, supportedRegions: restStopSupportedFranceCountries))
        _spainManager = State(initialValue: RestStopDownloadManager(store: spainStore, supportedRegions: restStopSupportedSpainCountries))
        _italyManager = State(initialValue: RestStopDownloadManager(store: italyStore, supportedRegions: restStopSupportedItalyCountries))
        _norwayManager = State(initialValue: RestStopDownloadManager(store: norwayStore, supportedRegions: restStopSupportedNorwayCountries))
        _greatBritainManager = State(initialValue: RestStopDownloadManager(store: greatBritainStore, supportedRegions: restStopSupportedGreatBritainCountries))
    }

    private var rows: [EuropaPOIRow] {
        let all = europaRows() + franceRows() + spainRows() + italyRows() + norwayRows() + greatBritainRows()
        return all.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Erste nicht-`nil` Fehlermeldung über alle Manager hinweg - im Alltag praktisch immer
    /// höchstens eine gleichzeitig gesetzt (ein Download-Fehler pro Nutzeraktion).
    private var errorMessage: String? {
        europaManager.errorMessage ?? franceManager.errorMessage ?? spainManager.errorMessage
            ?? italyManager.errorMessage ?? norwayManager.errorMessage ?? greatBritainManager.errorMessage
    }

    private func clearErrorMessages() {
        europaManager.errorMessage = nil
        franceManager.errorMessage = nil
        spainManager.errorMessage = nil
        italyManager.errorMessage = nil
        norwayManager.errorMessage = nil
        greatBritainManager.errorMessage = nil
    }

    var body: some View {
        Form {
            Section {
                ForEach(rows) { row in
                    rowView(row)
                }
            } footer: {
                Text("Trinkwasser, Cafés, Aussichtspunkte, Fahrrad-Reparaturstationen, Bänke, Biergärten, Toiletten, E-Bike-Ladestationen und Bäckereien aus OpenStreetMap.")
            }
        }
        .navigationTitle("POIs Europa")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Fehler", isPresented: .constant(errorMessage != nil),
            presenting: errorMessage
        ) { _ in
            Button("OK") { clearErrorMessages() }
        } message: { message in
            Text(message)
        }
    }

    @ViewBuilder
    private func rowView(_ row: EuropaPOIRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName)
                if let progress = row.progress {
                    ProgressView(value: progress)
                        .frame(maxWidth: 120)
                } else if row.isDeleting {
                    Text("Wird gelöscht …")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if row.isDownloaded {
                    Text("Heruntergeladen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(row.sizeDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if row.isDeleting {
                ProgressView()
            } else if row.progress != nil {
                Button("Abbrechen", role: .destructive) { row.cancel() }
            } else if row.isDownloaded {
                Button("Löschen", role: .destructive) { row.delete() }
            } else {
                Button("Herunterladen") { row.download() }
            }
        }
    }

    private func europaRows() -> [EuropaPOIRow] {
        restStopSupportedEuropaLands.map { region in
            EuropaPOIRow(
                id: region.rawValue,
                displayName: region.displayName,
                isDownloaded: europaManager.isDownloaded(region),
                isDeleting: europaManager.deletingRegions.contains(region),
                progress: europaManager.progress[region],
                sizeDisplay: europaManager.approximateSizeDisplay(region),
                download: { europaManager.download(region) },
                cancel: { europaManager.cancel(region) },
                delete: { europaManager.delete(region) }
            )
        }
    }

    private func franceRows() -> [EuropaPOIRow] {
        restStopSupportedFranceCountries.map { region in
            EuropaPOIRow(
                id: region.rawValue,
                displayName: region.displayName,
                isDownloaded: franceManager.isDownloaded(region),
                isDeleting: franceManager.deletingRegions.contains(region),
                progress: franceManager.progress[region],
                sizeDisplay: franceManager.approximateSizeDisplay(region),
                download: { franceManager.download(region) },
                cancel: { franceManager.cancel(region) },
                delete: { franceManager.delete(region) }
            )
        }
    }

    private func spainRows() -> [EuropaPOIRow] {
        restStopSupportedSpainCountries.map { region in
            EuropaPOIRow(
                id: region.rawValue,
                displayName: region.displayName,
                isDownloaded: spainManager.isDownloaded(region),
                isDeleting: spainManager.deletingRegions.contains(region),
                progress: spainManager.progress[region],
                sizeDisplay: spainManager.approximateSizeDisplay(region),
                download: { spainManager.download(region) },
                cancel: { spainManager.cancel(region) },
                delete: { spainManager.delete(region) }
            )
        }
    }

    private func italyRows() -> [EuropaPOIRow] {
        restStopSupportedItalyCountries.map { region in
            EuropaPOIRow(
                id: region.rawValue,
                displayName: region.displayName,
                isDownloaded: italyManager.isDownloaded(region),
                isDeleting: italyManager.deletingRegions.contains(region),
                progress: italyManager.progress[region],
                sizeDisplay: italyManager.approximateSizeDisplay(region),
                download: { italyManager.download(region) },
                cancel: { italyManager.cancel(region) },
                delete: { italyManager.delete(region) }
            )
        }
    }

    private func norwayRows() -> [EuropaPOIRow] {
        restStopSupportedNorwayCountries.map { region in
            EuropaPOIRow(
                id: region.rawValue,
                displayName: region.displayName,
                isDownloaded: norwayManager.isDownloaded(region),
                isDeleting: norwayManager.deletingRegions.contains(region),
                progress: norwayManager.progress[region],
                sizeDisplay: norwayManager.approximateSizeDisplay(region),
                download: { norwayManager.download(region) },
                cancel: { norwayManager.cancel(region) },
                delete: { norwayManager.delete(region) }
            )
        }
    }

    private func greatBritainRows() -> [EuropaPOIRow] {
        restStopSupportedGreatBritainCountries.map { region in
            EuropaPOIRow(
                id: region.rawValue,
                displayName: region.displayName,
                isDownloaded: greatBritainManager.isDownloaded(region),
                isDeleting: greatBritainManager.deletingRegions.contains(region),
                progress: greatBritainManager.progress[region],
                sizeDisplay: greatBritainManager.approximateSizeDisplay(region),
                download: { greatBritainManager.download(region) },
                cancel: { greatBritainManager.cancel(region) },
                delete: { greatBritainManager.delete(region) }
            )
        }
    }
}

#Preview {
    NavigationStack {
        EuropaRestStopsView(
            europaStore: RestStopStore(),
            franceStore: RestStopStore(),
            spainStore: RestStopStore(),
            italyStore: RestStopStore(),
            norwayStore: RestStopStore(),
            greatBritainStore: RestStopStore()
        )
    }
}
