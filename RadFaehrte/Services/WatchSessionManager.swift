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
/// installiert, ist `WCSession` trotzdem aktivierbar - `send` wird dann einfach zum No-op, kein
/// zusätzlicher Zustand nötig.
///
/// Ausschließlich `updateApplicationContext` statt `sendMessage`: kommt zuverlässig auch an, wenn
/// die Watch-App gerade nicht im Vordergrund ist (per Live-Test 2026-07-30 bestätigt - ein
/// ursprünglich für das Haptik-Signal genutztes `sendMessage` scheiterte während einer echten
/// Fahrt wiederholt mit "not reachable", weil das eine aktiv laufende Verbindung braucht, die
/// beim Radfahren mit geschlossener Watch-App normalerweise nicht gegeben ist -
/// `WatchNavState.hapticTrigger` löst das jetzt, indem die Watch selbst eine Änderung dieses
/// Zählers im ohnehin zuverlässig ankommenden Kontext erkennt, s. dort).
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
        do {
            try WCSession.default.updateApplicationContext(state.dictionaryRepresentation)
            Self.appendDebugLog("send: OK hapticTrigger=\(state.hapticTrigger) -> \(state.instructionText) / \(state.distanceText)")
        } catch {
            Self.appendDebugLog("send: FAILED \(error)")
        }
    }

    /// TEMP-DEBUG (Apple-Watch-Anbindung, Live-Test 2026-07-30): Datei-Logging statt Konsole, da
    /// `print()` beim Piping über `devicectl --console` bekanntermaßen gepuffert wird (s.
    /// ROADMAP.md) - wieder entfernen, sobald der Haptik-Fix (`hapticTrigger`-Zähler statt
    /// `sendMessage`) live bestätigt ist.
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

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
