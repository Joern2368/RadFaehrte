//
//  WatchSessionManager.swift
//  RadFaehrte
//
//  Created for Apple-Watch-Anbindung.
//

import CoreLocation
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
@Observable
final class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    /// Hochzählender Zähler, der bei jedem Wechsel zu `isReachable == true` erhöht wird - Auslöser
    /// dafür, dass `ContentView` bei laufender Navigation Status und Routen-Geometrie erneut sendet
    /// (s. dort, `onChange(of: watchSessionManager.reachabilityChangeCount)`). Nötig, weil
    /// `sendRoute`/`transferUserInfo` (anders als `send`/`updateApplicationContext`, s. dessen
    /// Dokumentation) keinen "letzten Stand" kennt, den die Watch beim Start selbst abholen könnte -
    /// wird die Watch-App erst **nach** Navigationsstart geöffnet, hängt die zu diesem Zeitpunkt
    /// bereits gequeuete Routen-Übertragung unbestimmt lange in der Zustellwarteschlange
    /// (Live-Beobachtung Nutzer 2026-08-03: Anweisungen erschienen sofort korrekt, Karte blieb leer,
    /// bis die Watch-App zuerst geöffnet wurde). `isReachable` wechselt zuverlässig auf `true`, sobald
    /// die Watch-App in den Vordergrund kommt - der richtige Moment für ein erneutes Senden.
    private(set) var reachabilityChangeCount = 0

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sendet bewusst **immer**, ohne Vergleich mit dem zuletzt gesendeten Zustand - eine frühere
    /// Version übersprang unveränderte Sends, was nach einer Neuinstallation der Watch-App zu
    /// einer stillen, leeren/stummen App führte (Nutzer-Beobachtung 2026-08-01): Die frische
    /// Watch-App kannte den aktuellen Stand nicht, das iPhone hielt ihn aber für "bereits
    /// gesendet" und schickte nichts erneut, solange sich der Navigationsstatus nicht zufällig
    /// änderte. Da während der Navigation ohnehin schon fast jede Sekunde gesendet wird (Distanz
    /// ändert sich laufend), ist der Mehraufwand durch den Wegfall der Sparsamkeits-Prüfung
    /// vernachlässigbar - macht die Übertragung dafür robust gegen Neuinstallation/
    /// Verbindungsaussetzer der Watch-App.
    func send(_ state: WatchNavState) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        do {
            try WCSession.default.updateApplicationContext(state.dictionaryRepresentation)
            Self.appendDebugLog("send: OK hapticTrigger=\(state.hapticTrigger) -> \(state.instructionText) / \(state.distanceText)")
        } catch {
            Self.appendDebugLog("send: FAILED \(error)")
        }
    }

    /// Zusätzlich zum zuverlässigen, aber nicht zeitkritischen `send`/`updateApplicationContext`
    /// (s. Dokumentation oben) ein sofortiger `sendMessage`-Versuch, falls die Watch gerade
    /// erreichbar ist - rein additiv, `send` bleibt in jedem Fall die verlässliche Quelle (kommt so
    /// oder so an, ggf. nur etwas verzögert). Bewusst nicht für jedes reguläre Status-Update
    /// während der Fahrt (s. o., warum `sendMessage` dafür verworfen wurde), sondern nur für das
    /// einmalige "Navigation beendet"-Ereignis: Live-Beobachtung Nutzer (2026-08-03) - nach Beenden
    /// am iPhone zeigte die Watch (dort die ganze Fahrt über geöffnet, also erreichbar) noch
    /// minutenlang die letzte Anweisung/Karte weiter, `updateApplicationContext` liefert laut
    /// Apple-Doku nur "wenn es passt", nicht sofort. Ein bei erreichbarer Gegenseite sofort
    /// zustellendes `sendMessage` behebt genau diesen sichtbar störenden Sonderfall, ohne die
    /// bewusste Entscheidung gegen `sendMessage` als alleinigen Kanal (s. o., Fall "Watch-App im
    /// Hintergrund während der Fahrt") zurückzunehmen.
    func sendImmediateIfReachable(_ state: WatchNavState) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(state.dictionaryRepresentation, replyHandler: nil) { error in
            Self.appendDebugLog("sendImmediateIfReachable: FAILED \(error)")
        }
    }

    /// Schickt die Geometrie der aktuell aktiven Route für die Kartenanzeige auf der Watch -
    /// separat von `send`/`updateApplicationContext` (s. `WatchRouteTransferKey`), da sie sich
    /// während einer Fahrt kaum ändert. Bewusst ohne Sparsamkeits-Prüfung (anders als in einer
    /// früheren Version) - wird ohnehin nur bei Navigationsstart/Neuberechnung aufgerufen, nicht
    /// bei jedem Standort-Update, ein Weglassen wäre nach einer Neuinstallation der Watch-App
    /// genau dieselbe Falle wie bei `send` (s. dort).
    func sendRoute(_ lines: [[CLLocationCoordinate2D]]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let payload = lines.map { line in line.map { [$0.latitude, $0.longitude] } }
        WCSession.default.transferUserInfo([WatchRouteTransferKey.lines: payload])
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

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        DispatchQueue.main.async {
            self.reachabilityChangeCount += 1
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
