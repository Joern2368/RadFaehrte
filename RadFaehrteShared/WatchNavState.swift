//
//  WatchNavState.swift
//  RadFaehrteShared
//
//  Von iOS-App und Watch-App gemeinsam genutzt (eigener geteilter Ordner, damit dieselbe Datei
//  ohne Duplikat in beiden Xcode-Targets landet).
//

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

    static let idle = WatchNavState(
        isNavigating: false, instructionText: "", distanceText: "", direction: .straight, routeName: nil, hapticTrigger: 0
    )

    init(isNavigating: Bool, instructionText: String, distanceText: String, direction: Direction, routeName: String?, hapticTrigger: Int) {
        self.isNavigating = isNavigating
        self.instructionText = instructionText
        self.distanceText = distanceText
        self.direction = direction
        self.routeName = routeName
        self.hapticTrigger = hapticTrigger
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
        return dict
    }

    init(dictionary: [String: Any]) {
        isNavigating = dictionary["isNavigating"] as? Bool ?? false
        instructionText = dictionary["instructionText"] as? String ?? ""
        distanceText = dictionary["distanceText"] as? String ?? ""
        direction = Direction(rawValue: dictionary["direction"] as? String ?? "") ?? .straight
        routeName = dictionary["routeName"] as? String
        hapticTrigger = dictionary["hapticTrigger"] as? Int ?? 0
    }
}
