//
//  SettingsView.swift
//  RadFaehrte
//

import SwiftUI

/// Bewusst kurz gehalten: Bundesländer-Downloads (16 Zeilen), Erklärtext und Versions-/Kontakt-Info
/// stecken in eigenen Unterseiten (`OfflineMapsView`, `HowItWorksView`, `AboutView`) statt allesamt
/// hier zu stehen - sonst wurde der Screen unübersichtlich lang.
struct SettingsView: View {
    @AppStorage(AppSettingsKey.averageSpeedKmh) private var averageSpeedKmh = AppSettingsDefaults.averageSpeedKmh
    @AppStorage(AppSettingsKey.navigationLookaheadMeters) private var navigationLookaheadMeters = AppSettingsDefaults.navigationLookaheadMeters
    let wayGraphStore: WayGraphStore

    init(wayGraphStore: WayGraphStore = WayGraphStore()) {
        self.wayGraphStore = wayGraphStore
    }

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
                    Text("Wie viele Meter voraus in der 2D-Kartenansicht während der Navigation sichtbar sind - z. B. wie früh eine bevorstehende Abbiegung zu sehen ist. Gilt nicht im 3D-Modus.")
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
                    NavigationLink {
                        OfflineMapsView(wayGraphStore: wayGraphStore)
                    } label: {
                        Label("Offline-Karten", systemImage: "arrow.down.circle")
                    }
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
