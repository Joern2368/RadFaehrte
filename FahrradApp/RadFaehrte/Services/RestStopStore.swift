//
//  RestStopStore.swift
//  RadFaehrte
//

import Foundation

/// Bei jeder inkompatiblen Änderung am `rest_stops.sqlite`-Schema (s. `Scripts/build_rest_stops.py`)
/// hochzählen - analog `wayGraphFormatVersion` in `WayGraphStore.swift`, aber eigenständig, da
/// unabhängiges Binärformat. `nonisolated(unsafe)` aus demselben Grund wie dort (Projekt läuft
/// standardmäßig auf MainActor, `RestStopStore` selbst ist aber bewusst `nonisolated`).
///
/// Version 3 (2026-08-21): Kein Schema-/Spaltenwechsel, sondern ein reiner Inhalts-Refresh - alle
/// 16 Release-Assets wurden neu gebaut (Bänke-Kategorie, die bei den meisten Bundesländern nie
/// nachgezogen wurde, plus neue Biergarten-Kategorie, s. ROADMAP.md). Trotzdem hochgezählt, damit
/// bereits heruntergeladene Regionen beim nächsten Start automatisch verworfen werden statt still
/// auf altem Datenstand zu bleiben, bis jemand manuell löscht und neu lädt.
///
/// Version 4 (2026-08-22): Gleiches Muster für die neue Toiletten-Kategorie - wieder alle 16 Assets
/// neu gebaut, wieder nur Inhalts-Refresh ohne Schema-Änderung.
///
/// Version 5 (2026-08-24): Gleiches Muster für E-Bike-Ladestationen und Bäckereien (die dabei
/// ebenfalls getestete Fahrrad-Luftpumpen-Kategorie wurde nach 0 Treffern in Bremen+Bayern wieder
/// verworfen, s. `Scripts/build_rest_stops.py`) - wieder alle 16 Assets neu gebaut, wieder nur
/// Inhalts-Refresh ohne Schema-Änderung.
private nonisolated(unsafe) let restStopsFormatVersion = 5

/// Bundesländer, für die eine `rest-stops-v1`-Datei existiert - inzwischen alle 16 (erst als Test
/// nur Bremen/Niedersachsen, nach positivem Nutzer-Feedback auf ganz Deutschland ausgeweitet, s.
/// ROADMAP.md). Eigene Konstante statt direkt `Bundesland.allCases` an den Aufrufstellen, damit ein
/// künftiger Fall, der (aus welchem Grund auch immer) noch keine Datei hat, an einer einzigen
/// Stelle ausgeschlossen werden kann.
let restStopSupportedRegions: [Bundesland] = Bundesland.allCases

/// Länder außerhalb Deutschlands, für die eine `rest-stops-eu-v1`-Datei existiert - begonnen mit
/// drei kleinen Testländern, Luxemburg, Liechtenstein und Andorra (2026-08-24), analog dem
/// ursprünglichen Bremen/Niedersachsen-Test bei den Bundesländern, seither auf weitere Länder
/// ausgeweitet. Bewusst nicht `EuropaLand.allCases` (von dessen 34 Fällen hat noch nicht jedes eine
/// gebaute POI-Datei) - Erweiterung auf weitere Länder erfolgt hier, analog
/// `restStopSupportedRegions`.
/// 34 von 36 `EuropaLand`-Fällen abgedeckt (2026-08-27) - San Marino und Vatikanstadt bewusst
/// ausgenommen (0 Treffer bei beiden, analog der verworfenen Fahrrad-Luftpumpen-Kategorie, s.
/// ROADMAP.md). Konstante bewusst weiterhin gepflegt statt auf `EuropaLand.allCases` umgestellt,
/// für den Fall, dass künftig ein neuer `EuropaLand`-Fall ergänzt wird, der noch keine gebaute
/// POI-Datei hat (s. Doc-Kommentar oben).
let restStopSupportedEuropaLands: [EuropaLand] = [.luxembourg, .liechtenstein, .andorra, .austria, .netherlands, .switzerland, .belgium, .denmark, .slovakia, .greece, .portugal, .czechia, .poland, .malta, .monaco, .cyprus, .kosovo, .macedonia, .montenegro, .albania, .bosniaHerzegovina, .bulgaria, .romania, .hungary, .croatia, .slovenia, .serbia, .sweden, .iceland, .estonia, .latvia, .lithuania, .ireland, .finland]

