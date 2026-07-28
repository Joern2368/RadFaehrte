//
//  WatchSessionManager.swift
//  RadFaehrte
//
//  Created for Apple-Watch-Anbindung.
//

import Foundation
import WatchConnectivity

/// Sendet den aktuellen Navigationsstatus per WatchConnectivity an eine gekoppelte Apple Watch mit
/// installierter RadFährte-Watch-App. Ist keine Watch gekoppelt oder die Watch-App nicht
/// installiert, ist `WCSession` trotzdem aktivierbar - `send`/`sendHapticTurnEvent` werden dann
/// einfach zu No-ops, kein zusätzlicher Zustand nötig.
///
/// `updateApplicationContext` statt `sendMessage` für den laufenden Status: kommt auch an, wenn
/// die Watch-App gerade nicht im Vordergrund/erreichbar ist (liefert beim nächsten Start nur den
/// jeweils letzten Stand, was hier reicht). Nur das kurze Haptik-Signal vor einer Abbiegung
/// (`sendHapticTurnEvent`) braucht ein aktiv erreichbares Gegenstück und nutzt deshalb
/// `sendMessage` - verpufft stillschweigend, wenn die Watch gerade nicht erreichbar ist (kein
/// Beinbruch, es ist nur ein Zusatzhinweis zur Anzeige).
final class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    private var lastSentState: WatchNavState?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ state: WatchNavState) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        guard state != lastSentState else { return }
        lastSentState = state
        try? WCSession.default.updateApplicationContext(state.dictionaryRepresentation)
    }

    func sendHapticTurnEvent() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage([WatchMessageKey.hapticTurnEvent: true], replyHandler: nil, errorHandler: nil)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
