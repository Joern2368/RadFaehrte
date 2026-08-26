//
//  WayGraphStore.swift
//  RadFaehrte
//

import CoreLocation
import Foundation

/// Grobe Rechteck-Näherung an die tatsächliche (unregelmäßige) Grenze einer Region - dient nur als
/// billiger Vorfilter, *bevor* ein `WayGraphRepository` (bei großen Ländern hunderte MB, s.
/// `WayGraphCache`) überhaupt von der Platte geladen wird, nicht als exakte Grenzprüfung. Deshalb
/// bewusst mit großzügigem Rand statt möglichst eng: Ein fälschlich als "möglich" durchgelassener
/// Kandidat kostet nur einen zusätzlichen (günstigen) `nearestNode`-Aufruf auf dem bereits geladenen
/// Graphen, ein fälschlich ausgeschlossener Kandidat würde dagegen die Offline-Engine für eine
/// eigentlich abgedeckte Region unbemerkt überspringen.
nonisolated struct RegionBoundingBox {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double

    /// `marginDegrees` deckt sowohl die Ungenauigkeit der Rechteck-Näherung an der eigentlich
    /// unregelmäßigen Grenze ab als auch den Schnapp-Radius von `WayGraphRepository.nearestNode`
    /// (Standard 2000 m ≈ 0,018°) - großzügig auf 0,15° (≈ 15-17 km) gerundet.
    func contains(_ coordinate: CLLocationCoordinate2D, marginDegrees: Double = 0.15) -> Bool {
        coordinate.latitude >= minLat - marginDegrees && coordinate.latitude <= maxLat + marginDegrees
            && coordinate.longitude >= minLon - marginDegrees && coordinate.longitude <= maxLon + marginDegrees
    }
}

/// Eine Region, für die ein Wege-Graph für die "ruhige Wege"-Offline-Routing-Engine heruntergeladen
/// werden kann (siehe `Scripts/build_way_graph.py`). `rawValue` entspricht zugleich dem
/// Dateinamens-Präfix des jeweiligen Release-Assets (`<rawValue>_ways.sqlite`). `Bundesland`
/// (Deutschland) und `EuropaLand` (weitere europäische Länder, aktuell nur Niederlande) sind die
/// beiden aktuellen Regionstypen - je einer pro Land/Ländergruppe, damit `WayGraphStore`/
/// `WayGraphDownloadManager`/`OfflineMapsView` nicht auf Deutschland-Bundesländer festgelegt sind.
nonisolated protocol DownloadableRegion: Hashable, CaseIterable, Identifiable where AllCases: RandomAccessCollection {
    var rawValue: String { get }
    var displayName: String { get }
    var downloadURL: URL { get }
    /// Tatsächliche Dateigröße des generierten Wege-Graphen, für die Anzeige vor dem Download.
    var approximateSizeMB: Int { get }
    /// Grobe Bounding-Box, mit der `ContentView.offlineGraphCandidatePaths` Regionen aussortiert,
    /// die Start/Ziel offensichtlich nicht abdecken können, bevor deren (bei großen Ländern sehr
    /// große) Wege-Graph überhaupt geladen wird - s. `RegionBoundingBox`.
    var boundingBox: RegionBoundingBox { get }
}

/// Bei jeder inkompatiblen Änderung am `.sqlite`-Binärformat (siehe `Scripts/build_way_graph.py`)
/// hochzählen - bereits heruntergeladene Graphen im alten Format würden sonst mit falscher
/// Byte-Schrittweite fehlinterpretiert statt sauber neu heruntergeladen zu werden. Auch bei reinen
/// Gewichtungs-Änderungen ohne Format-Bruch hochzählen (die App hat sonst keine Möglichkeit zu
/// erkennen, dass sich die Zahlenwerte in einer bereits heruntergeladenen Datei geändert haben).
/// Freistehende Konstante (nicht in `WayGraphStore` selbst), damit alle Regionstypen (Bundesland,
/// EuropaLand, ...) dieselbe Versionsprüfung teilen, obwohl sie eigene generische Instanzen von
/// `WayGraphStore` sind. `nonisolated(unsafe)`, da das Projekt standardmäßig auf MainActor
/// isoliert (`-default-isolation=MainActor`) - `WayGraphStore` selbst ist aber bewusst
/// `nonisolated` (s. u.) und liest diese Konstante, was ohne diese Annotation einen
/// Compiler-Fehler gäbe. Sicher, weil unveränderliche `Int`-Konstante (kein echtes Race möglich).
private nonisolated(unsafe) let wayGraphFormatVersion = 7

