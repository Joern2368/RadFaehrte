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

    /// Letzter roher `CMDeviceMotion.heading`-Wert (unkorrigiert) - Grundlage für
    /// `currentHeading`, s. `magnetometerBiasCorrection` unten.
    private var rawDeviceHeading: CLLocationDirection?
    /// Geglätteter Versatz des Magnetometer-Headings gegen den GPS-Kurs (`CLLocation.course`),
    /// s. `magnetometerBiasCorrection` für die Herleitung.
    private var magnetometerBiasEstimate: CLLocationDirection?

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
        // `smoothedCameraCoordinate` zurücksetzen, statt eine evtl. veraltete Position aus einer
        // früheren Sitzung als Startwert für den Tiefpassfilter zu übernehmen (`smoothed(...)`
        // gibt bei `previous == nil` die neue Position direkt zurück, ganz ohne Glättung/Verzögerung).
        // Ohne das kroch die Kamera beim Live-Test (München-Testroute von Rotterdam aus,
        // 2026-07-27) über viele Sekunden sichtbar langsam von einer alten Position zur echten
        // aktuellen Position, statt sofort dort zu sein - wirkte wie ein andauerndes "Wandern" der
        // Karte, das nie richtig ankommt.
        smoothedCameraCoordinate = nil
        magnetometerBiasEstimate = nil
        manager.startUpdatingLocation()
        startDeviceMotionHeadingUpdates()
        Self.appendDebugLog("=== Session gestartet \(Date()) ===")
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
            rawDeviceHeading = motion.heading
            currentHeading = Self.correctedHeading(rawHeading: motion.heading, bias: magnetometerBiasEstimate)
            headingUpdateCount += 1
        }
    }

    /// Korrigiert einen dauerhaften Magnetometer-Versatz des `CMDeviceMotion.heading`-Werts gegen
    /// den GPS-Kurs (`CLLocation.course`) - zweiter Versuch nach dem in der Roadmap dokumentierten
    /// "Verworfenen Versuch" vom 2026-07-25. Der damalige Live-Test zeigte eine Verschlechterung
    /// (Kartendrehung blieb bei einer falschen, ungefähr konstanten Nordost-Ausrichtung stehen),
    /// wurde aber ohne Messdaten wieder zurückgebaut. Diesmal per `heading_debug.log` einer
    /// tatsächlichen Fahrt (2026-08-03, Bremen Altstadt) ausgewertet, bevor erneut korrigiert wird:
    /// Bei 15-19 km/h stimmte `course` über mehr als eine Minute durchgehend auf ±10° mit der aus
    /// den GPS-Rohpositionen berechneten tatsächlichen Bewegungsrichtung überein, während
    /// `currentHeading` einen stabilen Versatz von ca. 35-45° zeigte (vermutlich Magnetstörung
    /// durch Halterung/Vorderrad - Nutzer-Beschreibung: Handy zeigte zum Vorderrad, also am Lenker/
    /// Vorbau montiert). Eine Offline-Simulation dieser Korrektur gegen exakt diese Aufzeichnung
    /// senkte den mittleren Heading-Fehler von 34° auf 8°. Absicherungen gegen die beim ersten
    /// Versuch vermutete Ursache (an einer Kreuzung/Rampe war der GPS-Kurs vermutlich selbst durch
    /// Mehrwegeausbreitung ungenau):
    /// - Nur bei ausreichender Geschwindigkeit (`minSpeedForBiasKmh`) und einigermaßen
    ///   vertrauenswürdigem `courseAccuracy` (`maxCourseAccuracyForBias`) wird der Versatz
    ///   überhaupt neu geschätzt - bei Stillstand/langsamer Fahrt oder unzuverlässigem Kurs bleibt
    ///   die zuletzt bekannte Schätzung unverändert liegen, statt auf einen einzelnen schlechten
    ///   Wert zu springen.
    /// - Starke Glättung (`biasSmoothingAlpha`) verhindert, dass ein einzelner Ausreißer die
    ///   Schätzung sofort kippt - ein echter Versatz baut sich über mehrere Sekunden auf, ein
    ///   einzelner falscher Kurswert verschiebt sie nur geringfügig.
    /// Trotzdem noch nicht erneut live gegengetestet (**Offen**, s. ROADMAP.md) - falls die
    /// Kartendrehung nach diesem Umbau wieder "hängen bleibt" statt echten Kurven zu folgen, ist
    /// `heading_debug.log` weiterhin aktiv und liefert die nötigen Rohdaten zur weiteren Diagnose.
    private static let minSpeedForBiasKmh: Double = 8
    private static let maxCourseAccuracyForBias: Double = 100
    private static let biasSmoothingAlpha: Double = 0.15

    private func updateMagnetometerBiasEstimate(for location: CLLocation) {
        guard let rawDeviceHeading,
              location.speed * 3.6 >= Self.minSpeedForBiasKmh,
              location.course >= 0,
              location.courseAccuracy >= 0, location.courseAccuracy <= Self.maxCourseAccuracyForBias
        else { return }
        let observedBias = Self.angularDifference(rawDeviceHeading, location.course)
        if let previous = magnetometerBiasEstimate {
            magnetometerBiasEstimate = previous + Self.biasSmoothingAlpha * Self.angularDifference(observedBias, previous)
        } else {
            magnetometerBiasEstimate = observedBias
        }
        currentHeading = Self.correctedHeading(rawHeading: rawDeviceHeading, bias: magnetometerBiasEstimate)
    }

    /// Kürzeste Winkeldifferenz `a - b`, auf den Bereich -180..<180 normiert.
    private static func angularDifference(_ a: CLLocationDirection, _ b: CLLocationDirection) -> CLLocationDirection {
        let raw = (a - b).truncatingRemainder(dividingBy: 360)
        if raw < -180 { return raw + 360 }
        if raw >= 180 { return raw - 360 }
        return raw
    }

    private static func correctedHeading(rawHeading: CLLocationDirection, bias: CLLocationDirection?) -> CLLocationDirection {
        guard let bias else { return rawHeading }
        return (rawHeading - bias).truncatingRemainder(dividingBy: 360) + (rawHeading - bias < 0 ? 360 : 0)
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
        updateMagnetometerBiasEstimate(for: location)
        locationUpdateCount += 1
        // TEMP-DEBUG (s. ROADMAP.md "Magnetometer-Bias..."): Schreibt bei jedem GPS-Update eine
        // Zeile mit Heading vs. GPS-Kurs in eine Datei statt auf die Live-Konsole, damit die
        // Aufzeichnung auch ohne angeschlossenes/entsperrtes iPhone während einer Fahrt läuft -
        // wieder entfernen, sobald die Nordwest/Nordost-Beobachtung geklärt ist.
        Self.appendDebugLog(
            "\(Date().timeIntervalSince1970),lat=\(location.coordinate.latitude),lon=\(location.coordinate.longitude),"
            + "hAcc=\(location.horizontalAccuracy),speedKmh=\(location.speed * 3.6),course=\(location.course),"
            + "courseAcc=\(location.courseAccuracy),rawHeading=\(rawDeviceHeading ?? -1),bias=\(magnetometerBiasEstimate ?? -999),"
            + "heading=\(currentHeading ?? -1)"
        )
    }

    /// Nur für das temporäre Datei-Logging oben - Pfad in `Documents`, damit die Datei auch nach
    /// App-Neustart erhalten bleibt und sich per `devicectl device copy from` auslesen lässt, ohne
    /// dass währenddessen ein Kabel/entsperrtes Gerät nötig ist.
    private static let debugLogURL: URL? = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask).first?
        .appendingPathComponent("heading_debug.log")

    private static func appendDebugLog(_ line: String) {
        guard let debugLogURL else { return }
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: debugLogURL.path), let handle = try? FileHandle(forWritingTo: debugLogURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: debugLogURL)
        }
    }

    /// Exponentielle Glättung (Tiefpass) der GPS-Position für `smoothedCameraCoordinate`. Fester
    /// `alpha`-Wert von 0.4 für normales GPS-Rauschen während der Fahrt.
    ///
    /// ⚠️ Reicht **allein** nicht: Auch mit zurückgesetztem `previous` bei Sitzungsstart (s.
    /// `startUpdating`) blieb beim Live-Test (Rotterdam, 2026-07-27) ein sichtbares "Kriechen" der
    /// Kamera über mehrere Sekunden bestehen. Ursache: Ein GPS-Kaltstart liefert oft mehrere
    /// aufeinanderfolgende *echte, aber jeweils genauere* Fixes (erst grob über WLAN/Zellfunk, dann
    /// zunehmend präzise über Satelliten) - jeder einzelne Sprung ist real, keine Sitzungs-Altlast,
    /// wird vom Filter aber trotzdem als "Rauschen" behandelt und nur zu 40 % nachvollzogen, bevor
    /// der nächste (wieder nur teils nachvollzogene) Fix kommt - macht den Effekt in der Summe
    /// über mehrere Updates hinweg genauso sichtbar wie eine Sitzungs-Altlast.
    /// Deshalb zusätzlich eine große Sprünge direkt (ohne Glättung) übernehmende Grenze: Ab
    /// `snapThresholdMeters` wird der Vorsprung als echte Neupositionierung gewertet (Kaltstart-
    /// Korrektur oder tatsächliches Teleportieren, z. B. nach Import/Sprung im Simulator), nicht als
    /// Rauschen während der Fahrt - dafür sind übliche GPS-Ungenauigkeiten viel zu klein.
    private static func smoothed(
        _ new: CLLocationCoordinate2D, previous: CLLocationCoordinate2D?, alpha: Double = 0.4,
        snapThresholdMeters: Double = 50
    ) -> CLLocationCoordinate2D {
        guard let previous else { return new }
        let previousLocation = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
        let newLocation = CLLocation(latitude: new.latitude, longitude: new.longitude)
        guard previousLocation.distance(from: newLocation) <= snapThresholdMeters else { return new }
        return CLLocationCoordinate2D(
            latitude: previous.latitude + alpha * (new.latitude - previous.latitude),
            longitude: previous.longitude + alpha * (new.longitude - previous.longitude)
        )
    }
}
