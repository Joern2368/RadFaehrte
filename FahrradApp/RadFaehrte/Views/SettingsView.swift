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
    let restStopStore: RestStopStore
    private let recentPlaceStore = RecentPlaceStore()
    @State private var showClearRecentsConfirmation = false

    init(
        wayGraphStore: WayGraphStore<Bundesland> = WayGraphStore(),
        europaWayGraphStore: WayGraphStore<EuropaLand> = WayGraphStore(),
        franceWayGraphStore: WayGraphStore<FranceRegion> = WayGraphStore(),
        italyWayGraphStore: WayGraphStore<ItalyRegion> = WayGraphStore(),
        spainWayGraphStore: WayGraphStore<SpainRegion> = WayGraphStore(),
        restStopStore: RestStopStore = RestStopStore()
    ) {
        self.wayGraphStore = wayGraphStore
        self.europaWayGraphStore = europaWayGraphStore
        self.franceWayGraphStore = franceWayGraphStore
        self.italyWayGraphStore = italyWayGraphStore
        self.spainWayGraphStore = spainWayGraphStore
        self.restStopStore = restStopStore
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
                            footer: "Wie bei den Bundesländern: Für ein heruntergeladenes Land nutzt \"Direkte Fahrrad-Route\" dort eine eigene Offline-Engine statt online über Apple zu routen - funktioniert auch ganz ohne Internetverbindung. Frankreich, Italien und Spanien sind für eine einzelne Datei zu groß und deshalb wie bei den Bundesländern nach Regionen aufgeteilt - die Einträge führen zu deren eigenen Listen.",
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
                                }
                            ]
                        )
                    } label: {
                        Label("Offline-Karten Europa", systemImage: "arrow.down.circle")
                    }
                } header: {
                    Text("Offline-Karten")
                }

                Section {
                    Toggle("Rastplätze anzeigen", isOn: $showRestStops)
                    NavigationLink {
                        RestStopsOfflineView(store: restStopStore)
                    } label: {
                        Label("Rastplätze herunterladen", systemImage: "mappin.and.ellipse")
                    }
                } header: {
                    Text("Rastplätze")
                } footer: {
                    Text("Trinkwasser, Cafés, Aussichtspunkte und Fahrrad-Reparaturstationen aus OpenStreetMap auf der Karte anzeigen.")
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
        }
    }
}

#Preview {
    SettingsView()
}
