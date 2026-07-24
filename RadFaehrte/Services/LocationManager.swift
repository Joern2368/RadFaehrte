//
//  LocationManager.swift
//  RadFaehrte
//

import CoreLocation
import CoreMotion
import Observation

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let motionManager = CMMotionManager()

    var authorizationStatus: CLAuthorizationStatus
    var currentLocation: CLLocation?
    /// Für die Navigationskamera geglättete Position (exponentieller Tiefpassfilter) - dämpft
    /// GPS-Rauschen, das sonst als sichtbares Ruckeln auffiel (Nutzer-Vergleich mit Komoot).
    /// Bewusst getrennt von `currentLocation`: Distanzsummierung, Abweichungserkennung und
    /// Routen-Einrasten nutzen weiterhin die unveränderte Rohposition, deren Schwellenwerte schon
    /// gegen echte Fahrten kalibriert sind.
    private(set) var smoothedCameraCoordinate: CLLocationCoordinate2D?
    var currentHeading: CLLocationDirection?
    private(set) var locationUpdateCount = 0
    private(set) var headingUpdateCount = 0

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .otherNavigation
        // Ohne das würde iOS Updates automatisch pausieren, wenn es meint, der Nutzer stünde
        // still (z. B. an einer Ampel oder kurz in einem Geschäft) - während aktiver Navigation
        // unerwünscht.
        manager.pausesLocationUpdatesAutomatically = false
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
        startDeviceMotionHeadingUpdates()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
        motionManager.stopDeviceMotionUpdates()
    }

    /// Nutzt CoreMotion (Gyroskop + Beschleunigungssensor + Magnetometer fusioniert über
    /// `CMDeviceMotion.heading`) statt `CLLocationManager`s reiner Magnetometer-Richtung
    /// (`didUpdateHeading`). Im Live-Vergleich mit Komoot (zwei Bildschirmaufnahmen, per
    /// Einzelbild-Analyse verglichen) fror die Kartendrehung bei reiner CLHeading-Nutzung
    /// sichtbar für über eine Sekunde ein und holte dann ruckartig auf, statt sich wie bei Komoot
    /// bei jedem Frame gleichmäßig weiterzudrehen - Indiz, dass CLHeading-Updates bei
    /// Magnetometer-Störungen unregelmäßig eintrafen. `CMDeviceMotion.heading` ist genau für
    /// diesen Fall gedacht: gyroskop-stabilisiert, mit fester hoher Rate verfügbar, unabhängig von
    /// kurzzeitigen Magnetometer-Ausfällen. Braucht laufende Standort-Updates für die
    /// Nordkorrektur (`.xTrueNorthZVertical`), deshalb erst hier gestartet, nicht im `init`.
    private func startDeviceMotionHeadingUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 20.0
        motionManager.startDeviceMotionUpdates(using: .xTrueNorthZVertical, to: .main) { [weak self] motion, error in
            guard let self, let motion, error == nil, motion.heading >= 0 else { return }
            currentHeading = motion.heading
            headingUpdateCount += 1
        }
    }

    /// Aktiviert/deaktiviert Standort-Updates im Hintergrund (Bildschirm gesperrt oder App im
    /// Hintergrund) - nur während aktiver Navigation gedacht, nicht für einmalige Standortabfragen
    /// (z. B. "aktuellen Standort verwenden"). Zeigt bei aktivem Hintergrund-Tracking den blauen
    /// System-Indikator oben in der Statusleiste (wie bei Komoot/Google Maps), auf den man tippen
    /// kann, um zurück zur App zu springen - funktioniert bewusst mit "Bei Nutzung"- statt
    /// "Immer"-Standortzugriff (braucht dafür `UIBackgroundModes: [location]`, s.
    /// `Supplemental-Info.plist`; `true` ohne diese Deklaration stürzt die App ab).
    func setBackgroundUpdatesEnabled(_ enabled: Bool) {
        manager.allowsBackgroundLocationUpdates = enabled
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        smoothedCameraCoordinate = Self.smoothed(location.coordinate, previous: smoothedCameraCoordinate)
        locationUpdateCount += 1
    }

    /// Exponentielle Glättung (Tiefpass) der GPS-Position für `smoothedCameraCoordinate`. Fester
    /// `alpha`-Wert von 0.4: GPS-Fixes selbst kommen ohnehin nur ~1×/Sekunde (nicht mit der
    /// höheren Kamera-Update-Rate), eine adaptive Unterscheidung wie bei der früheren
    /// Kompass-Glättung (kleine Abweichung = Rauschen, große = echte Bewegung) ist bei derart
    /// wenigen Samples nicht sinnvoll möglich.
    private static func smoothed(
        _ new: CLLocationCoordinate2D, previous: CLLocationCoordinate2D?, alpha: Double = 0.4
    ) -> CLLocationCoordinate2D {
        guard let previous else { return new }
        return CLLocationCoordinate2D(
            latitude: previous.latitude + alpha * (new.latitude - previous.latitude),
            longitude: previous.longitude + alpha * (new.longitude - previous.longitude)
        )
    }
}
