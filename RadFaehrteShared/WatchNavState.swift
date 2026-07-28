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

    static let idle = WatchNavState(
        isNavigating: false, instructionText: "", distanceText: "", direction: .straight, routeName: nil
    )

    init(isNavigating: Bool, instructionText: String, distanceText: String, direction: Direction, routeName: String?) {
        self.isNavigating = isNavigating
        self.instructionText = instructionText
        self.distanceText = distanceText
        self.direction = direction
        self.routeName = routeName
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
    }
}

/// Nachrichten-Schlüssel für das kurzlebige Haptik-Signal (`WCSession.sendMessage`, separat von
/// `updateApplicationContext`: das ist für ein einmaliges Ereignis kurz vor einer Abbiegung
/// gedacht, nicht für dauerhaften Zustand) - die Watch übersetzt den Empfang in haptisches
/// Feedback (`WKInterfaceDevice.play(.directionUp)`).
enum WatchMessageKey {
    static let hapticTurnEvent = "hapticTurnEvent"
}