/// Bundesländer, für die ein Wege-Graph heruntergeladen werden kann. `rawValue` entspricht dem
/// Geofabrik-Bezeichner (download.geofabrik.de/europe/germany/<rawValue>-latest.osm.pbf).
nonisolated enum Bundesland: String, CaseIterable, Identifiable, DownloadableRegion {
    case badenWuerttemberg = "baden-wuerttemberg"
    case bayern
    case berlin
    case brandenburg
    case bremen
    case hamburg
    case hessen
    case mecklenburgVorpommern = "mecklenburg-vorpommern"
    case niedersachsen
    case nordrheinWestfalen = "nordrhein-westfalen"
    case rheinlandPfalz = "rheinland-pfalz"
    case saarland
    case sachsen
    case sachsenAnhalt = "sachsen-anhalt"
    case schleswigHolstein = "schleswig-holstein"
    case thueringen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .badenWuerttemberg: return "Baden-Württemberg"
        case .bayern: return "Bayern"
        case .berlin: return "Berlin"
        case .brandenburg: return "Brandenburg"
        case .bremen: return "Bremen"
        case .hamburg: return "Hamburg"
        case .hessen: return "Hessen"
        case .mecklenburgVorpommern: return "Mecklenburg-Vorpommern"
        case .niedersachsen: return "Niedersachsen"
        case .nordrheinWestfalen: return "Nordrhein-Westfalen"
        case .rheinlandPfalz: return "Rheinland-Pfalz"
        case .saarland: return "Saarland"
        case .sachsen: return "Sachsen"
        case .sachsenAnhalt: return "Sachsen-Anhalt"
        case .schleswigHolstein: return "Schleswig-Holstein"
        case .thueringen: return "Thüringen"
        }
    }

    var boundingBox: RegionBoundingBox {
        switch self {
        case .badenWuerttemberg:
            return RegionBoundingBox(minLat: 47.53, maxLat: 49.79, minLon: 7.51, maxLon: 10.50)
        case .bayern:
            return RegionBoundingBox(minLat: 47.27, maxLat: 50.56, minLon: 8.98, maxLon: 13.84)
        case .berlin:
            return RegionBoundingBox(minLat: 52.34, maxLat: 52.68, minLon: 13.09, maxLon: 13.76)
        case .brandenburg:
            return RegionBoundingBox(minLat: 51.36, maxLat: 53.56, minLon: 11.27, maxLon: 14.77)
        case .bremen:
            return RegionBoundingBox(minLat: 53.01, maxLat: 53.61, minLon: 8.48, maxLon: 8.99)
        case .hamburg:
            return RegionBoundingBox(minLat: 53.39, maxLat: 53.75, minLon: 8.48, maxLon: 10.33)
        case .hessen:
            return RegionBoundingBox(minLat: 49.39, maxLat: 51.66, minLon: 7.77, maxLon: 10.24)
        case .mecklenburgVorpommern:
            return RegionBoundingBox(minLat: 53.05, maxLat: 54.68, minLon: 10.59, maxLon: 14.41)
        case .niedersachsen:
            return RegionBoundingBox(minLat: 51.29, maxLat: 53.89, minLon: 6.65, maxLon: 11.60)
        case .nordrheinWestfalen:
            return RegionBoundingBox(minLat: 50.32, maxLat: 52.53, minLon: 5.87, maxLon: 9.46)
        case .rheinlandPfalz:
            return RegionBoundingBox(minLat: 48.97, maxLat: 50.94, minLon: 6.11, maxLon: 8.51)
        case .saarland:
            return RegionBoundingBox(minLat: 49.11, maxLat: 49.64, minLon: 6.36, maxLon: 7.41)
        case .sachsen:
            return RegionBoundingBox(minLat: 50.17, maxLat: 51.68, minLon: 11.87, maxLon: 15.04)
        case .sachsenAnhalt:
            return RegionBoundingBox(minLat: 50.94, maxLat: 53.04, minLon: 10.56, maxLon: 13.19)
        case .schleswigHolstein:
            return RegionBoundingBox(minLat: 53.36, maxLat: 55.06, minLon: 7.86, maxLon: 11.32)
        case .thueringen:
            return RegionBoundingBox(minLat: 50.20, maxLat: 51.65, minLon: 9.88, maxLon: 12.65)
        }
    }
}

