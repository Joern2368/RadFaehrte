//
//  RestStopKindSettingsView.swift
//  RadFaehrte
//

import SwiftUI

/// Eigene Unterseite statt Inline-Toggles in `SettingsView`/`NavigationQuickSettingsView` - analog
/// `NavigationStatSettingsView`, um die dortigen "POIs"-Sektionen nicht um zusätzliche
/// Toggle-Zeilen (eine pro Kategorie) zu verlängern.
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
                        Label { Text(kind.label) } icon: { RestStopKindIcon(kind: kind) }
                    }
                }
            } footer: {
                Text("Legt fest, welche POI-Kategorien als Pins auf der Karte angezeigt werden.")
            }
        }
        .navigationTitle("POI-Kategorien")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        RestStopKindSettingsView()
    }
}
