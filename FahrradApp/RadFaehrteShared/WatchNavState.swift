//
//  WatchNavState.swift
//  RadFaehrteShared
//
//  Von iOS-App und Watch-App gemeinsam genutzt (eigener geteilter Ordner, damit dieselbe Datei
//  ohne Duplikat in beiden Xcode-Targets landet).
//

import CoreLocation
import Foundation

/// Navigationsstatus, der per WatchConnectivity vom iPhone zur Apple Watch übertragen wird.
struct WatchNavState: Equatable {
    enum Direction: String {
        case straight, left, right
    }

    var isNavigating: Bool
    var instructionText: String
    var distanceText: String
    var direction: Direction
    var routeName: String?
    /// Hochzählender Zähler, der bei jeder bevorstehenden Abbiegung erhöht wird - die Watch löst
    /// haptisches Feedback aus, sobald sich dieser Wert gegenüber dem zuletzt gesehenen ändert.
    /// Bewusst Teil des ohnehin per `updateApplicationContext` übertragenen Zustands statt einer
    /// separaten `sendMessage`-Nachricht: Letztere braucht eine gerade aktiv erreichbare
    /// Gegenseite (Watch-App im Vordergrund) - beim Radfahren hat man die App aber normalerweise
    /// nicht die ganze Zeit offen. `updateApplicationContext` kommt dagegen zuverlässig auch im
    /// Hintergrund an (per Live-Test 2026-07-30 bestätigt: `sendMessage` scheiterte wiederholt mit
    /// "not reachable", während der reguläre Status-Zustand parallel immer ankam).
    var hapticTrigger: Int
    /// Aktuelle Position - für die Kartenanzeige auf der Watch. Bewusst Teil des ohnehin bei jedem
    /// Standort-Update gesendeten Zustands (winziger Zusatz, zwei `Double`s) statt eines eigenen
    /// Kanals - anders als die Routen-Geometrie (s. `WatchSessionManager.sendRoute`), die sich
    /// während einer Fahrt kaum ändert und deshalb separat nur bei Bedarf übertragen wird.
    var currentLatitude: Double?
    var currentLongitude: Double?
    /// Fahrtrichtung in Grad (0 = Norden), identisch zu `LocationManager.currentHeading` auf der
    /// iPhone-Seite - lässt die Watch-Karte wie beim iPhone in Fahrtrichtung gedreht anzeigen
    /// (Heading-up) statt starr nordausgerichtet.
    var heading: Double?

    var currentCoordinate: CLLocationCoordinate2D? {
        guard let currentLatitude, let currentLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: currentLatitude, longitude: currentLongitude)
    }

    static let idle = WatchNavState(
        isNavigating: false, instructionText: "", distanceText: "", direction: .straight, routeName: nil,
        hapticTrigger: 0, currentLatitude: nil, currentLongitude: nil, heading: nil
    )

    init(
        isNavigating: Bool, instructionText: String, distanceText: String, direction: Direction, routeName: String?,
        hapticTrigger: Int, currentLatitude: Double?, currentLongitude: Double?, heading: Double?
    ) {
        self.isNavigating = isNavigating
        self.instructionText = instructionText
        self.distanceText = distanceText
        self.direction = direction
        self.routeName = routeName
        self.hapticTrigger = hapticTrigger
        self.currentLatitude = currentLatitude
        self.currentLongitude = currentLongitude
        self.heading = heading
    }

    /// `WCSession.updateApplicationContext` verlangt ein Property-List-kompatibles Dictionary
    /// (nur String/NSNumber/NSArray/NSDictionary/NSData/NSDate) - deshalb hier ein flaches
    /// Dictionary mit primitiven Werten statt einer generischen `Codable`-JSON-Kodierung.
    var dictionaryRepresentation: [String: Any] {
        var dict: [String: Any] = [
            "isNavigating": isNavigating,
            "instructionText": instructionText,
            "distanceText": distanceText,
            "direction": direction.rawValue,
            "hapticTrigger": hapticTrigger,
        ]
        if let routeName {
            dict["routeName"] = routeName
        }
        if let currentLatitude, let currentLongitude {
            dict["currentLatitude"] = currentLatitude
            dict["currentLongitude"] = currentLongitude
        }
        if let heading {
            dict["heading"] = heading
        }
        return dict
    }

    init(dictionary: [String: Any]) {
        isNavigating = dictionary["isNavigating"] as? Bool ?? false
        instructionText = dictionary["instructionText"] as? String ?? ""
        distanceText = dictionary["distanceText"] as? String ?? ""
        direction = Direction(rawValue: dictionary["direction"] as? String ?? "") ?? .straight
        routeName = dictionary["routeName"] as? String
        hapticTrigger = dictionary["hapticTrigger"] as? Int ?? 0
        currentLatitude = dictionary["currentLatitude"] as? Double
        currentLongitude = dictionary["currentLongitude"] as? Double
        heading = dictionary["heading"] as? Double
    }
}

/// Schlüssel für die separat (nicht Teil von `WatchNavState`) per `WCSession.transferUserInfo`
/// übertragene Routen-Geometrie - anders als der laufende Navigationsstatus ändert sie sich
/// während einer Fahrt kaum (nur bei Auswahl/Neuberechnung), wird deshalb nicht bei jedem
/// Standort-Update erneut mitgeschickt (unnötiger Datenverkehr). `transferUserInfo` statt
/// `updateApplicationContext`, weil Letzteres nur einen einzigen, komplett ersetzten Kontext
/// kennt - ein zweiter `updateApplicationContext`-Aufruf für die Route würde den zuletzt
/// gesendeten Navigationsstatus überschreiben.
enum WatchRouteTransferKey {
    /// Wert: `[[[Double]]]` - äußere Ebene = einzelne Linien (bei kuratierten Routen mit Lücken
    /// mehrere getrennte Segmente möglich), mittlere Ebene = Punkte einer Linie, innerste Ebene
    /// = `[Breite, Länge]`.
    static let lines = "routeLines"
}
