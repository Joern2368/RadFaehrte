//
//  WatchSessionManager.swift
//  RadFaehrte Watch App
//
//  Empfängt den Navigationsstatus vom iPhone (s. RadFaehrte/Services/WatchSessionManager.swift,
//  Gegenstück auf der iOS-Seite) und löst bei einer bevorstehenden Abbiegung haptisches Feedback aus.
//

import Foundation
import WatchConnectivity
import WatchKit

final class WatchSessionManager: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = WatchSessionManager()

    @Published var state: WatchNavState = .idle

    /// Zuletzt gesehener `hapticTrigger`-Wert - `nil` bedeutet "noch keine Basislinie", damit ein
    /// beim App-Start bereits vorhandener (alter) Kontext nicht sofort eine Vibration auslöst,
    /// sondern nur eine tatsächliche **Änderung** während einer laufenden Navigation.
    private var lastHapticTrigger: Int?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Übernimmt einen neu empfangenen Zustand. `playHapticIfChanged` ist beim allerersten
    /// Empfang nach App-Start bewusst `false` (reiner Sync-Vorgang, keine echte neue Abbiegung),
    /// bei jedem späteren Update `true`.
    private func apply(_ newState: WatchNavState, playHapticIfChanged: Bool) {
        if playHapticIfChanged, newState.isNavigating,
           let lastHapticTrigger, newState.hapticTrigger != lastHapticTrigger {
            playTurnHaptic(direction: newState.direction)
        }
        lastHapticTrigger = newState.hapticTrigger
        state = newState
    }

    /// Eigenes, klar unterscheidbares Muster statt eines einzelnen `WKHapticType`-Aufrufs -
    /// Nutzer-Feedback nach dem ersten Live-Test (2026-07-31): die einfache `.directionUp`-Haptik
    /// wirkte zu schwach, außerdem sollen sich Links-/Rechtsabbiegungen blind unterscheiden
    /// lassen. `.notification` statt `.directionUp`/`.click` gewählt, weil es im Vergleich der
    /// System-Haptiken am kräftigsten/auffälligsten wirkt. `WKInterfaceDevice.play(_:)` selbst hat
    /// keinen Stärke-Regler - die Watch-Haptik-Palette ist auf feste, von Apple definierte Muster
    /// beschränkt (kein Custom-Intensity-API wie Core Haptics unter iOS) - deshalb hier stattdessen
    /// mehrfaches, zeitlich versetztes Abspielen: links = 2× lang (eher aufeinanderfolgend), rechts
    /// = 5× kurz (schneller Stakkato), sonstige Manöver (z. B. Kreisverkehr/Ausfahrt ohne klare
    /// Links/Rechts-Erkennung im Text) = 3× mittig als dritte, unterscheidbare Variante.
    private func playTurnHaptic(direction: WatchNavState.Direction) {
        switch direction {
        case .left:
            playRepeated(.notification, count: 2, interval: 0.45)
        case .right:
            playRepeated(.notification, count: 5, interval: 0.16)
        case .straight:
            playRepeated(.notification, count: 3, interval: 0.3)
        }
    }

    private func playRepeated(_ type: WKHapticType, count: Int, interval: TimeInterval) {
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i)) {
                WKInterfaceDevice.current().play(type)
            }
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // `didReceiveApplicationContext` liefert automatisch den zuletzt vom iPhone gesendeten
        // Stand nach - `session.receivedApplicationContext` deckt trotzdem den Fall ab, dass die
        // Watch-App komplett neu gestartet wird, nachdem der Kontext schon vorher ankam.
        let newState = WatchNavState(dictionary: session.receivedApplicationContext)
        DispatchQueue.main.async {
            self.apply(newState, playHapticIfChanged: false)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let newState = WatchNavState(dictionary: applicationContext)
        DispatchQueue.main.async {
            self.apply(newState, playHapticIfChanged: true)
        }
    }
}
