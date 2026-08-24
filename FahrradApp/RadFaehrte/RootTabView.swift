//
//  RootTabView.swift
//  RadFaehrte
//

import SwiftUI

private enum AppTab: Hashable {
    case route, history, ownRoutes, settings
}

/// Wurzel-Navigation der App. Angelehnt an gängige Radrouten-Apps (z. B. Komoot), aber bewusst
/// schlank gehalten: "Einstellungen" bekommt erst dann mehr Inhalt, wenn weitere Optionen
/// hinzukommen - siehe ROADMAP.md, Phase 1.5/2.
/// Vier Tabs: "Route" (Suche/Navigation), "Verlauf" (Protokoll tatsächlich gefahrener Touren),
/// "Eigene Routen" (importierte Ziel-Touren zum Nachfahren, z. B. GPX) und "Einstellungen".
struct RootTabView: View {
    @State private var showSplash = true
    @State private var selectedTab: AppTab = .route
    /// Aus dem Eigene-Routen-Tab per "Starten" gesetzt; `ContentView` konsumiert das und setzt sie
    /// anschließend auf `nil` zurück (kein wiederholtes Auslösen bei erneutem Tab-Wechsel).
    @State private var routeToStart: ImportedRoute?
    /// Eine Instanz für die ganze App, damit ein per Teilen-Menü importiertes GPX (`onOpenURL`)
    /// und die Liste im Eigene-Routen-Tab denselben Datenstand sehen.
    private let importedRouteStore = ImportedRouteStore()
    /// Hochgezählt, wenn `onOpenURL` eine neue Tour speichert, damit `OwnRoutesView` seine Liste
    /// neu lädt (sie bekäme sonst nichts mit, falls sie schon sichtbar ist/bleibt).
    @State private var importedRoutesVersion = 0
    /// Eine Instanz für die ganze App, damit eine im Route-Tab beendete Fahrt (`ContentView`)
    /// und die Liste im Verlauf-Tab denselben Datenstand sehen.
    private let drivenTourStore = DrivenTourStore()
    /// Hochgezählt, sobald `ContentView` eine beendete Fahrt speichert, damit `HistoryView` seine
    /// Liste neu lädt (analog `importedRoutesVersion`).
    @State private var drivenToursVersion = 0
    /// Eine Instanz für die ganze App, damit ein in den Einstellungen heruntergeladenes
    /// Bundesland sofort von `ContentView`s "Direkte Fahrrad-Route" gesehen wird.
    private let wayGraphStore = WayGraphStore<Bundesland>()
    /// Analog `wayGraphStore`, aber für Länder außerhalb Deutschlands (aktuell nur Niederlande).
    private let europaWayGraphStore = WayGraphStore<EuropaLand>()
    /// Analog `wayGraphStore`, aber für die 21 französischen Regionen (Frankreich als Ganzes ist
    /// für den Wege-Graph-Bau zu groß, s. `FranceRegion`-Doc-Kommentar).
    private let franceWayGraphStore = WayGraphStore<FranceRegion>()
    /// Analog `franceWayGraphStore`, aber für die 5 italienischen Makro-Regionen (s.
    /// `ItalyRegion`-Doc-Kommentar).
    private let italyWayGraphStore = WayGraphStore<ItalyRegion>()
    /// Analog `franceWayGraphStore`/`italyWayGraphStore`, aber für die 18 spanischen Regionen (s.
    /// `SpainRegion`-Doc-Kommentar).
    private let spainWayGraphStore = WayGraphStore<SpainRegion>()
    /// Eine Instanz für die ganze App, damit ein in den Einstellungen heruntergeladenes
    /// Rastplätze-Bundesland sofort auf der Karte in `ContentView` sichtbar wird - analog
    /// `wayGraphStore`.
    private let restStopStore = RestStopStore<Bundesland>()
    /// Analog `restStopStore`, aber für Länder außerhalb Deutschlands (aktuell nur Luxemburg, s.
    /// `restStopSupportedEuropaLands`).
    private let europaRestStopStore = RestStopStore<EuropaLand>()

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                Tab("Route", systemImage: "bicycle", value: AppTab.route) {
                    ContentView(
                        routeToStart: $routeToStart,
                        drivenTourStore: drivenTourStore,
                        wayGraphStore: wayGraphStore,
                        europaWayGraphStore: europaWayGraphStore,
                        franceWayGraphStore: franceWayGraphStore,
                        italyWayGraphStore: italyWayGraphStore,
                        spainWayGraphStore: spainWayGraphStore,
                        restStopStore: restStopStore,
                        europaRestStopStore: europaRestStopStore,
                        onTourSaved: { drivenToursVersion += 1 }
                    )
                }
                Tab("Verlauf", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                    HistoryView(
                        store: drivenTourStore,
                        refreshTrigger: drivenToursVersion,
                        onStart: { tour in
                            routeToStart = importedRoute(from: tour)
                            selectedTab = .route
                        }
                    )
                }
                Tab("Eigene Routen", systemImage: "square.and.arrow.down.on.square", value: AppTab.ownRoutes) {
                    OwnRoutesView(
                        store: importedRouteStore,
                        refreshTrigger: importedRoutesVersion,
                        onStart: { route in
                            routeToStart = route
                            selectedTab = .route
                        }
                    )
                }
                Tab("Einstellungen", systemImage: "gearshape", value: AppTab.settings) {
                    SettingsView(
                        wayGraphStore: wayGraphStore,
                        europaWayGraphStore: europaWayGraphStore,
                        franceWayGraphStore: franceWayGraphStore,
                        italyWayGraphStore: italyWayGraphStore,
                        spainWayGraphStore: spainWayGraphStore,
                        restStopStore: restStopStore,
                        europaRestStopStore: europaRestStopStore
                    )
                }
            }

            if showSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.3)) {
                showSplash = false
            }
        }
        .task {
            preloadDownloadedWayGraphs()
        }
        .task {
            // Bewusst hier statt in `RadFaehrteApp.init()`: Zu diesem frühen Zeitpunkt gibt es noch
            // kein sichtbares Fenster, aus dem HealthKit den System-Berechtigungsdialog präsentieren
            // könnte - `requestAuthorization` schlägt dort still fehl, ohne dass der Nutzer je
            // gefragt wird (live beobachtet: Watch-Seite, die den Aufruf ebenfalls in `init()`
            // macht, fragte zuverlässig, das iPhone hier zunächst nicht). Sobald `RootTabView`
            // tatsächlich auf dem Bildschirm ist, existiert ein Fenster, von dem aus die Anfrage
            // zuverlässig präsentiert werden kann.
            WorkoutRecorder.shared.requestAuthorizationIfNeeded()
        }
        .onOpenURL(perform: importSharedGPX)
    }

    /// Lädt bereits heruntergeladene Wege-Graphen (Bundesländer + Länder) direkt beim App-Start
    /// im Hintergrund in den `WayGraphCache` vor, statt erst bei der ersten Routenberechnung -
    /// bei großen Ländern (Niederlande: 466 MB) war genau dieses erste Laden beim Live-Test in
    /// Rotterdam spürbar langsam (2026-07-26/27). Ist der Nutzer schon länger in der App
    /// unterwegs (Adresse eingeben, Karte ansehen), bevor er tatsächlich eine Route anfragt, ist
    /// der Graph mit etwas Glück bereits fertig geladen. `.background`-Priorität, damit das nicht
    /// mit dem eigentlichen App-Start/der UI um Ressourcen konkurriert.
    private func preloadDownloadedWayGraphs() {
        let paths = Bundesland.allCases.compactMap { wayGraphStore.path(for: $0) }
            + EuropaLand.allCases.compactMap { europaWayGraphStore.path(for: $0) }
            + FranceRegion.allCases.compactMap { franceWayGraphStore.path(for: $0) }
            + ItalyRegion.allCases.compactMap { italyWayGraphStore.path(for: $0) }
            + SpainRegion.allCases.compactMap { spainWayGraphStore.path(for: $0) }
        guard !paths.isEmpty else { return }
        Task.detached(priority: .background) {
            for path in paths {
                _ = WayGraphCache.shared.repository(for: path)
            }
        }
    }

    /// Wandelt eine Verlaufs-Tour in eine `ImportedRoute` um, um beim Direkt-Starten aus dem
    /// Verlauf-Tab denselben Mechanismus wie bei Eigenen Routen wiederzuverwenden
    /// (`routeToStart`/`ContentView.startImportedRoute`) - beide sind für die Navigation
    /// gleichwertig: eine feste Punktreihenfolge ohne DB-Match. `displayName` liefert bei Touren
    /// ohne eigenen Namen einen datumsbasierten Titel fürs Ziel-Feld.
    private func importedRoute(from tour: DrivenTour) -> ImportedRoute {
        ImportedRoute(name: tour.displayName, coordinates: tour.clCoordinates)
    }

    /// Wird aufgerufen, wenn eine GPX-Datei über das Teilen-Menü/"Öffnen mit" an die App
    /// übergeben wird (siehe `Supplemental-Info.plist`, `CFBundleDocumentTypes`). Speichert die
    /// Tour genauso wie der manuelle Import im Eigene-Routen-Tab und wechselt dorthin, damit
    /// sichtbar wird, dass der Import geklappt hat.
    private func importSharedGPX(url: URL) {
        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer { if didAccessSecurityScope { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let parsed = GPXParser.parse(data: data), parsed.coordinates.count >= 2 else { return }

        let fallbackName = url.deletingPathExtension().lastPathComponent
        let route = ImportedRoute(
            name: parsed.name?.isEmpty == false ? parsed.name! : fallbackName,
            coordinates: parsed.coordinates
        )
        importedRouteStore.save(route)
        importedRoutesVersion += 1
        selectedTab = .ownRoutes
    }
}

#Preview {
    RootTabView()
}
