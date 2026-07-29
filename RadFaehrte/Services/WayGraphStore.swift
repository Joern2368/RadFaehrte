//
//  WayGraphStore.swift
//  RadFaehrte
//

import Foundation

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
}

/// Weitere europäische Länder außerhalb Deutschlands, für die ein Wege-Graph heruntergeladen werden
/// kann - bisher Niederlande (Anlass: Rotterdam-Reise 2026-07-27), Polen und Schweden (s.
/// ROADMAP.md). Eigener Typ statt eines Falls in `Bundesland`, weil es Länder statt Bundesländer
/// sind (andere Ebene) und die Einstellungen sie in einer eigenen Liste ("Offline-Karten Europa")
/// getrennt von den deutschen Bundesländern anzeigen. Fallnamen bewusst auf Englisch (wie bei
/// Geofabrik/den Release-Asset-Dateinamen, z. B. `netherlands_ways.sqlite`) statt Deutsch wie bei
/// `Bundesland` - dort passt der deutsche Fallname zufällig zum Geofabrik-Bezeichner
/// (download.geofabrik.de/europe/germany/<bundesland>), hier nicht (download.geofabrik.de/europe/
/// <land-englisch>). `displayName` liefert trotzdem die deutsche UI-Bezeichnung.
nonisolated enum EuropaLand: String, CaseIterable, Identifiable, DownloadableRegion {
    case netherlands
    case poland
    case sweden

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .netherlands: return "Niederlande"
        case .poland: return "Polen"
        case .sweden: return "Schweden"
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