/// Weitere europäische Länder außerhalb Deutschlands, für die ein Wege-Graph heruntergeladen werden
/// kann - bisher Niederlande (Anlass: Rotterdam-Reise 2026-07-27), Polen, Schweden, Dänemark,
/// Belgien, Luxemburg, Schweiz, Österreich, Tschechien, Slowakei und Albanien (s. ROADMAP.md). Eigener Typ
/// statt eines Falls in `Bundesland`, weil es Länder statt Bundesländer sind (andere Ebene) und
/// die Einstellungen sie in einer eigenen Liste ("Offline-Karten Europa") getrennt von den
/// deutschen Bundesländern anzeigen. Fallnamen bewusst auf Englisch (wie bei Geofabrik/den
/// Release-Asset-Dateinamen, z. B. `netherlands_ways.sqlite`) statt Deutsch wie bei `Bundesland` -
/// dort passt der deutsche Fallname zufällig zum Geofabrik-Bezeichner
/// (download.geofabrik.de/europe/germany/<bundesland>), hier nicht
/// (download.geofabrik.de/europe/<land-englisch>). `displayName` liefert trotzdem die deutsche
/// UI-Bezeichnung.
///
/// Sonderfall `sanMarino`/`vaticanCity`: Beide haben bei Geofabrik keinen eigenen Extrakt (in
/// `italy.osm.pbf` enthalten) - stattdessen per `Scripts/extract_micro_country.py` (eigener
/// Ersatz für "osmium extract --polygon", da osmium-tool auf dem Baurechner nicht installiert
/// ist, nur die Python-Bindings) mit dem echten Verwaltungsgrenz-Polygon (von Nominatim, s.
/// `Scripts/data/<land>-boundary.json`) aus dem Italien-Gesamtextrakt herausgeschnitten - nicht
/// nur eine Bounding-Box, damit an der Grenze nicht unnötig viel italienisches Straßennetz
/// mitgenommen wird. Kein eigener Release-Tag nötig, beide sind wie Andorra/Liechtenstein/Monaco
/// klein genug für `way-graphs-eu-v1`.
nonisolated enum EuropaLand: String, CaseIterable, Identifiable, DownloadableRegion {
    case albania
    case andorra
    case austria
    case belgium
    case bosniaHerzegovina = "bosnia-herzegovina"
    case bulgaria
    case croatia
    case cyprus
    case czechia
    case denmark
    case estonia
    case finland
    case greece
    case hungary
    case iceland
    case ireland
    case kosovo
    case latvia
    case liechtenstein
    case lithuania
    case luxembourg
    case macedonia
    case malta
    case monaco
    case montenegro
    case netherlands
    case poland
    case portugal
    case romania
    case sanMarino = "san-marino"
    case serbia
    case slovakia
    case slovenia
    case sweden
    case switzerland
    case vaticanCity = "vatican"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .albania: return "Albanien"
        case .andorra: return "Andorra"
        case .austria: return "Österreich"
        case .belgium: return "Belgien"
        case .bosniaHerzegovina: return "Bosnien und Herzegowina"
        case .bulgaria: return "Bulgarien"
        case .croatia: return "Kroatien"
        case .cyprus: return "Zypern"
        case .czechia: return "Tschechien"
        case .denmark: return "Dänemark"
        case .estonia: return "Estland"
        case .finland: return "Finnland"
        case .greece: return "Griechenland"
        case .hungary: return "Ungarn"
        case .iceland: return "Island"
        case .ireland: return "Irland"
        case .kosovo: return "Kosovo"
        case .latvia: return "Lettland"
        case .liechtenstein: return "Liechtenstein"
        case .lithuania: return "Litauen"
        case .luxembourg: return "Luxemburg"
        case .macedonia: return "Nordmazedonien"
        case .malta: return "Malta"
        case .monaco: return "Monaco"
        case .montenegro: return "Montenegro"
        case .netherlands: return "Niederlande"
        case .poland: return "Polen"
        case .portugal: return "Portugal"
        case .romania: return "Rumänien"
        case .sanMarino: return "San Marino"
        case .serbia: return "Serbien"
        case .slovakia: return "Slowakei"
        case .slovenia: return "Slowenien"
        case .sweden: return "Schweden"
        case .switzerland: return "Schweiz"
        case .vaticanCity: return "Vatikanstadt"
        }
    }

    var boundingBox: RegionBoundingBox {
        switch self {
        case .albania:
            return RegionBoundingBox(minLat: 39.63, maxLat: 42.66, minLon: 18.90, maxLon: 21.06)
        case .andorra:
            return RegionBoundingBox(minLat: 42.43, maxLat: 42.66, minLon: 1.41, maxLon: 1.79)
        case .austria:
            return RegionBoundingBox(minLat: 46.37, maxLat: 49.02, minLon: 9.53, maxLon: 17.16)
        case .belgium:
            return RegionBoundingBox(minLat: 49.49, maxLat: 51.60, minLon: 2.34, maxLon: 6.41)
        case .bosniaHerzegovina:
            return RegionBoundingBox(minLat: 42.55, maxLat: 45.28, minLon: 15.72, maxLon: 19.63)
        case .bulgaria:
            return RegionBoundingBox(minLat: 41.23, maxLat: 44.22, minLon: 22.35, maxLon: 29.19)
        case .croatia:
            return RegionBoundingBox(minLat: 42.16, maxLat: 46.56, minLon: 13.09, maxLon: 19.46)
        case .cyprus:
            return RegionBoundingBox(minLat: 34.23, maxLat: 36.00, minLon: 31.95, maxLon: 34.96)
        case .czechia:
            return RegionBoundingBox(minLat: 48.54, maxLat: 51.06, minLon: 12.08, maxLon: 18.86)
        case .denmark:
            return RegionBoundingBox(minLat: 54.44, maxLat: 58.06, minLon: 7.70, maxLon: 15.65)
        case .estonia:
            return RegionBoundingBox(minLat: 57.50, maxLat: 60.00, minLon: 20.85, maxLon: 28.21)
        case .finland:
            return RegionBoundingBox(minLat: 59.29, maxLat: 70.10, minLon: 19.02, maxLon: 31.62)
        case .greece:
            return RegionBoundingBox(minLat: 34.59, maxLat: 41.75, minLon: 18.97, maxLon: 29.66)
        case .hungary:
            return RegionBoundingBox(minLat: 45.73, maxLat: 48.59, minLon: 16.11, maxLon: 22.91)
        case .iceland:
            return RegionBoundingBox(minLat: 62.85, maxLat: 67.50, minLon: -25.74, maxLon: -12.42)
        case .ireland:
            return RegionBoundingBox(minLat: 47.96, maxLat: 56.87, minLon: -16.31, maxLon: -5.06)
        case .kosovo:
            return RegionBoundingBox(minLat: 41.85, maxLat: 43.28, minLon: 20.01, maxLon: 21.79)
        case .latvia:
            return RegionBoundingBox(minLat: 55.66, maxLat: 58.09, minLon: 19.73, maxLon: 28.26)
        case .liechtenstein:
            return RegionBoundingBox(minLat: 47.05, maxLat: 47.27, minLon: 9.47, maxLon: 9.64)
        case .lithuania:
            return RegionBoundingBox(minLat: 53.89, maxLat: 56.45, minLon: 20.62, maxLon: 26.84)
        case .luxembourg:
            return RegionBoundingBox(minLat: 49.45, maxLat: 50.18, minLon: 5.73, maxLon: 6.53)
        case .macedonia:
            return RegionBoundingBox(minLat: 40.85, maxLat: 42.38, minLon: 20.45, maxLon: 23.04)
        case .malta:
            return RegionBoundingBox(minLat: 35.52, maxLat: 36.33, minLon: 13.82, maxLon: 14.86)
        case .monaco:
            return RegionBoundingBox(minLat: 43.48, maxLat: 43.75, minLon: 7.41, maxLon: 7.60)
        case .montenegro:
            return RegionBoundingBox(minLat: 41.62, maxLat: 43.56, minLon: 18.17, maxLon: 20.36)
        case .netherlands:
            return RegionBoundingBox(minLat: 50.75, maxLat: 53.55, minLon: 3.36, maxLon: 7.23)
        case .poland:
            return RegionBoundingBox(minLat: 49.00, maxLat: 54.84, minLon: 14.12, maxLon: 24.15)
        case .portugal:
            // Umfasst neben dem Festland auch Azoren und Madeira (Geofabrik-Extrakt deckt beide
            // Archipele mit ab), deshalb deutlich breiter als das Festland allein.
            return RegionBoundingBox(minLat: 29.25, maxLat: 42.16, minLon: -33.62, maxLon: -6.18)
        case .romania:
            return RegionBoundingBox(minLat: 43.61, maxLat: 48.27, minLon: 20.24, maxLon: 30.28)
        case .sanMarino:
            return RegionBoundingBox(minLat: 43.89, maxLat: 43.99, minLon: 12.40, maxLon: 12.52)
        case .serbia:
            return RegionBoundingBox(minLat: 42.23, maxLat: 46.19, minLon: 18.81, maxLon: 23.01)
        case .slovakia:
            return RegionBoundingBox(minLat: 47.73, maxLat: 49.62, minLon: 16.83, maxLon: 22.57)
        case .slovenia:
            return RegionBoundingBox(minLat: 45.42, maxLat: 46.88, minLon: 13.31, maxLon: 16.60)
        case .sweden:
            return RegionBoundingBox(minLat: 55.34, maxLat: 69.06, minLon: 11.11, maxLon: 24.17)
        case .switzerland:
            return RegionBoundingBox(minLat: 45.82, maxLat: 47.81, minLon: 5.95, maxLon: 10.50)
        case .vaticanCity:
            return RegionBoundingBox(minLat: 41.90, maxLat: 41.91, minLon: 12.45, maxLon: 12.46)
        }
    }
}

