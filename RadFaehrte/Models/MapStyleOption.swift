//
//  MapStyleOption.swift
//  RadFaehrte
//

import MapKit
import SwiftUI

/// Nutzerauswahl für den Kartenstil (Einstellungen > Karte). Persistiert als Rohwert unter
/// `AppSettingsKey.mapStyle`; `ContentView` wendet `mapStyle` über `.mapStyle(...)` auf die
/// Karte an.
enum MapStyleOption: String, CaseIterable, Identifiable {
    case standard
    case satellite
    case hybrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .satellite: return "Satellit"
        case .hybrid: return "Hybrid"
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .standard: return .standard
        case .satellite: return .imagery
        case .hybrid: return .hybrid
        }
    }
}
