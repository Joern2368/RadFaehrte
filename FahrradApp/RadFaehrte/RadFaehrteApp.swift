//
//  RadFaehrteApp.swift
//  RadFaehrte
//
//  Created by Jörn Frankenfeld on 17.07.26.
//

import SwiftUI

@main
struct RadFaehrteApp: App {
    @AppStorage(AppSettingsKey.appearanceMode) private var appearanceModeRaw = AppSettingsDefaults.appearanceMode
    // Für `application(_:handleEventsForBackgroundURLSession:completionHandler:)`, s.
    // `AppDelegate`-Doc-Kommentar.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Muss vor allen anderen Schritten laufen, damit die Hintergrund-`URLSession` schon
        // existiert, bevor evtl. wartende Delegate-Events eintreffen (s.
        // `BackgroundDownloadCoordinator`).
        BackgroundDownloadCoordinator.shared.activate()
        // Klemmt einen bereits gespeicherten Sichtweite-Wert auf die aktuell gültige Range - z. B.
        // wenn die Obergrenze wie am 2026-08-28 (300 -> 250) nachträglich gesenkt wurde. Ohne das
        // bliebe ein Altwert wie 300 unverändert in UserDefaults und würde weiterhin roh in
        // `ContentView.navigationCameraDistance` einfließen, obwohl der Stepper ihn nicht mehr
        // zulässt.
        let lookaheadKey = AppSettingsKey.navigationLookaheadMeters
        if let stored = UserDefaults.standard.object(forKey: lookaheadKey) as? Double {
            let range = AppSettingsDefaults.navigationLookaheadRange
            let clamped = min(max(stored, range.lowerBound), range.upperBound)
            if clamped != stored {
                UserDefaults.standard.set(clamped, forKey: lookaheadKey)
            }
        }
        WatchSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme((AppearanceMode(rawValue: appearanceModeRaw) ?? .system).colorScheme)
        }
    }
}
