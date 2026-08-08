//
//  RouteSummary.swift
//  RadFaehrte
//

/// Leichtgewichtiges Gegenstück zu `BikeRoute` für reine Auflistungen (z. B. "Alle Routen") -
/// ohne den teuren Geometrie-Blob, der für eine Listenzeile ohnehin nicht gebraucht wird.
struct RouteSummary: Identifiable, Hashable {
    let id: Int64
    let name: String
    let network: String?
    let ref: String?
    let distanceKm: Double?
    let operatorName: String?

    /// Anzeigetext für das `network`-Tag (OSM-Konvention: icn/ncn/rcn/lcn), `nil` bei
    /// unbekanntem oder fehlendem Wert - dann wird in der Liste kein Badge angezeigt.
    var networkLabel: String? {
        switch network {
        case "icn": return "international"
        case "ncn": return "national"
        case "rcn": return "regional"
        case "lcn": return "lokal"
        default: return nil
        }
    }
}

/// Grobe Schätzung der Fahrzeit für eine Route-Vorschau (Katalog- oder eigene Routen), basierend
/// auf der in den Einstellungen hinterlegten Wunschgeschwindigkeit (`averageSpeedKmh`) - dieselbe
/// Grundlage wie `remainingHours` in `ContentView`, dort aber für die verbleibende Strecke
/// während der Fahrt statt für die Gesamtstrecke vor Fahrtbeginn.
func estimatedDurationText(distanceKm: Double?, speedKmh: Double) -> String? {
    guard let distanceKm, distanceKm > 0, speedKmh > 0 else { return nil }
    let totalMinutes = Int((distanceKm / speedKmh * 60).rounded())
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0 {
        return minutes > 0 ? "≈ \(hours) Std. \(minutes) Min." : "≈ \(hours) Std."
    }
    return "≈ \(minutes) Min."
}
