//
//  WatchSessionManager.swift
//  RadFaehrte Watch App
//
//  Empfängt den Navigationsstatus vom iPhone (s. RadFaehrte/Services/WatchSessionManager.swift,
//  Gegenstück auf der iOS-Seite) und löst bei einer bevorstehenden Abbiegung haptisches Feedback aus.
//

import CoreLocation
import Foundation
import WatchConnectivity
import WatchKit

final class WatchSessionManager: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = WatchSessionManager()

    @Published var state: WatchNavState = .idle
    /// Geometrie der aktuell aktiven Route für die Kartenanzeige (s. `WatchContentView`) - separat
    /// von `state`, da sie über `transferUserInfo` statt `updateApplicationContext` ankommt (s.
    /// `WatchRouteTransferKey`).
    @Published var routeLines: [[CLLocationCoordinate2D]] = []

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
        let shouldPlay = playHapticIfChanged && newState.isNavigating
            && lastHapticTrigger != nil && newState.hapticTrigger != lastHapticTrigger
        Self.appendDebugLog(
            "apply: playHapticIfChanged=\(playHapticIfChanged) isNavigating=\(newState.isNavigating) "
            + "lastHapticTrigger=\(String(describing: lastHapticTrigger)) newHapticTrigger=\(newState.hapticTrigger) "
            + "direction=\(newState.direction) shouldPlay=\(shouldPlay)"
        )
        if shouldPlay {
            playTurnHaptic(direction: newState.direction)
        }
        // Trainings-Session koppelt sich an den Navigationsstatus, nicht an `playHapticIfChanged`.
        // Start bewusst nur, wenn die Watch-App gerade aktiv geöffnet ist (Nutzerwunsch 2026-08-02:
        // die Uhr soll nicht bei jeder iPhone-Navigation automatisch im Hintergrund mitlaufen -
        // hoher Akkuverbrauch -, sondern nur, wenn der Nutzer die App selbst dafür öffnet; das
        // eigentliche Öffnen während einer bereits laufenden Navigation wird separat in
        // `RadFaehrteWatchApp` per `scenePhase`-Wechsel behandelt). Stop dagegen unabhängig vom
        // Vordergrund-Status, damit eine einmal gestartete Session beim Navigationsende zuverlässig
        // auch im Hintergrund endet (identisch zum bisherigen Verhalten).
        if newState.isNavigating != state.isNavigating {
            if newState.isNavigating {
                if WKApplication.shared().applicationState == .active {
                    WorkoutSessionManager.shared.start()
                }
            } else {
                WorkoutSessionManager.shared.stop()
            }
        }
        lastHapticTrigger = newState.hapticTrigger
        state = newState
    }

    /// Klar unterscheidbares Haptik-Muster pro Richtung, per Live-Test am Handgelenk gefunden
    /// (2026-08-01, über temporäre Test-Buttons in der Watch-App, inzwischen wieder entfernt):
    ///
    /// - `.navigationLeftTurn`/`.navigationRightTurn`/`.navigationGenericManeuver` (Apples eigene,
    ///   extra für Turn-by-Turn-Navigation vorgesehene Typen) blieben auf diesem Gerät (Apple Watch
    ///   Series 8, watchOS 26.5) **komplett stumm** - kein Impuls spürbar. `.notification` vibriert
    ///   dagegen zuverlässig, deshalb als einziger Baustein verwendet statt der wirkungslosen
    ///   Navigations-Typen.
    /// - Unterscheidung über die **Anzahl** der `.notification`-Impulse (1× links, 2× geradeaus,
    ///   3× rechts) statt über den Typ.
    /// - **Mindestabstand zwischen den Impulsen entscheidend, nicht die Anzahl selbst**: 0,35 s und
    ///   0,6 s Pause verschmolzen mehrere Impulse zuverlässig zu einem einzigen gefühlten Impuls;
    ///   der nötige Mindestabstand liegt irgendwo zwischen 0,6 s und 2,6 s. 1,2 s zwischen allen
    ///   Impulsen bestätigt: alle Impulse kommen einzeln an, links/rechts fühlen sich klar
    ///   unterscheidbar an.
    ///
    /// **Noch offen**: nur im Vordergrund (manueller Button-Tap) verifiziert. Frühere
    /// `asyncAfter`-Versuche scheiterten bei einer **echten**, im Hintergrund laufenden Navigation
    /// am kurzen Zeitfenster nach `didReceiveApplicationContext` (s. ROADMAP.md, zweiter
    /// Funktionsbug) - ob das aktuelle Muster (bis zu 2,4 s Gesamtdauer bei "rechts") dort ebenso
    /// zuverlässig ankommt, ist noch durch eine echte Fahrt mit Abbiegung zu bestätigen.
    private func playTurnHaptic(direction: WatchNavState.Direction) {
        let pattern: [(type: WKHapticType, delay: Double)]
        switch direction {
        case .left: pattern = [(.notification, 0)]
        case .right: pattern = [(.notification, 0), (.notification, 1.2), (.notification, 2.4)]
        case .straight: pattern = [(.notification, 0), (.notification, 1.2)]
        }
        Self.appendDebugLog("playTurnHaptic: direction=\(direction) pattern=\(pattern)")
        for (i, pulse) in pattern.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + pulse.delay) {
                WKInterfaceDevice.current().play(pulse.type)
                Self.appendDebugLog("playTurnHaptic: pulse \(i + 1)/\(pattern.count) played type=\(pulse.type)")
            }
        }
    }

    /// TEMP-DEBUG (Apple-Watch-Anbindung, Haptik-Muster-Suche 2026-07-31): Datei-Logging auf der
    /// Watch selbst statt Konsole (analog zum iPhone-seitigen `WatchSessionManager.
    /// appendDebugLog`) - wieder entfernen, sobald das Haptik-Muster live bestätigt ist.
    private static let debugLogURL: URL? = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask).first?
        .appendingPathComponent("watch_haptic_debug.log")

    private static func appendDebugLog(_ line: String) {
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

    /// Gegenstück zu `WatchSessionManager.sendImmediateIfReachable` auf der iOS-Seite - sofortige
    /// Zustellung bei erreichbarer Gegenseite (anders als `didReceiveApplicationContext`, das nur
    /// "wenn es passt" ankommt). Bewusst dieselbe `apply`-Logik wie beim Kontext-Pfad, damit sich
    /// Anzeige/Haptik/Trainings-Stop nicht unterscheiden, je nachdem, über welchen Kanal ein
    /// Zustand ankam.
    /// Bewusst zuerst auf die Routen-Geometrie geprüft (s. `WatchRouteTransferKey.lines`), da
    /// `sendRouteImmediateIfReachable` auf der iOS-Seite denselben Kanal (`sendMessage`) wie die
    /// regulären Status-Updates nutzt - ohne diese Unterscheidung würde `WatchNavState(dictionary:)`
    /// eine Routen-Nachricht fälschlich als (leeren) Navigationsstatus interpretieren.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let rawLines = message[WatchRouteTransferKey.lines] as? [[[Double]]] {
            applyRouteLines(rawLines)
            return
        }
        let newState = WatchNavState(dictionary: message)
        DispatchQueue.main.async {
            self.apply(newState, playHapticIfChanged: true)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let rawLines = userInfo[WatchRouteTransferKey.lines] as? [[[Double]]] else { return }
        applyRouteLines(rawLines)
    }

    private func applyRouteLines(_ rawLines: [[[Double]]]) {
        let lines = rawLines.map { line in
            line.compactMap { point -> CLLocationCoordinate2D? in
                guard point.count == 2 else { return nil }
                return CLLocationCoordinate2D(latitude: point[0], longitude: point[1])
            }
        }
        DispatchQueue.main.async {
            self.routeLines = lines
        }
    }
}
