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
        guard WCSession.isSupported() else {
            Self.appendDebugLog("send: WCSession not supported")
            return
        }
        guard WCSession.default.activationState == .activated else {
            Self.appendDebugLog("send: not activated (state=\(WCSession.default.activationState.rawValue))")
            return
        }
        guard state != lastSentState else {
            Self.appendDebugLog("send: unchanged, skip (\(state.instructionText) / \(state.distanceText))")
            return
        }
        lastSentState = state
        do {
            try WCSession.default.updateApplicationContext(state.dictionaryRepresentation)
            Self.appendDebugLog("send: OK isPaired=\(WCSession.default.isPaired) watchAppInstalled=\(WCSession.default.isWatchAppInstalled) reachable=\(WCSession.default.isReachable) -> \(state.instructionText) / \(state.distanceText)")
        } catch {
            Self.appendDebugLog("send: FAILED \(error)")
        }
    }

    /// TEMP-DEBUG (Apple-Watch-Anbindung, Live-Test 2026-07-28): Datei-Logging statt Konsole, da
    /// `print()` beim Piping über `devicectl --console` bekanntermaßen gepuffert wird (s.
    /// ROADMAP.md) - wieder entfernen, sobald der Watch-Anzeige-Bug gefunden ist.
    private static let debugLogURL: URL? = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask).first?
        .appendingPathComponent("watch_debug.log")

    static func appendDebugLog(_ line: String) {
        guard let debugLogURL else { return }
        guard let data = ("\(Date()) \(line)\n").data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: debugLogURL.path), let handle = try? FileHandle(forWritingTo: debugLogURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: debugLogURL)
        }
    }

    func sendHapticTurnEvent() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage([WatchMessageKey.hapticTurnEvent: true], replyHandler: nil, errorHandler: nil)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Self.appendDebugLog("activationDidCompleteWith: state=\(activationState.rawValue) error=\(String(describing: error)) isPaired=\(session.isPaired) isWatchAppInstalled=\(session.isWatchAppInstalled)")
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
