//
//  WayGraphDownloadManager.swift
//  RadFaehrte
//

import Foundation
import Observation

/// GitHub-Release-Adresse und ungefähre Downloadgröße der Bundesland-Wege-Graphen (siehe
/// `Scripts/build_way_graph.py`, hochgeladen als Release-Assets im `RadFaehrte`-Repo).
/// `nonisolated`, damit diese `DownloadableRegion`-Konformität (die Protokoll selbst ist
/// `nonisolated`, s. `WayGraphStore.swift`) nicht durch die MainActor-Standardisolierung des
/// Projekts (`-default-isolation=MainActor`) wieder isoliert wird - sonst Warnung "conformance
/// ... crosses into main actor-isolated code" (in Swift 6 ein Fehler).
nonisolated extension Bundesland {
    var downloadURL: URL {
        // v4: Kanten enthalten zusätzlich einen Namens-Index in eine deduplizierte
        // Straßennamen-Tabelle (siehe `WayGraphRepository`, `BikeRoutingEngine.buildSteps`) für
        // echte Turn-by-Turn-Anweisungen. Ursprünglich als v3 mit UInt16-Index versucht -
        // Baden-Württemberg erreichte beim echten Bau aber dessen 65.535er-Grenze, deshalb direkt
        // auf UInt32 umgestellt (v4) statt v3 fehlerhaft auszuliefern. Inkompatibel zum alten
        // Format, deshalb neuer Release-Tag statt Assets im alten (way-graphs-v2) zu
        // überschreiben.
        URL(string: "https://github.com/Joern2368/RadFaehrte/releases/download/way-graphs-v4/\(rawValue)_ways.sqlite")!
    }

    var approximateSizeMB: Int {
        // v4-Größen (mit Straßennamen-Tabelle) - ca. 20-27 % größer als die alten v2-Werte, s.
        // Doc-Kommentar an `downloadURL`.
        switch self {
        case .badenWuerttemberg: return 563
        case .bayern: return 815
        case .berlin: return 33
        case .brandenburg: return 165
        case .bremen: return 9
        case .hamburg: return 23
        case .hessen: return 290
        case .mecklenburgVorpommern: return 75
        case .niedersachsen: return 326
        case .nordrheinWestfalen: return 543
        case .rheinlandPfalz: return 276
        case .saarland: return 38
        case .sachsen: return 200
        case .sachsenAnhalt: return 132
        case .schleswigHolstein: return 102
        case .thueringen: return 154
        }
    }
}

/// GitHub-Release-Adresse und ungefähre Downloadgröße der Wege-Graphen für Länder außerhalb
/// Deutschlands - eigener Release-Tag (`way-graphs-eu-v1`) statt der Bundesland-Assets
/// (`way-graphs-v4`), da unabhängig davon versioniert (Format ist aber identisch, s.
/// `wayGraphFormatVersion` in `WayGraphStore.swift`).
nonisolated extension EuropaLand {
    var downloadURL: URL {
        URL(string: "https://github.com/Joern2368/RadFaehrte/releases/download/way-graphs-eu-v1/\(rawValue)_ways.sqlite")!
    }

    var approximateSizeMB: Int {
        switch self {
        case .netherlands: return 428
        case .poland: return 1535
        }
    }
}

/// Lädt Wege-Graphen für die "ruhige Wege"-Offline-Routing-Engine herunter (siehe
/// `WayGraphStore`, `BikeRoutingEngine`) und meldet den Fortschritt für die Einstellungen-UI.
/// Generisch über `Region` (`Bundesland` oder `EuropaLand`), analog `WayGraphStore`.
@Observable
final class WayGraphDownloadManager<Region: DownloadableRegion> {
    private let store: WayGraphStore<Region>
    /// Eigene, von `@Observable` verfolgte Eigenschaft statt bei jedem Zugriff frisch
    /// `store.isDownloaded(_:)` (Dateisystem-Check) abzufragen - nur Änderungen an einer
    /// tatsächlichen Property lösen ein SwiftUI-Neurendern aus, ein reiner Methodenaufruf ohne
    /// Property-Zugriff (auch wenn er intern das Dateisystem ändert) tut das nicht.
    private(set) var downloaded: Set<Region>
    private(set) var progress: [Region: Double] = [:]
    var errorMessage: String?

