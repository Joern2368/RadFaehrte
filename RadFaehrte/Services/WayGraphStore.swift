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
private nonisolated(unsafe) let wayGraphFormatVersion = 6

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
nonisolated enum EuropaLand: String, CaseIterable, Identifiable, DownloadableRegion {
    case albania
    case austria
    case belgium
    case czechia
    case denmark
    case luxembourg
    case netherlands
    case poland
    case slovakia
    case sweden
    case switzerland

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .albania: return "Albanien"
        case .austria: return "Österreich"
        case .belgium: return "Belgien"
        case .czechia: return "Tschechien"
        case .denmark: return "Dänemark"
        case .luxembourg: return "Luxemburg"
        case .netherlands: return "Niederlande"
        case .poland: return "Polen"
        case .slovakia: return "Slowakei"
        case .sweden: return "Schweden"
        case .switzerland: return "Schweiz"
        }
    }

    var boundingBox: RegionBoundingBox {
        switch self {
        case .albania:
            return RegionBoundingBox(minLat: 39.63, maxLat: 42.66, minLon: 18.90, maxLon: 21.06)
        case .austria:
            return RegionBoundingBox(minLat: 46.37, maxLat: 49.02, minLon: 9.53, maxLon: 17.16)
        case .belgium:
            return RegionBoundingBox(minLat: 49.49, maxLat: 51.60, minLon: 2.34, maxLon: 6.41)
        case .czechia:
            return RegionBoundingBox(minLat: 48.54, maxLat: 51.06, minLon: 12.08, maxLon: 18.86)
        case .denmark:
            return RegionBoundingBox(minLat: 54.44, maxLat: 58.06, minLon: 7.70, maxLon: 15.65)
        case .luxembourg:
            return RegionBoundingBox(minLat: 49.45, maxLat: 50.18, minLon: 5.73, maxLon: 6.53)
        case .netherlands:
            return RegionBoundingBox(minLat: 50.75, maxLat: 53.55, minLon: 3.36, maxLon: 7.23)
        case .poland:
            return RegionBoundingBox(minLat: 49.00, maxLat: 54.84, minLon: 14.12, maxLon: 24.15)
        case .slovakia:
            return RegionBoundingBox(minLat: 47.73, maxLat: 49.62, minLon: 16.83, maxLon: 22.57)
        case .sweden:
            return RegionBoundingBox(minLat: 55.34, maxLat: 69.06, minLon: 11.11, maxLon: 24.17)
        case .switzerland:
            return RegionBoundingBox(minLat: 45.82, maxLat: 47.81, minLon: 5.95, maxLon: 10.50)
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
