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
