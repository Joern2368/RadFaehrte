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
let restStopSupportedEuropaLands: [EuropaLand] = [.luxembourg, .liechtenstein, .andorra, .austria, .netherlands, .switzerland, .belgium, .denmark]

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
