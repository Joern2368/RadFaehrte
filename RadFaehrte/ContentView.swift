//
//  ContentView.swift
//  RadFaehrte
//

import SwiftUI
import MapKit

struct ContentView: View {
    @AppStorage(AppSettingsKey.averageSpeedKmh) private var averageSpeedKmh = AppSettingsDefaults.averageSpeedKmh

    /// Aus dem Eigene-Routen-Tab per "Starten" gesetzt (siehe `RootTabView`). Wird über `onChange`
    /// konsumiert (`startImportedRoute`) und danach wieder auf `nil` gesetzt.
    @Binding var routeToStart: ImportedRoute?
    /// Für die App gemeinsame Instanz aus `RootTabView`, damit eine hier beendete Fahrt im
    /// Verlauf-Tab (`HistoryView`) auftaucht.
    var drivenTourStore = DrivenTourStore()
    /// Für die App gemeinsame Instanz, um heruntergeladene Bundesländer für die
    /// "ruhige Wege"-Offline-Routing-Engine zu finden (siehe `selectDirectRoute`).
    var wayGraphStore = WayGraphStore<Bundesland>()
    /// Analog `wayGraphStore`, aber für Länder außerhalb Deutschlands (aktuell nur Niederlande).
    var europaWayGraphStore = WayGraphStore<EuropaLand>()
    /// Von `RootTabView` übergeben, um nach dem Speichern einer Fahrt den Verlauf-Tab zum
    /// Neuladen zu bewegen (siehe `HistoryView.refreshTrigger`).
    var onTourSaved: () -> Void = {}
    /// Solange aktiv, ignoriert `runMatching()` Änderungen an `startPlace`/`zielPlace` - die
    /// werden beim Start einer importierten Tour selbst gesetzt (für Marker/Anzeige), sollen
    /// aber keine normale DB-Suche auslösen und das synthetische `RouteMatch` überschreiben.
    /// Wird zurückgesetzt, sobald der Nutzer die Suchfelder selbst bedient (siehe `boundStartPlace`/
    /// `boundZielPlace`) oder tauscht/den aktuellen Standort wählt.
    @State private var isImportedRouteMode = false

    @State private var startPlace: SelectedPlace?
    @State private var zielPlace: SelectedPlace?
    @State private var cameraPosition: MapCameraPosition = .region(Self.germanyRegion)

    @State private var matcher = RouteMatcher(repository: RouteRepository())
    @State private var matches: [RouteMatch] = []
    @State private var selectedMatch: RouteMatch?
    /// Aktuell angezeigte Seite im Wisch-Pager der `resultsSection` (Prototyp: nur eine Zeile
    /// "alle Fahrradtouren" statt einer scrollbaren Liste, Durchblättern per Swipe).
    @State private var pagedMatchIndex = 0
    /// Radrouten in der Nähe des gewählten Starts, solange noch kein Ziel eingegeben wurde -
    /// Vorschau direkt nach der Standortwahl (siehe `loadNearbyMatches`). Sobald ein Ziel gesetzt
    /// wird, übernimmt wieder die normale Start+Ziel-Suche (`matches`).
    @State private var nearbyMatches: [RouteMatch] = []
    /// `true`, solange das Start- bzw. Ziel-Suchfeld aktiv fokussiert ist (Adress-Vorschlagsliste
    /// sichtbar) - blendet währenddessen `resultsSection` aus, damit die Vorschlagsliste den
    /// vollen verfügbaren Platz bekommt statt sich den Bildschirm mit ihr zu teilen.
    @State private var isEditingStart = false
    @State private var isEditingZiel = false
    /// `true`, wenn `matches` nicht von `findMatches` (innerhalb des Schwellenwerts) stammen,
    /// sondern vom Fallback `findClosestMatches` (keine Route in der Nähe gefunden, stattdessen
    /// die nächstgelegenen Vorschläge unabhängig vom Schwellenwert). Steuert den Hinweistext in
    /// `resultsSection`.
    @State private var isFallbackMatches = false
    /// Entlang der jeweiligen Routen-Geometrie berechnete Strecke zwischen den nächstgelegenen
    /// Punkten zu Start und Ziel, pro Routen-ID. Wird asynchron nachgeladen (siehe
    /// `loadRouteSegmentDistances`). Fehlender Key = noch nicht berechnet; Key mit `nil`-Wert =
    /// berechnet, aber kein zusammenhängender Pfad gefunden (z. B. Lücke in den Kartendaten).
    @State private var routeSegmentDistances: [Int64: RouteMatcher.RouteSegmentDistance?] = [:]
    @State private var matchingGeneration = 0

    @State private var locationManager = LocationManager()
    @State private var isNavigating = false
    @State private var showLocationDeniedAlert = false
    @State private var showEndNavigationConfirmation = false
    @State private var isResolvingCurrentLocationForStart = false
    @State private var hasCenteredOnInitialLocation = false
    @State private var selectedRouteLines: [[CLLocationCoordinate2D]] = []
    @State private var is3DEnabled = false
    @State private var isHeadingUpEnabled = true
    /// Nutzer-Wunsch: Anweisungs-Banner + Statistik-Leiste per Button ein-/ausblendbar - ist er
    /// ausgeblendet, geht die Karte bis an den Bildschirmrand, sonst nur bis zur Unterkante des
    /// Banners (s. `mapFillsFullScreen`). Startet bei jeder neuen Navigation wieder eingeblendet
    /// (s. `startNavigating`).
    @State private var isNavigationBannerVisible = true
    /// Nutzer-Feedback: Während der Navigation ist die Tab-Leiste ausgeblendet, daher war der
    /// Einstellungen-Tab (z. B. für eine Tempo-Änderung mitten in der Fahrt) unerreichbar. Zahnrad-
    /// Button in `navigationControlsOverlay` öffnet stattdessen dieses Sheet, Navigation läuft
    /// währenddessen unverändert im Hintergrund weiter.
    @State private var showQuickSettings = false
    @AppStorage(AppSettingsKey.navigationLookaheadMeters) private var navigationLookaheadMeters = AppSettingsDefaults.navigationLookaheadMeters
    @AppStorage(AppSettingsKey.mapStyle) private var mapStyleRaw = AppSettingsDefaults.mapStyle
    @AppStorage(AppSettingsKey.navigationDefaultHeadingUp) private var navigationDefaultHeadingUp = AppSettingsDefaults.navigationDefaultHeadingUp

    /// Ausgelagert aus dem `Map`-Modifier-Aufruf selbst - dort inline führte der Swift-Compiler-
    /// Typchecker sonst zu "unable to type-check this expression in reasonable time" (die ohnehin
    /// schon sehr komplexe `body`-Ausdruck-Kette der Karte wurde dadurch zu viel).
    private var currentMapStyle: MapStyle {
        (MapStyleOption(rawValue: mapStyleRaw) ?? .standard).mapStyle
    }
    @State private var connectorRouteToStart: MKRoute?
    @State private var connectorRouteToEnd: MKRoute?
    @State private var isDirectRouteMode = false
    @State private var isLoadingDirectRoute = false
    @State private var directRoutes: [DirectRoute] = []
    @State private var selectedDirectRouteIndex = 0
    /// `true`, während eine automatische Neuberechnung der "Direkten Fahrrad-Route" wegen
    /// Abweichens von der Strecke läuft (siehe `checkDirectRouteDeviation`) - verhindert
    /// überlappende Neuberechnungen bei mehreren Standort-Updates während eine noch läuft.
    @State private var isRerouting = false
    /// Zeitpunkt der letzten automatischen Neuberechnung - verhindert wiederholtes Neuberechnen,
    /// falls der GPS-Punkt genau um den Schwellenwert herum schwankt.
    @State private var lastRerouteAt: Date?
    @State private var isFollowingUser = true
    @State private var currentRegionSpan: MKCoordinateSpan?
    @State private var tourStartTime: Date?
    @State private var tourDistanceMeters: Double = 0
    /// Aufsummierte positive/negative Höhenänderung seit Navigationsstart (siehe
    /// `accumulateTourDistance`). Naive Punkt-zu-Punkt-Summe wie bei `tourDistanceMeters` - ohne
    /// Barometer entsprechend GPS-rauschanfällig, aber für eine grobe Anzeige ausreichend.
    @State private var tourElevationGainMeters: Double = 0
    @State private var tourElevationLossMeters: Double = 0
    @State private var tourMaxSpeedKmh: Double = 0
    /// Reine Bewegungszeit seit Start, ohne Stillstand (Ampeln, Pausen) - siehe
    /// `accumulateTourDistance` (`isMoving`/`lastMovingUpdateTimestamp`). Im Gegensatz zu
    /// `tourStartTime`, aus dem die "Fahrtzeit" (inkl. Pausen) abgeleitet wird.
    @State private var tourMovingSeconds: Double = 0
    @State private var lastMovingUpdateTimestamp: Date?
    @State private var lastTourLocation: CLLocation?
    @AppStorage(AppSettingsKey.navigationStatFieldCount) private var navigationStatFieldCount = AppSettingsDefaults.navigationStatFieldCount
    @AppStorage(AppSettingsKey.navigationStatSlots) private var navigationStatSlotsRaw = AppSettingsDefaults.navigationStatSlots
    /// Aufgezeichnete Positionen der laufenden Fahrt, fürs Verlauf-Tab (siehe `DrivenTour`).
    @State private var tourTrackPoints: [CLLocationCoordinate2D] = []
    @State private var tourSummary: TourSummary?
    @State private var currentDirectRouteStepIndex = 0
    /// Zuletzt für ein Haptik-Signal an die Apple Watch genutzter Schritt-Index (s.
    /// `checkWatchHapticTrigger`) - verhindert wiederholtes Auslösen für denselben Abbiege-Schritt.
    @State private var lastWatchHapticStepIndex: Int?

    /// Karte geht bis an den Bildschirmrand (kein Rand, keine abgerundeten Ecken), solange
    /// navigiert wird und der Nutzer den Banner per Button ausgeblendet hat. Ist er eingeblendet,
    /// bleibt die Karte wie gewohnt unterhalb des Banners begrenzt (s. `isNavigationBannerVisible`).
    private var mapFillsFullScreen: Bool {
        isNavigating && !isNavigationBannerVisible
    }

