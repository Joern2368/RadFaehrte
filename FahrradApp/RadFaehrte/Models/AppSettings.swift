//
//  AppSettings.swift
//  RadFaehrte
//

import Foundation

/// `UserDefaults`-Keys für `@AppStorage`, zentral gehalten, damit `SettingsView` (schreibt) und
/// `ContentView` (liest, für die Fahrzeit-Schätzung) denselben Key verwenden.
enum AppSettingsKey {
    static let averageSpeedKmh = "averageSpeedKmh"
    static let navigationLookaheadMeters = "navigationLookaheadMeters"
    static let navigationStatFieldCount = "navigationStatFieldCount"
    static let navigationStatSlots = "navigationStatSlots"
    static let appearanceMode = "appearanceMode"
    static let mapStyle = "mapStyle"
    static let navigationDefaultHeadingUp = "navigationDefaultHeadingUp"
    static let isVoiceGuidanceEnabled = "isVoiceGuidanceEnabled"
    static let showRestStops = "showRestStops"
    static let showRestStopKinds = "showRestStopKinds"
    static let allowFootwayShortcuts = "allowFootwayShortcuts"
    static let allowStepsShortcuts = "allowStepsShortcuts"
}

enum AppSettingsDefaults {
    static let averageSpeedKmh: Double = 15
    static let averageSpeedRange: ClosedRange<Double> = 3...50

    /// Entspricht der bisher fest verdrahteten Kamera-Distanz von 300 (s.
    /// `ContentView.navigationCameraDistance`), damit sich für Nutzer, die den neuen Regler nicht
    /// anfassen, an der Sichtweite nichts ändert.
    static let navigationLookaheadMeters: Double = 80
    static let navigationLookaheadRange: ClosedRange<Double> = 50...250

    static let navigationStatFieldCount: Int = 3
    /// Reihenfolge entspricht der bisherigen festen Leiste (Aktuell/Strecke/Ziel) plus drei neuen
    /// Werten für den 6er-Modus - damit ändert sich für Nutzer, die nur 3 Felder wählen, an der
    /// bisherigen Anzeige nichts.
    static let navigationStatSlotsDefaultKinds: [NavigationStatKind] = [
        .currentSpeed, .distanceTraveled, .distanceToDestination,
        .arrivalTimeAverageSpeed, .elapsedTime, .elevationGain,
    ]
    static let navigationStatSlots: String =
        navigationStatSlotsDefaultKinds.map(\.rawValue).joined(separator: ",")

    static let appearanceMode: String = AppearanceMode.system.rawValue
    static let mapStyle: String = MapStyleOption.standard.rawValue

    /// Entspricht dem bisher fest verdrahteten Start-Zustand von `isHeadingUpEnabled` in
    /// `ContentView` (`true`), damit sich für Nutzer, die die Einstellung nicht anfassen, am
    /// bisherigen Verhalten nichts ändert.
    static let navigationDefaultHeadingUp: Bool = true

    static let isVoiceGuidanceEnabled: Bool = true

    /// Opt-in (nicht standardmäßig an) - lädt sonst ungefragt Rastplatz-Pins auf die Karte, obwohl
    /// die zugehörige Region evtl. noch nicht heruntergeladen wurde, s. `restStopSupportedRegions`
    /// (inzwischen alle 16 Bundesländer).
    static let showRestStops: Bool = false

    /// Standardmäßig alle Kategorien aktiv, damit sich für Nutzer, die die Kategorie-Auswahl nicht
    /// anfassen, am bisherigen Verhalten (alle Rastplatz-Kategorien sichtbar) nichts ändert.
    static let showRestStopKinds: String = RestStop.Kind.encode(Set(RestStop.Kind.allCases))

    /// Standardmäßig an: Ein kurzer Fußweg-Abstecher (z. B. eine Unterführung) ist meist eine
    /// unproblematische Abkürzung, die die Offline-Engine sonst gar nicht erst in Betracht zieht
    /// (Nutzer-Wunsch 2026-08-29). Nur wirksam, wenn `weight_multiplier`/`is_pushable` in
    /// `Scripts/build_way_graph.py` die entsprechenden Kanten überhaupt in den Graphen aufnehmen
    /// (s. `WayGraphRepository.WayCategory.push`, `BikeRoutingEngine.search`).
    static let allowFootwayShortcuts: Bool = true

    /// Standardmäßig aus: Ein Rad über Treppen zu tragen/heben ist unangenehmer als ein kurzer
    /// Fußweg-Abstecher (v. a. mit Gepäck oder E-Bike-Gewicht) - Nutzer entscheidet bewusst, ob
    /// die Offline-Engine das als Abkürzung vorschlagen darf.
    static let allowStepsShortcuts: Bool = false
}