/// Französische Regionen (Einteilung vor der 2016er-Gebietsreform, wie von Geofabrik verwendet:
/// download.geofabrik.de/europe/france/<region>), für die ein Wege-Graph heruntergeladen werden
/// kann - eigener Typ statt eines Falls in `EuropaLand` (analog zu `Bundesland` vs. `EuropaLand`),
/// weil Frankreich als Ganzes für den Wege-Graph-Bau zu groß ist (4,7 GB PBF, zweimal am
/// Speicherdruck des 16-GB-Baurechners gescheitert, s. ROADMAP.md "Frankreich als neuntes Land").
/// Die 21 Regionen liegen zwischen 32 MB (Corse) und 500 MB (Rhône-Alpes) - dieselbe
/// Größenordnung, die für Bundesländer/kleinere Länder bereits zuverlässig funktioniert.
/// Kuratierte Routen (`france.sqlite`) sind davon unabhängig bereits vollständig für ganz
/// Frankreich vorhanden (kein Speicherproblem bei der leichtgewichtigen Routen-Extraktion).
nonisolated enum FranceRegion: String, CaseIterable, Identifiable, DownloadableRegion {
    case alsace
    case aquitaine
    case auvergne
    case basseNormandie = "basse-normandie"
    case bourgogne
    case bretagne
    case centre
    case champagneArdenne = "champagne-ardenne"
    case corse
    case francheComte = "franche-comte"
    case hauteNormandie = "haute-normandie"
    case ileDeFrance = "ile-de-france"
    case languedocRoussillon = "languedoc-roussillon"
    case limousin
    case lorraine
    case midiPyrenees = "midi-pyrenees"
    case nordPasDeCalais = "nord-pas-de-calais"
    case paysDeLaLoire = "pays-de-la-loire"
    case picardie
    case poitouCharentes = "poitou-charentes"
    case provenceAlpesCoteDAzur = "provence-alpes-cote-d-azur"
    case rhoneAlpes = "rhone-alpes"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .alsace: return "Elsass"
        case .aquitaine: return "Aquitanien"
        case .auvergne: return "Auvergne"
        case .basseNormandie: return "Basse-Normandie"
        case .bourgogne: return "Burgund"
        case .bretagne: return "Bretagne"
        case .centre: return "Centre-Val de Loire"
        case .champagneArdenne: return "Champagne-Ardenne"
        case .corse: return "Korsika"
        case .francheComte: return "Franche-Comté"
        case .hauteNormandie: return "Haute-Normandie"
        case .ileDeFrance: return "Île-de-France"
        case .languedocRoussillon: return "Languedoc-Roussillon"
        case .limousin: return "Limousin"
        case .lorraine: return "Lothringen"
        case .midiPyrenees: return "Midi-Pyrénées"
        case .nordPasDeCalais: return "Nord-Pas-de-Calais"
        case .paysDeLaLoire: return "Pays de la Loire"
        case .picardie: return "Picardie"
        case .poitouCharentes: return "Poitou-Charentes"
        case .provenceAlpesCoteDAzur: return "Provence-Alpes-Côte d'Azur"
        case .rhoneAlpes: return "Rhône-Alpes"
        }
    }

    /// Aus den PBF-Headern per Range-Request ermittelt (`osmium.io.Reader(...).header().box()`
    /// auf die ersten 500 KB jeder Datei - der Header-Block liegt am Dateianfang, ein Download
    /// der kompletten, teils hunderte MB großen Dateien war dafür nicht nötig).
    var boundingBox: RegionBoundingBox {
        switch self {
        case .alsace:
            return RegionBoundingBox(minLat: 47.38, maxLat: 49.21, minLon: 6.84, maxLon: 8.31)
        case .aquitaine:
            return RegionBoundingBox(minLat: 42.61, maxLat: 45.72, minLon: -1.84, maxLon: 1.45)
        case .auvergne:
            return RegionBoundingBox(minLat: 44.61, maxLat: 46.81, minLon: 2.06, maxLon: 4.49)
        case .basseNormandie:
            return RegionBoundingBox(minLat: 48.18, maxLat: 49.89, minLon: -2.09, maxLon: 0.98)
        case .bourgogne:
            return RegionBoundingBox(minLat: 46.15, maxLat: 48.40, minLon: 2.84, maxLon: 5.52)
        case .bretagne:
            return RegionBoundingBox(minLat: 47.08, maxLat: 49.41, minLon: -5.88, maxLon: -1.01)
        case .centre:
            return RegionBoundingBox(minLat: 46.35, maxLat: 48.94, minLon: 0.05, maxLon: 3.13)
        case .champagneArdenne:
            return RegionBoundingBox(minLat: 47.58, maxLat: 50.22, minLon: 3.38, maxLon: 5.89)
        case .corse:
            return RegionBoundingBox(minLat: 41.31, maxLat: 43.17, minLon: 8.32, maxLon: 9.75)
        case .francheComte:
            return RegionBoundingBox(minLat: 46.26, maxLat: 48.03, minLon: 5.25, maxLon: 7.14)
        case .hauteNormandie:
            return RegionBoundingBox(minLat: 48.67, maxLat: 50.09, minLon: 0.01, maxLon: 1.80)
        case .ileDeFrance:
            return RegionBoundingBox(minLat: 48.12, maxLat: 49.24, minLon: 1.45, maxLon: 3.56)
        case .languedocRoussillon:
            return RegionBoundingBox(minLat: 42.17, maxLat: 44.98, minLon: 1.69, maxLon: 4.85)
        case .limousin:
            return RegionBoundingBox(minLat: 44.92, maxLat: 46.46, minLon: 0.63, maxLon: 2.61)
        case .lorraine:
            return RegionBoundingBox(minLat: 47.81, maxLat: 49.62, minLon: 4.89, maxLon: 7.69)
        case .midiPyrenees:
            return RegionBoundingBox(minLat: 42.53, maxLat: 45.05, minLon: -0.33, maxLon: 3.45)
        case .nordPasDeCalais:
            return RegionBoundingBox(minLat: 49.97, maxLat: 51.28, minLon: 1.28, maxLon: 4.27)
        case .paysDeLaLoire:
            return RegionBoundingBox(minLat: 46.22, maxLat: 48.57, minLon: -2.67, maxLon: 0.92)
        case .picardie:
            return RegionBoundingBox(minLat: 48.84, maxLat: 50.37, minLon: 1.36, maxLon: 4.26)
        case .poitouCharentes:
            return RegionBoundingBox(minLat: 45.09, maxLat: 47.18, minLon: -1.90, maxLon: 1.21)
        case .provenceAlpesCoteDAzur:
            return RegionBoundingBox(minLat: 42.32, maxLat: 45.13, minLon: 4.14, maxLon: 7.89)
        case .rhoneAlpes:
            return RegionBoundingBox(minLat: 44.11, maxLat: 46.57, minLon: 3.69, maxLon: 7.28)
        }
    }
}