    var body: some View {
        VStack(spacing: 12) {
            if !isNavigating {
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 8) {
                        LocationSearchField(
                            label: "Start",
                            selectedPlace: boundStartPlace,
                            isResolvingCurrentLocation: isResolvingCurrentLocationForStart,
                            onUseCurrentLocation: useCurrentLocationAsStart,
                            biasCoordinate: locationManager.currentLocation?.coordinate,
                            onFocusChange: { isEditingStart = $0 }
                        )
                        LocationSearchField(
                            label: "Ziel",
                            selectedPlace: boundZielPlace,
                            biasCoordinate: startPlace?.coordinate ?? locationManager.currentLocation?.coordinate,
                            onFocusChange: { isEditingZiel = $0 }
                        )
                    }

                    Button {
                        swapStartAndZiel()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                    .accessibilityIdentifier("swapStartZiel")
                }
                .padding(.horizontal)
                .padding(.top)
                .zIndex(1)

                if startPlace != nil && !isEditingStart && !isEditingZiel {
                    resultsSection
                        .padding(.horizontal)
                }

                if selectedMatch != nil || isDirectRouteMode {
                    Button {
                        startNavigating()
                    } label: {
                        Label("Los", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                }
            }

            if isNavigating && isNavigationBannerVisible {
                navigationHeaderSection
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            MapReader { proxy in
                Map(position: $cameraPosition) {
                    if let userLocationDisplayCoordinate {
                        Annotation("Standort", coordinate: userLocationDisplayCoordinate) {
                            userLocationMarker
                        }
                        .annotationTitles(.hidden)
                    }
                    if !isNavigating {
                        if let startPlace {
                            Marker(startPlace.title, systemImage: "flag.circle.fill", coordinate: startPlace.coordinate)
                                .tint(.green)
                        }
                        if let zielPlace {
                            Marker(zielPlace.title, systemImage: "flag.checkered.circle.fill", coordinate: zielPlace.coordinate)
                                .tint(.red)
                        }
                    }
                    routeOverlayContent
                    if isNavigating && displayedTourTrackPoints.count >= 2 {
                        MapPolyline(coordinates: displayedTourTrackPoints)
                            .stroke(.red, lineWidth: 5)
                    }
                }
                .mapControls { } // Eigene Steuerelemente (compassBadge, navigationControlsOverlay) statt MapKits Standard-Overlays.
                .mapStyle(currentMapStyle)
                .onMapCameraChange(frequency: .onEnd, handleMapCameraChange)
                .simultaneousGesture(SpatialTapGesture().onEnded { value in
                    handleMapTap(at: value.location, proxy: proxy)
                })
                // Pausiert die Verfolgung sofort bei den ersten Anzeichen eines Zwei-Finger-Zooms.
                // Live per Debug-Log bestätigt: Die Geste selbst feuert zuverlässig, das Problem lag
                // an einem Wettlauf mit dem nächsten automatischen Verfolgungs-Update (bis zu alle
                // 0,5 s) - das setzte die Zoom-Distanz oft zurück, bevor `handleMapCameraChange`
                // (per `.onEnd`-Häufigkeit, also erst nach Loslassen) den Kniff überhaupt als Geste
                // hätte erkennen können. `isFollowingUser` hier sofort auf `false` zu setzen
                // verhindert das automatische Update von vornherein, statt hinterher zu erkennen,
                // dass eins zu viel passiert ist.
                .simultaneousGesture(MagnificationGesture().onChanged { _ in
                    if isNavigating { isFollowingUser = false }
                })
                // Dieselbe Logik für Ein-Finger-Gesten (Verschieben, aber auch MapKits eingebautes
                // "Doppeltippen-und-Halten-dann-Ziehen"-Ein-Finger-Zoom) - `minimumDistance: 10`
                // verhindert, dass ein einfacher Tipp (Routenwahl über `handleMapTap`) fälschlich
                // schon als Verschieben zählt.
                .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in
                    if isNavigating { isFollowingUser = false }
                })
                // Zwei-Finger-Dreh-Geste, ebenfalls direkt statt über den (mittlerweile entfernten)
                // Kamera-Vergleich in `handleMapCameraChange` erkannt - der verglich die von MapKit
                // gemeldete Kamera mit der zuletzt selbst gesetzten und schaltete die Verfolgung
                // fälschlich ab, sobald ein automatisches Update (z. B. eine echte Kurve beim
                // Fahren, oder einfach nur eine kurze GPS-Ungenauigkeit nach längerem Stillstand)
                // nicht exakt zur zuletzt gesetzten Kamera passte - beides keine Nutzer-Gesten.
                .simultaneousGesture(RotationGesture().onChanged { _ in
                    if isNavigating { isFollowingUser = false }
                })
                .overlay(alignment: .topTrailing) {
                    if isNavigating {
                        VStack(spacing: 10) {
                            compassBadge
                            navigationControlsOverlay
                        }
                        .padding()
                    }
                }
                .overlay(alignment: .topLeading) {
                    endNavigationButton
                        .padding()
                }
                .overlay(alignment: .top) {
                    navigationBannerHandle
                }
                .overlay(alignment: .bottom) {
                    recenterButtonOverlay
                        .padding(.bottom, 24)
                }
                .clipShape(RoundedRectangle(cornerRadius: mapFillsFullScreen ? 0 : 12))
            }
            .padding(.horizontal, mapFillsFullScreen ? 0 : nil)
            .padding(.bottom, mapFillsFullScreen ? 0 : nil)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(isNavigating ? .hidden : .visible, for: .tabBar)
        .simultaneousGesture(TapGesture().onEnded {
            hideKeyboard()
        })
        .onAppear {
            switch locationManager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                locationManager.startUpdating()
            default:
                break
            }
        }
        .onChange(of: startPlace) { runMatching(); updateCamera(); loadNearbyMatches() }
        .onChange(of: zielPlace) { runMatching(); updateCamera(); loadNearbyMatches() }
        .onChange(of: selectedMatch) { _, newValue in
            if newValue != nil {
                isDirectRouteMode = false
                directRoutes = []
            }
            selectedRouteLines = newValue.map { Self.mergedLines($0.route.lines) } ?? []
            loadConnectorRoute(to: newValue)
        }
        .onChange(of: routeToStart) { _, newValue in
            if let newValue {
                startImportedRoute(newValue)
                routeToStart = nil
            }
        }
        .onChange(of: locationManager.locationUpdateCount) { handleLocationUpdate() }
        .onChange(of: locationManager.headingUpdateCount) { updateNavigationCamera() }
        .alert("Standortzugriff benötigt", isPresented: $showLocationDeniedAlert) {
            Button("Einstellungen öffnen") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Für den Navigationsmodus wird der Standortzugriff benötigt. Bitte in den Einstellungen erlauben.")
        }
        .confirmationDialog(
            "Navigation pausiert",
            isPresented: $showEndNavigationConfirmation,
            titleVisibility: .visible
        ) {
            // Bewusst kein `role: .cancel` für "Fortsetzen": iOS blendet den Cancel-Button in
            // diesem Dialog-Stil sonst komplett aus (nur Tippen daneben schließt ihn) - für Nutzer
            // nicht ohne Weiteres erkennbar (Nutzer-Feedback). Als normaler Button ohne Rolle
            // steht er garantiert sichtbar neben "Navigation beenden".
            Button("Fortsetzen") {}
            Button("Navigation beenden", role: .destructive) {
                stopNavigating()
            }
        }
        .sheet(item: $tourSummary) { summary in
            tourSummarySheet(summary)
        }
        .sheet(isPresented: $showQuickSettings) {
            NavigationQuickSettingsView()
        }
    }

