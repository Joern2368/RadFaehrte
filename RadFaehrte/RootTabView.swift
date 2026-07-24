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
    private let wayGraphStore = WayGraphStore()

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                Tab("Route", systemImage: "bicycle", value: AppTab.route) {
                    ContentView(
                        routeToStart: $routeToStart,
                        drivenTourStore: drivenTourStore,
                        wayGraphStore: wayGraphStore,
                        onTourSaved: { drivenToursVersion += 1 }
                    )
                }
                Tab("Verlauf", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                    HistoryView(store: drivenTourStore, refreshTrigger: drivenToursVersion)
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
                    SettingsView(wayGraphStore: wayGraphStore)
                }
            }

            if showSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.3)) {
                showSplash = false
            }
        }
        .onOpenURL(perform: importSharedGPX)
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