/// Frankreich als **eine** Region für POIs - anders als `FranceRegion` (21 Teilregionen, s. dessen
/// Doc-Kommentar), das für den Wege-Graph-Bau wegen Speicherdrucks bei der vollen 4,8-GB-Datei
/// nötig war. `build_rest_stops.py` liest dagegen nur einzelne Knoten ohne vollen Orts-Index
/// (`.with_locations()`) und ist damit deutlich leichtgewichtiger - eine einzelne Datei für ganz
/// Frankreich ist hier möglich (Nutzer-Entscheidung 2026-08-27: eine "Frankreich"-Zeile in den
/// Einstellungen statt 21 einzelner Regionen).
nonisolated enum FranceCountry: String, CaseIterable, Identifiable, DownloadableRegion {
    case france

    var id: String { rawValue }
    var displayName: String { "Frankreich" }

    /// Aus dem pbf-Header von `france-latest.osm.pbf` (`osmium.io.Reader(...).header().box()`),
    /// analog dem Vorgehen bei `FranceRegion`/`ItalyRegion`/`SpainRegion`.
    var boundingBox: RegionBoundingBox {
        RegionBoundingBox(minLat: 41.2386640, maxLat: 51.4288010, minLon: -6.9372070, maxLon: 10.0167910)
    }
}

/// Länder außerhalb Deutschlands, für die eine `rest-stops-fr-v1`-Datei existiert - bewusst analog
/// zu `restStopSupportedRegions`/`restStopSupportedEuropaLands` als eigene Konstante statt
/// `FranceCountry.allCases` direkt zu verwenden, auch wenn `FranceCountry` bisher nur einen Fall hat.
let restStopSupportedFranceCountries: [FranceCountry] = [.france]

/// Spanien als **eine** Region für POIs - analog `FranceCountry`. Bei den Wege-Graphen ist Spanien
/// wegen der Speicherprobleme beim vollen Länder-Bau in 18 `SpainRegion`-Teilregionen aufgeteilt;
/// das pbf ist mit 1,4 GB aber deutlich kleiner als Frankreichs 4,8 GB und damit für den
/// leichtgewichtigen POI-Bau (keine `.with_locations()`) auch als eine Datei gut machbar.
nonisolated enum SpainCountry: String, CaseIterable, Identifiable, DownloadableRegion {
    case spain

    var id: String { rawValue }
    var displayName: String { "Spanien" }

    /// Aus dem pbf-Header von `spain-latest.osm.pbf`, analog `FranceCountry.boundingBox`.
    var boundingBox: RegionBoundingBox {
        RegionBoundingBox(minLat: 35.1541530, maxLat: 44.1485500, minLon: -9.7790140, maxLon: 5.0985250)
    }
}

/// Länder außerhalb Deutschlands, für die eine `rest-stops-es-v1`-Datei existiert - analog
/// `restStopSupportedFranceCountries`.
let restStopSupportedSpainCountries: [SpainCountry] = [.spain]

/// Italien als **eine** Region für POIs - analog `FranceCountry`/`SpainCountry`. Bei den
/// Wege-Graphen ist Italien wegen der Speicherprobleme beim vollen Länder-Bau in 5
/// `ItalyRegion`-Makroregionen aufgeteilt; das pbf ist mit 2,1 GB ähnlich groß wie Polen (2 GB,
/// dort ohne Probleme als eine POI-Datei gebaut) und damit für den leichtgewichtigen POI-Bau
/// (keine `.with_locations()`) ebenfalls als eine Datei gut machbar.
nonisolated enum ItalyCountry: String, CaseIterable, Identifiable, DownloadableRegion {
    case italy

    var id: String { rawValue }
    var displayName: String { "Italien" }

    /// Aus dem pbf-Header von `italy-latest.osm.pbf`, analog `FranceCountry`/`SpainCountry`.
    var boundingBox: RegionBoundingBox {
        RegionBoundingBox(minLat: 35.0763800, maxLat: 47.1000450, minLon: 6.6026960, maxLon: 19.1249900)
    }
}

