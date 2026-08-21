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
private nonisolated(unsafe) let restStopsFormatVersion = 3

/// Bundesländer, für die eine `rest-stops-v1`-Datei existiert - inzwischen alle 16 (erst als Test
/// nur Bremen/Niedersachsen, nach positivem Nutzer-Feedback auf ganz Deutschland ausgeweitet, s.
/// ROADMAP.md). Eigene Konstante statt direkt `Bundesland.allCases` an den Aufrufstellen, damit ein
/// künftiger Fall, der (aus welchem Grund auch immer) noch keine Datei hat, an einer einzigen
/// Stelle ausgeschlossen werden kann.
let restStopSupportedRegions: [Bundesland] = Bundesland.allCases

/// Verwaltet heruntergeladene Rastplatz-Datenbanken (s. `RestStopRepository`), jeweils eine
/// SQLite-Datei pro Bundesland in `Documents/RestStops/` - analog `WayGraphStore`, aber bewusst
/// eigenständig statt generisch über `Region: DownloadableRegion`: Für einen 2-Länder-Test wäre
/// die generische Abstraktion verfrüht, und ein eigenständiger Typ hält diese neue, experimentelle
/// Funktion sauber von der bestehenden Wege-Graph-Maschinerie getrennt (leicht rückbaubar, falls
/// sich das Feature nicht bewährt).
nonisolated final class RestStopStore {
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

    func isDownloaded(_ region: Bundesland) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: region).path)
    }

    func path(for region: Bundesland) -> String? {
        isDownloaded(region) ? fileURL(for: region).path : nil
    }

    func delete(_ region: Bundesland) {
        try? FileManager.default.removeItem(at: fileURL(for: region))
    }

    /// Übernimmt eine fertig heruntergeladene Datei an ihren endgültigen Platz - analog
    /// `WayGraphStore.save(downloadedFile:for:)`.
    func save(downloadedFile tempURL: URL, for region: Bundesland) throws {
        let destination = fileURL(for: region)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    private func fileURL(for region: Bundesland) -> URL {
        directory.appendingPathComponent("\(region.rawValue).sqlite")
    }
}
