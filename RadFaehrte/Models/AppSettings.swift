//
//  AppSettings.swift
//  RadFaehrte
//

import Foundation

/// `UserDefaults`-Keys für `@AppStorage`, zentral gehalten, damit `SettingsView` (schreibt) und
/// `ContentView` (liest, für die Fahrzeit-Schätzung) denselben Key verwenden.
enum AppSettingsKey {
    static let averageSpeedKmh = "averageSpeedKmh"
}

enum AppSettingsDefaults {
    static let averageSpeedKmh: Double = 15
    static let averageSpeedRange: ClosedRange<Double> = 8...30
}