/// Italienische Makro-Regionen (Geofabrik-Einteilung: download.geofabrik.de/europe/italy/<region>),
/// für die ein Wege-Graph heruntergeladen werden kann - eigener Typ statt eines Falls in
/// `EuropaLand` (analog zu `FranceRegion`), weil Italien als Ganzes für einen einzelnen
/// Wege-Graphen zu groß ist: 2,06 GB PBF ergaben einen 2,67 GB großen Wege-Graphen, der
/// GitHubs 2-GiB-Asset-Limit überschritt (Upload schlug fehl, s. ROADMAP.md "Italien als
/// vierzehntes Land"). Nur 5 Makro-Regionen statt vieler kleiner Regionen wie bei Frankreich -
/// Geofabrik bietet für Italien keine feinere Einteilung an. Jede liegt zwischen 203 MB (Isole)
/// und 592 MB (Nord-Est), deutlich unter dem Limit. Kuratierte Routen (`italy.sqlite`) sind
/// davon unabhängig bereits vollständig für ganz Italien vorhanden.
nonisolated enum ItalyRegion: String, CaseIterable, Identifiable, DownloadableRegion {
    case centro
    case isole
    case nordEst = "nord-est"
    case nordOvest = "nord-ovest"
    case sud

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .centro: return "Mittelitalien"
        case .isole: return "Inseln (Sizilien, Sardinien)"
        case .nordEst: return "Nordostitalien"
        case .nordOvest: return "Nordwestitalien"
        case .sud: return "Süditalien"
        }
    }

    /// Aus den PBF-Headern per Range-Request ermittelt (analog `FranceRegion.boundingBox`).
    var boundingBox: RegionBoundingBox {
        switch self {
        case .centro:
            return RegionBoundingBox(minLat: 40.21, maxLat: 44.48, minLon: 8.61, maxLon: 14.98)
        case .isole:
            return RegionBoundingBox(minLat: 34.38, maxLat: 41.52, minLon: 7.42, maxLon: 15.71)
        case .nordEst:
            return RegionBoundingBox(minLat: 43.73, maxLat: 47.31, minLon: 9.20, maxLon: 14.83)
        case .nordOvest:
            return RegionBoundingBox(minLat: 43.44, maxLat: 47.06, minLon: 5.53, maxLon: 11.43)
        case .sud:
            return RegionBoundingBox(minLat: 37.80, maxLat: 42.91, minLon: 13.00, maxLon: 20.00)
        }
    }
}

/// Spanische Regionen (autonome Gemeinschaften, Geofabrik-Einteilung:
/// download.geofabrik.de/europe/spain/<region>), für die ein Wege-Graph heruntergeladen werden
/// kann - eigener Typ statt eines Falls in `EuropaLand` (analog zu `FranceRegion`/`ItalyRegion`).
/// Anders als bei Frankreich/Italien **vorsorglich** aufgeteilt, nicht erst nach einem
/// gescheiterten Gesamt-Versuch: Spaniens PBF (1,4 GB) läge zwar unter Polens erfolgreich
/// gebauter Größe, aber Italiens Muster (Ausgabe teils größer als PBF durch dichte Kartierung,
/// s. ROADMAP.md "Italien als vierzehntes Land") machte das Risiko real genug, direkt
/// aufzuteilen statt eventuell wieder stundenlang umsonst zu bauen. Geofabrik bietet 18
/// Regionen (16 "echte" + die Exklaven Ceuta/Melilla), zwischen ~0 MB (Exklaven) und 254 MB
/// (Cataluña) - deutlich kleiner als selbst Italiens Regionen. Kuratierte Routen
/// (`spain.sqlite`) sind davon unabhängig bereits vollständig für ganz Spanien vorhanden.
nonisolated enum SpainRegion: String, CaseIterable, Identifiable, DownloadableRegion {
    case andalucia
    case aragon
    case asturias
    case cantabria
    case castillaLaMancha = "castilla-la-mancha"
    case castillaYLeon = "castilla-y-leon"
    case cataluna
    case ceuta
    case extremadura
    case galicia
    case islasBaleares = "islas-baleares"
    case laRioja = "la-rioja"
    case madrid
    case melilla
    case murcia
    case navarra
    case paisVasco = "pais-vasco"
    case valencia

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .andalucia: return "Andalusien"
        case .aragon: return "Aragonien"
        case .asturias: return "Asturien"
        case .cantabria: return "Kantabrien"
        case .castillaLaMancha: return "Kastilien-La Mancha"
        case .castillaYLeon: return "Kastilien und León"
        case .cataluna: return "Katalonien"
        case .ceuta: return "Ceuta"
        case .extremadura: return "Extremadura"
        case .galicia: return "Galicien"
        case .islasBaleares: return "Balearen"
        case .laRioja: return "La Rioja"
        case .madrid: return "Madrid"
        case .melilla: return "Melilla"
        case .murcia: return "Murcia"
        case .navarra: return "Navarra"
        case .paisVasco: return "Baskenland"
        case .valencia: return "Valencia"
        }
    }

    /// Aus den PBF-Headern per Range-Request ermittelt (analog `FranceRegion.boundingBox`).
    var boundingBox: RegionBoundingBox {
        switch self {
        case .andalucia:
            return RegionBoundingBox(minLat: 35.71, maxLat: 38.73, minLon: -7.55, maxLon: -1.33)
        case .aragon:
            return RegionBoundingBox(minLat: 39.84, maxLat: 42.93, minLon: -2.18, maxLon: 0.77)
        case .asturias:
            return RegionBoundingBox(minLat: 42.88, maxLat: 44.03, minLon: -7.20, maxLon: -4.39)
        case .cantabria:
            return RegionBoundingBox(minLat: 42.75, maxLat: 43.89, minLon: -4.86, maxLon: -3.14)
        case .castillaLaMancha:
            return RegionBoundingBox(minLat: 38.02, maxLat: 41.33, minLon: -5.41, maxLon: -0.91)
        case .castillaYLeon:
            return RegionBoundingBox(minLat: 40.08, maxLat: 43.24, minLon: -7.08, maxLon: -1.77)
        case .cataluna:
            return RegionBoundingBox(minLat: 40.21, maxLat: 42.92, minLon: 0.16, maxLon: 4.17)
        case .ceuta:
            return RegionBoundingBox(minLat: 35.87, maxLat: 35.96, minLon: -5.39, maxLon: -5.26)
        case .extremadura:
            return RegionBoundingBox(minLat: 37.94, maxLat: 40.49, minLon: -7.64, maxLon: -4.64)
        case .galicia:
            return RegionBoundingBox(minLat: 41.77, maxLat: 44.31, minLon: -10.36, maxLon: -6.73)
        case .islasBaleares:
            return RegionBoundingBox(minLat: 38.06, maxLat: 40.71, minLon: 0.62, maxLon: 4.94)
        case .laRioja:
            return RegionBoundingBox(minLat: 41.91, maxLat: 42.65, minLon: -3.14, maxLon: -1.67)
        case .madrid:
            return RegionBoundingBox(minLat: 39.88, maxLat: 41.17, minLon: -4.59, maxLon: -3.05)
        case .melilla:
            return RegionBoundingBox(minLat: 35.26, maxLat: 35.33, minLon: -2.98, maxLon: -2.91)
        case .murcia:
            return RegionBoundingBox(minLat: 37.11, maxLat: 38.76, minLon: -2.35, maxLon: -0.25)
        case .navarra:
            return RegionBoundingBox(minLat: 41.91, maxLat: 43.37, minLon: -2.50, maxLon: -0.63)
        case .paisVasco:
            return RegionBoundingBox(minLat: 42.47, maxLat: 43.75, minLon: -3.45, maxLon: -1.66)
        case .valencia:
            return RegionBoundingBox(minLat: 37.84, maxLat: 40.79, minLon: -1.53, maxLon: 1.69)
        }
    }
}