/// Länder außerhalb Deutschlands, für die eine `rest-stops-it-v1`-Datei existiert - analog
/// `restStopSupportedFranceCountries`/`restStopSupportedSpainCountries`.
let restStopSupportedItalyCountries: [ItalyCountry] = [.italy]

/// Norwegen als **eine** Region für POIs - analog `FranceCountry`/`SpainCountry`/`ItalyCountry`.
/// Bei den Wege-Graphen ist Norwegen vorsorglich in 6 `NorwayRegion`-Teilregionen aufgeteilt (s.
/// dessen Doc-Kommentar) - reines Vorsichtsmaß wegen möglicher Ausgabegröße beim Wege-Graph-Bau,
/// nicht wegen tatsächlicher Speicherprobleme. Der leichtgewichtige POI-Bau (keine
/// `.with_locations()`) hat dieses Risiko nicht; das pbf ist mit 1,3 GB in der Größenordnung von
/// Spanien (dort problemlos als eine Datei gebaut). Enthält wie bei `NorwayRegion` auch die
/// Exklave Svalbard/Jan Mayen (dadurch eine ungewöhnlich große `boundingBox`, die bis weit in die
/// Arktis reicht - unschädlich, da nur ein günstiger Vorfilter, s. `RegionBoundingBox`-Doc-Kommentar).
nonisolated enum NorwayCountry: String, CaseIterable, Identifiable, DownloadableRegion {
    case norway

    var id: String { rawValue }
    var displayName: String { "Norwegen" }

    /// Aus dem pbf-Header von `norway-latest.osm.pbf`, analog `FranceCountry`/`SpainCountry`/
    /// `ItalyCountry`.
    var boundingBox: RegionBoundingBox {
        RegionBoundingBox(minLat: 57.5532300, maxLat: 81.0519500, minLon: -11.3680100, maxLon: 35.5271100)
    }
}

/// Länder außerhalb Deutschlands, für die eine `rest-stops-no-v1`-Datei existiert - analog
/// `restStopSupportedFranceCountries`/`restStopSupportedSpainCountries`/`restStopSupportedItalyCountries`.
let restStopSupportedNorwayCountries: [NorwayCountry] = [.norway]

/// Verwaltet heruntergeladene Rastplatz-Datenbanken (s. `RestStopRepository`), jeweils eine
/// SQLite-Datei pro Region in `Documents/RestStops/` - analog `WayGraphStore<Region>`, generisch
/// über `Region: DownloadableRegion` seit Luxemburg als zweitem unterstützten Land (2026-08-24;
/// zuvor bewusst fest auf `Bundesland`, s. Versionsgeschichte in ROADMAP.md, da eine generische
/// Abstraktion für einen reinen 2-Länder-Test verfrüht gewesen wäre). Die Genericisierung über
/// `DownloadableRegion` koppelt nicht an die Wege-Graph-Klassen (`WayGraphStore` o. Ä.) - das
/// Protokoll ist eine eigenständige, bereits von `Bundesland`/`EuropaLand` für andere Zwecke erfüllte
/// Abstraktion. Die POI-Funktion bleibt dadurch weiterhin ein eigener, unabhängig entfernbarer
/// Klassenbaum, getrennt von der Wege-Graph-Maschinerie.
nonisolated final class RestStopStore<Region: DownloadableRegion> {
    private let directory: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents.appendingPathComponent("RestStops", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        invalidateIfFormatChanged()
    }

    private func invalidateIfFormatChanged() {
        let versionFile = directory.appendingPathComponent(".format-version")
        let storedVersion = (try? String(contentsOf: versionFile, encoding: .utf8)).flatMap { Int($0) }
        guard storedVersion != restStopsFormatVersion else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "sqlite" {
            try? FileManager.default.removeItem(at: file)
        }
        try? "\(restStopsFormatVersion)".write(to: versionFile, atomically: true, encoding: .utf8)
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

    /// Übernimmt eine fertig heruntergeladene Datei an ihren endgültigen Platz - analog
    /// `WayGraphStore.save(downloadedFile:for:)`.
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