    private func startNavigating() {
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            showLocationDeniedAlert = true
            return
        default:
            break
        }
        locationManager.requestAuthorization()
        locationManager.startUpdating()
        locationManager.setBackgroundUpdatesEnabled(true)
        UIApplication.shared.isIdleTimerDisabled = true
        isNavigating = true
        isFollowingUser = true
        isNavigationBannerVisible = true
        isHeadingUpEnabled = navigationDefaultHeadingUp
        tourStartTime = Date()
        tourDistanceMeters = 0
        tourElevationGainMeters = 0
        tourElevationLossMeters = 0
        tourMaxSpeedKmh = 0
        tourMovingSeconds = 0
        lastMovingUpdateTimestamp = nil
        lastTourLocation = locationManager.currentLocation
        tourTrackPoints = locationManager.currentLocation.map { [$0.coordinate] } ?? []
        lastSnapSegment = nil
        lastUserMarkerSnapSegment = nil
        isUserLocationSnapped = false
        snappedUserLocationCoordinate = locationManager.currentLocation?.coordinate
        currentDirectRouteStepIndex = 0
        lastWatchHapticStepIndex = nil
        updateWatchNavigationState()
        if let location = locationManager.currentLocation {
            // Bewusst `animated: false` (sofortiges Setzen ohne Animation), nicht
            // `recenterAnimation: true`: Live-Test mit einer sehr langen Strecke (Rotterdam→
            // München, 660 km, 2026-07-27) zeigte, dass MapKit den Kamerawechsel von der
            // Ganze-Route-Übersicht (`.region(...)`, s. `updateCamera`) auf die enge
            // Navigationsansicht (`.camera(...)`, 300 m) bei einem so großen Zoom-Unterschied
            // sichtbar über mehrere Sekunden selbst "kriechen" ließ - unabhängig von der
            // angegebenen SwiftUI-Animationsdauer (weder `recenterAnimation`s 0,6 s noch die
            // normale kurze lineare Animation griffen). Direktes Setzen ohne Animation umgeht das
            // zuverlässig - Geschwindigkeit war dem Nutzer wichtiger als ein animierter Übergang.
            updateNavigationCamera(location: location, animated: false)
        } else {
            withAnimation {
                cameraPosition = .region(Self.regionToFit(
                    [startPlace?.coordinate, zielPlace?.coordinate].compactMap { $0 }
                ))
            }
        }
    }

    private func stopNavigating() {
        locationManager.stopUpdating()
        locationManager.setBackgroundUpdatesEnabled(false)
        UIApplication.shared.isIdleTimerDisabled = false
        isNavigating = false
        lastRerouteAt = nil
        WatchSessionManager.shared.send(.idle)
        if let tourStartTime {
            let duration = Date().timeIntervalSince(tourStartTime)
            let distanceKm = tourDistanceMeters / 1000
            let averageSpeedKmh = duration > 0 ? distanceKm / (duration / 3600) : 0
            // Wird erst beim expliziten Tippen auf "Im Verlauf speichern" im Sheet tatsächlich
            // persistiert (s. `tourSummarySheet`), nicht mehr automatisch hier - Nutzerwunsch,
            // nach jeder Tour selbst wählen zu können statt jede Fahrt ungefragt zu behalten.
            let drivenTour: DrivenTour? = tourTrackPoints.count >= 2
                ? DrivenTour(
                    distanceKm: distanceKm,
                    duration: duration,
                    averageSpeedKmh: averageSpeedKmh,
                    coordinates: Self.decimated(tourTrackPoints)
                )
                : nil
            tourSummary = TourSummary(
                distanceKm: distanceKm,
                duration: duration,
                averageSpeedKmh: averageSpeedKmh,
                drivenTour: drivenTour
            )
        }
        self.tourStartTime = nil
        lastTourLocation = nil
        tourTrackPoints = []
        lastSnapSegment = nil
        lastUserMarkerSnapSegment = nil
        isUserLocationSnapped = false
        snappedUserLocationCoordinate = nil
        // Suche zurücksetzen, damit direkt eine neue Route gesucht werden kann. Setzt zunächst
        // `isImportedRouteMode = false`, damit der anschließende `runMatching()`-Aufruf (getriggert
        // durch die `onChange`-Handler von `startPlace`/`zielPlace`) auch wirklich `matches`,
        // `selectedMatch`, `isDirectRouteMode` etc. mit zurücksetzt statt früh abzubrechen.
        isImportedRouteMode = false
        startPlace = nil
        zielPlace = nil
        updateCamera()
    }

    private func swapStartAndZiel() {
        isImportedRouteMode = false
        swap(&startPlace, &zielPlace)
    }

    /// `LocationSearchField` bindet hierüber statt direkt auf `$startPlace`/`$zielPlace`, damit
    /// jede Bedienung der Suchfelder (Auswahl oder Löschen) `isImportedRouteMode` zurücksetzt -
    /// `startImportedRoute` selbst setzt `startPlace`/`zielPlace` über die rohen `@State`-Werte,
    /// ohne über diesen Weg zu laufen.
    private var boundStartPlace: Binding<SelectedPlace?> {
        Binding(get: { startPlace }, set: { isImportedRouteMode = false; startPlace = $0 })
    }
    private var boundZielPlace: Binding<SelectedPlace?> {
        Binding(get: { zielPlace }, set: { isImportedRouteMode = false; zielPlace = $0 })
    }

    private func useCurrentLocationAsStart() {
        isImportedRouteMode = false
        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            showLocationDeniedAlert = true
            return
        default:
            break
        }
        isResolvingCurrentLocationForStart = true
        locationManager.requestAuthorization()
        locationManager.startUpdating()
        if let location = locationManager.currentLocation {
            resolveCurrentLocationAsStart(location)
        }
    }

    private func handleLocationUpdate() {
        if isNavigating {
            if let location = locationManager.currentLocation {
                accumulateTourDistance(location)
                advanceDirectRouteStepIfNeeded(location)
                checkDirectRouteDeviation(location)
                updateDisplayedUserLocation(location)
                updateWatchNavigationState()
                checkWatchHapticTrigger(location)
            }
            updateNavigationCamera()
        } else if isResolvingCurrentLocationForStart, let location = locationManager.currentLocation {
            resolveCurrentLocationAsStart(location)
        } else if !hasCenteredOnInitialLocation, startPlace == nil, zielPlace == nil,
                  let location = locationManager.currentLocation {
            hasCenteredOnInitialLocation = true
            locationManager.stopUpdating()
            withAnimation {
                cameraPosition = .region(MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
        }
    }

    /// Mindestabstand (Meter) zum zuletzt aufgezeichneten Punkt, bevor ein neuer Punkt für die
    /// rote "gefahrene Strecke"-Linie übernommen wird - ohne diesen Filter erzeugte reines
    /// GPS-Rauschen (v. a. bei langsamer Fahrt/zu Fuß, wo die tatsächliche Bewegung zwischen zwei
    /// Updates kaum größer als die Positionsungenauigkeit ist) eine sichtbar gezackte Linie, weil
    /// jedes einzelne verrauschte Update als eigener Punkt einging. Live auf dem Gerät getestet:
    /// 8 m reichten in dicht bebauter Umgebung nicht, um die Linie ruhig wirken zu lassen.
    private static let minTrackPointDistanceMeters: Double = 18

    /// Geometrie der aktuell gewählten Route, falls bekannt (kuratierte Radroute/importierte Tour
    /// über `selectedRouteLines`, oder "Direkte Fahrrad-Route" über `directRoutes`) - dient
    /// `snapToActiveRoute` zum Einrasten der aufgezeichneten Punkte auf die tatsächliche Straße.
    private var activeNavigationRouteLines: [[CLLocationCoordinate2D]] {
        if isDirectRouteMode, directRoutes.indices.contains(selectedDirectRouteIndex) {
            return [directRoutes[selectedDirectRouteIndex].coordinates]
        }
        return selectedRouteLines
    }

    /// Toleranz fürs Einrasten der roten Linie auf die Routen-Geometrie - bewusst eng (nur echtes
    /// GPS-Rauschen ausgleichen, s. Nutzer-Screenshot: Punkt lag nur wenige Meter neben der
    /// geraden Route), nicht zum Verdecken eines tatsächlichen Abweichens gedacht. Ursprünglich
    /// 15 m, dann komplett entfernt (Zickzack in Kurven durch Segment-Sprünge, s.
    /// `snapToActiveRoute`), jetzt enger als vorher (7 m) wieder eingeführt: Ein so kleiner Radius
    /// kann kaum noch über eine echte Kurve hinweg auf ein "falsches", weiter entferntes Segment
    /// springen.
    private static let routeSnapThresholdKm: Double = 0.007

    /// Einrasten/Lösen-Schwellenwerte für den sichtbaren blauen Standort-Punkt (separat von
    /// `routeSnapThresholdKm`, das nur die rote Strecke betrifft). Bewusst mit zwei
    /// unterschiedlichen Werten (Hysterese) statt einem einzelnen Schwellenwert: Bei nur einem
    /// Wert würde der Punkt bei einer GPS-Position, die genau um die Schwelle herum pendelt,
    /// bei jedem Update zwischen eingerastet/frei hin- und herspringen. Mit einer niedrigeren
    /// Einraste- (10 m) als Löse-Schwelle (20 m) bleibt der einmal erreichte Zustand stabil.
    private static let userLocationSnapEngageThresholdKm: Double = 0.010
    private static let userLocationSnapReleaseThresholdKm: Double = 0.020

    /// Zuletzt zum Einrasten genutztes Segment - für die Trägheit in `snapToActiveRoute`.
    @State private var lastSnapSegment: (start: CLLocationCoordinate2D, end: CLLocationCoordinate2D)?

    /// Analog `lastSnapSegment`, aber für den sichtbaren blauen Punkt (`userLocationDisplayCoordinate`)
    /// statt die rote Strecke - eigener Zustand, da beide unterschiedliche Schwellenwerte nutzen.
    @State private var lastUserMarkerSnapSegment: (start: CLLocationCoordinate2D, end: CLLocationCoordinate2D)?
    @State private var isUserLocationSnapped = false
    @State private var snappedUserLocationCoordinate: CLLocationCoordinate2D?

    /// Rastet einen Punkt auf die nächstgelegene Stelle der aktuellen Routen-Geometrie ein, falls
    /// nah genug (`routeSnapThresholdKm`). Bevorzugt dabei das zuletzt genutzte Segment
    /// (`preferredSegment`) und wechselt nur zu einem anderen, wenn das global nächstgelegene
    /// Segment deutlich (>30 %) näher liegt. Ohne diese Trägheit sprang das Einrasten gerade an
    /// Kurven/Ecken zwischen zwei Segmenten hin und her, sobald beide fast gleich nah lagen -
    /// sichtbar als Zacken in der Linie (Live-Test). Gibt zusätzlich das dabei verwendete Segment
    /// zurück, damit der Aufrufer es sich fürs nächste Mal merken kann.
    private func snapToActiveRoute(
        _ point: CLLocationCoordinate2D,
        preferredSegment: (start: CLLocationCoordinate2D, end: CLLocationCoordinate2D)?,
        thresholdKm: Double = Self.routeSnapThresholdKm
    ) -> (point: CLLocationCoordinate2D, segment: (start: CLLocationCoordinate2D, end: CLLocationCoordinate2D)?) {
        let routeLines = activeNavigationRouteLines
        guard !routeLines.isEmpty, let globalNearest = RouteMatcher.nearestPoint(from: point, toLines: routeLines) else {
            return (point, nil)
        }
        var chosenCoordinate = globalNearest.coordinate
        var chosenDistanceKm = globalNearest.distanceKm
        var chosenSegment = (start: globalNearest.segmentStart, end: globalNearest.segmentEnd)

        if let preferredSegment {
            let onPreferred = RouteMatcher.nearestPoint(from: point, onSegment: preferredSegment.start, preferredSegment.end)
            if onPreferred.distanceKm <= chosenDistanceKm * 1.3 {
                chosenCoordinate = onPreferred.coordinate
                chosenDistanceKm = onPreferred.distanceKm
                chosenSegment = preferredSegment
            }
        }

        guard chosenDistanceKm < thresholdKm else { return (point, nil) }
        return (chosenCoordinate, chosenSegment)
    }

    /// Aktualisiert `snappedUserLocationCoordinate`/`isUserLocationSnapped` für den sichtbaren
    /// blauen Punkt, mit Hysterese (s. `userLocationSnapEngageThresholdKm`/
    /// `...ReleaseThresholdKm`): Solange noch nicht eingerastet, gilt die engere Einraste-Schwelle;
    /// sobald eingerastet, gilt die weitere Löse-Schwelle, damit der Zustand bei leicht
    /// schwankender GPS-Position nicht bei jedem Update kippt.
    private func updateDisplayedUserLocation(_ location: CLLocation) {
        let threshold = isUserLocationSnapped
            ? Self.userLocationSnapReleaseThresholdKm
            : Self.userLocationSnapEngageThresholdKm
        let snap = snapToActiveRoute(location.coordinate, preferredSegment: lastUserMarkerSnapSegment, thresholdKm: threshold)
        lastUserMarkerSnapSegment = snap.segment
        isUserLocationSnapped = snap.segment != nil
        snappedUserLocationCoordinate = snap.point
    }

    /// `tourTrackPoints` plus die aktuelle Live-Position als zusätzlicher, nicht dauerhaft
    /// gespeicherter Endpunkt - nur zum Zeichnen. `tourTrackPoints` selbst wird erst alle
    /// `minTrackPointDistanceMeters` fortgeschrieben (gegen GPS-Rauschen, s. dort), dadurch blieb
    /// die rote Linie sichtbar bis zu ~18 m hinter dem blauen Punkt zurück statt bis zu ihm
    /// durchzugehen. Diese Eigenschaft schließt die Lücke, ohne die gespeicherten (für
    /// Distanzberechnung/Tour-Speicherung genutzten) Punkte selbst dichter zu machen.
    /// Nutzt bewusst dieselbe Koordinate wie der blaue Punkt (`userLocationDisplayCoordinate`)
    /// statt eine eigene `snapToActiveRoute`-Berechnung: Beide unabhängig zu berechnen führte an
    /// Kreuzungen/Rampen mit mehreren nah beieinanderliegenden Routen-Segmenten (unterschiedliche
    /// Einraste-Schwellenwerte für blauen Punkt vs. rote Linie, s. `userLocationSnapEngageThresholdKm`
    /// vs. `routeSnapThresholdKm`) dazu, dass beide auf unterschiedliche Segmente einrasteten - die
    /// rote Linie erschien dadurch sichtbar neben statt exakt hinter dem blauen Punkt
    /// (Nutzer-Screenshot 2026-07-25 an einer Autobahnrampen-Kreuzung). Mit derselben Koordinate
    /// endet die rote Linie jetzt immer exakt dort, wo auch der blaue Punkt sitzt.
    private var displayedTourTrackPoints: [CLLocationCoordinate2D] {
        guard let point = userLocationDisplayCoordinate else { return tourTrackPoints }
        return tourTrackPoints + [point]
    }

    private func accumulateTourDistance(_ location: CLLocation) {
        // Ungenaue Fixe (z. B. zwischen Gebäuden; `horizontalAccuracy < 0` bedeutet ungültig)
        // fließen weder in die Distanz noch in die Linie ein.
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 30 else { return }

        if location.speed >= 0 {
            tourMaxSpeedKmh = max(tourMaxSpeedKmh, location.speed * 3.6)
        }

        // Bei verlässlich niedriger gemeldeter Geschwindigkeit (`speed >= 0` heißt gültig) gilt
        // die Position als Stillstand; bei unbekannter Geschwindigkeit (`< 0`) wie bisher als
        // Bewegung behandelt.
        let isMoving = location.speed < 0 || location.speed >= 0.5

        // Reine Bewegungszeit ("Moving Time", `tourMovingSeconds`): `lastMovingUpdateTimestamp`
        // wird bei *jedem* Update aktualisiert, auch bei Stillstand - sonst würde eine Pause beim
        // nächsten Loslegen fälschlich mitgezählt (der letzte verarbeitete Zeitstempel läge dann
        // vor der Pause). Nur das Zeitintervall selbst wird je nach aktuellem Bewegungszustand
        // gezählt oder verworfen; Cap bei 10 s gegen große Lücken (z. B. App im Hintergrund).
        if let lastMovingUpdateTimestamp {
            let delta = location.timestamp.timeIntervalSince(lastMovingUpdateTimestamp)
            if isMoving, delta > 0, delta < 10 {
                tourMovingSeconds += delta
            }
        }
        lastMovingUpdateTimestamp = location.timestamp

        // Bei Stillstand (z. B. kurz angehalten, in einem Geschäft) kann die gemeldete Position
        // ohne echte Bewegung um mehrere Zehnermeter "wandern", was sonst eine sichtbare
        // Ausreißer-Spitze in der Linie erzeugte.
        guard isMoving else { return }
        if let lastTourLocation {
            tourDistanceMeters += location.distance(from: lastTourLocation)
            if location.verticalAccuracy >= 0, lastTourLocation.verticalAccuracy >= 0 {
                let elevationDelta = location.altitude - lastTourLocation.altitude
                if elevationDelta > 0 {
                    tourElevationGainMeters += elevationDelta
                } else {
                    tourElevationLossMeters += -elevationDelta
                }
            }
        }
        lastTourLocation = location

        let snap = snapToActiveRoute(location.coordinate, preferredSegment: lastSnapSegment)
        lastSnapSegment = snap.segment
        let point = snap.point

        if let last = tourTrackPoints.last {
            let lastLocation = CLLocation(latitude: last.latitude, longitude: last.longitude)
            guard CLLocation(latitude: point.latitude, longitude: point.longitude)
                .distance(from: lastLocation) > Self.minTrackPointDistanceMeters else { return }
        }
        tourTrackPoints.append(point)
    }

    /// Rückt bei der direkten Fahrrad-Route (MKDirections) zum nächsten Navigationsschritt vor,
    /// sobald der Nutzer nah genug (< 30 m) am Ende des aktuellen Schritts ist. Offizielle
    /// Radrouten haben keine Schritt-Daten und werden hier nicht behandelt.
    ///
    /// Reicht dieser einfache Radius-Check nicht (Nutzer-Meldung: nach einem Tunnel ohne
    /// GPS-Empfang blieb die vor dem Tunnel angekündigte Abbiegung stehen, obwohl die Straße
    /// längst hinter dem Nutzer lag, und die Entfernungsanzeige wuchs nur noch), wird zusätzlich
    /// per Fortschritts-Vergleich entlang der Routen-Geometrie nachgeholt: Setzt GPS irgendwo
    /// deutlich weiter vorn auf der Strecke wieder ein (mehrere Schritt-Enden übersprungen, nicht
    /// nur eins), erkennt `nearestSegmentIndex` das am Vergleich der Segment-Indizes und
    /// überspringt alle bereits passierten Schritte auf einmal, statt für immer auf dem
    /// 30-m-Radius um den ersten (längst passierten) Schritt hängen zu bleiben.
    private func advanceDirectRouteStepIfNeeded(_ location: CLLocation) {
        guard isDirectRouteMode, directRoutes.indices.contains(selectedDirectRouteIndex) else { return }
        let route = directRoutes[selectedDirectRouteIndex]
        let steps = route.steps
        guard currentDirectRouteStepIndex < steps.count - 1 else { return }

        let stepEnd = steps[currentDirectRouteStepIndex].endCoordinate
        let stepEndLocation = CLLocation(latitude: stepEnd.latitude, longitude: stepEnd.longitude)
        if location.distance(from: stepEndLocation) < 30 {
            currentDirectRouteStepIndex += 1
            return
        }

        // Der erste Fix nach einer Funklücke (z. B. Tunnelausgang) ist oft noch ungenau (analog
        // `accumulateTourDistance`) - ohne diesen Filter könnte ein einzelner schlecht platzierter
        // Fix den Fortschritts-Vergleich fälschlich zu weit vorspringen lassen.
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 30,
              let locationSegmentIndex = Self.nearestSegmentIndex(of: location.coordinate, in: route.coordinates)
        else { return }
        var advanced = currentDirectRouteStepIndex
        while advanced < steps.count - 1,
              let endSegmentIndex = Self.nearestSegmentIndex(of: steps[advanced].endCoordinate, in: route.coordinates),
              locationSegmentIndex > endSegmentIndex {
            advanced += 1
        }
        if advanced != currentDirectRouteStepIndex {
            currentDirectRouteStepIndex = advanced
        }
    }

    /// Index des Liniensegments in `coordinates`, dem `point` am nächsten liegt - Grundlage für
    /// den Fortschritts-Vergleich in `advanceDirectRouteStepIfNeeded` (ein höherer Index bedeutet
    /// "weiter auf der Route fortgeschritten"). Nutzt dieselbe ebene Punkt-zu-Segment-Projektion
    /// wie `distanceMeters(from:toLine:)`, gibt zusätzlich den Index zurück statt nur die Distanz.
    private static func nearestSegmentIndex(of point: CLLocationCoordinate2D, in coordinates: [CLLocationCoordinate2D]) -> Int? {
        guard coordinates.count >= 2 else { return nil }
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * max(cos(point.latitude * .pi / 180), 0.1)

        func toLocal(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            (
                (c.longitude - point.longitude) * metersPerDegreeLon,
                (c.latitude - point.latitude) * metersPerDegreeLat
            )
        }

        var bestIndex: Int?
        var bestDistance = Double.greatestFiniteMagnitude
        var prev = toLocal(coordinates[0])
        for i in 1..<coordinates.count {
            let curr = toLocal(coordinates[i])
            let distance = distanceFromOriginToSegmentMeters(a: prev, b: curr)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = i - 1
            }
            prev = curr
        }
        return bestIndex
    }

    /// Meter-Schwellenwert, ab dem ein Abweichen von der "Direkten Fahrrad-Route" während der
    /// Navigation eine automatische Neuberechnung auslöst (wie bei Apple/Google Maps). Gilt
    /// bewusst **nicht** für kuratierte Radrouten (`RouteMatch`) - dort will man die Strecke genau
    /// entlangfahren, ein Abweichen soll dorthin zurückführen statt die Route zu ändern (siehe
    /// `loadConnectorRoute`).
    private static let directRouteDeviationThresholdKm: Double = 0.025
    /// Mindestabstand zwischen zwei automatischen Neuberechnungen, damit ein GPS-Punkt, der genau
    /// um den Schwellenwert herum schwankt, nicht wiederholt Netzwerk-/Rechenlast auslöst.
    private static let directRouteRerouteCooldown: TimeInterval = 15

    /// Spiegelt die aktuelle Navigations-Kopfzeile (Anweisung + Live-Entfernung, s.
    /// `navigationInstructionTitle`/`currentStepDistanceText`) an eine gekoppelte Apple Watch -
    /// nutzt bewusst dieselben berechneten Werte wie die iPhone-Anzeige, damit beide nie
    /// auseinanderlaufen können.
    private func updateWatchNavigationState() {
        let direction: WatchNavState.Direction
        switch previewedStep?.direction ?? .straight {
        case .straight: direction = .straight
        case .left: direction = .left
        case .right: direction = .right
        }
        let state = WatchNavState(
            isNavigating: true,
            instructionText: navigationInstructionTitle,
            distanceText: currentStepDistanceText ?? navigationInstructionSubtitle,
            direction: direction,
            routeName: isDirectRouteMode ? nil : selectedMatch?.route.name
        )
        WatchSessionManager.shared.send(state)
    }

    /// Löst ein kurzes Haptik-Signal auf der Apple Watch aus, kurz bevor eine Abbiegung der
    /// "Direkten Fahrrad-Route" ansteht (< 50 m, wie der 30-m-Radius von
    /// `advanceDirectRouteStepIfNeeded`, aber etwas großzügiger, damit die Vibration spürbar vor
    /// der eigentlichen Abbiegung ankommt). Nur bei echten Abbiegungen (`.left`/`.right`) - bei
    /// `.straight` (bzw. kuratierten Radrouten ohne Schritt-Daten) gibt es nichts anzukündigen.
    /// `lastWatchHapticStepIndex` verhindert wiederholtes Auslösen für denselben Schritt.
    private func checkWatchHapticTrigger(_ location: CLLocation) {
        guard isDirectRouteMode, directRoutes.indices.contains(selectedDirectRouteIndex),
              let previewedStep, previewedStep.direction != .straight,
              lastWatchHapticStepIndex != currentDirectRouteStepIndex
        else { return }
        let steps = directRoutes[selectedDirectRouteIndex].steps
        guard steps.indices.contains(currentDirectRouteStepIndex) else { return }
        let stepEnd = steps[currentDirectRouteStepIndex].endCoordinate
        let stepEndLocation = CLLocation(latitude: stepEnd.latitude, longitude: stepEnd.longitude)
        guard location.distance(from: stepEndLocation) < 50 else { return }
        lastWatchHapticStepIndex = currentDirectRouteStepIndex
        WatchSessionManager.shared.sendHapticTurnEvent()
    }

    private func checkDirectRouteDeviation(_ location: CLLocation) {
        guard isDirectRouteMode, !isRerouting, zielPlace != nil,
              directRoutes.indices.contains(selectedDirectRouteIndex) else { return }
        if let lastRerouteAt, Date().timeIntervalSince(lastRerouteAt) < Self.directRouteRerouteCooldown { return }
        guard let nearest = RouteMatcher.nearestPoint(
            from: location.coordinate, toLines: [directRoutes[selectedDirectRouteIndex].coordinates]
        ), nearest.distanceKm > Self.directRouteDeviationThresholdKm else { return }
        rerouteDirectRoute(from: location.coordinate)
    }

    /// Berechnet die "Direkte Fahrrad-Route" vom aktuellen Standort aus neu (Ziel bleibt gleich) -
    /// ausgelöst durch `checkDirectRouteDeviation`, wenn der Nutzer während der Navigation von der
    /// Strecke abweicht. Ersetzt `directRoutes` erst, sobald die neue Route fertig berechnet ist,
    /// damit die Karte in der Zwischenzeit nicht kurz leer wird.
    private func rerouteDirectRoute(from location: CLLocationCoordinate2D) {
        guard let ziel = zielPlace?.coordinate else { return }
        isRerouting = true
        lastRerouteAt = Date()
        let candidatePaths = offlineGraphCandidatePaths()
        Task {
            defer { isRerouting = false }
            var newRoutes: [DirectRoute] = []
            for path in candidatePaths {
                newRoutes = await Self.offlineDirectRoutes(path: path, from: location, to: ziel)
                if !newRoutes.isEmpty { break }
            }
            if newRoutes.isEmpty {
                newRoutes = await Self.directions(from: location, to: ziel, alternates: true)
                    .map(DirectRoute.init(route:))
            }
            guard isDirectRouteMode, isNavigating, !newRoutes.isEmpty else { return }
            directRoutes = newRoutes
            selectedDirectRouteIndex = 0
            currentDirectRouteStepIndex = 0
            lastWatchHapticStepIndex = nil
        }
    }

    /// Pfade aller heruntergeladenen Wege-Graphen (Bundesländer + weitere Länder), in der
    /// Reihenfolge, in der sie für die Offline-Engine versucht werden sollen (s. `loadDirectRoute`/
    /// `rerouteDirectRoute`). `path(for:)` ist eine schnelle, synchrone Existenzprüfung, daher
    /// unproblematisch außerhalb eines Tasks. Es wird bewusst nicht nur die erste gefundene Region
    /// verwendet: Sind z. B. sowohl ein deutsches Bundesland als auch die Niederlande
    /// heruntergeladen, würde sonst ein Fahrtziel in der jeweils anderen Region niemals die
    /// Offline-Engine nutzen, obwohl eine passende Region vorhanden wäre - `offlineDirectRoutes`
    /// liefert für eine nicht abgedeckte Region ohnehin ein leeres Ergebnis, wird also einfach
    /// übersprungen.
    private func offlineGraphCandidatePaths() -> [String] {
        Bundesland.allCases.compactMap { wayGraphStore.path(for: $0) }
            + EuropaLand.allCases.compactMap { europaWayGraphStore.path(for: $0) }
    }

    private func resolveCurrentLocationAsStart(_ location: CLLocation) {
        isResolvingCurrentLocationForStart = false
        locationManager.stopUpdating()
        startPlace = SelectedPlace(title: "Aktueller Standort", subtitle: "", coordinate: location.coordinate)
    }

    /// Wann zuletzt eine *automatische* Verfolgungs-Aktualisierung gesetzt wurde - siehe
    /// `updateNavigationCamera` für den Grund der Drosselung.
    @State private var lastAutomaticCameraUpdate: Date = .distantPast

    /// `animated: false` für den "Standort"-Button (`recenterButtonOverlay`): Nach längerem
    /// manuellem Verschieben kann der Sprung zurück zum Nutzer deutlich größer sein als die
    /// kleinen kontinuierlichen Verfolgungs-Updates während der Fahrt - bei einem großen,
    /// animierten Kamerasprung verschwand das blaue Standort-Symbol dabei beobachtet komplett
    /// von der Karte (MapKit-Eigenheit). Ohne Animation tritt das nicht auf.
    ///
    /// Automatische Aufrufe (aus Standort-/Kompass-Updates, `animated: true`) werden zusätzlich
    /// gedrosselt (`navigationCameraUpdateInterval`), damit nicht mehrere überlappende Animationen
    /// gleichzeitig laufen. Der "Standort"-Button selbst ist von der Drosselung ausgenommen
    /// (`animated: false`), damit er immer sofort reagiert.
    ///
    /// Manuelles Verschieben/Zoomen/Drehen pausiert die Verfolgung über die drei direkten
    /// Gesten-Handler auf der `Map` (`DragGesture`/`MagnificationGesture`/`RotationGesture`).
    /// Ursprünglich gab es zusätzlich einen Vergleich der von MapKit gemeldeten Kamera mit der
    /// zuletzt selbst gesetzten (`handleMapCameraChange`, `camerasRoughlyMatch`) als Rückfalllogik
    /// für die Dreh-Geste, die damals noch keinen eigenen Handler hatte. Live-Test beim Fahren
    /// zeigte aber, dass dieser Vergleich auch ohne jede Nutzer-Geste anschlug - z. B. nach
    /// längerem Stillstand (leicht abweichender GPS-Fix beim Wiederanfahren) oder bei einer
    /// echten, zügigen Kurve (die gemeldete Kamera hinkte der zuletzt gesetzten kurz hinterher) -
    /// und schaltete die Verfolgung dann fälschlich ab. Entfernt und durch den expliziten
    /// `RotationGesture`-Handler ersetzt, der nur auf echte Zwei-Finger-Gesten reagiert.
    private static let navigationCameraUpdateInterval: TimeInterval = 0.3

    /// `recenterAnimation` überschreibt die sonst genutzte lineare Kurz-Animation (s. u.) für den
    /// "Zentrieren"-Banner: ein einzelner, deutlich größerer Sprung nach längerem manuellem
    /// Verschieben wirkt mit einer sanfteren, etwas längeren Ease-Animation weniger abrupt als mit
    /// der sonst für viele kleine, aneinandergereihte Updates gedachten linearen 0,3-s-Animation.
    /// Frühere Version verzichtete beim Zentrieren komplett auf Animation (`animated: false`),
    /// weil ein großer *animierter* Sprung das blaue Standort-Symbol laut Live-Test kurz komplett
    /// verschwinden ließ (MapKit-Eigenheit) - falls das wieder auftritt, ist das der erste
    /// Verdächtige.
    /// Rechnet den einstellbaren "Wieviele Meter voraus sichtbar"-Wert (`navigationLookaheadMeters`,
    /// Einstellungen) in die von `MapCamera` erwartete `distance` um. Nur für die 2D-Ansicht (`pitch:
    /// 0`) kalibriert - bei aktiviertem 3D-Modus verzerrt der gekippte Blickwinkel den Zusammenhang
    /// zwischen `distance` und tatsächlich sichtbaren Metern spürbar, deshalb bleibt 3D bei der
    /// bisherigen festen Distanz. Der Skalierungsfaktor ist eine erste, grobe Schätzung (Live-Test
    /// auf dem iPhone steht noch aus) - er ist so gewählt, dass der Default-Wert exakt die bisherige
    /// feste Distanz von 300 ergibt, es sich für Nutzer, die den Regler nicht anfassen, also nichts
    /// ändert.
    private static let lookaheadMetersToDistanceScale = 300 / AppSettingsDefaults.navigationLookaheadMeters

    private var navigationCameraDistance: CLLocationDistance {
        guard !is3DEnabled else { return 300 }
        return navigationLookaheadMeters * Self.lookaheadMetersToDistanceScale
    }

    private func updateNavigationCamera(
        location: CLLocation? = nil, animated: Bool = true, recenterAnimation: Bool = false
    ) {
        guard isNavigating, isFollowingUser, let location = location ?? locationManager.currentLocation else { return }
        if animated, !recenterAnimation {
            guard Date().timeIntervalSince(lastAutomaticCameraUpdate) > Self.navigationCameraUpdateInterval else { return }
            lastAutomaticCameraUpdate = Date()
        }
        let newCamera = MapCamera(
            centerCoordinate: locationManager.smoothedCameraCoordinate ?? location.coordinate,
            distance: navigationCameraDistance,
            heading: isHeadingUpEnabled ? (locationManager.currentHeading ?? 0) : 0,
            pitch: is3DEnabled ? 60 : 0
        )
        if recenterAnimation {
            withAnimation(.easeInOut(duration: 0.6)) {
                cameraPosition = .camera(newCamera)
            }
        } else if animated {
            // Lineare statt der SwiftUI-Standardanimation (Ease-Out/Federung): Bei aneinander-
            // gereihten automatischen Updates bremste die Standardanimation gegen Ende jedes
            // Segments spürbar ab, bevor das nächste begann - fühlte sich "holprig" an statt
            // gleichmäßig. Linear mit exakt der Drossel-Dauer verbindet die Segmente nahtloser.
            withAnimation(.linear(duration: Self.navigationCameraUpdateInterval)) {
                cameraPosition = .camera(newCamera)
            }
        } else {
            cameraPosition = .camera(newCamera)
        }
    }

    /// Nur noch für `currentRegionSpan` gebraucht (u. a. für "Route einpassen" außerhalb der
    /// Navigation) - das Erkennen manueller Nutzer-Gesten läuft seit dem Live-Test-Fund oben
    /// (s. Doc-Kommentar an `navigationCameraUpdateInterval`) vollständig über die drei direkten
    /// Gesten-Handler auf der `Map`, nicht mehr über einen Kamera-Abgleich hier.
    private func handleMapCameraChange(_ context: MapCameraUpdateContext) {
        currentRegionSpan = context.region.span
    }

    /// Wählt beim Antippen der Karte die geometrisch nächstgelegene Route aus den
    /// Alternativen der direkten Fahrrad-Route aus. MapKits eingebautes `Map(selection:)` +
    /// `.tag()` auf `MapPolyline` erkennt Taps auf dünnen/überlappenden Linien nur sehr
    /// unzuverlässig - dieselbe Punkt-zu-Segment-Projektion wie in
    /// `RouteMatcher.nearestPoint(from:toLines:)`, hier direkt auf `DirectRoute.coordinates`
    /// angewendet, ist deutlich robuster. Die Toleranz skaliert mit dem sichtbaren
    /// Kartenausschnitt, damit sie sowohl beim Heranzoomen als auch beim Übersichtsblick
    /// sinnvoll bleibt.
    private func handleMapTap(at point: CGPoint, proxy: MapProxy) {
        guard isDirectRouteMode, directRoutes.count > 1,
              let tapCoordinate = proxy.convert(point, from: .local) else { return }

        var bestIndex: Int?
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, route) in directRoutes.enumerated() {
            let distance = Self.distanceMeters(from: tapCoordinate, toLine: route.coordinates)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        let latitudeDeltaMeters = (currentRegionSpan?.latitudeDelta ?? 0.02) * 111_320
        let tolerance = max(30, latitudeDeltaMeters * 0.05)
        if let bestIndex, bestDistance < tolerance {
            selectedDirectRouteIndex = bestIndex
        }
    }

    /// Kürzeste Distanz (in Metern) von `point` zu einer Liniengeometrie, über dieselbe ebene
    /// Punkt-zu-Segment-Projektion wie `RouteMatcher.closestPointOnSegmentMeters`.
    private static func distanceMeters(from point: CLLocationCoordinate2D, toLine coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count >= 2 else { return .greatestFiniteMagnitude }

        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * max(cos(point.latitude * .pi / 180), 0.1)

        func toLocal(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            (
                (c.longitude - point.longitude) * metersPerDegreeLon,
                (c.latitude - point.latitude) * metersPerDegreeLat
            )
        }

        var best = Double.greatestFiniteMagnitude
        var prev = toLocal(coordinates[0])
        for i in 1..<coordinates.count {
            let curr = toLocal(coordinates[i])
            best = min(best, distanceFromOriginToSegmentMeters(a: prev, b: curr))
            prev = curr
        }
        return best
    }

    private static func distanceFromOriginToSegmentMeters(
        a: (x: Double, y: Double), b: (x: Double, y: Double)
    ) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0 {
            return (a.x * a.x + a.y * a.y).squareRoot()
        }
        var t = (-a.x * dx - a.y * dy) / lengthSquared
        t = max(0, min(1, t))
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        return (projX * projX + projY * projY).squareRoot()
    }

    /// Kopfzeile im Navigationsmodus mit Richtungspfeil, aktueller Anweisung und Statistik-
    /// Leiste (Tempo/Strecke/Zielentfernung), angelehnt an gängige Rad-Navigations-Apps. Bei der
    /// direkten Fahrrad-Route (online MKDirections oder offline `BikeRoutingEngine`) werden echte
    /// Turn-by-Turn-Anweisungen mit Straßennamen gezeigt, der Pfeil zeigt bei Offline-Routen
    /// zusätzlich die geschätzte Abbiege-Richtung (`navigationInstructionIcon`) und der
    /// Untertitel die Live-Entfernung zur nächsten Anweisung (`currentStepDistanceText`);
    /// offizielle Radrouten haben keine Straßennamen pro Wegabschnitt in der Datenbank, daher
    /// hier nur eine generische "Route folgen"-Anzeige mit Routennamen.
    private var navigationHeaderSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: navigationInstructionIcon)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(navigationInstructionTitle)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text(navigationInstructionSubtitle)
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.62, green: 0.85, blue: 0.90))
                }
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.110, green: 0.290, blue: 0.341)) // Markenfarbe Petrol #1C4A57

            navigationStatsRow
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.background)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top)
        // Nach oben wischen blendet den Banner aus statt eines eigenen Buttons (Nutzer-Wunsch:
        // ein Button weniger auf der Karte) - `translation.height` negativ genug (< -30) reicht als
        // Schwelle, ohne einen normalen Tap auf die Statistik-Leiste versehentlich auszulösen.
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard value.translation.height < -30 else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isNavigationBannerVisible = false
                    }
                }
        )
    }

    /// Ersetzt den Banner, solange er ausgeblendet ist (s. `navigationHeaderSection`): schmaler
    /// Griff statt eines vollen Buttons, damit auf der Karte möglichst wenig Bedienelemente zu sehen
    /// sind. Tap oder Wisch nach unten holen den Banner zurück - Tap zusätzlich zur Wisch-Geste, da
    /// Wischen auf einem so schmalen Ziel weniger zuverlässig zu treffen ist.
    @ViewBuilder
    private var navigationBannerHandle: some View {
        if isNavigating && !isNavigationBannerVisible {
            Capsule()
                .fill(.regularMaterial)
                .frame(width: 44, height: 20)
                .overlay {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isNavigationBannerVisible = true
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onEnded { value in
                            guard value.translation.height > 20 else { return }
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isNavigationBannerVisible = true
                            }
                        }
                )
                .accessibilityIdentifier("showNavigationBanner")
                .accessibilityLabel("Hinweise einblenden")
        }
    }

    /// Nutzer-konfigurierbare Statistik-Leiste (3 oder 6 frei wählbare Felder, s.
    /// `NavigationStatKind` + `SettingsView`) - eine Zeile bei 3 Feldern, zwei Zeilen à drei bei 6.
    private var navigationStatsRow: some View {
        let kinds = navigationStatKinds
        let rows: [[NavigationStatKind]] = kinds.count <= 3
            ? [kinds]
            : [Array(kinds.prefix(3)), Array(kinds.dropFirst(3))]
        return VStack(spacing: 10) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                if rowIndex > 0 {
                    Divider()
                }
                HStack(spacing: 0) {
                    ForEach(rows[rowIndex].indices, id: \.self) { columnIndex in
                        if columnIndex > 0 {
                            Divider().frame(height: 32)
                        }
                        let kind = rows[rowIndex][columnIndex]
                        let display = statDisplay(for: kind)
                        navigationStat(value: display.value, unit: display.unit, label: kind.label)
                    }
                }
            }
        }
    }

    /// Liest die persistierten Slot-Auswahl (`navigationStatSlotsRaw`) und schneidet sie auf die
    /// eingestellte Feld-Anzahl zu. Fehlt ein gespeicherter Slot (z. B. nach App-Update mit neuen
    /// Kategorien), wird mit den Standardwerten aufgefüllt statt eine zu kurze Leiste zu zeigen.
    private var navigationStatKinds: [NavigationStatKind] {
        let parsed = navigationStatSlotsRaw.split(separator: ",").compactMap { NavigationStatKind(rawValue: String($0)) }
        var slots = parsed
        for kind in AppSettingsDefaults.navigationStatSlotsDefaultKinds where slots.count < 6 {
            if !slots.contains(kind) { slots.append(kind) }
        }
        return Array(slots.prefix(navigationStatFieldCount))
    }

    private func navigationStat(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(unit.isEmpty ? value : "\(value) \(unit)")
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Anzeigewert + Einheit für ein einzelnes Statistik-Feld. Leere Einheit bedeutet, dass
    /// `value` bereits die vollständige Anzeige ist (z. B. eine Uhrzeit).
    private func statDisplay(for kind: NavigationStatKind) -> (value: String, unit: String) {
        switch kind {
        case .currentSpeed:
            return (String(format: "%.1f", currentSpeedKmh), "km/h")
        case .distanceTraveled:
            return (String(format: "%.1f", tourDistanceMeters / 1000), "km")
        case .distanceToDestination:
            guard let distanceToDestinationKm else { return ("–", "") }
            return (String(format: "%.1f", distanceToDestinationKm), "km")
        case .arrivalTimeSetSpeed:
            return (arrivalTimeText(speedKmh: averageSpeedKmh) ?? "–", "")
        case .arrivalTimeAverageSpeed:
            return (arrivalTimeText(speedKmh: currentAverageSpeedKmh) ?? "–", "")
        case .averageSpeed:
            return (String(format: "%.1f", currentAverageSpeedKmh), "km/h")
        case .elapsedTime:
            return elapsedTimeDisplay
        case .elevationGain:
            return (String(format: "%.0f", tourElevationGainMeters), "hm")
        case .elevationLoss:
            return (String(format: "%.0f", tourElevationLossMeters), "hm")
        case .maxSpeed:
            return (String(format: "%.1f", tourMaxSpeedKmh), "km/h")
        case .movingTime:
            return movingTimeDisplay
        case .remainingTimeSetSpeed:
            return remainingTimeDisplay(speedKmh: averageSpeedKmh)
        case .remainingTimeAverageSpeed:
            return remainingTimeDisplay(speedKmh: currentAverageSpeedKmh)
        case .currentAltitude:
            guard let currentAltitudeMeters else { return ("–", "") }
            return (String(format: "%.0f", currentAltitudeMeters), "m")
        }
    }

    /// Durchschnittstempo der laufenden Fahrt seit `tourStartTime` (nicht die in den Einstellungen
    /// hinterlegte Wunschgeschwindigkeit, s. `averageSpeedKmh`).
    private var currentAverageSpeedKmh: Double {
        guard let tourStartTime else { return 0 }
        let hours = Date().timeIntervalSince(tourStartTime) / 3600
        guard hours > 0 else { return 0 }
        return (tourDistanceMeters / 1000) / hours
    }

    private var currentAltitudeMeters: Double? {
        guard let location = locationManager.currentLocation, location.verticalAccuracy >= 0 else { return nil }
        return location.altitude
    }

    private var elapsedTimeDisplay: (value: String, unit: String) {
        guard let tourStartTime else { return ("–", "") }
        return durationDisplay(seconds: Int(Date().timeIntervalSince(tourStartTime)))
    }

    private var movingTimeDisplay: (value: String, unit: String) {
        guard tourStartTime != nil else { return ("–", "") }
        return durationDisplay(seconds: Int(tourMovingSeconds))
    }

    private func durationDisplay(seconds: Int) -> (value: String, unit: String) {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return (String(format: "%d:%02d", hours, minutes), "h")
        }
        return ("\(minutes)", "min")
    }

    /// Verbleibende Fahrzeit in Stunden bis zum Ziel, basierend auf der übergebenen Geschwindigkeit
    /// (eingestellte Wunschgeschwindigkeit oder bisheriges Ø-Tempo der Fahrt). `nil` ohne Ziel oder
    /// ohne (noch) plausible Geschwindigkeit - gemeinsame Grundlage für `arrivalTimeText` und
    /// `remainingTimeDisplay`.
    private func remainingHours(speedKmh: Double) -> Double? {
        guard speedKmh > 0, let distanceToDestinationKm else { return nil }
        return distanceToDestinationKm / speedKmh
    }

    /// Geschätzte Ankunftszeit basierend auf der verbleibenden Entfernung zum Ziel und der
    /// übergebenen Geschwindigkeit (s. `remainingHours`).
    private func arrivalTimeText(speedKmh: Double) -> String? {
        guard let remainingHours = remainingHours(speedKmh: speedKmh) else { return nil }
        let arrival = Date().addingTimeInterval(remainingHours * 3600)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: arrival)
    }

    private func remainingTimeDisplay(speedKmh: Double) -> (value: String, unit: String) {
        guard let remainingHours = remainingHours(speedKmh: speedKmh) else { return ("–", "") }
        return durationDisplay(seconds: Int(remainingHours * 3600))
    }

    /// `Step.instructions`/`direction` beschreiben das Manöver **am Anfang** des jeweiligen
    /// Schritts (analog `MKRoute.Step`) - während man `currentDirectRouteStepIndex` entlangfährt,
    /// ist genau die Anweisung des **nächsten** Schritts die bevorstehende Abbiegung, auf die man
    /// sich vorbereiten soll (samt Entfernung zu ihrem Beginn, s. `currentStepDistanceText`) -
    /// nicht die des aktuellen Schritts, die ja beim Betreten schon "passiert" ist. Nur beim
    /// letzten Schritt (kein nächster mehr vorhanden) bleibt es bei dessen eigener Anweisung, da
    /// es nichts mehr anzukündigen gibt.
    private var previewedStep: DirectRoute.Step? {
        guard isDirectRouteMode, directRoutes.indices.contains(selectedDirectRouteIndex) else { return nil }
        let steps = directRoutes[selectedDirectRouteIndex].steps
        guard steps.indices.contains(currentDirectRouteStepIndex) else { return nil }
        if steps.indices.contains(currentDirectRouteStepIndex + 1) {
            return steps[currentDirectRouteStepIndex + 1]
        }
        return steps[currentDirectRouteStepIndex]
    }

    private var navigationInstructionTitle: String {
        guard let previewedStep else { return "Route folgen" }
        return previewedStep.instructions.isEmpty ? "Los geht's" : previewedStep.instructions
    }

    /// Pfeil-Icon passend zur `direction` des angekündigten Schritts (`previewedStep`) - siehe
    /// `DirectRoute.Step.Direction` (nur bei Offline-Routen tatsächlich links/rechts, sonst immer
    /// geradeaus).
    private var navigationInstructionIcon: String {
        switch previewedStep?.direction ?? .straight {
        case .straight: return "arrow.up"
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        }
    }

    /// Live-Entfernung zum Ende des **aktuellen** Schritts (z. B. "In 150 m") - das ist genau der
    /// Punkt, an dem das in `previewedStep` angekündigte Manöver stattfindet. Auf 10 m gerundet,
    /// damit die Anzeige nicht bei jedem GPS-Update um 1-2 m "zittert". `nil` ohne aktive
    /// Schritt-Daten (kuratierte/importierte Routen ohne Straßennamen), dann zeigt die
    /// Kopfzeile stattdessen wie bisher den Routennamen.
    private var currentStepDistanceText: String? {
        guard isDirectRouteMode, directRoutes.indices.contains(selectedDirectRouteIndex),
              let location = locationManager.currentLocation
        else { return nil }
        let steps = directRoutes[selectedDirectRouteIndex].steps
        guard steps.indices.contains(currentDirectRouteStepIndex) else { return nil }
        let end = steps[currentDirectRouteStepIndex].endCoordinate
        let distanceMeters = location.distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
        // Je näher die Abbiegung, desto feiner die Rundung - aus 10-m-Schritten über die ganze
        // Strecke wurde beim Radfahren als zu unruhig empfunden (Nutzer-Feedback); 10 m sind nur
        // noch im Nahbereich (< 100 m) nötig, wo es auf den genauen Punkt ankommt.
        let step: Double = distanceMeters >= 1000 ? 100 : (distanceMeters >= 100 ? 50 : 10)
        let roundedMeters = Int((distanceMeters / step).rounded()) * Int(step)
        if roundedMeters >= 1000 {
            return String(format: "In %.1f km", Double(roundedMeters) / 1000)
        }
        return "In \(roundedMeters) m"
    }

    private var navigationInstructionSubtitle: String {
        if let currentStepDistanceText {
            return currentStepDistanceText
        }
        if isDirectRouteMode {
            return "Direkte Fahrrad-Route"
        }
        return selectedMatch?.route.name ?? "Radroute"
    }

    private var currentSpeedKmh: Double {
        guard let speed = locationManager.currentLocation?.speed, speed >= 0 else { return 0 }
        return speed * 3.6
    }

    private var distanceToDestinationKm: Double? {
        guard let location = locationManager.currentLocation, let ziel = zielPlace?.coordinate else { return nil }
        return location.distance(from: CLLocation(latitude: ziel.latitude, longitude: ziel.longitude)) / 1000
    }

    /// Anzeigeposition des blauen Standort-Punkts: während der Navigation eingerastet auf die
    /// aktive Routen-Geometrie (`snappedUserLocationCoordinate`, s. `updateDisplayedUserLocation`),
    /// sonst die rohe GPS-Position. Ersetzt MapKits `UserAnnotation()`, die sich nicht einrasten
    /// lässt (s. ROADMAP.md, "Offene Idee: blauen Punkt selbst einrasten").
    private var userLocationDisplayCoordinate: CLLocationCoordinate2D? {
        guard let raw = locationManager.currentLocation?.coordinate else { return nil }
        return isNavigating ? (snappedUserLocationCoordinate ?? raw) : raw
    }

    /// Eigene Standort-Markierung statt `UserAnnotation()` (s. `userLocationDisplayCoordinate`).
    private var userLocationMarker: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 20, height: 20)
                .shadow(radius: 1)
            Circle()
                .fill(Color.blue)
                .frame(width: 15, height: 15)
        }
    }

    private var compassBadge: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.85))
            Image(systemName: "location.north.fill")
                .font(.system(size: 13))
                .foregroundStyle(.red)
                .rotationEffect(.degrees(-(locationManager.currentHeading ?? 0)))
        }
        .frame(width: 32, height: 32)
    }

    /// Zwei einzelne schwebende Kreis-Buttons (2D/3D, Heading/Nord-up) statt eines gemeinsamen
    /// Kastens - der Beenden-Button saß dort früher als dritte Zeile direkt daneben und wurde
    /// dadurch beim Bedienen der beiden anderen leicht versehentlich getroffen (Nutzer-Meldung).
    /// Beenden hat jetzt einen eigenen, räumlich getrennten Button (`endNavigationButton`, oben
    /// links statt oben rechts) - zusätzlich zur Sicherheitsabfrage in `confirmEndNavigationDialog`.
    @ViewBuilder
    private var navigationControlsOverlay: some View {
        if isNavigating {
            VStack(spacing: 10) {
                Button {
                    is3DEnabled.toggle()
                    isFollowingUser = true
                    updateNavigationCamera()
                } label: {
                    // Zeigt den Zielzustand (worauf ein Tap umschaltet), nicht den aktuellen -
                    // in 2D-Ansicht steht "3D" (zum Wechseln dorthin) und umgekehrt.
                    // `.regularMaterial` statt `.thinMaterial`: Auf Apple Maps' oft hellen/beigen
                    // Kartenfarben ging der helle, halbtransparente Kreis visuell fast unter
                    // (Nutzer-Feedback). Reines Schwarz (erster Versuch) war dagegen zu dunkel -
                    // gewünscht war nur ein etwas dunklerer Ton desselben Materials, nicht Schwarz.
                    Text(is3DEnabled ? "2D" : "3D")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityIdentifier("toggle2D3D")
                .accessibilityLabel(is3DEnabled ? "Zu 2D wechseln" : "Zu 3D wechseln")

                Button {
                    isHeadingUpEnabled.toggle()
                    isFollowingUser = true
                    updateNavigationCamera()
                } label: {
                    // Kompass-Pfeil (Heading-up) vs. "N"-Buchstabe (Nord-up) statt zweier
                    // Pfeil-Varianten - ein zweiter Pfeil (`arrowtriangle.up.fill`) war dem
                    // Fahrtrichtungs-Pfeil zu ähnlich (Nutzer-Feedback), "N" ist eindeutig als
                    // "Norden" erkennbar und kollidiert nicht mit dem Pfeil-Symbol.
                    if isHeadingUpEnabled {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.orange, in: Circle())
                    } else {
                        Text("N")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.orange, in: Circle())
                    }
                }
                .accessibilityIdentifier("toggleHeadingUp")
                .accessibilityLabel(isHeadingUpEnabled ? "Heading-up" : "Nord-up")

                Button {
                    showQuickSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityIdentifier("openQuickSettings")
                .accessibilityLabel("Einstellungen")
            }
        }
    }

    /// Räumlich getrennt von `navigationControlsOverlay` (oben links statt oben rechts), damit er
    /// nicht mehr versehentlich beim Bedienen von 2D/3D oder Heading-up getroffen wird. Löst nur
    /// noch die Sicherheitsabfrage aus (`confirmEndNavigationDialog`), beendet die Navigation
    /// nicht mehr direkt - Pause-Symbol statt "X", da ein Tap die Fahrt erstmal nur unterbricht
    /// (man kann im Dialog auch "Weiter" wählen), nicht sofort beendet.
    @ViewBuilder
    private var endNavigationButton: some View {
        if isNavigating {
            Button {
                showEndNavigationConfirmation = true
            } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Beenden")
        }
    }

    /// Auffälliger Banner unten mittig statt eines kleinen Icons (Vorbild Komoot: "Zentrieren"-
    /// Hinweis) - taucht nur situativ auf, wenn die Kamera dem Standort nicht mehr folgt (z. B.
    /// nach manuellem Verschieben/Zoomen der Karte), und bringt mit einem Tipp zurück in die
    /// normale Fahrtansicht. Bewusst deutlich sichtbarer als das vorherige kleine Icon unten
    /// rechts, das leicht übersehen wurde.
    @ViewBuilder
    private var recenterButtonOverlay: some View {
        if isNavigating && !isFollowingUser {
            Button {
                isFollowingUser = true
                updateNavigationCamera(recenterAnimation: true)
            } label: {
                Label("Zentrieren", systemImage: "location.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.orange, in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            }
            .accessibilityIdentifier("recenterOnUser")
        }
    }

    @MapContentBuilder
    private var routeOverlayContent: some MapContent {
        if isDirectRouteMode {
            ForEach(Array(directRoutes.enumerated()), id: \.offset) { index, route in
                if index != selectedDirectRouteIndex {
                    MapPolyline(coordinates: route.coordinates)
                        .stroke(Color.gray.opacity(0.7), lineWidth: 4)
                }
            }
            if directRoutes.indices.contains(selectedDirectRouteIndex) {
                MapPolyline(coordinates: directRoutes[selectedDirectRouteIndex].coordinates)
                    .stroke(.blue, lineWidth: 5)
            }
        } else {
            ForEach(Array(selectedRouteLines.enumerated()), id: \.offset) { _, line in
                MapPolyline(coordinates: line)
                    .stroke(.blue, lineWidth: 4)
            }
            if let connectorRouteToStart {
                MapPolyline(connectorRouteToStart.polyline)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
            }
            if let connectorRouteToEnd {
                MapPolyline(connectorRouteToEnd.polyline)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
            }
        }
    }

    /// Macht eine aus dem Verlauf-Tab gestartete, importierte Tour zur aktiven Route. Baut dafür
    /// ein synthetisches `RouteMatch` (die Tourpunkte liegen bereits in Reihenfolge vor, daher
    /// direkt die bekannte Gesamtlänge statt einer Dijkstra-Berechnung) und nutzt anschließend
    /// dieselbe Anzeige-/Wegbeschreibungs-Logik wie bei einem normalen DB-Match: Das bestehende
    /// `.onChange(of: selectedMatch)` setzt `selectedRouteLines` und berechnet über
    /// `loadConnectorRoute` bei Bedarf automatisch eine Wegbeschreibung vom aktuellen Standort
    /// zum Streckenanfang.
    private func startImportedRoute(_ imported: ImportedRoute) {
        let coordinates = imported.clCoordinates
        guard coordinates.count >= 2 else { return }

        let bikeRoute = BikeRoute(
            id: Int64(imported.id.hashValue),
            name: imported.name,
            network: nil,
            ref: nil,
            distanceKm: nil,
            operatorName: nil,
            lines: [coordinates]
        )
        let endCoordinate = coordinates.last!
        let usingCurrentLocation = locationManager.currentLocation != nil
        let startCoordinate = locationManager.currentLocation?.coordinate ?? coordinates.first!
        let nearestToStart = RouteMatcher.nearestPoint(from: startCoordinate, toLines: [coordinates])
        let match = RouteMatch(
            route: bikeRoute,
            distanceToStartKm: nearestToStart?.distanceKm ?? 0,
            distanceToEndKm: 0,
            nearestPointToStart: nearestToStart?.coordinate ?? coordinates.first!,
            nearestPointToEnd: endCoordinate
        )

        isImportedRouteMode = true
        startPlace = SelectedPlace(
            title: usingCurrentLocation ? "Aktueller Standort" : "Streckenanfang",
            subtitle: "", coordinate: startCoordinate
        )
        zielPlace = SelectedPlace(title: imported.name, subtitle: "", coordinate: endCoordinate)
        matches = [match]
        selectedMatch = match
        routeSegmentDistances[bikeRoute.id] = RouteMatcher.RouteSegmentDistance(
            distanceKm: imported.totalDistanceKm, alternateDistanceKm: nil
        )
        updateCamera()
    }

    /// Berechnet eine direkte Fahrrad-Wegbeschreibung von Start zu Ziel, unabhängig vom
    /// importierten Radroutennetz. Für Ziele außerhalb der Reichweite bestehender
    /// Radfernwege/-netze (oder wenn schlicht keine gefunden wurden). Zeigt, falls von
    /// Apple verfügbar, mehrere Routenalternativen zur Auswahl (wie in Karten-Apps üblich).
    private func selectDirectRoute() {
        selectedMatch = nil
        isDirectRouteMode = true
        loadDirectRoute()
    }

    private func loadDirectRoute() {
        directRoutes = []
        selectedDirectRouteIndex = 0
        guard let start = startPlace?.coordinate, let ziel = zielPlace?.coordinate else { return }
        isLoadingDirectRoute = true
        // Bevorzugt die Offline-Engine, falls eine Region (Bundesland oder Land) heruntergeladen
        // ist, die Start und Ziel abdeckt (ruhige Wege statt nur die kürzeste Verbindung) - s.
        // `offlineGraphCandidatePaths`.
        let candidatePaths = offlineGraphCandidatePaths()
        Task {
            for path in candidatePaths {
                let offlineRoutes = await Self.offlineDirectRoutes(path: path, from: start, to: ziel)
                if !offlineRoutes.isEmpty {
                    isLoadingDirectRoute = false
                    if isDirectRouteMode { directRoutes = offlineRoutes }
                    return
                }
            }
            let routes = await Self.directions(from: start, to: ziel, alternates: true)
            isLoadingDirectRoute = false
            if isDirectRouteMode { directRoutes = routes.map(DirectRoute.init(route:)) }
        }
    }

    /// Berechnet die Route(n) über die heruntergeladene Offline-Engine (siehe
    /// `WayGraphRepository`/`BikeRoutingEngine`), abseits des Hauptthreads (A*-Suche). Der Graph
    /// selbst wird über `WayGraphCache` nur beim allerersten Zugriff von der Festplatte geladen -
    /// bei großen Ländern (Niederlande: 466 MB) dauerte das erneute Parsen bei **jeder**
    /// Berechnung spürbar lange (Live-Test Rotterdam, 2026-07-26). Leeres Array, wenn Start oder
    /// Ziel außerhalb der Reichweite der heruntergeladenen Region liegen.
    private static func offlineDirectRoutes(
        path: String, from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D
    ) async -> [DirectRoute] {
        let results = await Task.detached(priority: .userInitiated) { () -> [BikeRoutingEngine.Result] in
            guard let repository = WayGraphCache.shared.repository(for: path) else { return [] }
            return BikeRoutingEngine(repository: repository)
                .routes(from: start, to: end, maxAlternatives: 2)
        }.value
        return results.map(DirectRoute.init(offlineResult:))
    }

    /// Zeigt Wegbeschreibungen zwischen Start/Ziel und dem jeweils nächstgelegenen Punkt der
    /// ausgewählten Route, falls dieser spürbar entfernt liegt (z. B. wenn der Radweg nicht
    /// direkt am Start- oder Zielpunkt beginnt/endet). Nutzt Fahrrad-Wegbeschreibung mit
    /// Fallback auf Fußweg, falls Radrouting für die Region nicht verfügbar ist.
    private func loadConnectorRoute(to match: RouteMatch?) {
        connectorRouteToStart = nil
        connectorRouteToEnd = nil
        guard let match else { return }

        if let start = startPlace?.coordinate, match.distanceToStartKm > 0.05 {
            Task {
                if let route = await Self.directions(from: start, to: match.nearestPointToStart).first {
                    if match.id == selectedMatch?.id { connectorRouteToStart = route }
                }
            }
        }
        if let ziel = zielPlace?.coordinate, match.distanceToEndKm > 0.05 {
            Task {
                if let route = await Self.directions(from: match.nearestPointToEnd, to: ziel).first {
                    if match.id == selectedMatch?.id { connectorRouteToEnd = route }
                }
            }
        }
    }

    private static func directions(
        from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, alternates: Bool = false
    ) async -> [MKRoute] {
        let sourceItem = MKMapItem(location: CLLocation(latitude: source.latitude, longitude: source.longitude), address: nil)
        let destinationItem = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)

        let cyclingRequest = MKDirections.Request()
        cyclingRequest.source = sourceItem
        cyclingRequest.destination = destinationItem
        cyclingRequest.transportType = .cycling
        cyclingRequest.requestsAlternateRoutes = alternates

        if let routes = try? await MKDirections(request: cyclingRequest).calculate().routes, !routes.isEmpty {
            return routes
        }

        let walkingRequest = MKDirections.Request()
        walkingRequest.source = sourceItem
        walkingRequest.destination = destinationItem
        walkingRequest.transportType = .walking
        walkingRequest.requestsAlternateRoutes = alternates

        return (try? await MKDirections(request: walkingRequest).calculate().routes) ?? []
    }

    private func tourSummarySheet(_ summary: TourSummary) -> some View {
        VStack(spacing: 24) {
            Text("Tour beendet")
                .font(.title2.bold())
                .padding(.top, 24)

            HStack(spacing: 32) {
                VStack(spacing: 4) {
                    Text(String(format: "%.1f km", summary.distanceKm))
                        .font(.title3.bold())
                    Text("Strecke")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 4) {
                    Text(formattedTourDuration(summary.duration))
                        .font(.title3.bold())
                    Text("Dauer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 4) {
                    Text(String(format: "%.1f km/h", summary.averageSpeedKmh))
                        .font(.title3.bold())
                    Text("⌀ Tempo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let drivenTour = summary.drivenTour {
                VStack(spacing: 12) {
                    Button("Im Verlauf speichern") {
                        drivenTourStore.save(drivenTour)
                        onTourSaved()
                        tourSummary = nil
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Verwerfen", role: .destructive) {
                        tourSummary = nil
                    }
                }
                .padding(.bottom, 24)
            } else {
                Button("Fertig") {
                    tourSummary = nil
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 24)
            }
        }
        .padding(.horizontal)
        .presentationDetents([.height(summary.drivenTour != nil ? 280 : 220)])
        .interactiveDismissDisabled(summary.drivenTour != nil)
    }

    /// Wisch-Pager für eine Liste von Treffern (verwendet sowohl für `matches` als auch
    /// `nearbyMatches`, mit jeweils passendem Untertitel-Text - Swipen wählt die angezeigte
    /// Seite direkt aus, zeigt sie also sofort auf der Karte.
    @ViewBuilder
    private func matchesPager(_ items: [RouteMatch], subtitle: @escaping (RouteMatch) -> String) -> some View {
        TabView(selection: $pagedMatchIndex) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, match in
                Button {
                    selectedMatch = match
                } label: {
                    matchRow(match, subtitle: subtitle(match))
                        .padding(.bottom, 26)
                }
                .buttonStyle(.plain)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .automatic : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .frame(height: 102)
        .onChange(of: pagedMatchIndex) {
            if items.indices.contains(pagedMatchIndex) {
                selectedMatch = items[pagedMatchIndex]
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        VStack(spacing: 0) {
            if zielPlace == nil {
                // Nur Start gesetzt: Vorschau der Radrouten in der Nähe (siehe `loadNearbyMatches`),
                // bevor überhaupt ein Ziel eingegeben wurde.
                if nearbyMatches.isEmpty {
                    Text("Keine Radroute in der Nähe gefunden")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                } else {
                    Text("Radrouten in der Nähe:")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .padding(.horizontal, 4)
                    matchesPager(nearbyMatches, subtitle: nearbySubtitle(for:))
                }
            } else {
                directRouteSection

                if matches.isEmpty {
                    Divider()
                    Text("Keine passende Radroute in der Nähe gefunden")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                } else {
                    Divider()
                    if isFallbackMatches {
                        Text("Keine Radroute in der Nähe – nächstgelegene Vorschläge:")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                            .padding(.horizontal, 4)
                    }
                    matchesPager(matches, subtitle: subtitle(for:))
                }
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: matches) { pagedMatchIndex = 0 }
        .onChange(of: nearbyMatches) { pagedMatchIndex = 0 }
    }

    /// Einzelne Zeile für die direkte Fahrrad-Route. Bei mehreren Alternativen können diese
    /// direkt auf der Karte per Antippen gewählt werden (siehe `handleMapTap`, per eigenem
    /// Punkt-zu-Linie-Hit-Testing statt MapKits unzuverlässigem `Map(selection:)`).
    @ViewBuilder
    private var directRouteSection: some View {
        Button {
            selectDirectRoute()
        } label: {
            if isDirectRouteMode, directRoutes.indices.contains(selectedDirectRouteIndex) {
                directRouteRow(directRoutes[selectedDirectRouteIndex])
            } else {
                directRoutePlaceholderRow
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("selectDirectRoute")
        Divider()
    }

    private func directRouteRow(_ route: DirectRoute) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(route.isOffline ? "Ruhige Route (offline)" : "Direkte Fahrrad-Route")
                    .font(.subheadline.weight(.medium))
                Text(directRouteSubtitle(for: route))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private func directRouteSubtitle(for route: DirectRoute) -> String {
        var parts = [
            "\(String(format: "%.1f", route.distanceMeters / 1000)) km",
            estimatedTravelTimeText(distanceKm: route.distanceMeters / 1000),
            route.isOffline ? "ruhige Wege bevorzugt" : "außerhalb des Radroutennetzes"
        ]
        if directRoutes.count > 1 {
            parts.append("\(directRoutes.count) Routen – auf Karte wählbar")
        }
        return parts.joined(separator: " · ")
    }

    private var directRoutePlaceholderRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Direkte Fahrrad-Route")
                    .font(.subheadline.weight(.medium))
                Text("Berechnete Route außerhalb des Radroutennetzes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isLoadingDirectRoute {
                ProgressView()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private func matchRow(_ match: RouteMatch, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(match.route.name ?? "Unbenannte Route")
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if match.id == selectedMatch?.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private func subtitle(for match: RouteMatch) -> String {
        var parts: [String] = []
        if let distanceKm = match.route.distanceKm {
            parts.append("\(Int(distanceKm)) km Gesamtlänge")
        }
        if let segmentState = routeSegmentDistances[match.id] {
            if let segment = segmentState {
                var segmentText = "~\(String(format: "%.1f", segment.distanceKm)) km auf der Route"
                if let alternateKm = segment.alternateDistanceKm {
                    segmentText += " (andere Richtung ~\(String(format: "%.1f", alternateKm)) km)"
                }
                parts.append(segmentText)
                parts.append(estimatedTravelTimeText(distanceKm: segment.distanceKm))
            } else {
                parts.append("Kartendaten hier lückenhaft")
            }
        }
        parts.append("~\(String(format: "%.1f", match.combinedDistanceKm)) km Entfernung zur Route")
        return parts.joined(separator: " · ")
    }

    /// Untertitel für die Vorschau-Zeile in `nearbyMatches` (Start ohne Ziel) - anders als
    /// `subtitle(for:)` ohne Streckenlänge-entlang-der-Route (kein zweiter Punkt vorhanden) und
    /// ohne `combinedDistanceKm` (wäre hier doppelt gezählt, siehe `RouteMatcher.findNearby`).
    private func nearbySubtitle(for match: RouteMatch) -> String {
        var parts: [String] = []
        if let distanceKm = match.route.distanceKm {
            parts.append("\(Int(distanceKm)) km Gesamtlänge")
        }
        parts.append("~\(String(format: "%.1f", match.distanceToStartKm)) km entfernt")
        return parts.joined(separator: " · ")
    }

    /// Grobe Fahrzeit-Schätzung (Distanz ÷ in den Einstellungen hinterlegte Durchschnitts-
    /// geschwindigkeit), einheitlich für alle Routenarten verwendet (auch "Direkte Fahrrad-
    /// Route" statt MKDirections' eigener Schätzung, damit die Einstellung überall greift).
    private func estimatedTravelTimeText(distanceKm: Double) -> String {
        guard averageSpeedKmh > 0 else { return "" }
        let minutes = Int((distanceKm / averageSpeedKmh * 60).rounded())
        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            return remainder == 0 ? "ca. \(hours) h" : "ca. \(hours) h \(remainder) min"
        }
        return "ca. \(minutes) Min."
    }

    private func runMatching() {
        guard !isImportedRouteMode else { return }
        matchingGeneration += 1
        routeSegmentDistances = [:]
        guard let start = startPlace?.coordinate, let end = zielPlace?.coordinate else {
            matches = []
            isFallbackMatches = false
            selectedMatch = nil
            isDirectRouteMode = false
            directRoutes = []
            return
        }
        let strictMatches = matcher.findMatches(start: start, end: end)
        if strictMatches.isEmpty {
            matches = matcher.findClosestMatches(start: start, end: end)
            isFallbackMatches = !matches.isEmpty
        } else {
            matches = strictMatches
            isFallbackMatches = false
        }
        loadRouteSegmentDistances(for: matches, generation: matchingGeneration)
        // Vorauswahl: "Direkte Fahrrad-Route" statt automatisch der ersten kuratierten Radroute
        // (Nutzer-Entscheidung) - die kuratierten Treffer bleiben im Wisch-Pager weiterhin wählbar.
        selectDirectRoute()
    }

    /// Radrouten rund um den gewählten Start, solange noch kein Ziel eingegeben ist - Vorschau
    /// direkt nach der Standortwahl statt erst nach vollständiger Start+Ziel-Eingabe. Sobald ein
    /// Ziel gesetzt wird, übernimmt `runMatching()` wieder die normale Suche.
    private func loadNearbyMatches() {
        guard !isImportedRouteMode, zielPlace == nil, let start = startPlace?.coordinate else {
            nearbyMatches = []
            return
        }
        nearbyMatches = matcher.findNearby(around: start)
        pagedMatchIndex = 0
        selectedMatch = nearbyMatches.first
    }

    /// Unterhalb dieser Streckenlänge "auf der Route" (zwischen den nächstgelegenen Punkten zu
    /// Start und Ziel) wird ein Treffer als eigenständige Routenempfehlung ausgefiltert -
    /// Nutzer-Entscheidung: Ein Umweg zu einer benannten Route lohnt sich nicht, wenn man sie
    /// danach nur ein kurzes Stück nutzt (Beispiel: "Premiumroute D15" mit nur ~1,3 km
    /// nutzbarem Abschnitt bei einer insgesamt kurzen Fahrt). Gilt nur für die Start+Ziel-Suche
    /// (`matches`), nicht für die ziellose Nähe-Vorschau (`nearbyMatches`, `RouteMatcher.findNearby`),
    /// die kein Start→Ziel-Teilstück kennt.
    private static let minimumRouteSegmentKm: Double = 5

    /// Berechnet für jeden Treffer im Hintergrund die tatsächlich zu fahrende Strecke entlang
    /// der Routen-Geometrie zwischen den nächstgelegenen Punkten zu Start und Ziel, inklusive
    /// einer längeren Alternative, falls vorhanden (siehe `RouteMatcher.routeSegmentDistance`).
    /// `generation` verwirft veraltete Ergebnisse, falls Start/Ziel sich ändern, bevor eine
    /// frühere Berechnung fertig ist.
    private func loadRouteSegmentDistances(for matches: [RouteMatch], generation: Int) {
        let expectedCount = matches.count
        for match in matches {
            let routeId = match.id
            let lines = match.route.lines
            let start = match.nearestPointToStart
            let end = match.nearestPointToEnd
            Task.detached(priority: .userInitiated) {
                let result = RouteMatcher.routeSegmentDistance(along: lines, from: start, to: end)
                await MainActor.run {
                    guard matchingGeneration == generation else { return }
                    routeSegmentDistances[routeId] = result
                    // Sobald für alle Treffer die tatsächliche Streckenlänge bekannt ist, zu kurze
                    // Treffer aussortieren und den Rest neu sortieren (siehe
                    // `filterAndReorderMatchesByPracticalDistance`).
                    if routeSegmentDistances.count == expectedCount {
                        filterAndReorderMatchesByPracticalDistance()
                    }
                }
            }
        }
    }

    /// Entfernt Treffer, deren Streckenabschnitt "auf der Route" zu kurz ist, um als eigenständige
    /// Routenempfehlung sinnvoll zu sein (`minimumRouteSegmentKm`), oder bei denen sich mangels
    /// zusammenhängendem Pfad (Lücke in den Kartendaten) gar keine Länge ermitteln ließ - für
    /// Letzteres lässt sich ja nicht prüfen, ob der Abschnitt lang genug wäre. Sortiert die
    /// verbleibenden Treffer danach nach der Gesamtstrecke, die man real fahren würde (Anfahrt
    /// zum Streckenanfang + Strecke auf der Route + Anfahrt vom Streckenende zum Ziel) statt nur
    /// nach der Anfahrtsdistanz. So landet ein Fernweg, der nur zufällig nah an Start und Ziel
    /// vorbeikommt, dazwischen aber einen großen Umweg macht, weiter unten als eine Route, die
    /// beide Punkte tatsächlich direkt verbindet. Zeigte die entfernte Auswahl selbst gerade auf
    /// einen jetzt aussortierten Treffer, fällt die Auswahl zurück auf die "Direkte Fahrrad-Route".
    private func filterAndReorderMatchesByPracticalDistance() {
        matches.removeAll { match in
            guard let segment = routeSegmentDistances[match.id], let segment else { return true }
            return segment.distanceKm < Self.minimumRouteSegmentKm
        }
        matches.sort { practicalDistanceKm(for: $0) < practicalDistanceKm(for: $1) }

        if let selectedMatch, !matches.contains(where: { $0.id == selectedMatch.id }) {
            self.selectedMatch = nil
            isDirectRouteMode = true
        }
    }

    /// Realistische Gesamtstrecke für einen Treffer (Anfahrt zum Streckenanfang + Strecke auf der
    /// Route + Anfahrt vom Streckenende zum Ziel).
    private func practicalDistanceKm(for match: RouteMatch) -> Double {
        guard let segment = routeSegmentDistances[match.id], let segment else {
            return .greatestFiniteMagnitude
        }
        return match.distanceToStartKm + segment.distanceKm + match.distanceToEndKm
    }

    private func updateCamera() {
        let coordinates = [startPlace?.coordinate, zielPlace?.coordinate].compactMap { $0 }
        withAnimation {
            cameraPosition = .region(Self.regionToFit(coordinates))
        }
    }

    /// Manche Routen (v.a. regionale Netz-Relationen wie "Radverkehrsnetz Bayern") haben
    /// zehntausende Geometriepunkte; MapKit braucht dafür beim Anzeigen spürbar lange
    /// (>1s), da das Rendern synchron beim View-Update passiert. Für die Darstellung reicht
    /// eine grobe Ausdünnung, die Matching-Logik nutzt weiterhin die volle Auflösung.
    private static func decimated(_ line: [CLLocationCoordinate2D], maxPoints: Int = 500) -> [CLLocationCoordinate2D] {
        guard line.count > maxPoints else { return line }
        let step = max(1, line.count / maxPoints)
        var indices = Swift.stride(from: 0, to: line.count, by: step).map { $0 }
        if indices.last != line.count - 1 {
            indices.append(line.count - 1)
        }
        return indices.map { line[$0] }
    }

    /// Manche Routen bestehen aus tausenden einzelnen, meist sehr kurzen Liniensegmenten
    /// (z. B. "Weser - Romantische Straße": 5256 Segmente, obwohl geometrisch lückenlos
    /// aneinander anschließend). Ein separates `MapPolyline` pro Segment lässt MapKit beim
    /// Hinzufügen der Overlays spürbar hängen (mehrere Sekunden). Hier werden Segmente, die
    /// einen gemeinsamen Endpunkt haben, zu durchgehenden Linien verkettet, um die Anzahl
    /// der Overlays drastisch zu reduzieren. Die Matching-Logik bleibt davon unberührt.
    private static func mergedLines(
        _ lines: [[CLLocationCoordinate2D]], epsilon: Double = 1e-5
    ) -> [[CLLocationCoordinate2D]] {
        func key(_ c: CLLocationCoordinate2D) -> String {
            "\(Int((c.latitude / epsilon).rounded())):\(Int((c.longitude / epsilon).rounded()))"
        }

        var endpointIndex: [String: [(line: Int, atStart: Bool)]] = [:]
        for (i, line) in lines.enumerated() where line.count >= 2 {
            endpointIndex[key(line.first!), default: []].append((i, true))
            endpointIndex[key(line.last!), default: []].append((i, false))
        }

        var used = Array(repeating: false, count: lines.count)

        func unusedNeighbor(at point: CLLocationCoordinate2D) -> (line: Int, atStart: Bool)? {
            endpointIndex[key(point)]?.first { !used[$0.line] }
        }

        var merged: [[CLLocationCoordinate2D]] = []
        for start in 0..<lines.count {
            guard !used[start], lines[start].count >= 2 else { continue }
            used[start] = true
            var chain = lines[start]

            while let next = unusedNeighbor(at: chain.last!) {
                used[next.line] = true
                var nextLine = lines[next.line]
                if !next.atStart { nextLine.reverse() }
                chain.append(contentsOf: nextLine.dropFirst())
            }
            while let prev = unusedNeighbor(at: chain.first!) {
                used[prev.line] = true
                var prevLine = lines[prev.line]
                if prev.atStart { prevLine.reverse() }
                chain.insert(contentsOf: prevLine.dropLast(), at: 0)
            }

            merged.append(decimated(chain))
        }
        return merged
    }

    private static let germanyRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.1657, longitude: 10.4515),
        span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
    )

    private static func regionToFit(_ coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else { return germanyRegion }

        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let minLat = lats.min()!
        let maxLat = lats.max()!
        let minLon = lons.min()!
        let maxLon = lons.max()!

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.05),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.05)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

extension RouteMatch: Equatable {
    static func == (lhs: RouteMatch, rhs: RouteMatch) -> Bool {
        lhs.id == rhs.id
    }
}

struct TourSummary: Identifiable {
    let id = UUID()
    let distanceKm: Double
    let duration: TimeInterval
    let averageSpeedKmh: Double
    /// `nil`, wenn zu wenige Punkte aufgezeichnet wurden (s. `stopNavigating`), um überhaupt eine
    /// sinnvolle Tour zu speichern - dann gibt es im Sheet auch nichts zur Auswahl zu stellen.
    let drivenTour: DrivenTour?
}

/// Eine Option für die "Direkte Fahrrad-Route": online über `MKDirections` berechnet (mit
/// Schritt-für-Schritt-Anweisungen), oder - wenn ein Bundesland heruntergeladen ist und die
/// Strecke abdeckt - offline über `BikeRoutingEngine` (bevorzugt ruhige Wege/Radwege statt nur
/// die kürzeste Verbindung). `MKRoute` selbst lässt sich nicht manuell konstruieren (kein
/// öffentlicher Initializer), daher dieser eigene, leichtgewichtige Typ statt `[MKRoute]`.
struct DirectRoute: Identifiable {
    struct Step {
        /// Grobe Richtung fürs Pfeil-Icon in der Navigations-Kopfzeile. Nur bei Offline-Routen
        /// (`BikeRoutingEngine`) tatsächlich `.left`/`.right` - MKDirections liefert online keine
        /// strukturierte Abbiege-Richtung, nur den fertigen `instructions`-Text (Apples eigene
        /// Formulierung reicht dort bereits ohne zusätzliches Icon).
        enum Direction {
            case straight, left, right
        }

        let instructions: String
        let endCoordinate: CLLocationCoordinate2D
        let direction: Direction
    }

    let id = UUID()
    let coordinates: [CLLocationCoordinate2D]
    let distanceMeters: Double
    let isOffline: Bool
    /// Bei Offline-Routen aus `BikeRoutingEngine.Result.steps` (Straßenname + grob geschätzte
    /// Abbiege-Richtung, s. dort) - leer nur, wenn der heruntergeladene Wege-Graph noch im alten
    /// Format ohne Namen vorliegt oder kein Pfad gefunden wurde. Die Navigations-UI fällt in dem
    /// Fall automatisch auf "Route folgen" zurück, genau wie bei DB-/importierten Routen.
    let steps: [Step]

    init(route: MKRoute) {
        coordinates = route.polyline.coordinates
        distanceMeters = route.distance
        isOffline = false
        steps = route.steps.map {
            Step(instructions: $0.instructions, endCoordinate: $0.polyline.coordinates.last ?? route.polyline.coordinate, direction: .straight)
        }
    }

    init(offlineResult: BikeRoutingEngine.Result) {
        coordinates = offlineResult.coordinates
        distanceMeters = offlineResult.distanceMeters
        isOffline = true
        steps = offlineResult.steps.map {
            let direction: Step.Direction
            switch $0.direction {
            case .straight: direction = .straight
            case .left: direction = .left
            case .right: direction = .right
            }
            return Step(instructions: $0.instructions, endCoordinate: $0.endCoordinate, direction: direction)
        }
    }
}

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

private func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

#Preview {
    ContentView(routeToStart: .constant(nil))
}
