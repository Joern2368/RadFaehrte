//
//  AppearanceMode.swift
//  RadFaehrte
//

import SwiftUI

/// Nutzerauswahl für das Erscheinungsbild der App (Einstellungen > Erscheinungsbild). Persistiert
/// als Rohwert unter `AppSettingsKey.appearanceMode`; `RadFaehrteApp` wendet `colorScheme` auf die
/// Wurzel-View an.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Hell"
        case .dark: return "Dunkel"
        }
    }

    /// `nil` überlässt die Darstellung dem System (folgt automatisch dessen Hell/Dunkel-Einstellung).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
