//
//  NavigationSettingsView.swift
//  RadFaehrte
//

import SwiftUI

/// Bündelt die Einstellungen rund um die Navigations-Ansicht (Durchschnittsgeschwindigkeit,
/// Sichtweite, Statistik-Leiste) auf einer eigenen Unterseite statt einzeln auf dem Hauptscreen -
/// gehören inhaltlich zusammen und halten `SettingsView` kurz.
struct NavigationSettingsView: View {
    @AppStorage(AppSettingsKey.averageSpeedKmh) private var averageSpeedKmh = AppSettingsDefaults.averageSpeedKmh
    @AppStorage(AppSettingsKey.navigationLookaheadMeters) private var navigationLookaheadMeters = AppSettingsDefaults.navigationLookaheadMeters
    @AppStorage(AppSettingsKey.isVoiceGuidanceEnabled) private var isVoiceGuidanceEnabled = AppSettingsDefaults.isVoiceGuidanceEnabled
    @AppStorage(AppSettingsKey.allowFootwayShortcuts) private var allowFootwayShortcuts = AppSettingsDefaults.allowFootwayShortcuts
    @AppStorage(AppSettingsKey.allowStepsShortcuts) private var allowStepsShortcuts = AppSettingsDefaults.allowStepsShortcuts

    var body: some View {
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
                Toggle("Sprachausgabe für Abbiegehinweise", isOn: $isVoiceGuidanceEnabled)
            } footer: {
                Text("Kündigt Abbiegungen zusätzlich zur Watch-Vibration laut an - wie bei der Watch-Vibration nur für einen ausgewählten Einzeltreffer, eine kombinierte Kette oder die \"Direkte Fahrrad-Route\", jeweils mit heruntergeladenem Wege-Graph bzw. echten Abbiege-Hinweisen.")
            }

            Section {
                Toggle("Fußwege als Abkürzung einbeziehen", isOn: $allowFootwayShortcuts)
                Toggle("Treppen als Abkürzung einbeziehen", isOn: $allowStepsShortcuts)
            } header: {
                Text("Routing")
            } footer: {
                Text("Betrifft nur die Offline-Engine (heruntergeladene Regionen): Bei aktivierten Fußwegen bezieht die Route ganz normal genutzte Fußwege ein (z. B. Uferwege, Unterführungen) - läuft direkt daneben ein echter Radweg, wird der trotzdem bevorzugt. Treppen bleiben eine reine Notlösung für kurze, klar lohnende Abstecher. Genutzte Abschnitte werden in der Wegearten-Aufschlüsselung als \"Schiebestrecke\"/\"Treppe\" ausgewiesen.")
            }
        }
        .navigationTitle("Navigation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        NavigationSettingsView()
    }
}
