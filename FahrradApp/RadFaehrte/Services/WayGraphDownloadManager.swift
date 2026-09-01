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
        // v5: Kanten enthalten zusätzlich ein `wayCategory`-Feld (Radweg/Ruhige Straße/
        // Landstraße/Unbefestigter Weg/Sonstiger Weg, s. `WayGraphRepository.WayCategory`) für die
        // Wegearten-Anzeige ("X km Landstraße" usw., s. ROADMAP.md). Kanten-Record dadurch 17 → 18
        // Byte, Magic `"RFG2"` → `"RFG3"` in `Scripts/build_way_graph_v2.py` - inkompatibel zum
        // alten Format, deshalb neuer Release-Tag statt Assets im alten (way-graphs-v4) zu
        // überschreiben (s. `wayGraphFormatVersion` in `WayGraphStore.swift`, das alte
        // heruntergeladene Dateien beim Formatwechsel automatisch verwirft). Vorherige Historie
        // (v3 UInt16-Namensindex-Überlauf bei Baden-Württemberg, v4-Umstellung auf UInt32) s.
        // Git-Historie dieser Zeile.
        URL(string: "https://github.com/Joern2368/RadFaehrte/releases/download/way-graphs-v5/\(rawValue)_ways.sqlite")!
    }

    var approximateSizeMB: Int {
        // v5-Größen (mit wayCategory-Feld) - ca. 4-6 % größer als die alten v4-Werte (1 von 17
        // Byte mehr pro Kante), s. Doc-Kommentar an `downloadURL`. Reale Release-Asset-Größen nach
        // dem v5-Rebuild (2026-08-17), nicht mehr grob geschätzt.
        switch self {
        case .badenWuerttemberg: return 593
        case .bayern: return 840
        case .berlin: return 32
        case .brandenburg: return 158
        case .bremen: return 11
        case .hamburg: return 22
        case .hessen: return 278
        case .mecklenburgVorpommern: return 72
        case .niedersachsen: return 345
        case .nordrheinWestfalen: return 593
        case .rheinlandPfalz: return 264
        case .saarland: return 36
        case .sachsen: return 191
        case .sachsenAnhalt: return 126
        case .schleswigHolstein: return 97
        case .thueringen: return 148
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
        case .albania: return 140
        case .andorra: return 6
        case .austria: return 929
        case .belgium: return 299
        case .bosniaHerzegovina: return 223
        case .bulgaria: return 268
        case .croatia: return 244
        case .cyprus: return 75
        case .czechia: return 495
        case .denmark: return 286
        case .estonia: return 100
        case .finland: return 908
        case .greece: return 971
        case .hungary: return 309
        case .iceland: return 54
        case .ireland: return 413
        case .kosovo: return 58
        case .latvia: return 133
        case .liechtenstein: return 4
        case .lithuania: return 168
        case .luxembourg: return 35
        case .macedonia: return 63
        case .malta: return 8
        case .monaco: return 1
        case .montenegro: return 70
        case .netherlands: return 428
        case .poland: return 1409
        case .portugal: return 724
        case .romania: return 507
        case .sanMarino: return 2
        case .serbia: return 355
        case .slovakia: return 318
        case .slovenia: return 255
        case .sweden: return 1060
        case .switzerland: return 645
        case .vaticanCity: return 1
        }
    }
}

/// GitHub-Release-Adresse und tatsächliche Downloadgröße der Wege-Graphen für die 21
/// französischen Regionen - eigener Release-Tag (`way-graphs-fr-v1`), analog
/// `way-graphs-eu-v1`/`way-graphs-v4`. Größen nach dem Batch-Build (`Scripts/build_france_regions.sh`,
/// s. ROADMAP.md) mit den tatsächlich gemessenen Werten befüllt.
nonisolated extension FranceRegion {
    var downloadURL: URL {
        URL(string: "https://github.com/Joern2368/RadFaehrte/releases/download/way-graphs-fr-v1/\(rawValue)_ways.sqlite")!
    }

    var approximateSizeMB: Int {
        switch self {
        case .alsace: return 95
        case .aquitaine: return 257
        case .auvergne: return 173
        case .basseNormandie: return 104
        case .bourgogne: return 160
        case .bretagne: return 254
        case .centre: return 176
        case .champagneArdenne: return 93
        case .corse: return 48
        case .francheComte: return 117
        case .hauteNormandie: return 65
        case .ileDeFrance: return 136
        case .languedocRoussillon: return 320
        case .limousin: return 101
        case .lorraine: return 145
        case .midiPyrenees: return 357
        case .nordPasDeCalais: return 140
        case .paysDeLaLoire: return 220
        case .picardie: return 88
        case .poitouCharentes: return 161
        case .provenceAlpesCoteDAzur: return 381
        case .rhoneAlpes: return 532
        }
    }
}