/// Norwegische Regionen (Geofabrik-Einteilung: download.geofabrik.de/europe/norway/<region>), für
/// die ein Wege-Graph heruntergeladen werden kann - eigener Typ statt eines Falls in `EuropaLand`
/// (analog zu `FranceRegion`/`ItalyRegion`/`SpainRegion`). Wie bei Spanien **vorsorglich**
/// aufgeteilt statt erst nach einem gescheiterten Gesamt-Versuch: Norwegens PBF (~1,37 GB) läge
/// zwar in der Größenordnung von Polen/Schweden (beide erfolgreich als Einzeldatei gebaut), aber
/// Italiens Muster (Ausgabe teils größer als PBF durch dichte Kartierung, s. ROADMAP.md "Italien
/// als vierzehntes Land") macht das Risiko real genug, direkt aufzuteilen. Geofabrik bietet 5
/// "echte" Regionen (Fylker-Gruppierungen) plus der Exklave Svalbard/Jan Mayen, zwischen ~1 MB
/// (Svalbard/Jan Mayen) und 536 MB (Østlandet, Oslo-Region - dichter kartiert als der Rest
/// Norwegens, allein deshalb schon größer als der gesamte Norden Nord-Norge) - analog Ceuta/
/// Melilla bei Spanien wird die winzige Exklave mit aufgenommen statt gesondert behandelt.
/// Kuratierte Routen (`norway.sqlite`) sind davon unabhängig für ganz Norwegen extrahiert.
nonisolated enum NorwayRegion: String, CaseIterable, Identifiable, DownloadableRegion {
    case nordNorge = "nord-norge"
    case ostlandet
    case sorlandet
    case svalbardJanMayen = "svalbard-janmayen"
    case trondelag
    case vestlandet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nordNorge: return "Nord-Norge"
        case .ostlandet: return "Østlandet"
        case .sorlandet: return "Sørlandet"
        case .svalbardJanMayen: return "Svalbard und Jan Mayen"
        case .trondelag: return "Trøndelag"
        case .vestlandet: return "Vestlandet"
        }
    }

    /// Aus den PBF-Headern per HTTP-Range-Request ermittelt (analog `SpainRegion.boundingBox`).
    var boundingBox: RegionBoundingBox {
        switch self {
        case .nordNorge:
            return RegionBoundingBox(minLat: 64.94, maxLat: 72.41, minLon: 7.84, maxLon: 40.07)
        case .ostlandet:
            return RegionBoundingBox(minLat: 58.60, maxLat: 62.70, minLon: 7.10, maxLon: 14.40)
        case .sorlandet:
            return RegionBoundingBox(minLat: 57.58, maxLat: 59.67, minLon: 5.70, maxLon: 10.59)
        case .svalbardJanMayen:
            return RegionBoundingBox(minLat: 70.15, maxLat: 81.11, minLon: -11.37, maxLon: 35.35)
        case .trondelag:
            return RegionBoundingBox(minLat: 62.26, maxLat: 65.95, minLon: 5.79, maxLon: 14.40)
        case .vestlandet:
            return RegionBoundingBox(minLat: 56.39, maxLat: 65.12, minLon: 2.33, maxLon: 9.37)
        }
    }
}

