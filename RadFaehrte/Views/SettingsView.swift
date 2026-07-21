//
//  SettingsView.swift
//  RadFaehrte
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettingsKey.averageSpeedKmh) private var averageSpeedKmh = AppSettingsDefaults.averageSpeedKmh

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
            }
            .navigationTitle("Einstellungen")
        }
    }
}

#Preview {
    SettingsView()
}
