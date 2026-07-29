//
//  NavigationQuickSettingsView.swift
//  RadFaehrte
//

import SwiftUI

/// Eigenes, bewusst kurzes Sheet statt der vollständigen `SettingsView` - während der Navigation
/// per Zahnrad-Button erreichbar (`ContentView.navigationControlsOverlay`), da die Tab-Leiste dann
/// ausgeblendet ist und der Einstellungen-Tab sonst nicht erreichbar wäre (Nutzer-Feedback). Zeigt
/// nur die unterwegs relevanten Werte (Tempo, Sichtweite, Kartenstil, Statistik-Leiste) - Offline-
/// Karten-Downloads o. Ä. wären hier fehl am Platz.
struct NavigationQuickSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettingsKey.averageSpeedKmh) private var averageSpeedKmh = AppSettingsDefaults.averageSpeedKmh
    @AppStorage(AppSettingsKey.navigationLookaheadMeters) private var navigationLookaheadMeters = AppSettingsDefaults.navigationLookaheadMeters
    @AppStorage(AppSettingsKey.mapStyle) private var mapStyleRaw = AppSettingsDefaults.mapStyle

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
    NavigationQuickSettingsView()
}
