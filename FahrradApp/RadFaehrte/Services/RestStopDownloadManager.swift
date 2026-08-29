//
//  RestStopDownloadManager.swift
//  RadFaehrte
//

import Foundation
import Observation

/// Ergänzt `DownloadableRegion` um die POI-spezifische Download-Adresse/-Größe - eigenes, kleines
/// Protokoll statt Wiederverwendung von `DownloadableRegion.downloadURL`/`.approximateSizeMB`, da
/// diese bereits für die (unabhängigen) Wege-Graph-Release-Assets reserviert sind und andere
/// Werte/Release-Tags hätten.
nonisolated protocol RestStopDownloadableRegion: DownloadableRegion {
    var restStopDownloadURL: URL { get }
    /// Tatsächliche Release-Asset-Größe in KB, für die Anzeige vor dem Download - reine
    /// Nachschlagewerte statt Formel, da die POI-Dichte nicht mit Fläche/Bevölkerung korreliert
    /// (s. `Bundesland`/`EuropaLand`-Konformitäten unten).
    var restStopApproximateSizeKB: Int { get }
}

/// `rest-stops-v1`-Release, separat vom Wege-Graph-Release (`way-graphs-v5`) und von `Bundesland`s
/// dort reservierter `downloadURL`. Formel statt Dictionary (analog `Bundesland.downloadURL` in
/// `WayGraphDownloadManager.swift`), da inzwischen alle 16 Bundesländer denselben Tag nutzen, s.
/// `restStopSupportedRegions`.
nonisolated extension Bundesland: RestStopDownloadableRegion {
    var restStopDownloadURL: URL {
        URL(string: "https://github.com/Joern2368/RadFaehrte/releases/download/rest-stops-v1/\(rawValue)_reststops.sqlite")!
    }

    /// Tatsächliche Release-Asset-Größen in KB (nach dem Bau aller 16 Bundesländer mit E-Bike-
    /// Ladestationen + Bäckereien, 2026-08-24).
    var restStopApproximateSizeKB: Int {
        switch self {
        case .badenWuerttemberg: return 7768
        case .bayern: return 8932
        case .berlin: return 1456
        case .brandenburg: return 2704
        case .bremen: return 232
        case .hamburg: return 680
        case .hessen: return 4156
        case .mecklenburgVorpommern: return 920
        case .niedersachsen: return 4240
        case .nordrheinWestfalen: return 7684
        case .rheinlandPfalz: return 3008
        case .saarland: return 508
        case .sachsen: return 2624
        case .sachsenAnhalt: return 1044
        case .schleswigHolstein: return 1596
        case .thueringen: return 1568
        }
    }
}

/// Eigener Release-Tag `rest-stops-eu-v1` statt `rest-stops-v1` (analog dem Wege-Graph-Muster
/// `way-graphs-v5` für Bundesländer vs. `way-graphs-eu-v1` für `EuropaLand`) - bisher nur Luxemburg
/// als Testland gebaut, s. `restStopSupportedEuropaLands`.
nonisolated extension EuropaLand: RestStopDownloadableRegion {
    var restStopDownloadURL: URL {
        URL(string: "https://github.com/Joern2368/RadFaehrte/releases/download/rest-stops-eu-v1/\(rawValue)_reststops.sqlite")!
    }

    var restStopApproximateSizeKB: Int {
        switch self {
        case .luxembourg: return 544
        case .liechtenstein: return 56
        case .andorra: return 36
        case .austria: return 6244
        case .netherlands: return 6040
        case .switzerland: return 6336
        case .belgium: return 3492
        case .denmark: return 1812
        case .slovakia: return 1700
        case .greece: return 1956
        case .portugal: return 2352
        case .czechia: return 4008
        case .poland: return 7572
        case .malta: return 96
        case .monaco: return 28
        case .cyprus: return 280
        case .kosovo: return 136
        case .macedonia: return 140
        case .montenegro: return 360
        case .albania: return 368
        case .bosniaHerzegovina: return 340
        case .bulgaria: return 936
        case .romania: return 732
        case .hungary: return 2544
        case .croatia: return 1208
        case .slovenia: return 680
        case .serbia: return 632
        case .sweden: return 2296
        case .iceland: return 204
        case .estonia: return 652
        case .latvia: return 728
        case .lithuania: return 496
        case .ireland: return 940
        case .finland: return 1328
        // San Marino/Vatikanstadt: 0 Treffer (beide winzig, s. ROADMAP.md) - deshalb nicht in
        // `restStopSupportedEuropaLands` gelistet, hier aber trotzdem nötig für die
        // Exhaustiveness-Prüfung über alle `EuropaLand`-Fälle.
        case .sanMarino: return 0
        case .vaticanCity: return 0
        }
    }
}

