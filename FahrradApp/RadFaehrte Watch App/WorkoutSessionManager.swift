//
//  WorkoutSessionManager.swift
//  RadFaehrte Watch App
//
//  Startet/beendet passend zur Navigation (s. `WatchSessionManager.state.isNavigating`) eine
//  HKWorkoutSession/HKLiveWorkoutBuilder - genau wie Komoot/Strava/Google Maps das nutzen, um
//  während der Fahrt zuverlässig im Hintergrund weiterzulaufen (ohne aktive Trainings-Session
//  pausiert eine watchOS-App im Hintergrund gelegentlich, s. ROADMAP.md). Dient hier bewusst nur
//  als Hintergrund-Wachhalte-Trick - die Session wird am Ende verworfen statt gespeichert
//  (`discardWorkout`), nicht in Health persistiert (Nutzer-Entscheidung 2026-08-02: Das iPhone
//  speichert nach jeder Fahrt ohnehin bereits ein Training, s. `RadFaehrte/Services/
//  WorkoutRecorder.swift` - eine zusätzliche Watch-Session hätte sonst einen doppelten
//  Health-Eintrag erzeugt, wann immer die Watch-App während der Fahrt geöffnet war).
//

import Foundation
import HealthKit

final class WorkoutSessionManager: NSObject {
    static let shared = WorkoutSessionManager()

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private override init() {
        super.init()
    }

    /// Nur `workoutType` - eine Session zu *starten* verlangt Freigabe fürs Schreiben dieses Typs,
    /// auch wenn sie am Ende verworfen statt gespeichert wird (s. o.). Ohne Speicherabsicht keine
    /// weiteren Typen (Energie/Distanz/Herzfrequenz) nötig.
    private static let shareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
    ]

    /// Berechtigung früh anfragen (App-Start), damit sie bei der ersten Fahrt bereits erteilt ist -
    /// ein bei Navigationsstart erst angestoßener Dialog käme zu spät für den Beginn der Fahrt.
    func requestAuthorizationIfNeeded() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthStore.requestAuthorization(toShare: Self.shareTypes, read: []) { _, _ in }
    }

    /// Beim App-Start prüfen, ob eine Trainings-Session aus einer vorherigen (z. B. durch
    /// Ruhezustand beendeten) Watch-App-Instanz noch offen ist, und sie sauber beenden (und
    /// verwerfen) - sonst bliebe sie unsichtbar aktiv im Hintergrund hängen (Akkuverbrauch,
    /// "Training beenden?"-Systemdialog). Ob danach ein neues Training nötig ist, entscheidet der
    /// reguläre Start/Stop-Pfad anhand des frisch vom iPhone synchronisierten Navigationsstatus.
    func recoverOrphanedSessionIfNeeded() {
        healthStore.recoverActiveWorkoutSession { [weak self] recovered, _ in
            guard let self, let recovered else { return }
            DispatchQueue.main.async {
                self.session = recovered
                self.builder = recovered.associatedWorkoutBuilder()
                self.builder?.delegate = self
                recovered.delegate = self
                // `finish()` läuft über den Delegate-Callback `didChangeTo: .ended`, sobald die
                // Session unten formal beendet wird - konsistent mit dem regulären `stop()`-Pfad.
                if recovered.state != .stopped {
                    recovered.stopActivity(with: Date())
                }
                recovered.end()
            }
        }
    }

    func start() {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder

            let startDate = Date()
            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { _, _ in }
        } catch {
            session = nil
            builder = nil
        }
    }

    func stop() {
        guard let session, session.state == .running || session.state == .paused else { return }
        session.stopActivity(with: Date())
        session.end()
    }

    /// Muss auf dem Main-Thread aufgerufen werden (s. Aufrufer) - `session`/`builder` werden ohne
    /// zusätzliche Synchronisierung gelesen/geschrieben. Verwirft bewusst statt zu speichern (s.
    /// Kommentar am Dateianfang) - `discardWorkout()` braucht anders als der Speicherpfad
    /// (`endCollection`+`finishWorkout`) kein vorheriges `endCollection`.
    private func finish() {
        builder?.discardWorkout()
        session = nil
        builder = nil
    }
}

extension WorkoutSessionManager: HKWorkoutSessionDelegate {
    // Delegate-Methoden laufen laut Apple-Doku auf einer beliebigen Queue, nicht garantiert dem
    // Main-Thread - deshalb hier auf Main zurückspringen, da `session`/`builder` sonst
    // nebenläufig mit `start()`/`stop()` (immer vom Main-Thread aus, s. `WatchSessionManager.
    // apply`) verändert würden.
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard toState == .ended else { return }
        DispatchQueue.main.async { [weak self] in
            self?.finish()
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.session = nil
            self?.builder = nil
        }
    }
}

extension WorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {}
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
