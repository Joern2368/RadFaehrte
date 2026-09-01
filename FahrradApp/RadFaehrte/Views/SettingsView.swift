//
//  SettingsView.swift
//  RadFaehrte
//

import SwiftUI

/// Bewusst kurz gehalten: Bundesländer-Downloads (16 Zeilen), Erklärtext und Versions-/Kontakt-Info
/// stecken in eigenen Unterseiten (`OfflineMapsView`, `HowItWorksView`, `AboutView`) statt allesamt
/// hier zu stehen - sonst wurde der Screen unübersichtlich lang.
struct SettingsView: View {
    @AppStorage(AppSettingsKey.appearanceMode) private var appearanceModeRaw = AppSettingsDefaults.appearanceMode
    @AppStorage(AppSettingsKey.mapStyle) private var mapStyleRaw = AppSettingsDefaults.mapStyle
    @AppStorage(AppSettingsKey.navigationDefaultHeadingUp) private var navigationDefaultHeadingUp = AppSettingsDefaults.navigationDefaultHeadingUp
    @AppStorage(AppSettingsKey.showRestStops) private var showRestStops = AppSettingsDefaults.showRestStops
    let wayGraphStore: WayGraphStore<Bundesland>
    let europaWayGraphStore: WayGraphStore<EuropaLand>
    let franceWayGraphStore: WayGraphStore<FranceRegion>
    let italyWayGraphStore: WayGraphStore<ItalyRegion>
    let spainWayGraphStore: WayGraphStore<SpainRegion>
    let norwayWayGraphStore: WayGraphStore<NorwayRegion>
    let greatBritainWayGraphStore: WayGraphStore<GreatBritainRegion>
    let restStopStore: RestStopStore<Bundesland>
    let europaRestStopStore: RestStopStore<EuropaLand>
    let franceRestStopStore: RestStopStore<FranceCountry>
    let spainRestStopStore: RestStopStore<SpainCountry>
    let italyRestStopStore: RestStopStore<ItalyCountry>
    let norwayRestStopStore: RestStopStore<NorwayCountry>
    let greatBritainRestStopStore: RestStopStore<GreatBritainCountry>
    private let recentPlaceStore = RecentPlaceStore()
    @State private var showClearRecentsConfirmation = false
    @State private var showResetConfirmation = false
    @State private var germanyStorageBytes: Int64 = 0
    @State private var europeStorageBytes: Int64 = 0