/// Eigener Release-Tag `rest-stops-fr-v1`, unabhängig von `rest-stops-eu-v1` - Frankreich ist bei
/// `EuropaLand` bewusst kein Fall (dort steht `FranceRegion` für die 21-Regionen-Aufteilung, s.
/// `WayGraphStore.swift`), s. `FranceCountry`-Doc-Kommentar in `RestStopStore.swift`.
nonisolated extension FranceCountry: RestStopDownloadableRegion {
    var restStopDownloadURL: URL {
        URL(string: "https://github.com/Joern2368/RadFaehrte/releases/download/rest-stops-fr-v1/\(rawValue)_reststops.sqlite")!
    }

    var restStopApproximateSizeKB: Int {
        switch self {
        case .france: return 18608
        }
    }

    /// `downloadURL`/`approximateSizeMB` aus dem geerbten `DownloadableRegion` werden für diesen
    /// POI-only-Typ nie aufgerufen (kein Wege-Graph-Code iteriert über `FranceCountry` - für
    /// Wege-Graphen gilt weiterhin `FranceRegion`). Zeigen der Einfachheit halber auf dieselben
    /// Werte wie `restStopDownloadURL`/`restStopApproximateSizeKB` statt erfundene Platzhalter zu
    /// liefern.
    var downloadURL: URL { restStopDownloadURL }
    var approximateSizeMB: Int { restStopApproximateSizeKB / 1024 }
}

/// Eigener Release-Tag `rest-stops-es-v1`, analog `rest-stops-fr-v1` bei `FranceCountry`.
nonisolated extension SpainCountry: RestStopDownloadableRegion {
    var restStopDownloadURL: URL {
        URL(string: "https://github.com/Joern2368/RadFaehrte/releases/download/rest-stops-es-v1/\(rawValue)_reststops.sqlite")!
    }

    var restStopApproximateSizeKB: Int {
        switch self {
        case .spain: return 9408
        }
    }

    var downloadURL: URL { restStopDownloadURL }
    var approximateSizeMB: Int { restStopApproximateSizeKB / 1024 }
}

/// Eigener Release-Tag `rest-stops-it-v1`, analog `rest-stops-fr-v1`/`rest-stops-es-v1`.
nonisolated extension ItalyCountry: RestStopDownloadableRegion {
    var restStopDownloadURL: URL {
        URL(string: "https://github.com/Joern2368/RadFaehrte/releases/download/rest-stops-it-v1/\(rawValue)_reststops.sqlite")!
    }

    var restStopApproximateSizeKB: Int {
        switch self {
        case .italy: return 13708
        }
    }

    var downloadURL: URL { restStopDownloadURL }
    var approximateSizeMB: Int { restStopApproximateSizeKB / 1024 }
}

/// Eigener Release-Tag `rest-stops-no-v1`, analog `rest-stops-fr-v1`/`-es-v1`/`-it-v1`.
nonisolated extension NorwayCountry: RestStopDownloadableRegion {
    var restStopDownloadURL: URL {
        URL(string: "https://github.com/Joern2368/RadFaehrte/releases/download/rest-stops-no-v1/\(rawValue)_reststops.sqlite")!
    }

    var restStopApproximateSizeKB: Int {
        switch self {
        case .norway: return 1444
        }
    }

    var downloadURL: URL { restStopDownloadURL }
    var approximateSizeMB: Int { restStopApproximateSizeKB / 1024 }
}

/// Eigener Release-Tag `rest-stops-gb-v1`, analog `rest-stops-fr-v1`/`-es-v1`/`-it-v1`/`-no-v1`.
nonisolated extension GreatBritainCountry: RestStopDownloadableRegion {
    var restStopDownloadURL: URL {
        URL(string: "https://github.com/Joern2368/RadFaehrte/releases/download/rest-stops-gb-v1/\(rawValue)_reststops.sqlite")!
    }

    var restStopApproximateSizeKB: Int {
        switch self {
        case .greatBritain: return 9976
        }
    }

    var downloadURL: URL { restStopDownloadURL }
    var approximateSizeMB: Int { restStopApproximateSizeKB / 1024 }
}

