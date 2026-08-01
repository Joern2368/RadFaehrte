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
    let wayGraphStore: WayGraphStore<Bundesland>
    let europaWayGraphStore: WayGraphStore<EuropaLand>

    init(
        wayGraphStore: WayGraphStore<Bundesland> = WayGraphStore(),
        europaWayGraphStore: WayGraphStore<EuropaLand> = WayGraphStore()
    ) {
        self.wayGraphStore = wayGraphStore
        self.europaWayGraphStore = europaWayGraphStore
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        NavigationSettingsView()
                    } label: {
                        Label("Navigation", systemImage: "location.north.line")
                    }
                } footer: {
                    Text("Durchschnittsgeschwindigkeit, Sichtweite und Statistik-Leiste während der Navigation.")
                }

                Section {
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
                    Text("Karte")
                } footer: {
                    Text("Die Kartenausrichtung gilt als Vorgabe beim Start einer neuen Navigation - während der Fahrt lässt sie sich über den Umschalt-Button jederzeit ändern.")
                }

                Section {
                    Picker("Erscheinungsbild", selection: $appearanceModeRaw) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
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
                            footer: "Wie bei den Bundesländern: Für ein heruntergeladenes Land nutzt \"Direkte Fahrrad-Route\" dort eine eigene Offline-Engine statt online über Apple zu routen - funktioniert auch ganz ohne Internetverbindung."
                        )
                    } label: {
                        Label("Offline-Karten Europa", systemImage: "arrow.down.circle")
                    }
                }

                Section {
                    NavigationLink {
                        AllRoutesView()
                    } label: {
                        Label("Alle Routen", systemImage: "list.bullet")
                    }
                } footer: {
                    Text("Routen nach Ort oder Name durchsuchen - z. B. um zu prüfen, ob ein bekannter Radweg in der App hinterlegt ist.")
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
                }
            }
            .navigationTitle("Einstellungen")
        }
    }
}

#Preview {
    SettingsView()
}
