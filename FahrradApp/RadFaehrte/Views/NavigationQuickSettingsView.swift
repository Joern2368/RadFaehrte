//
//  NavigationQuickSettingsView.swift
//  RadFaehrte
//

import SwiftUI

/// Eigenes, bewusst kurzes Sheet statt der vollständigen `SettingsView` - während der Navigation
/// per Zahnrad-Button erreichbar (`ContentView.navigationControlsOverlay`), da die Tab-Leiste dann
/// ausgeblendet ist und der Einstellungen-Tab sonst nicht erreichbar wäre (Nutzer-Feedback). Zeigt
/// nur die unterwegs relevanten Werte (Tempo, Sichtweite, Kartenstil, Statistik-Leiste,
/// Sprachausgabe, Rastplätze) - Offline-Karten-Downloads für Wege-Graphen (bis zu einigen hundert
/// MB) wären hier fehl am Platz. Der Rastplätze-Download gehört trotzdem dazu (Nutzer-Wunsch,
/// 2026-08-21): die Dateien sind mit unter 1 MB pro Bundesland winzig, und unterwegs zu merken
/// "hier wäre eine Pause gut" ist gerade der Moment, in dem man die Anzeige an-/ausschalten oder
/// das aktuelle Bundesland nachladen möchte - dafür extra in den Einstellungen-Tab wechseln zu
/// müssen (Tab-Leiste während der Navigation ausgeblendet) wäre unnötig umständlich.
struct NavigationQuickSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettingsKey.averageSpeedKmh) private var averageSpeedKmh = AppSettingsDefaults.averageSpeedKmh
    @AppStorage(AppSettingsKey.navigationLookaheadMeters) private var navigationLookaheadMeters = AppSettingsDefaults.navigationLookaheadMeters
    @AppStorage(AppSettingsKey.mapStyle) private var mapStyleRaw = AppSettingsDefaults.mapStyle
    @AppStorage(AppSettingsKey.isVoiceGuidanceEnabled) private var isVoiceGuidanceEnabled = AppSettingsDefaults.isVoiceGuidanceEnabled
    @AppStorage(AppSettingsKey.showRestStops) private var showRestStops = AppSettingsDefaults.showRestStops
    let restStopStore: RestStopStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $averageSpeedKmh, in: AppSettingsDefaults.averageSpeedRange, step: 1) {
                        HStack {
                            Text("Durchschnittsgeschwindigkeit")
                            Spacer()
                            Text("\(Int(averageSpeedKmh)) km/h")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Wird für die geschätzte Fahrzeit in der Routenliste verwendet.")
                }

                Section {
                    Stepper(value: $navigationLookaheadMeters, in: AppSettingsDefaults.navigationLookaheadRange, step: 10) {
                        HStack {
                            Text("Sichtweite beim Navigieren")
                            Spacer()
                            Text("\(Int(navigationLookaheadMeters)) m")
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Wie viele Meter voraus in der 2D-Kartenansicht während der Navigation sichtbar sind. Gilt nicht im 3D-Modus.")
                }

                Section {
                    Picker("Kartenstil", selection: $mapStyleRaw) {
                        ForEach(MapStyleOption.allCases) { style in
                            Text(style.label).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    NavigationLink {
                        NavigationStatSettingsView()
                    } label: {
                        Label("Statistik-Leiste", systemImage: "square.grid.3x2")
                    }
                } footer: {
                    Text("Welche Werte in der Statistik-Leiste über der Karte während der Navigation angezeigt werden.")
                }

                Section {
                    Toggle("Sprachausgabe für Abbiegehinweise", isOn: $isVoiceGuidanceEnabled)
                } footer: {
                    Text("Kündigt Abbiegungen zusätzlich zur Watch-Vibration laut an - wie bei der Watch-Vibration nur für einen ausgewählten Einzeltreffer, eine kombinierte Kette oder die \"Direkte Fahrrad-Route\", jeweils mit heruntergeladenem Wege-Graph bzw. echten Abbiege-Hinweisen.")
                }

                Section {
                    Toggle("Rastplätze anzeigen", isOn: $showRestStops)
                    NavigationLink {
                        RestStopKindSettingsView()
                    } label: {
                        Label("Rastplatz-Kategorien", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    NavigationLink {
                        RestStopsOfflineView(store: restStopStore)
                    } label: {
                        Label("Rastplätze herunterladen", systemImage: "mappin.and.ellipse")
                    }
                } header: {
                    Text("Rastplätze")
                } footer: {
                    Text("Trinkwasser, Cafés, Aussichtspunkte, Fahrrad-Reparaturstationen, Bänke, Biergärten und Toiletten aus OpenStreetMap auf der Karte anzeigen.")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationQuickSettingsView(restStopStore: RestStopStore())
}