/// Lädt Rastplatz-Datenbanken herunter und meldet den Fortschritt für `RestStopsOfflineView` -
/// analog `WayGraphDownloadManager<Region>`, generisch über `Region: RestStopDownloadableRegion`
/// seit Luxemburg als zweitem unterstützten Land (s. `RestStopStore`-Doc-Kommentar). Anders als bei
/// `WayGraphDownloadManager` liest der Initialisierer die unterstützten Regionen nicht selbst aus
/// einer einzigen globalen Konstante, sondern bekommt sie übergeben (`restStopSupportedRegions` bzw.
/// `restStopSupportedEuropaLands` - zwei getrennte Listen, eine pro Regionstyp).
@Observable
final class RestStopDownloadManager<Region: RestStopDownloadableRegion> {
    private let store: RestStopStore<Region>
    private(set) var downloaded: Set<Region>
    private(set) var progress: [Region: Double] = [:]
    private(set) var deletingRegions: Set<Region> = []
    var errorMessage: String?

    init(store: RestStopStore<Region>, supportedRegions: [Region]) {
        self.store = store
        downloaded = Set(supportedRegions.filter { store.isDownloaded($0) })
        // Läuft ein Download bereits im Hintergrund weiter (z. B. View verlassen und wieder
        // geöffnet, oder App nach einem Hintergrund-Download-Fortschritt neu gestartet) - sofort
        // mit dem aktuellen Fortschritt weiter anzeigen statt bei 0 % neu zu wirken (s.
        // `BackgroundDownloadCoordinator`).
        for region in supportedRegions {
            guard let fraction = BackgroundDownloadCoordinator.shared.currentProgress(
                kind: .restStop, regionRawValue: region.rawValue
            ) else { continue }
            progress[region] = fraction
            observeDownload(region)
        }
    }

    func isDownloaded(_ region: Region) -> Bool {
        downloaded.contains(region)
    }

    func approximateSizeKB(_ region: Region) -> Int {
        region.restStopApproximateSizeKB
    }

    /// "~200 KB" bzw. "~7,0 MB" - seit der Bänke-/Biergarten-Erweiterung liegen etliche Regionen
    /// im mehrstelligen MB-Bereich (s. `restStopApproximateSizeKB`), eine reine KB-Anzeige wäre dort
    /// nicht mehr gut lesbar. `Locale(identifier: "de_DE")` explizit gesetzt (s. CLAUDE.md), damit
    /// das Dezimalkomma unabhängig von der Geräte-Regionseinstellung deutsch bleibt.
    func approximateSizeDisplay(_ region: Region) -> String {
        let kb = approximateSizeKB(region)
        guard kb >= 1000 else { return "~\(kb) KB" }
        let mb = Double(kb) / 1024
        let formatted = mb.formatted(
            .number.precision(.fractionLength(1)).locale(Locale(identifier: "de_DE"))
        )
        return "~\(formatted) MB"
    }

    func delete(_ region: Region) {
        guard !deletingRegions.contains(region) else { return }
        let path = store.path(for: region)
        deletingRegions.insert(region)
        Task.detached { [store] in
            if let path {
                RestStopCache.shared.invalidate(path: path)
            }
            store.delete(region)
            await MainActor.run { [weak self] in
                self?.downloaded.remove(region)
                self?.deletingRegions.remove(region)
            }
        }
    }

    func cancel(_ region: Region) {
        BackgroundDownloadCoordinator.shared.cancelDownload(kind: .restStop, regionRawValue: region.rawValue)
    }

    /// Registriert die Fortschritts-/Abschluss-Callbacks beim `BackgroundDownloadCoordinator` -
    /// gemeinsam genutzt von `download(_:)` (neuer Download) und `init` (bereits laufender
    /// Hintergrund-Download, s. dortiger Kommentar).
    private func observeDownload(_ region: Region) {
        BackgroundDownloadCoordinator.shared.observe(
            kind: .restStop,
            regionRawValue: region.rawValue,
            onProgress: { [weak self] fraction in
                self?.progress[region] = fraction
            },
            onCompletion: { [weak self] result in
                guard let self else { return }
                self.progress[region] = nil
                switch result {
                case .success:
                    self.downloaded.insert(region)
                case .failure(let error):
                    self.errorMessage = "Download fehlgeschlagen: \(error.localizedDescription)"
                }
            }
        )
    }

    func download(_ region: Region) {
        guard progress[region] == nil else { return }
        progress[region] = 0
        observeDownload(region)
        BackgroundDownloadCoordinator.shared.startDownload(
            kind: .restStop, regionRawValue: region.rawValue, url: region.restStopDownloadURL
        )
    }
}
