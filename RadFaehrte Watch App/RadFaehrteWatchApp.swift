//
//  RadFaehrteWatchApp.swift
//  RadFaehrte Watch App
//

import SwiftUI

@main
struct RadFaehrteWatchApp: App {
    init() {
        WatchSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}