/// Großbritannische Regionen (Geofabrik-Einteilung:
/// download.geofabrik.de/europe/united-kingdom/england/<county>, .../scotland, .../wales), für die
/// ein Wege-Graph heruntergeladen werden kann - eigener Typ statt eines Falls in `EuropaLand`
/// (analog zu `FranceRegion`/`ItalyRegion`/`SpainRegion`/`NorwayRegion`). Geofabrik bot
/// England/Schottland/Wales lange nur als Gesamtdatei an (s. ROADMAP.md "Vermutlich Regionen-Split
/// nötig") - inzwischen (Umbenennung von "great-britain" zu "united-kingdom") liefert Geofabrik
/// England zusätzlich granular in 47 Grafschaften (Counties), Schottland und Wales bleiben je eine
/// Datei (325 MB bzw. 147 MB - beide klein genug für eine Einzeldatei). England allein (1,69 GB
/// PBF, sehr dicht kartiert) wäre dagegen ein hohes Risiko fürs GitHub-2-GiB-Limit (Italiens
/// Lehre: Ausgabe teils größer als PBF, s. ROADMAP.md "Italien als vierzehntes Land") - deshalb
/// durchgängig auf Grafschafts-Ebene aufgeteilt, keine gröbere Zwischenstufe verfügbar. Insgesamt
/// 49 Regionen (47 Grafschaften + Schottland + Wales); tatsächliche Wege-Graph-Größen nach dem
/// Build zwischen 2 MB (Rutland) und 282 MB (Schottland). Alle 49 liefen im ersten Durchlauf glatt
/// durch (~34 Min Gesamtbauzeit). Kuratierte Routen (`great-britain.sqlite`) sind davon unabhängig
/// für ganz
/// Großbritannien (ohne Nordirland - das deckt bereits die bestehende Irland-Datenbank ab) aus dem
/// `great-britain`-Gesamtextrakt (nicht `united-kingdom`, der zusätzlich Nordirland enthält)
/// extrahiert.
nonisolated enum GreatBritainRegion: String, CaseIterable, Identifiable, DownloadableRegion {
    case bedfordshire
    case berkshire
    case bristol
    case buckinghamshire
    case cambridgeshire
    case cheshire
    case cornwall
    case cumbria
    case derbyshire
    case devon
    case dorset
    case durham
    case eastSussex = "east-sussex"
    case eastYorkshireWithHull = "east-yorkshire-with-hull"
    case essex
    case gloucestershire
    case greaterLondon = "greater-london"
    case greaterManchester = "greater-manchester"
    case hampshire
    case herefordshire
    case hertfordshire
    case isleOfWight = "isle-of-wight"
    case kent
    case lancashire
    case leicestershire
    case lincolnshire
    case merseyside
    case norfolk
    case northYorkshire = "north-yorkshire"
    case northamptonshire
    case northumberland
    case nottinghamshire
    case oxfordshire
    case rutland
    case shropshire
    case somerset
    case southYorkshire = "south-yorkshire"
    case staffordshire
    case suffolk
    case surrey
    case tyneAndWear = "tyne-and-wear"
    case warwickshire
    case westMidlands = "west-midlands"
    case westSussex = "west-sussex"
    case westYorkshire = "west-yorkshire"
    case wiltshire
    case worcestershire
    case scotland
    case wales

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bedfordshire: return "Bedfordshire"
        case .berkshire: return "Berkshire"
        case .bristol: return "Bristol"
        case .buckinghamshire: return "Buckinghamshire"
        case .cambridgeshire: return "Cambridgeshire"
        case .cheshire: return "Cheshire"
        case .cornwall: return "Cornwall"
        case .cumbria: return "Cumbria"
        case .derbyshire: return "Derbyshire"
        case .devon: return "Devon"
        case .dorset: return "Dorset"
        case .durham: return "Durham"
        case .eastSussex: return "East Sussex"
        case .eastYorkshireWithHull: return "East Yorkshire mit Hull"
        case .essex: return "Essex"
        case .gloucestershire: return "Gloucestershire"
        case .greaterLondon: return "Greater London"
        case .greaterManchester: return "Greater Manchester"
        case .hampshire: return "Hampshire"
        case .herefordshire: return "Herefordshire"
        case .hertfordshire: return "Hertfordshire"
        case .isleOfWight: return "Isle of Wight"
        case .kent: return "Kent"
        case .lancashire: return "Lancashire"
        case .leicestershire: return "Leicestershire"
        case .lincolnshire: return "Lincolnshire"
        case .merseyside: return "Merseyside"
        case .norfolk: return "Norfolk"
        case .northYorkshire: return "North Yorkshire"
        case .northamptonshire: return "Northamptonshire"
        case .northumberland: return "Northumberland"
        case .nottinghamshire: return "Nottinghamshire"
        case .oxfordshire: return "Oxfordshire"
        case .rutland: return "Rutland"
        case .shropshire: return "Shropshire"
        case .somerset: return "Somerset"
        case .southYorkshire: return "South Yorkshire"
        case .staffordshire: return "Staffordshire"
        case .suffolk: return "Suffolk"
        case .surrey: return "Surrey"
        case .tyneAndWear: return "Tyne and Wear"
        case .warwickshire: return "Warwickshire"
        case .westMidlands: return "West Midlands"
        case .westSussex: return "West Sussex"
        case .westYorkshire: return "West Yorkshire"
        case .wiltshire: return "Wiltshire"
        case .worcestershire: return "Worcestershire"
        case .scotland: return "Schottland"
        case .wales: return "Wales"
        }
    }

    /// Aus den PBF-Headern per HTTP-Range-Request ermittelt (analog `SpainRegion.boundingBox`).
    var boundingBox: RegionBoundingBox {
        switch self {
        case .bedfordshire:
            return RegionBoundingBox(minLat: 51.80, maxLat: 52.32, minLon: -0.70, maxLon: -0.14)
        case .berkshire:
            return RegionBoundingBox(minLat: 51.33, maxLat: 51.58, minLon: -1.59, maxLon: -0.49)
        case .bristol:
            return RegionBoundingBox(minLat: 51.40, maxLat: 51.55, minLon: -2.73, maxLon: -2.51)
        case .buckinghamshire:
            return RegionBoundingBox(minLat: 51.49, maxLat: 52.20, minLon: -1.14, maxLon: -0.48)
        case .cambridgeshire:
            return RegionBoundingBox(minLat: 52.01, maxLat: 52.74, minLon: -0.50, maxLon: 0.52)
        case .cheshire:
            return RegionBoundingBox(minLat: 52.95, maxLat: 53.48, minLon: -3.13, maxLon: -1.97)
        case .cornwall:
            return RegionBoundingBox(minLat: 49.42, maxLat: 50.93, minLon: -6.85, maxLon: -4.15)
        case .cumbria:
            return RegionBoundingBox(minLat: 53.90, maxLat: 55.19, minLon: -3.91, maxLon: -2.16)
        case .derbyshire:
            return RegionBoundingBox(minLat: 52.70, maxLat: 53.54, minLon: -2.04, maxLon: -1.16)
        case .devon:
            return RegionBoundingBox(minLat: 50.11, maxLat: 51.31, minLon: -4.75, maxLon: -2.88)
        case .dorset:
            return RegionBoundingBox(minLat: 50.50, maxLat: 51.08, minLon: -2.96, maxLon: -1.68)
        case .durham:
            return RegionBoundingBox(minLat: 54.45, maxLat: 54.92, minLon: -2.36, maxLon: -1.10)
        case .eastSussex:
            return RegionBoundingBox(minLat: 50.70, maxLat: 51.15, minLon: -0.14, maxLon: 0.87)
        case .eastYorkshireWithHull:
            return RegionBoundingBox(minLat: 53.55, maxLat: 54.21, minLon: -1.11, maxLon: 0.49)
        case .essex:
            return RegionBoundingBox(minLat: 51.45, maxLat: 52.09, minLon: -0.02, maxLon: 1.31)
        case .gloucestershire:
            return RegionBoundingBox(minLat: 51.41, maxLat: 52.12, minLon: -2.71, maxLon: -1.61)
        case .greaterLondon:
            return RegionBoundingBox(minLat: 51.29, maxLat: 51.69, minLon: -0.51, maxLon: 0.34)
        case .greaterManchester:
            return RegionBoundingBox(minLat: 53.33, maxLat: 53.69, minLon: -2.73, maxLon: -1.91)
        case .hampshire:
            return RegionBoundingBox(minLat: 50.69, maxLat: 51.39, minLon: -1.96, maxLon: -0.73)
        case .herefordshire:
            return RegionBoundingBox(minLat: 51.83, maxLat: 52.40, minLon: -3.14, maxLon: -2.34)
        case .hertfordshire:
            return RegionBoundingBox(minLat: 51.60, maxLat: 52.08, minLon: -0.75, maxLon: 0.20)
        case .isleOfWight:
            return RegionBoundingBox(minLat: 50.51, maxLat: 50.80, minLon: -1.66, maxLon: -1.03)
        case .kent:
            return RegionBoundingBox(minLat: 50.81, maxLat: 51.50, minLon: 0.03, maxLon: 1.52)
        case .lancashire:
            return RegionBoundingBox(minLat: 53.48, maxLat: 54.25, minLon: -3.09, maxLon: -2.04)
        case .leicestershire:
            return RegionBoundingBox(minLat: 52.39, maxLat: 52.98, minLon: -1.60, maxLon: -0.66)
        case .lincolnshire:
            return RegionBoundingBox(minLat: 52.64, maxLat: 53.73, minLon: -0.95, maxLon: 0.49)
        case .merseyside:
            return RegionBoundingBox(minLat: 53.29, maxLat: 53.71, minLon: -3.34, maxLon: -2.58)
        case .norfolk:
            return RegionBoundingBox(minLat: 52.35, maxLat: 53.36, minLon: 0.15, maxLon: 1.99)
        case .northYorkshire:
            return RegionBoundingBox(minLat: 53.62, maxLat: 54.70, minLon: -2.57, maxLon: -0.04)
        case .northamptonshire:
            return RegionBoundingBox(minLat: 51.98, maxLat: 52.64, minLon: -1.33, maxLon: -0.34)
        case .northumberland:
            return RegionBoundingBox(minLat: 54.78, maxLat: 55.85, minLon: -2.69, maxLon: -1.22)
        case .nottinghamshire:
            return RegionBoundingBox(minLat: 52.78, maxLat: 53.50, minLon: -1.34, maxLon: -0.67)
        case .oxfordshire:
            return RegionBoundingBox(minLat: 51.46, maxLat: 52.17, minLon: -1.72, maxLon: -0.87)
        case .rutland:
            return RegionBoundingBox(minLat: 52.52, maxLat: 52.76, minLon: -0.82, maxLon: -0.43)
        case .shropshire:
            return RegionBoundingBox(minLat: 52.31, maxLat: 53.00, minLon: -3.24, maxLon: -2.23)
        case .somerset:
            return RegionBoundingBox(minLat: 50.82, maxLat: 51.50, minLon: -3.84, maxLon: -2.24)
        case .southYorkshire:
            return RegionBoundingBox(minLat: 53.30, maxLat: 53.66, minLon: -1.83, maxLon: -0.85)
        case .staffordshire:
            return RegionBoundingBox(minLat: 52.42, maxLat: 53.23, minLon: -2.47, maxLon: -1.58)
        case .suffolk:
            return RegionBoundingBox(minLat: 51.93, maxLat: 52.55, minLon: 0.34, maxLon: 1.76)
        case .surrey:
            return RegionBoundingBox(minLat: 51.07, maxLat: 51.47, minLon: -0.85, maxLon: 0.06)
        case .tyneAndWear:
            return RegionBoundingBox(minLat: 54.80, maxLat: 55.11, minLon: -1.85, maxLon: -1.26)
        case .warwickshire:
            return RegionBoundingBox(minLat: 51.95, maxLat: 52.69, minLon: -1.96, maxLon: -1.17)
        case .westMidlands:
            return RegionBoundingBox(minLat: 52.35, maxLat: 52.66, minLon: -2.21, maxLon: -1.42)
        case .westSussex:
            return RegionBoundingBox(minLat: 50.71, maxLat: 51.17, minLon: -0.96, maxLon: 0.04)
        case .westYorkshire:
            return RegionBoundingBox(minLat: 53.52, maxLat: 53.96, minLon: -2.18, maxLon: -1.20)
        case .wiltshire:
            return RegionBoundingBox(minLat: 50.95, maxLat: 51.71, minLon: -2.36, maxLon: -1.49)
        case .worcestershire:
            return RegionBoundingBox(minLat: 51.97, maxLat: 52.46, minLon: -2.66, maxLon: -1.76)
        case .scotland:
            return RegionBoundingBox(minLat: 54.54, maxLat: 61.35, minLon: -14.86, maxLon: 0.73)
        case .wales:
            return RegionBoundingBox(minLat: 51.04, maxLat: 53.77, minLon: -6.18, maxLon: -2.65)
        }
    }
}

