//
//  WayGraphDownloadManager.swift
//  RadFaehrte
//

import Foundation
import Observation

/// GitHub-Release-Adresse und ungefähre Downloadgröße der Wege-Graphen (siehe
/// `Scripts/build_way_graph.py`, hochgeladen als Release-Assets im `RadFaehrte`-Repo).
extension Bundesland {
    var downloadURL: URL {
        // v2: Kanten enthalten zusätzlich einen Versatz-Wert für seitlich verschobene
        // cycleway=track/lane-Darstellung (siehe `BikeRoutingEngine.offsetPoint`) - inkompatibel
        // zum alten Format, deshalb neuer Release-Tag statt Assets im alten zu überschreiben.
        URL(string: "https://github.com/Joern2368/RadFaehrte/releases/download/way-graphs-v2/\(rawValue)_ways.sqlite")!
    }

    /// Tatsächliche Dateigröße der generierten Wege-Graphen (siehe `Scripts/build_way_graph.py`),
    /// für die Anzeige vor dem Download.
    var approximateSizeMB: Int {
        switch self {
        case .badenWuerttemberg: return 448
        case .bayern: return 650
        case .berlin: return 26
        case .brandenburg: return 132
        case .bremen: return 7
        case .hamburg: return 19
        case .hessen: return 231
        case .mecklenburgVorpommern: return 60
        case .niedersachsen: return 259
        case .nordrheinWestfalen: return 432
        case .rheinlandPfalz: return 220
        case .saarland: return 30
        case .sachsen: return 159
        case .sachsenAnhalt: return 105
        case .schleswigHolstein: return 81
        case .thueringen: return 123
        }
    }
}

/// Lädt Wege-Graphen für die "ruhige Wege"-Offline-Routing-Engine herunter (siehe
/// `WayGraphStore`, `BikeRoutingEngine`) und meldet den Fortschritt für die Einstellungen-UI.
@Observable
final class WayGraphDownloadManager {
    private let store: WayGraphStore
    /// Eigene, von `@Observable` verfolgte Eigenschaft statt bei jedem Zugriff frisch
    /// `store.isDownloaded(_:)` (Dateisystem-Check) abzufragen - nur Änderungen an einer
    /// tatsächlichen Property lösen ein SwiftUI-Neurendern aus, ein reiner Methodenaufruf ohne
    /// Property-Zugriff (auch wenn er intern das Dateisystem ändert) tut das nicht.
    private(set) var downloaded: Set<Bundesland>
    private(set) var progress: [Bundesland: Double] = [:]
    var errorMessage: String?

    /// Hält die KVO-Beobachtung des Downloadfortschritts am Leben, solange ein Download läuft -
    /// würde sie nicht referenziert, würde sie sofort wieder freigegeben.
    private var observations: [Bundesland: NSKeyValueObservation] = [:]

    init(store: WayGraphStore) {
        self.store = store
        downloaded = Set(Bundesland.allCases.filter { store.isDownloaded($0) })
    }

    func isDownloaded(_ bundesland: Bundesland) -> Bool {
        downloaded.contains(bundesland)
    }

    func delete(_ bundesland: Bundesland) {
        store.delete(bundesland)
        downloaded.remove(bundesland)
    }

    func download(_ bundesland: Bundesland) {
        guard progress[bundesland] == nil else { return }
        progress[bundesland] = 0

        let task = URLSession.shared.downloadTask(with: bundesland.downloadURL) { [store] tempURL, _, error in
            // Die Datei muss synchron in diesem Completion-Handler übernommen werden, nicht erst
            // in einem nachgelagerten `Task { @MainActor in ... }` - URLSession löscht die
            // temporäre Datei sofort, sobald der Handler zurückkehrt, und der Hop auf den
            // MainActor kam manchmal zu spät ("... couldn't be moved ... because ... doesn't
            // exist"). `store` ist deshalb `nonisolated` und lässt sich hier direkt aufrufen.
            var errorMessage: String?
            if let error {
                errorMessage = "Download fehlgeschlagen: \(error.localizedDescription)"
            } else if let tempURL {
                do {
                    try store.save(downloadedFile: tempURL, for: bundesland)
                } catch {
                    errorMessage = "Speichern fehlgeschlagen: \(error.localizedDescription)"
                }
            } else {
                errorMessage = "Download fehlgeschlagen: keine Datei erhalten."
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observations[bundesland] = nil
                self.progress[bundesland] = nil
                if let errorMessage {
                    self.errorMessage = errorMessage
                } else {
                    self.downloaded.insert(bundesland)
                }
            }
        }

        observations[bundesland] = task.progress.observe(\.fractionCompleted) { [weak self] taskProgress, _ in
            Task { @MainActor in
                self?.progress[bundesland] = taskProgress.fractionCompleted
            }
        }
        task.resume()
    }
}
