//
//  RestStop.swift
//  RadFaehrte
//

import CoreLocation
import Foundation
import SwiftUI

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
        case drinkingWater, cafe, viewpoint, bicycleRepairStation, bench, beerGarden, toilets,
            ebikeCharging, bakery

        var id: String { rawValue }

        var label: String {
            switch self {
            case .drinkingWater: return "Trinkwasser"
            case .cafe: return "Café"
            case .viewpoint: return "Aussichtspunkt"
            case .bicycleRepairStation: return "Fahrrad-Reparaturstation"
            case .bench: return "Bank"
            case .beerGarden: return "Biergarten"
            case .toilets: return "Toilette"
            case .ebikeCharging: return "E-Bike-Ladestation"
            case .bakery: return "Bäckerei"
            }
        }

        var icon: String {
            switch self {
            case .drinkingWater: return "drop.fill"
            case .cafe: return "cup.and.saucer.fill"
            case .viewpoint: return "binoculars.fill"
            case .bicycleRepairStation: return "wrench.and.screwdriver.fill"
            case .bench: return "chair.fill"
            case .beerGarden: return "mug.fill"
            case .toilets: return "toilet.fill"
            case .ebikeCharging: return "bolt.fill"
            /// Fallback für Kontexte, die zwingend einen SF-Symbol-Namen brauchen - fürs visuelle
            /// Rendering überschreibt `emoji` das hier (SF Symbols hat kein Brezel-/Bäckerei-Symbol,
            /// geprüft gegen `SFSymbols.framework`s `name_availability.plist`: weder "pretzel" noch
            /// "bread" noch "bakery" vorhanden).
            case .bakery: return "birthday.cake.fill"
            }
        }

        /// Emoji-Override fürs visuelle Rendering (Pin auf der Karte, Listen-Icons) anstelle von
        /// `icon` - s. Kommentar dort. `nil` für alle Kategorien mit passendem SF Symbol.
        var emoji: String? {
            switch self {
            case .bakery: return "🥨"
            default: return nil
            }
        }

        /// Einfärbung des Pin-/Listen-Icons zur visuellen Unterscheidung der Kategorien auf der
        /// Karte (Nutzer-Feedback: Symbole waren alle einheitlich blau, schwer auf den ersten Blick
        /// zu unterscheiden). Bei `emoji`-Kategorien ungenutzt, da das Emoji seine eigene Farbe
        /// mitbringt.
        var color: Color {
            switch self {
            case .drinkingWater: return .blue
            case .cafe: return .brown
            case .viewpoint: return .green
            case .bicycleRepairStation: return .orange
            case .bench: return .red
            case .beerGarden: return .yellow
            case .toilets: return .cyan
            case .ebikeCharging: return .mint
            case .bakery: return .pink
            }
        }

        /// Persistiert als kommagetrennte `rawValue`-Liste in einem einzelnen `@AppStorage`-String
        /// (`AppSettingsKey.showRestStopKinds`) - analog `NavigationStatKind`/`navigationStatSlots`
        /// in `AppSettings.swift`, statt einem eigenen `UserDefaults`-Key pro Kategorie.
        static func decode(_ raw: String) -> Set<Kind> {
            Set(raw.split(separator: ",").compactMap { Kind(rawValue: String($0)) })
        }

        static func encode(_ kinds: Set<Kind>) -> String {
            Kind.allCases.filter(kinds.contains).map(\.rawValue).joined(separator: ",")
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

/// Icon einer `RestStop.Kind` - Emoji (`kind.emoji`) wenn gesetzt, sonst farbiges SF Symbol
/// (`kind.icon`/`kind.color`). Gemeinsam genutzt vom Karten-Pin (`ContentView`), dem Detail-Sheet
/// und der Kategorie-Liste (`RestStopKindSettingsView`), damit alle drei Stellen bei einer neuen
/// Kategorie automatisch konsistent bleiben.
struct RestStopKindIcon: View {
    let kind: RestStop.Kind

    var body: some View {
        if let emoji = kind.emoji {
            Text(emoji)
        } else {
            Image(systemName: kind.icon)
                .foregroundStyle(kind.color)
        }
    }
}