    init(
        wayGraphStore: WayGraphStore<Bundesland> = WayGraphStore(),
        europaWayGraphStore: WayGraphStore<EuropaLand> = WayGraphStore(),
        franceWayGraphStore: WayGraphStore<FranceRegion> = WayGraphStore(),
        italyWayGraphStore: WayGraphStore<ItalyRegion> = WayGraphStore(),
        spainWayGraphStore: WayGraphStore<SpainRegion> = WayGraphStore(),
        norwayWayGraphStore: WayGraphStore<NorwayRegion> = WayGraphStore(),
        greatBritainWayGraphStore: WayGraphStore<GreatBritainRegion> = WayGraphStore(),
        restStopStore: RestStopStore<Bundesland> = RestStopStore(),
        europaRestStopStore: RestStopStore<EuropaLand> = RestStopStore(),
        franceRestStopStore: RestStopStore<FranceCountry> = RestStopStore(),
        spainRestStopStore: RestStopStore<SpainCountry> = RestStopStore(),
        italyRestStopStore: RestStopStore<ItalyCountry> = RestStopStore(),
        norwayRestStopStore: RestStopStore<NorwayCountry> = RestStopStore(),
        greatBritainRestStopStore: RestStopStore<GreatBritainCountry> = RestStopStore()
    ) {
        self.wayGraphStore = wayGraphStore
        self.europaWayGraphStore = europaWayGraphStore
        self.franceWayGraphStore = franceWayGraphStore
        self.italyWayGraphStore = italyWayGraphStore
        self.spainWayGraphStore = spainWayGraphStore
        self.norwayWayGraphStore = norwayWayGraphStore
        self.greatBritainWayGraphStore = greatBritainWayGraphStore
        self.restStopStore = restStopStore
        self.europaRestStopStore = europaRestStopStore
        self.franceRestStopStore = franceRestStopStore
        self.spainRestStopStore = spainRestStopStore
        self.italyRestStopStore = italyRestStopStore
        self.norwayRestStopStore = norwayRestStopStore
        self.greatBritainRestStopStore = greatBritainRestStopStore
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Erscheinungsbild", selection: $appearanceModeRaw) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Kartenstil", selection: $mapStyleRaw) {
                        ForEach(MapStyleOption.allCases) { style in
                            Text(style.label).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Standard-Kartenausrichtung", selection: $navigationDefaultHeadingUp) {
                        Text("Fahrtrichtung oben").tag(true)
                        Text("Norden oben").tag(false)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Darstellung")
                } footer: {
                    Text("Die Kartenausrichtung gilt als Vorgabe beim Start einer neuen Navigation - während der Fahrt lässt sie sich über den Umschalt-Button jederzeit ändern.")
                }

                Section {
                    NavigationLink {
                        NavigationSettingsView()
                    } label: {
                        Label("Navigation", systemImage: "location.north.line")
                    }
                } header: {
                    Text("Navigation")
                } footer: {
                    Text("Durchschnittsgeschwindigkeit, Sichtweite und Statistik-Leiste während der Navigation.")
                }

                Section {
                    HStack {
                        Text("Deutschland")
                        Spacer()
                        Text(formattedSize(germanyStorageBytes))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Europa")
                        Spacer()
                        Text(formattedSize(europeStorageBytes))
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink {
                        OfflineMapsView(
                            store: wayGraphStore,
                            title: "Offline-Karten Deutschland",
                            footer: "Für heruntergeladene Bundesländer nutzt \"Direkte Fahrrad-Route\" eine eigene Offline-Engine, die ruhige Wege und Radwege bevorzugt, statt online über Apple zu routen - funktioniert auch ganz ohne Internetverbindung."
                        )
                    } label: {
                        Label("Offline-Karten Deutschland", systemImage: "arrow.down.circle")
                    }
                    NavigationLink {
                        OfflineMapsView(
                            store: europaWayGraphStore,
                            title: "Offline-Karten Europa",
                            footer: "Wie bei den Bundesländern: Für ein heruntergeladenes Land nutzt \"Direkte Fahrrad-Route\" dort eine eigene Offline-Engine statt online über Apple zu routen - funktioniert auch ganz ohne Internetverbindung. Frankreich, Italien, Spanien, Norwegen und Großbritannien sind für eine einzelne Datei zu groß und deshalb wie bei den Bundesländern nach Regionen aufgeteilt - die Einträge führen zu deren eigenen Listen.",
                            extraRows: [
                                OfflineMapsView<EuropaLand>.ExtraRow(label: "Frankreich") {
                                    NavigationLink {
                                        OfflineMapsView(
                                            store: franceWayGraphStore,
                                            title: "Offline-Karten Frankreich",
                                            footer: "Frankreich ist für den Wege-Graph-Bau zu groß für eine einzelne Datei - daher wie bei den Bundesländern nach Regionen aufgeteilt. Für heruntergeladene Regionen nutzt \"Direkte Fahrrad-Route\" dieselbe Offline-Engine wie bei Bundesländern/anderen Ländern."
                                        )
                                    } label: {
                                        Text("Frankreich")
                                    }
                                },
                                OfflineMapsView<EuropaLand>.ExtraRow(label: "Italien") {
                                    NavigationLink {
                                        OfflineMapsView(
                                            store: italyWayGraphStore,
                                            title: "Offline-Karten Italien",
                                            footer: "Italien ist für den Wege-Graph-Bau zu groß für eine einzelne Datei - daher in 5 Makro-Regionen aufgeteilt. Für heruntergeladene Regionen nutzt \"Direkte Fahrrad-Route\" dieselbe Offline-Engine wie bei Bundesländern/anderen Ländern."
                                        )
                                    } label: {
                                        Text("Italien")
                                    }
                                },
                                OfflineMapsView<EuropaLand>.ExtraRow(label: "Spanien") {
                                    NavigationLink {
                                        OfflineMapsView(
                                            store: spainWayGraphStore,
                                            title: "Offline-Karten Spanien",
                                            footer: "Spanien ist für den Wege-Graph-Bau zu groß für eine einzelne Datei - daher in 18 Regionen aufgeteilt. Für heruntergeladene Regionen nutzt \"Direkte Fahrrad-Route\" dieselbe Offline-Engine wie bei Bundesländern/anderen Ländern."
                                        )
                                    } label: {
                                        Text("Spanien")
                                    }
                                },
                                OfflineMapsView<EuropaLand>.ExtraRow(label: "Norwegen") {
                                    NavigationLink {
                                        OfflineMapsView(
                                            store: norwayWayGraphStore,
                                            title: "Offline-Karten Norwegen",
                                            footer: "Norwegen ist für den Wege-Graph-Bau zu groß für eine einzelne Datei - daher in 6 Regionen aufgeteilt. Für heruntergeladene Regionen nutzt \"Direkte Fahrrad-Route\" dieselbe Offline-Engine wie bei Bundesländern/anderen Ländern."
                                        )
                                    } label: {
                                        Text("Norwegen")
                                    }
                                },
                                OfflineMapsView<EuropaLand>.ExtraRow(label: "Großbritannien") {
                                    NavigationLink {
                                        OfflineMapsView(
                                            store: greatBritainWayGraphStore,
                                            title: "Offline-Karten Großbritannien",
                                            footer: "Großbritannien ist für den Wege-Graph-Bau zu groß für eine einzelne Datei - daher in 49 Regionen aufgeteilt (47 englische Grafschaften, Schottland, Wales). Für heruntergeladene Regionen nutzt \"Direkte Fahrrad-Route\" dieselbe Offline-Engine wie bei Bundesländern/anderen Ländern."
                                        )
                                    } label: {
                                        Text("Großbritannien")
                                    }
                                }
                            ]
                        )
                    } label: {
                        Label("Offline-Karten Europa", systemImage: "arrow.down.circle")
                    }
                } header: {
                    Text("Offline-Karten")
                } footer: {
                    Text("Speicherplatz-Angaben umfassen Wege-Graphen und heruntergeladene POI-Daten zusammen.")
                }

                Section {
                    Toggle("POIs anzeigen", isOn: $showRestStops)
                    NavigationLink {
                        RestStopKindSettingsView()
                    } label: {
                        Label("POI-Kategorien", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    NavigationLink {
                        RestStopsOfflineView(store: restStopStore, title: "POIs Deutschland", regions: restStopSupportedRegions)
                    } label: {
                        Label("POIs Deutschland herunterladen", systemImage: "mappin.and.ellipse")
                    }
                    NavigationLink {
                        EuropaRestStopsView(
                            europaStore: europaRestStopStore,
                            franceStore: franceRestStopStore,
                            spainStore: spainRestStopStore,
                            italyStore: italyRestStopStore,
                            norwayStore: norwayRestStopStore,
                            greatBritainStore: greatBritainRestStopStore
                        )
                    } label: {
                        Label("POIs Europa herunterladen", systemImage: "mappin.and.ellipse")
                    }
                } header: {
                    Text("POIs")
                } footer: {
                    Text("Trinkwasser, Cafés, Aussichtspunkte, Fahrrad-Reparaturstationen, Bänke, Biergärten, Toiletten, E-Bike-Ladestationen und Bäckereien aus OpenStreetMap auf der Karte anzeigen.")
                }

                Section {
                    NavigationLink {
                        AllRoutesView()
                    } label: {
                        Label("Alle Routen", systemImage: "list.bullet")
                    }
                    NavigationLink {
                        FavoritePlacesView(store: FavoritePlaceStore())
                    } label: {
                        Label("Favoriten", systemImage: "star")
                    }
                    Button {
                        showClearRecentsConfirmation = true
                    } label: {
                        Label("Suchverlauf löschen", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Meine Routen & Orte")
                }
                .confirmationDialog(
                    "Suchverlauf löschen?",
                    isPresented: $showClearRecentsConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Löschen", role: .destructive) {
                        recentPlaceStore.clear()
                    }
                    Button("Abbrechen", role: .cancel) {}
                } message: {
                    Text("Entfernt alle \"Zuletzt gesucht\"-Einträge aus Start- und Ziel-Suche. Favoriten bleiben erhalten.")
                }

                Section {
                    Button {
                        showResetConfirmation = true
                    } label: {
                        Label("Einstellungen zurücksetzen", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text("Setzt Darstellung, Navigation, Routing und POI-Auswahl auf die Werkseinstellungen zurück. Heruntergeladene Offline-Karten, Favoriten, Routen und Suchverlauf bleiben erhalten.")
                }
                .alert(
                    "Einstellungen zurücksetzen?",
                    isPresented: $showResetConfirmation
                ) {
                    Button("Zurücksetzen", role: .destructive) {
                        AppSettingsReset.resetAll()
                    }
                    Button("Abbrechen", role: .cancel) {}
                } message: {
                    Text("Darstellung, Navigation, Routing und POI-Auswahl werden auf die Werkseinstellungen zurückgesetzt. Heruntergeladene Karten, Favoriten, Routen und Suchverlauf bleiben erhalten.")
                }

                Section {
                    NavigationLink {
                        HowItWorksView()
                    } label: {
                        Label("Wie funktioniert's?", systemImage: "questionmark.circle")
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("Info", systemImage: "info.circle")
                    }
                } header: {
                    Text("Hilfe")
                }
            }
            .navigationTitle("Einstellungen")
            .onAppear(perform: updateStorageTotals)
        }
    }

    private func updateStorageTotals() {
        germanyStorageBytes = wayGraphStore.totalDownloadedBytes() + restStopStore.totalDownloadedBytes()
        europeStorageBytes = europaWayGraphStore.totalDownloadedBytes()
            + franceWayGraphStore.totalDownloadedBytes()
            + italyWayGraphStore.totalDownloadedBytes()
            + spainWayGraphStore.totalDownloadedBytes()
            + norwayWayGraphStore.totalDownloadedBytes()
            + greatBritainWayGraphStore.totalDownloadedBytes()
            + europaRestStopStore.totalDownloadedBytes()
            + franceRestStopStore.totalDownloadedBytes()
            + spainRestStopStore.totalDownloadedBytes()
            + italyRestStopStore.totalDownloadedBytes()
            + norwayRestStopStore.totalDownloadedBytes()
            + greatBritainRestStopStore.totalDownloadedBytes()
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let megabytes = Double(bytes) / 1_048_576
        guard megabytes >= 1024 else {
            return "\(Int(megabytes.rounded())) MB"
        }
        return String(format: "%.1f GB", locale: Locale(identifier: "de_DE"), megabytes / 1024)
    }
}

#Preview {
    SettingsView()
}