/// Verwaltet heruntergeladene Wege-Graphen (siehe `WayGraphRepository`) für die
/// "ruhige Wege"-Offline-Routing-Engine, jeweils eine SQLite-Datei pro Region in
/// `Documents/WayGraphs/` (read-only gebündelte Ressourcen wie `routes.sqlite` liegen dagegen im
/// App-Bundle - diese Dateien werden dagegen zur Laufzeit heruntergeladen, deshalb `Documents/`).
/// Generisch über `Region` (`Bundesland` oder `EuropaLand`), damit Deutschland und weitere Länder
/// dieselbe Download-/Speicher-Logik teilen, aber unabhängig voneinander in den Einstellungen
/// gelistet werden können. Alle Regionstypen teilen sich denselben physischen Ordner - Dateinamen
/// kollidieren nicht, da `rawValue` je Typ eindeutig ist (Bundesländer vs. Ländernamen).
/// `nonisolated`, damit `save(downloadedFile:for:)` synchron aus dem `URLSessionDownloadTask`-
/// Completion-Handler aufgerufen werden kann (siehe `WayGraphDownloadManager.download`) - ohne
/// einen `Task { @MainActor in ... }`-Hop davor, der die von URLSession bereitgestellte
/// temporäre Datei manchmal schon gelöscht hatte, bevor `moveItem` sie erreichte.
nonisolated final class WayGraphStore<Region: DownloadableRegion> {
    private let directory: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents.appendingPathComponent("WayGraphs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        invalidateIfFormatChanged()
    }

    private func invalidateIfFormatChanged() {
        let versionFile = directory.appendingPathComponent(".format-version")
        let storedVersion = (try? String(contentsOf: versionFile, encoding: .utf8)).flatMap { Int($0) }
        guard storedVersion != wayGraphFormatVersion else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "sqlite" {
            try? FileManager.default.removeItem(at: file)
        }
        try? "\(wayGraphFormatVersion)".write(to: versionFile, atomically: true, encoding: .utf8)
    }

    func isDownloaded(_ region: Region) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: region).path)
    }

    func path(for region: Region) -> String? {
        isDownloaded(region) ? fileURL(for: region).path : nil
    }

    func delete(_ region: Region) {
        try? FileManager.default.removeItem(at: fileURL(for: region))
    }

    /// Übernimmt eine fertig heruntergeladene Datei (z. B. aus einem `URLSessionDownloadTask`,
    /// der sie in ein temporäres Verzeichnis schreibt) an ihren endgültigen Platz.
    func save(downloadedFile tempURL: URL, for region: Region) throws {
        let destination = fileURL(for: region)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    private func fileURL(for region: Region) -> URL {
        directory.appendingPathComponent("\(region.rawValue).sqlite")
    }
}
