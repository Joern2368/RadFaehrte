//
//  NavigationStat.swift
//  RadFaehrte
//

import Foundation

/// Katalog der Werte, die in der Statistik-Leiste der Navigations-Kopfzeile wählbar sind (siehe
/// `ContentView.navigationStatsRow`). Nutzer stellt in `SettingsView` pro Feld frei ein, welcher
/// Wert dort erscheint - dieses Enum ist der Rohwert dafür (`rawValue` wird kommagetrennt in
/// `AppSettingsKey.navigationStatSlots` persistiert).
///
/// Reihenfolge der Fälle bestimmt die Reihenfolge in der Auswahl-Liste (`NavigationStatKind.allCases`
/// in `NavigationStatSettingsView`) - bewusst nach Themen gruppiert (Geschwindigkeit, Strecke/
/// Fortschritt, Zeit, Höhe, Sonstiges) statt alphabetisch oder nach Einführungsdatum, damit
/// zusammengehörige Werte beim Durchscrollen der Liste beieinanderstehen. Persistierte Auswahl ist
/// davon unberührt (referenziert `rawValue`-Strings, nicht die Position).
enum NavigationStatKind: String, CaseIterable, Identifiable, Codable {
    // Geschwindigkeit
    case currentSpeed
    case averageSpeed
    case maxSpeed

    // Strecke/Fortschritt
    case distanceTraveled
    case distanceToDestination
    case progressPercent

    // Zeit
    case elapsedTime
    case movingTime
    case pausedTime
    case arrivalTimeSetSpeed
    case arrivalTimeAverageSpeed
    case remainingTimeSetSpeed
    case remainingTimeAverageSpeed

    // Höhe
    case currentAltitude
    case maxAltitude
    case elevationGain
    case elevationLoss
    case netElevation
    case currentGrade

    // Sonstiges
    case heading
    case currentTime
    case sunsetTime
    case timeUntilSunset
    case batteryLevel

    var id: String { rawValue }

    /// Kurzes Label unter dem Wert in der Statistik-Leiste selbst (wenig Platz).
    var label: String {
        switch self {
        case .currentSpeed: return "Aktuell"
        case .averageSpeed: return "Ø-Tempo"
        case .maxSpeed: return "Max"
        case .distanceTraveled: return "Strecke"
        case .distanceToDestination: return "Ziel"
        case .progressPercent: return "Fortschritt"
        case .elapsedTime: return "Fahrtzeit"
        case .movingTime: return "Bewegung"
        case .pausedTime: return "Pause"
        case .arrivalTimeSetSpeed: return "Ankunft"
        case .arrivalTimeAverageSpeed: return "Ankunft"
        case .remainingTimeSetSpeed: return "Restzeit"
        case .remainingTimeAverageSpeed: return "Restzeit"
        case .currentAltitude: return "Höhe"
        case .maxAltitude: return "Max. Höhe"
        case .elevationGain: return "Höhenmeter"
        case .elevationLoss: return "Bergab"
        case .netElevation: return "Saldo"
        case .currentGrade: return "Steigung"
        case .heading: return "Richtung"
        case .currentTime: return "Uhrzeit"
        case .sunsetTime: return "Untergang"
        case .timeUntilSunset: return "Bis Untergang"
        case .batteryLevel: return "Akku"
        }
    }

    /// Ausführlichere Beschreibung für die Auswahl-Liste in den Einstellungen, wo z. B. "Ankunft"
    /// oder "Restzeit" allein nicht zwischen den beiden Berechnungsgrundlagen unterscheiden würde.
    var settingsDescription: String {
        switch self {
        case .currentSpeed: return "Aktuelle Geschwindigkeit"
        case .averageSpeed: return "Durchschnittsgeschwindigkeit (bezogen auf reine Fahrzeit, ohne Pausen)"
        case .maxSpeed: return "Maximale Geschwindigkeit (seit Start)"
        case .distanceTraveled: return "Zurückgelegte Strecke"
        case .distanceToDestination: return "Entfernung zum Ziel"
        case .progressPercent: return "Fortschritt der Fahrt in Prozent (geschätzt aus zurückgelegter Strecke und Luftlinie zum Ziel)"
        case .elapsedTime: return "Fahrtzeit (seit Start, inkl. Pausen)"
        case .movingTime: return "Reine Fahrzeit ohne Stopps (Moving Time)"
        case .pausedTime: return "Pausenzeit (Fahrtzeit ohne Bewegungszeit)"
        case .arrivalTimeSetSpeed: return "Ankunftszeit (eingestellte Ø-Geschwindigkeit)"
        case .arrivalTimeAverageSpeed: return "Ankunftszeit (bisheriges Ø-Tempo der Fahrt)"
        case .remainingTimeSetSpeed: return "Restzeit bis Ziel (eingestellte Ø-Geschwindigkeit)"
        case .remainingTimeAverageSpeed: return "Restzeit bis Ziel (bisheriges Ø-Tempo der Fahrt)"
        case .currentAltitude: return "Aktuelle Höhe über NN"
        case .maxAltitude: return "Höchste erreichte Höhe über NN (seit Start)"
        case .elevationGain: return "Höhenmeter (bergauf, seit Start)"
        case .elevationLoss: return "Höhenmeter (bergab, seit Start)"
        case .netElevation: return "Netto-Höhenmeter (Gewinn minus Verlust, seit Start)"
        case .currentGrade: return "Aktuelle Steigung/Gefälle (%, über die letzten Meter geglättet)"
        case .heading: return "Fahrtrichtung (Himmelsrichtung, z. B. NO)"
        case .currentTime: return "Aktuelle Uhrzeit"
        case .sunsetTime: return "Sonnenuntergangszeit (heute, am aktuellen Standort)"
        case .timeUntilSunset: return "Restzeit bis Sonnenuntergang"
        case .batteryLevel: return "Akkustand des Telefons"
        }
    }
}