/// GitHub-Release-Adresse und tatsächliche Downloadgröße der Wege-Graphen für die 5
/// italienischen Makro-Regionen - eigener Release-Tag (`way-graphs-it-v1`), analog
/// `way-graphs-fr-v1`.
nonisolated extension ItalyRegion {
    var downloadURL: URL {
        URL(string: "https://github.com/Joern2368/RadFaehrte/releases/download/way-graphs-it-v1/\(rawValue)_ways.sqlite")!
    }

    var approximateSizeMB: Int {
        switch self {
        case .centro: return 527
        case .isole: return 343
        case .nordEst: return 616
        case .nordOvest: return 697
        case .sud: return 516
        }
    }
}

/// GitHub-Release-Adresse und tatsächliche Downloadgröße der Wege-Graphen für die 18
/// spanischen Regionen - eigener Release-Tag (`way-graphs-es-v1`), analog `way-graphs-it-v1`.
nonisolated extension SpainRegion {
    var downloadURL: URL {
        URL(string: "https://github.com/Joern2368/RadFaehrte/releases/download/way-graphs-es-v1/\(rawValue)_ways.sqlite")!
    }

    var approximateSizeMB: Int {
        switch self {
        case .andalucia: return 338
        case .aragon: return 210
        case .asturias: return 78
        case .cantabria: return 56
        case .castillaLaMancha: return 261
        case .castillaYLeon: return 378
        case .cataluna: return 608
        case .ceuta: return 1
        case .extremadura: return 92
        case .galicia: return 250
        case .islasBaleares: return 45
        case .laRioja: return 28
        case .madrid: return 83
        case .melilla: return 1
        case .murcia: return 97
        case .navarra: return 98
        case .paisVasco: return 114
        case .valencia: return 255
        }
    }
}

/// GitHub-Release-Adresse und tatsächliche Downloadgröße der Wege-Graphen für die 6
/// norwegischen Regionen - eigener Release-Tag (`way-graphs-no-v1`), analog `way-graphs-es-v1`.
nonisolated extension NorwayRegion {
    var downloadURL: URL {
        URL(string: "https://github.com/Joern2368/RadFaehrte/releases/download/way-graphs-no-v1/\(rawValue)_ways.sqlite")!
    }

    var approximateSizeMB: Int {
        switch self {
        case .nordNorge: return 144
        case .ostlandet: return 536
        case .sorlandet: return 73
        case .svalbardJanMayen: return 1
        case .trondelag: return 118
        case .vestlandet: return 279
        }
    }
}

/// GitHub-Release-Adresse und tatsächliche Downloadgröße der Wege-Graphen für die 49
/// großbritannischen Regionen - eigener Release-Tag (`way-graphs-gb-v1`), analog
/// `way-graphs-no-v1`. Größen nach dem Batch-Build (`Scripts/build_great_britain_regions.sh`, s.
/// ROADMAP.md) mit den tatsächlich gemessenen Werten befüllt.
nonisolated extension GreatBritainRegion {
    var downloadURL: URL {
        URL(string: "https://github.com/Joern2368/RadFaehrte/releases/download/way-graphs-gb-v1/\(rawValue)_ways.sqlite")!
    }

    var approximateSizeMB: Int {
        switch self {
        case .bedfordshire: return 12
        case .berkshire: return 17
        case .bristol: return 5
        case .buckinghamshire: return 18
        case .cambridgeshire: return 21
        case .cheshire: return 28
        case .cornwall: return 31
        case .cumbria: return 32
        case .derbyshire: return 26
        case .devon: return 54
        case .dorset: return 22
        case .durham: return 22
        case .eastSussex: return 15
        case .eastYorkshireWithHull: return 12
        case .essex: return 34
        case .gloucestershire: return 28
        case .greaterLondon: return 60
        case .greaterManchester: return 37
        case .hampshire: return 47
        case .herefordshire: return 10
        case .hertfordshire: return 23
        case .isleOfWight: return 3
        case .kent: return 44
        case .lancashire: return 32
        case .leicestershire: return 19
        case .lincolnshire: return 36
        case .merseyside: return 16
        case .norfolk: return 36
        case .northYorkshire: return 46
        case .northamptonshire: return 20
        case .northumberland: return 16
        case .nottinghamshire: return 23
        case .oxfordshire: return 19
        case .rutland: return 2
        case .shropshire: return 22
        case .somerset: return 41
        case .southYorkshire: return 21
        case .staffordshire: return 25
        case .suffolk: return 26
        case .surrey: return 28
        case .tyneAndWear: return 15
        case .warwickshire: return 17
        case .westMidlands: return 28
        case .westSussex: return 27
        case .westYorkshire: return 36
        case .wiltshire: return 29
        case .worcestershire: return 16
        case .scotland: return 282
        case .wales: return 141
        }
    }
}

