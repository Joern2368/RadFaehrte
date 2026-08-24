//
//  SunCalculator.swift
//  RadFaehrte
//

import CoreLocation
import Foundation

/// Näherungsweise Sonnenuntergangszeit für einen Standort/Tag - Low-Precision-Variante des NOAA-
/// Sonnenstand-Algorithmus (Meeus), auf wenige Minuten genau. Für eine Orientierungshilfe auf dem
/// Rad (`NavigationStatKind.sunsetTime`/`.timeUntilSunset`) reicht das, ohne Netzwerkzugriff oder
/// eine externe Wetter-/Astronomie-API zu brauchen - die Berechnung läuft komplett lokal aus
/// Standort + Gerätedatum.
enum SunCalculator {
    /// `nil` bei Polartag/-nacht (Sonne geht an diesem Tag am angegebenen Ort nicht unter) - für
    /// Deutschland/Mitteleuropa in der Praxis nie der Fall, aber die Formel selbst (Arkuskosinus
    /// außerhalb [-1, 1]) verlangt die Absicherung.
    static func sunset(for coordinate: CLLocationCoordinate2D, on date: Date) -> Date? {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let components = utcCalendar.dateComponents([.year, .month, .day], from: date)
        guard let noonUTC = utcCalendar.date(from: DateComponents(
            year: components.year, month: components.month, day: components.day, hour: 12
        )) else { return nil }

        // Julianisches Datum + Jahrhunderte seit J2000.0 - Basis für alle folgenden
        // Sonnenstand-Formeln (Meeus, "Astronomical Algorithms", vereinfacht auf Grad-Genauigkeit).
        let julianDay = noonUTC.timeIntervalSince1970 / 86400 + 2440587.5
        let centuriesSinceJ2000 = (julianDay - 2451545.0) / 36525

        let meanLongitudeDeg = normalizedDegrees(
            280.46646 + centuriesSinceJ2000 * (36000.76983 + centuriesSinceJ2000 * 0.0003032)
        )
        let meanAnomalyDeg = 357.52911 + centuriesSinceJ2000 * (35999.05029 - 0.0001537 * centuriesSinceJ2000)
        let eccentricity = 0.016708634 - centuriesSinceJ2000 * (0.000042037 + 0.0000001267 * centuriesSinceJ2000)

        let meanAnomalyRad = meanAnomalyDeg * .pi / 180
        let equationOfCenter = sin(meanAnomalyRad) * (1.914602 - centuriesSinceJ2000 * (0.004817 + 0.000014 * centuriesSinceJ2000))
            + sin(2 * meanAnomalyRad) * (0.019993 - 0.000101 * centuriesSinceJ2000)
            + sin(3 * meanAnomalyRad) * 0.000289
        let trueLongitudeDeg = meanLongitudeDeg + equationOfCenter

        let omegaDeg = 125.04 - 1934.136 * centuriesSinceJ2000
        let apparentLongitudeDeg = trueLongitudeDeg - 0.00569 - 0.00478 * sin(omegaDeg * .pi / 180)

        let meanObliquityDeg = 23 + (26 + (21.448 - centuriesSinceJ2000
            * (46.815 + centuriesSinceJ2000 * (0.00059 - centuriesSinceJ2000 * 0.001813))) / 60) / 60
        let obliquityDeg = meanObliquityDeg + 0.00256 * cos(omegaDeg * .pi / 180)

        let declinationRad = asin(sin(obliquityDeg * .pi / 180) * sin(apparentLongitudeDeg * .pi / 180))

        // Zeitgleichung (Differenz zwischen wahrer und mittlerer Sonnenzeit) in Minuten.
        let obliquityHalfTan = pow(tan(obliquityDeg * .pi / 180 / 2), 2)
        let meanLongitudeRad = meanLongitudeDeg * .pi / 180
        let equationOfTimeMinutes = 4 * (
            obliquityHalfTan * sin(2 * meanLongitudeRad)
            - 2 * eccentricity * sin(meanAnomalyRad)
            + 4 * eccentricity * obliquityHalfTan * sin(meanAnomalyRad) * cos(2 * meanLongitudeRad)
            - 0.5 * obliquityHalfTan * obliquityHalfTan * sin(4 * meanLongitudeRad)
            - 1.25 * eccentricity * eccentricity * sin(2 * meanAnomalyRad)
        ) * 180 / .pi

        // 90,833° statt 90° als Horizont-Winkel: übliche atmosphärische Refraktion (~34 Bogenminuten)
        // plus Sonnenradius (~16 Bogenminuten) - Standardkorrektur für den sichtbaren, nicht den
        // geometrischen Sonnenuntergang.
        let latitudeRad = coordinate.latitude * .pi / 180
        let cosHourAngle = cos(90.833 * .pi / 180) / (cos(latitudeRad) * cos(declinationRad))
            - tan(latitudeRad) * tan(declinationRad)
        guard cosHourAngle >= -1, cosHourAngle <= 1 else { return nil }
        let hourAngleDeg = acos(cosHourAngle) * 180 / .pi

        let solarNoonMinutesUTC = 720 - 4 * coordinate.longitude - equationOfTimeMinutes
        let sunsetMinutesUTC = solarNoonMinutesUTC + 4 * hourAngleDeg

        return noonUTC.addingTimeInterval(-12 * 3600 + sunsetMinutesUTC * 60)
    }

    private static func normalizedDegrees(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }
}
