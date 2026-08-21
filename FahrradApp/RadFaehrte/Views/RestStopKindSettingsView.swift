//
//  RestStopKindSettingsView.swift
//  RadFaehrte
//

import SwiftUI

/// Eigene Unterseite statt Inline-Toggles in `SettingsView`/`NavigationQuickSettingsView` - analog
/// `NavigationStatSettingsView`, um die dortigen "Rastplätze"-Sektionen nicht um 5 zusätzliche
/// Toggle-Zeilen zu verlängern.
struct RestStopKindSettingsView: View {
    @AppStorage(AppSettingsKey.showRestStopKinds) private var showRestStopKindsRaw = AppSettingsDefaults.showRestStopKinds

    private var enabledKinds: Set<RestStop.Kind> {
        RestStop.Kind.decode(showRestStopKindsRaw)
    }

    private func binding(for kind: RestStop.Kind) -> Binding<Bool> {
        Binding(
            get: { enabledKinds.contains(kind) },
            set: { isOn in
                var kinds = enabledKinds
                if isOn {
                    kinds.insert(kind)
                } else {
                    kinds.remove(kind)
                }
                showRestStopKindsRaw = RestStop.Kind.encode(kinds)
            }
        )
    }

    var body: some View {
        Form {
            Section {
                ForEach(RestStop.Kind.allCases) { kind in
                    Toggle(isOn: binding(for: kind)) {
                        Label(kind.label, systemImage: kind.icon)
                    }
                }
            } footer: {
                Text("Legt fest, welche Rastplatz-Kategorien als Pins auf der Karte angezeigt werden.")
            }
        }
        .navigationTitle("Rastplatz-Kategorien")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        RestStopKindSettingsView()
    }
}
