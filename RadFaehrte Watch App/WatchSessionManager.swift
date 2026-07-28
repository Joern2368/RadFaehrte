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

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // `didReceiveApplicationContext` liefert automatisch den zuletzt vom iPhone gesendeten
        // Stand nach - `session.receivedApplicationContext` deckt trotzdem den Fall ab, dass die
        // Watch-App komplett neu gestartet wird, nachdem der Kontext schon vorher ankam.
        DispatchQueue.main.async {
            self.state = WatchNavState(dictionary: session.receivedApplicationContext)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            self.state = WatchNavState(dictionary: applicationContext)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message[WatchMessageKey.hapticTurnEvent] != nil else { return }
        DispatchQueue.main.async {
            WKInterfaceDevice.current().play(.directionUp)
        }
    }
}
