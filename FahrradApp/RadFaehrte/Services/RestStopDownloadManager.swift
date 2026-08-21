//
//  RestStopDownloadManager.swift
//  RadFaehrte
//

import Foundation
import Observation

/// GitHub-Release-Adresse der Rastplatz-Datenbanken (s. `Scripts/build_rest_stops.py`), separat
/// vom Wege-Graph-Release (`way-graphs-v5`) und von `Bundesland`s dort reservierter `downloadURL`.
/// Formel statt Dictionary (analog `Bundesland.downloadURL` in `WayGraphDownloadManager.swift`),
/// da inzwischen alle 16 Bundesländer denselben `rest-stops-v1`-Tag nutzen, s.
/// `restStopSupportedRegions`.
private func restStopDownloadURL(for region: Bundesland) -> URL {
    URL(string: "https://github.com/Joern2368/RadFaehrte/releases/download/rest-stops-v1/\(region.rawValue)_reststops.sqlite")!
}

/// Tatsächliche Release-Asset-Größen in KB (nach dem Bau aller 16 Bundesländer mit Bänken +
/// Biergärten, 2026-08-21) - anders als die URL kein Formel-Ausdruck, da die Größe (POI-Dichte)
/// nicht mit der Bundesland-Fläche oder -Bevölkerung korreliert. Deutlich größer als die erste
/// Fassung (z. B. Bayern von 912 KB auf 8 MB): Ein Teil der 16 Regionen hatte die Bänke-
/// Wiedereinführung (s. `RestStop.swift`) nie mitbekommen und wurde hier zusammen mit den
/// Biergärten erstmals komplett neu gebaut, s. ROADMAP.md.
private let restStopApproximateSizeKB: [Bundesland: Int] = [
    .badenWuerttemberg: 7044,
    .bayern: 8004,
    .berlin: 1296,
    .brandenburg: 2388,
    .bremen: 200,
    .hamburg: 592,
    .hessen: 3792,
    .mecklenburgVorpommern: 804,
    .niedersachsen: 3720,
    .nordrheinWestfalen: 6836,
    .rheinlandPfalz: 2760,
    .saarland: 448,
    .sachsen: 2300,
    .sachsenAnhalt: 912,
    .schleswigHolstein: 1384,
    .thueringen: 1416,
]

/// Lädt Rastplatz-Datenbanken herunter und meldet den Fortschritt für `RestStopsOfflineView` -
/// analog `WayGraphDownloadManager`, aber fest auf `Bundesland` zugeschnitten (statt generisch über
/// `Region: DownloadableRegion`) und nur über `restStopSupportedRegions` iterierend, nicht über
/// `restStopSupportedRegions` statt direkt `Bundesland.allCases`, s. dessen Doc-Kommentar.
@Observable
final class RestStopDownloadManager {
    private let store: RestStopStore
    private(set) var downloaded: Set<Bundesland>
    private(set) var progress: [Bundesland: Double] = [:]
    private(set) var deletingRegions: Set<Bundesland> = []
    var errorMessage: String?

    private var observations: [Bundesland: NSKeyValueObservation] = [:]
    private var tasks: [Bundesland: URLSessionDownloadTask] = [:]

    init(store: RestStopStore) {
        self.store = store
        downloaded = Set(restStopSupportedRegions.filter { store.isDownloaded($0) })
    }

    func isDownloaded(_ region: Bundesland) -> Bool {
        downloaded.contains(region)
    }

    func approximateSizeKB(_ region: Bundesland) -> Int {
        restStopApproximateSizeKB[region] ?? 0
    }

    /// "~200 KB" bzw. "~7,0 MB" - seit der Bänke-/Biergarten-Erweiterung liegen etliche Regionen
    /// im mehrstelligen MB-Bereich (s. `restStopApproximateSizeKB`), eine reine KB-Anzeige wäre dort
    /// nicht mehr gut lesbar. `Locale(identifier: "de_DE")` explizit gesetzt (s. CLAUDE.md), damit
    /// das Dezimalkomma unabhängig von der Geräte-Regionseinstellung deutsch bleibt.
    func approximateSizeDisplay(_ region: Bundesland) -> String {
        let kb = approximateSizeKB(region)
        guard kb >= 1000 else { return "~\(kb) KB" }
        let mb = Double(kb) / 1024
        let formatted = mb.formatted(
            .number.precision(.fractionLength(1)).locale(Locale(identifier: "de_DE"))
        )
        return "~\(formatted) MB"
    }

    func delete(_ region: Bundesland) {
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

    func cancel(_ region: Bundesland) {
        tasks[region]?.cancel()
    }

    func download(_ region: Bundesland) {
        guard progress[region] == nil else { return }
        progress[region] = 0

        let task = URLSession.shared.downloadTask(with: restStopDownloadURL(for: region)) { [store] tempURL, _, error in
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