    /// Hält die KVO-Beobachtung des Downloadfortschritts am Leben, solange ein Download läuft -
    /// würde sie nicht referenziert, würde sie sofort wieder freigegeben.
    private var observations: [Region: NSKeyValueObservation] = [:]
    /// Referenz auf den laufenden Download-Task, damit `cancel(_:)` ihn abbrechen kann - ohne
    /// UI-Möglichkeit zum Abbrechen bliebe ein hängender Download (z. B. bei eingeschlafener
    /// WLAN-Verbindung) nur per Kill der ganzen App lösbar.
    private var tasks: [Region: URLSessionDownloadTask] = [:]

    init(store: WayGraphStore<Region>) {
        self.store = store
        downloaded = Set(Region.allCases.filter { store.isDownloaded($0) })
    }

    func isDownloaded(_ region: Region) -> Bool {
        downloaded.contains(region)
    }

    func delete(_ region: Region) {
        // Pfad vor dem Löschen merken (`path(for:)` liefert danach `nil`, da die Datei nicht mehr
        // existiert) - ohne diese Invalidierung würde `ContentView` nach einem erneuten Download
        // unbemerkt weiter mit dem alten, im `WayGraphCache` gehaltenen Graphen rechnen.
        if let path = store.path(for: region) {
            WayGraphCache.shared.invalidate(path: path)
        }
        store.delete(region)
        downloaded.remove(region)
    }

    /// Bricht einen laufenden Download ab (z. B. wenn er hängen geblieben ist). Der
    /// Completion-Handler in `download(_:)` feuert danach trotzdem noch (mit einem
    /// "abgebrochen"-Fehler von URLSession) - dort wird dieser Fall gezielt ignoriert, damit kein
    /// Fehler-Alert für eine vom Nutzer selbst gewollte Aktion erscheint.
    func cancel(_ region: Region) {
        tasks[region]?.cancel()
    }

    func download(_ region: Region) {
        guard progress[region] == nil else { return }
        progress[region] = 0

        let task = URLSession.shared.downloadTask(with: region.downloadURL) { [store] tempURL, _, error in
            // Die Datei muss synchron in diesem Completion-Handler übernommen werden, nicht erst
            // in einem nachgelagerten `Task { @MainActor in ... }` - URLSession löscht die
            // temporäre Datei sofort, sobald der Handler zurückkehrt, und der Hop auf den
            // MainActor kam manchmal zu spät ("... couldn't be moved ... because ... doesn't
            // exist"). `store` ist deshalb `nonisolated` und lässt sich hier direkt aufrufen.
            let wasCancelled = (error as? URLError)?.code == .cancelled
            var errorMessage: String?
            if wasCancelled {
                // Kein Fehler-Alert - der Nutzer hat selbst über `cancel(_:)` abgebrochen.
            } else if let error {
                errorMessage = "Download fehlgeschlagen: \(error.localizedDescription)"
            } else if let tempURL {
                do {
                    try store.save(downloadedFile: tempURL, for: region)
                    // Direkt nach dem Download im Hintergrund vorladen (s. `WayGraphCache`) -
                    // sonst würde die erste tatsächliche Routenberechnung mit dieser Region den
                    // vollen Ladepreis zahlen, obwohl der Download gerade erst fertig wurde und
                    // der Nutzer ohnehin meist noch in den Einstellungen verweilt.
                    if let path = store.path(for: region) {
                        Task.detached(priority: .background) {
                            _ = WayGraphCache.shared.repository(for: path)
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