/// Lädt Wege-Graphen für die "ruhige Wege"-Offline-Routing-Engine herunter (siehe
/// `WayGraphStore`, `BikeRoutingEngine`) und meldet den Fortschritt für die Einstellungen-UI.
/// Generisch über `Region` (`Bundesland`, `EuropaLand`, `FranceRegion` oder `ItalyRegion`), analog `WayGraphStore`.
@Observable
final class WayGraphDownloadManager<Region: DownloadableRegion> {
    private let store: WayGraphStore<Region>
    /// Eigene, von `@Observable` verfolgte Eigenschaft statt bei jedem Zugriff frisch
    /// `store.isDownloaded(_:)` (Dateisystem-Check) abzufragen - nur Änderungen an einer
    /// tatsächlichen Property lösen ein SwiftUI-Neurendern aus, ein reiner Methodenaufruf ohne
    /// Property-Zugriff (auch wenn er intern das Dateisystem ändert) tut das nicht.
    private(set) var downloaded: Set<Region>
    private(set) var progress: [Region: Double] = [:]
    /// Regionen, deren Löschen gerade läuft - für einen Ladeindikator in `OfflineMapsView`
    /// (s. Doc-Kommentar an `delete(_:)`).
    private(set) var deletingRegions: Set<Region> = []
    var errorMessage: String?

    init(store: WayGraphStore<Region>) {
        self.store = store
        downloaded = Set(Region.allCases.filter { store.isDownloaded($0) })
        // Läuft ein Download bereits im Hintergrund weiter (z. B. View verlassen und wieder
        // geöffnet, oder App nach einem Hintergrund-Download-Fortschritt neu gestartet) - sofort
        // mit dem aktuellen Fortschritt weiter anzeigen statt bei 0 % neu zu wirken (s.
        // `BackgroundDownloadCoordinator`).
        for region in Region.allCases {
            guard let fraction = BackgroundDownloadCoordinator.shared.currentProgress(
                kind: .wayGraph, regionRawValue: region.rawValue
            ) else { continue }
            progress[region] = fraction
            observeDownload(region)
        }
    }

    func isDownloaded(_ region: Region) -> Bool {
        downloaded.contains(region)
    }

    /// Löscht eine heruntergeladene Region. Läuft in einem `Task.detached` statt synchron auf dem
    /// Main-Thread: Bei großen Regionen (z. B. Polen, ~1,4 GB) blockierte das Freigeben des
    /// gemappten Wege-Graphen (`WayGraphCache.invalidate`) plus das eigentliche Löschen die UI
    /// spürbar (~5 s) ohne jede Rückmeldung - wirkte wie ein nicht erkannter Tastendruck
    /// (Nutzer-Meldung 2026-08-02). `deletingRegions` zeigt währenddessen einen Ladeindikator in
    /// `OfflineMapsView`, analog zum Spinner bei der Kombinationssuche.
    func delete(_ region: Region) {
        guard !deletingRegions.contains(region) else { return }
        // Pfad vor dem Löschen merken (`path(for:)` liefert danach `nil`, da die Datei nicht mehr
        // existiert) - ohne diese Invalidierung würde `ContentView` nach einem erneuten Download
        // unbemerkt weiter mit dem alten, im `WayGraphCache` gehaltenen Graphen rechnen.
        let path = store.path(for: region)
        deletingRegions.insert(region)
        Task.detached { [store] in
            if let path {
                WayGraphCache.shared.invalidate(path: path)
            }
            store.delete(region)
            await MainActor.run { [weak self] in
                self?.downloaded.remove(region)
                self?.deletingRegions.remove(region)
            }
        }
    }

    /// Bricht einen laufenden Download ab (z. B. wenn er hängen geblieben ist).
    func cancel(_ region: Region) {
        BackgroundDownloadCoordinator.shared.cancelDownload(kind: .wayGraph, regionRawValue: region.rawValue)
    }

    /// Registriert die Fortschritts-/Abschluss-Callbacks beim `BackgroundDownloadCoordinator` -
    /// gemeinsam genutzt von `download(_:)` (neuer Download) und `init` (bereits laufender
    /// Hintergrund-Download, s. dortiger Kommentar).
    private func observeDownload(_ region: Region) {
        BackgroundDownloadCoordinator.shared.observe(
            kind: .wayGraph,
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
            kind: .wayGraph, regionRawValue: region.rawValue, url: region.downloadURL
        )
    }
}
