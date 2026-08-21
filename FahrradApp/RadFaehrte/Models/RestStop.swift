//
//  RestStop.swift
//  RadFaehrte
//

import CoreLocation
import Foundation

/// Ein Rastplatz-POI aus OpenStreetMap (Trinkwasser, Café, Aussichtspunkt,
/// Fahrrad-Reparaturstation, Bank) - s. `Scripts/build_rest_stops.py`. Bänke waren zeitweise
/// komplett ausgeschlossen (überluden die Kartenanzeige, 93 % aller Treffer in Bremen allein,
/// Nutzer-Feedback 2026-08-19 "zu unruhig auf der Karte, zu viele Pins") - inzwischen per
/// Raster ausgedünnt statt ganz weggelassen (s. `BENCH_GRID_METERS` im Build-Skript). `id` ist
/// die stabile OSM-Knoten-ID
/// (statt einer frischen `UUID`), da diese Daten aus einer Datenquelle stammen statt vom Nutzer neu
/// angelegt zu werden - s. `FavoritePlace`/`RecentPlace` für dasselbe Prinzip bei nutzerseitig
/// erzeugten Orten.
struct RestStop: Identifiable, Codable, Equatable {
    let id: Int64
    let kind: Kind
    /// OSM-`name`-Tag, meist `nil` (Trinkwasserstellen sind selten benannt).
    let title: String?
    /// OSM-`opening_hours`-Rohtext (z. B. "Mo-Fr 08:00-18:00; Sa 09:00-14:00"), unverändert
    /// angezeigt statt ausgewertet ("gerade geöffnet?") - s. `Scripts/build_rest_stops.py`. `nil`,
    /// wenn der POI kein `opening_hours`-Tag trägt (nicht nur bei Cafés möglich, aber dort am
    /// häufigsten gesetzt).
    let openingHours: String?
    let coordinate: Coordinate

    /// `openingHours` mit den englischen OSM-Wochentags-/Sonderkürzeln (`Tu`, `We`, `Th`, `Su`,
    /// `PH`, `off`) durch deutsche ersetzt (`Di`, `Mi`, `Do`, `So`, `Feiertag`, `geschlossen`) -
    /// reine Text-Ersetzung per Wortgrenzen-Regex, **keine** Interpretation der OSM-`opening_hours`-
    /// Syntax selbst (Zeiten/Kommas/Semikolons/Bindestriche bleiben unverändert stehen). Für die
    /// App komplett hart deutsche Oberfläche (s. CLAUDE.md) - der rohe OSM-Text wäre sonst der
    /// einzige englische Programmpunkt.
    var openingHoursGerman: String? {
        guard let openingHours else { return nil }
        let range = NSRange(openingHours.startIndex..., in: openingHours)
        var result = ""
        var lastEnd = openingHours.startIndex
        Self.openingHoursTokenPattern.enumerateMatches(in: openingHours, range: range) { match, _, _ in
            guard let match, let matchRange = Range(match.range, in: openingHours) else { return }
            result += openingHours[lastEnd..<matchRange.lowerBound]
            let token = String(openingHours[matchRange])
            result += Self.openingHoursGermanTokens[token] ?? token
            lastEnd = matchRange.upperBound
        }
        result += openingHours[lastEnd...]
        return result
    }

    private static let openingHoursTokenPattern = try! NSRegularExpression(
        pattern: #"\b(Mo|Tu|We|Th|Fr|Sa|Su|PH|off)\b"#
    )

    private static let openingHoursGermanTokens: [String: String] = [
        "Tu": "Di", "We": "Mi", "Th": "Do", "Su": "So", "PH": "Feiertag", "off": "geschlossen",
    ]

    enum Kind: String, CaseIterable, Codable, Identifiable {
        case drinkingWater, cafe, viewpoint, bicycleRepairStation, bench

        var id: String { rawValue }

        var label: String {
            switch self {
            case .drinkingWater: return "Trinkwasser"
            case .cafe: return "Café"
            case .viewpoint: return "Aussichtspunkt"
            case .bicycleRepairStation: return "Fahrrad-Reparaturstation"
            case .bench: return "Bank"
            }
        }

        var icon: String {
            switch self {
            case .drinkingWater: return "drop.fill"
            case .cafe: return "cup.and.saucer.fill"
            case .viewpoint: return "binoculars.fill"
            case .bicycleRepairStation: return "wrench.and.screwdriver.fill"
            case .bench: return "chair.fill"
            }
        }
    }

    struct Coordinate: Codable, Equatable {
        let latitude: Double
        let longitude: Double

        var clLocationCoordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    var clCoordinate: CLLocationCoordinate2D {
        coordinate.clLocationCoordinate
    }
}
