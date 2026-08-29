//
//  AppDelegate.swift
//  RadFaehrte
//

import UIKit

/// Nötig für `application(_:handleEventsForBackgroundURLSession:completionHandler:)` - dieser
/// Callback existiert nur auf `UIApplicationDelegate`, nicht im SwiftUI-`App`-Protokoll. Das
/// System ruft ihn auf, wenn es die App (ggf. neu) startet, um Events einer Hintergrund-
/// `URLSession` zuzustellen (s. `BackgroundDownloadCoordinator`) - etwa wenn ein Bundesland-/
/// Länder-Download fertig wurde, während die App im Hintergrund war oder ganz beendet ist.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundDownloadCoordinator.shared.setBackgroundSessionCompletionHandler(completionHandler)
    }
}
