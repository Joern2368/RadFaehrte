//
//  RadFaehrteWatchApp.swift
//  RadFaehrte Watch App
//

import SwiftUI

@main
struct RadFaehrteWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        WatchSessionManager.shared.activate()
        WorkoutSessionManager.shared.requestAuthorizationIfNeeded()
        WorkoutSessionManager.shared.recoverOrphanedSessionIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
        // Deckt den Fall ab, dass die Navigation bereits läuft, bevor der Nutzer die Watch-App
        // öffnet (kein neuer `WatchNavState`-Sync bei reinem App-Öffnen, s. `WatchSessionManager.
        // apply` für den Start-Trigger bei einem tatsächlichen Statuswechsel).
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, WatchSessionManager.shared.state.isNavigating else { return }
            WorkoutSessionManager.shared.start()
        }
    }
}
