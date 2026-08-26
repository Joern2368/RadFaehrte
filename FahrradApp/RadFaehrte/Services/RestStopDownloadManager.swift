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
        default:
            // Nur die in `restStopSupportedEuropaLands` gelisteten Länder haben bisher eine gebaute
            // POI-Datei - dieser Zweig wird praktisch nie erreicht, ist aber wegen der
            // Exhaustiveness-Prüfung über alle 34 `EuropaLand`-Fälle nötig.
            return 0
        }
    }
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

    private var observations: [Region: NSKeyValueObservation] = [:]
    private var tasks: [Region: URLSessionDownloadTask] = [:]

    init(store: RestStopStore<Region>, supportedRegions: [Region]) {
        self.store = store
        downloaded = Set(supportedRegions.filter { store.isDownloaded($0) })
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
        tasks[region]?.cancel()
    }

    func download(_ region: Region) {
        guard progress[region] == nil else { return }
        progress[region] = 0

        let task = URLSession.shared.downloadTask(with: region.restStopDownloadURL) { [store] tempURL, _, error in
            // Synchron im Completion-Handler übernehmen, nicht erst nach einem Hop auf den
            // MainActor - URLSession löscht die temporäre Datei sofort nach Rückkehr des Handlers
            // (s. ausführlicher Kommentar in `WayGraphDownloadManager.download`).
            let wasCancelled = (error as? URLError)?.code == .cancelled
            var errorMessage: String?
            if wasCancelled {
                // Kein Fehler-Alert - der Nutzer hat selbst über `cancel(_:)` abgebrochen.
            } else if let error {
                errorMessage = "Download fehlgeschlagen: \(error.localizedDescription)"
            } else if let tempURL {
                do {
                    try store.save(downloadedFile: tempURL, for: region)
                    if let path = store.path(for: region) {
                        // Ohne `invalidate` würde ein erneuter Download derselben, bereits im
                        // laufenden Prozess gecachten Region (z. B. um neue Kategorien
                        // nachzuladen) stillschweigend die alte, im Speicher gehaltene Repository
                        // weiterverwenden statt die neu heruntergeladene Datei zu lesen - bis zum
                        // nächsten App-Neustart. Live-Fund 2026-08-23.
                        RestStopCache.shared.invalidate(path: path)
                        Task.detached(priority: .background) {
                            _ = RestStopCache.shared.repository(for: path)
                        }
                    }
                } catch {
                    errorMessage = "Speichern fehlgeschlagen: \(error.localizedDescription)"
                }
            } else {
                errorMessage = "Download fehlgeschlagen: keine Datei erhalten."
            }

            let resolvedErrorMessage = errorMessage
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observations[region] = nil
                self.tasks[region] = nil
                self.progress[region] = nil
                if let resolvedErrorMessage {
                    self.errorMessage = resolvedErrorMessage
                } else if !wasCancelled {
                    self.downloaded.insert(region)
                }
            }
        }
        tasks[region] = task

        observations[region] = task.progress.observe(\.fractionCompleted) { [weak self] taskProgress, _ in
            let fraction = taskProgress.fractionCompleted
            Task { @MainActor [weak self] in
                self?.progress[region] = fraction
            }
        }
        task.resume()
    }
}
