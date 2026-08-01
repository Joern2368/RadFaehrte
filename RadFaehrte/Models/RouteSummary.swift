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
