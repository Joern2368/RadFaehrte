//
//  NavigationStatSettingsView.swift
//  RadFaehrte
//

import SwiftUI

/// Eigene Unterseite statt Inline-Sektion in `SettingsView` - bei 6 Feldern wären das dort bis zu
/// 7 Zeilen (Anzahl-Umschalter + 6 Picker) gewesen, was den bewusst kurz gehaltenen Hauptscreen
/// (s. Kommentar in `SettingsView`) gesprengt hätte.
struct NavigationStatSettingsView: View {
    @AppStorage(AppSettingsKey.navigationStatFieldCount) private var navigationStatFieldCount = AppSettingsDefaults.navigationStatFieldCount
    @AppStorage(AppSettingsKey.navigationStatSlots) private var navigationStatSlotsRaw = AppSettingsDefaults.navigationStatSlots

    /// Persistierte Slot-Auswahl, aufgefüllt auf 6 Einträge (auch wenn aktuell nur 3 angezeigt
    /// werden) - damit beim Umschalten zwischen 3 und 6 Feldern keine bereits getroffene Auswahl
    /// verloren geht.
    private var statSlots: [NavigationStatKind] {
        var slots = navigationStatSlotsRaw.split(separator: ",").compactMap { NavigationStatKind(rawValue: String($0)) }
        for kind in AppSettingsDefaults.navigationStatSlotsDefaultKinds where slots.count < 6 {
            if !slots.contains(kind) { slots.append(kind) }
        }
        return Array(slots.prefix(6))
    }

    private func statSlotBinding(_ index: Int) -> Binding<NavigationStatKind> {
        Binding(
            get: { statSlots[index] },
            set: { newValue in
                var slots = statSlots
                slots[index] = newValue
                navigationStatSlotsRaw = slots.map(\.rawValue).joined(separator: ",")
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Anzahl der Felder", selection: $navigationStatFieldCount) {
                    Text("3").tag(3)
                    Text("6").tag(6)
                }
                .pickerStyle(.segmented)
            }

            // Ohne `.animation(nil, ...)` löst das Umschalten der Feld-Anzahl im selben Zug ein
            // Einfügen/Entfernen von bis zu 3 Picker-Zeilen weiter unten aus. Die dadurch
            // ausgelöste implizite List-Diffing-Animation kann den Tap auf dem Segmented Control
            // "verschlucken" (Tester musste laut Feedback mehrfach auf "6" tippen, bis die Auswahl
            // griff) - mit deaktivierter Animation greift der Tap sofort.
            Section {
                ForEach(0..<navigationStatFieldCount, id: \.self) { index in
                    Picker("Feld \(index + 1)", selection: statSlotBinding(index)) {
                        ForEach(NavigationStatKind.allCases) { kind in
                            Text(kind.settingsDescription).tag(kind)
                        }
                    }
                }
            } footer: {
                Text("Legt fest, welche Werte in der Statistik-Leiste über der Karte während der Navigation angezeigt werden.")
            }
            .animation(nil, value: navigationStatFieldCount)
        }
        .navigationTitle("Statistik-Leiste")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        NavigationStatSettingsView()
    }
}
