//
//  WorkoutRecorder.swift
//  RadFaehrte
//
//  Speichert eine abgeschlossene Fahrt nachträglich als Radfahr-Training in Health - unabhängig
//  davon, ob eine Apple Watch beteiligt ist (dort läuft parallel eine eigene, *live* laufende
//  HKWorkoutSession, s. WorkoutSessionManager im Watch-Target, die zusätzlich das Pausieren der
//  Watch-App im Hintergrund verhindert). Auf dem iPhone gibt es dieses Hintergrund-Problem nicht
//  (Standortverfolgung läuft dort bereits zuverlässig weiter, s. ROADMAP.md "Bildschirm &
//  Hintergrund"), deshalb genügt hier ein einfacher, nicht-live `HKWorkoutBuilder` direkt nach
//  Fahrtende statt einer laufenden Session.
//

import CoreLocation
import Foundation
import HealthKit

final class WorkoutRecorder {
    static let shared = WorkoutRecorder()

    private let healthStore = HKHealthStore()

    private static let shareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.distanceCycling),
        HKSeriesType.workoutRoute(),
    ]

    private init() {}

    func requestAuthorizationIfNeeded() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthStore.requestAuthorization(toShare: Self.shareTypes, read: []) { _, _ in }
    }

    /// `locations` sind die ungeglätteten, zeitgestempelten Rohpositionen der Fahrt (s.
    /// `ContentView.tourRouteLocations`) - separat von der für die Kartenanzeige/den GPX-Export auf
    /// die Route eingerasteten und ausgedünnten `tourTrackPoints`, da eine `HKWorkoutRoute` echte
    /// Zeitstempel je Punkt braucht, um in der Fitness-App eine Karte anzuzeigen.
    func saveRide(start: Date, end: Date, distanceMeters: Double, locations: [CLLocation]) {
        guard HKHealthStore.isHealthDataAvailable(), end > start else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        builder.beginCollection(withStart: start) { [weak self] _, _ in
            let distanceSample = HKQuantitySample(
                type: HKQuantityType(.distanceCycling),
                quantity: HKQuantity(unit: .meter(), doubleValue: distanceMeters),
                start: start,
                end: end
            )
            builder.add([distanceSample]) { _, _ in
                builder.endCollection(withEnd: end) { _, _ in
                    builder.finishWorkout { workout, _ in
                        guard let self, let workout, locations.count >= 2 else { return }
                        self.saveRoute(locations, for: workout)
                    }
                }
            }
        }
    }

    private func saveRoute(_ locations: [CLLocation], for workout: HKWorkout) {
        let routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
        routeBuilder.insertRouteData(locations) { _, _ in
            routeBuilder.finishRoute(with: workout, metadata: nil) { _, _ in }
        }
    }
}
