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

    init() {
        WatchSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme((AppearanceMode(rawValue: appearanceModeRaw) ?? .system).colorScheme)
        }
    }
}
