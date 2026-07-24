//
//  WayGraphStore.swift
//  RadFaehrte
//

import Foundation

/// Bundesländer, für die eine Offline-Routing-Engine heruntergeladen werden kann (siehe
/// `Scripts/build_way_graph.py`). `rawValue` entspricht dem Geofabrik-Bezeichner
/// (download.geofabrik.de/europe/germany/<rawValue>-latest.osm.pbf) und zugleich dem
/// Dateinamens-Präfix des Release-Assets (`<rawValue>_ways.sqlite`).
enum Bundesland: String, CaseIterable, Identifiable {
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
}

/// Verwaltet heruntergeladene Wege-Graphen (siehe `WayGraphRepository`) für die
/// "ruhige Wege"-Offline-Routing-Engine, jeweils eine SQLite-Datei pro Bundesland in
/// `Documents/WayGraphs/` (read-only gebündelte Ressourcen wie `routes.sqlite` liegen dagegen im
/// App-Bundle - diese Dateien werden dagegen zur Laufzeit heruntergeladen, deshalb `Documents/`).
/// `nonisolated`, damit `save(downloadedFile:for:)` synchron aus dem `URLSessionDownloadTask`-
/// Completion-Handler aufgerufen werden kann (siehe `WayGraphDownloadManager.download`) - ohne
/// einen `Task { @MainActor in ... }`-Hop davor, der die von URLSession bereitgestellte
/// temporäre Datei manchmal schon gelöscht hatte, bevor `moveItem` sie erreichte.
nonisolated final class WayGraphStore {
    /// Bei jeder inkompatiblen Änderung am `.sqlite`-Binärformat (siehe
    /// `Scripts/build_way_graph.py`) hochzählen: bereits heruntergeladene Graphen im alten
    /// Format würden sonst mit falscher Byte-Schrittweite fehlinterpretiert statt sauber neu
    /// heruntergeladen zu werden.
    private static let formatVersion = 2

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
        guard storedVersion != Self.formatVersion else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "sqlite" {
            try? FileManager.default.removeItem(at: file)
        }
        try? "\(Self.formatVersion)".write(to: versionFile, atomically: true, encoding: .utf8)
    }

    func isDownloaded(_ bundesland: Bundesland) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: bundesland).path)
    }

    func path(for bundesland: Bundesland) -> String? {
        isDownloaded(bundesland) ? fileURL(for: bundesland).path : nil
    }

    func delete(_ bundesland: Bundesland) {
        try? FileManager.default.removeItem(at: fileURL(for: bundesland))
    }

    /// Übernimmt eine fertig heruntergeladene Datei (z. B. aus einem `URLSessionDownloadTask`,
    /// der sie in ein temporäres Verzeichnis schreibt) an ihren endgültigen Platz.
    func save(downloadedFile tempURL: URL, for bundesland: Bundesland) throws {
        let destination = fileURL(for: bundesland)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    private func fileURL(for bundesland: Bundesland) -> URL {
        directory.appendingPathComponent("\(bundesland.rawValue).sqlite")
    }
}
