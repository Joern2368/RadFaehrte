//
//  NavigationStat.swift
//  RadFaehrte
//

import Foundation

/// Katalog der Werte, die in der Statistik-Leiste der Navigations-Kopfzeile wählbar sind (siehe
/// `ContentView.navigationStatsRow`). Nutzer stellt in `SettingsView` pro Feld frei ein, welcher
/// Wert dort erscheint - dieses Enum ist der Rohwert dafür (`rawValue` wird kommagetrennt in
/// `AppSettingsKey.navigationStatSlots` persistiert).
enum NavigationStatKind: String, CaseIterable, Identifiable, Codable {
    case currentSpeed
    case distanceTraveled
    case distanceToDestination
    case arrivalTimeSetSpeed
    case arrivalTimeAverageSpeed
    case averageSpeed
    case elapsedTime
    case elevationGain
    case elevationLoss
    case maxSpeed
    case movingTime
    case remainingTimeSetSpeed
    case remainingTimeAverageSpeed
    case currentAltitude
    case currentGrade
    case maxAltitude
    case pausedTime

    var id: String { rawValue }

    /// Kurzes Label unter dem Wert in der Statistik-Leiste selbst (wenig Platz).
    var label: String {
        switch self {
        case .currentSpeed: return "Aktuell"
        case .distanceTraveled: return "Strecke"
        case .distanceToDestination: return "Ziel"
        case .arrivalTimeSetSpeed: return "Ankunft"
        case .arrivalTimeAverageSpeed: return "Ankunft"
        case .averageSpeed: return "Ø-Tempo"
        case .elapsedTime: return "Fahrtzeit"
        case .elevationGain: return "Höhenmeter"
        case .elevationLoss: return "Bergab"
        case .maxSpeed: return "Max"
        case .movingTime: return "Bewegung"
        case .remainingTimeSetSpeed: return "Restzeit"
        case .remainingTimeAverageSpeed: return "Restzeit"
        case .currentAltitude: return "Höhe"
        case .currentGrade: return "Steigung"
        case .maxAltitude: return "Max. Höhe"
        case .pausedTime: return "Pause"
        }
    }

    /// Ausführlichere Beschreibung für die Auswahl-Liste in den Einstellungen, wo z. B. "Ankunft"
    /// oder "Restzeit" allein nicht zwischen den beiden Berechnungsgrundlagen unterscheiden würde.
    var settingsDescription: String {
        switch self {
        case .currentSpeed: return "Aktuelle Geschwindigkeit"
        case .distanceTraveled: return "Zurückgelegte Strecke"
        case .distanceToDestination: return "Entfernung zum Ziel"
        case .arrivalTimeSetSpeed: return "Ankunftszeit (eingestellte Ø-Geschwindigkeit)"
        case .arrivalTimeAverageSpeed: return "Ankunftszeit (bisheriges Ø-Tempo der Fahrt)"
        case .averageSpeed: return "Durchschnittsgeschwindigkeit (seit Start)"
        case .elapsedTime: return "Fahrtzeit (seit Start, inkl. Pausen)"
        case .elevationGain: return "Höhenmeter (bergauf, seit Start)"
        case .elevationLoss: return "Höhenmeter (bergab, seit Start)"
        case .maxSpeed: return "Maximale Geschwindigkeit (seit Start)"
        case .movingTime: return "Reine Fahrzeit ohne Stopps (Moving Time)"
        case .remainingTimeSetSpeed: return "Restzeit bis Ziel (eingestellte Ø-Geschwindigkeit)"
        case .remainingTimeAverageSpeed: return "Restzeit bis Ziel (bisheriges Ø-Tempo der Fahrt)"
        case .currentAltitude: return "Aktuelle Höhe über NN"
        case .currentGrade: return "Aktuelle Steigung/Gefälle (%, über die letzten Meter geglättet)"
        case .maxAltitude: return "Höchste erreichte Höhe über NN (seit Start)"
        case .pausedTime: return "Pausenzeit (Fahrtzeit ohne Bewegungszeit)"
        }
    }
}
