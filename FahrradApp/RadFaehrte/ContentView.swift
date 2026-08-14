//
//  ContentView.swift
//  RadFaehrte
//

import SwiftUI
import MapKit

/// Ergebnis der Straßennamen-Suche für einen kuratierten Treffer/eine kombinierte Kette (s.
/// `curatedRouteStepsDetailSheet`/`combinedRouteDetailSheet`) - unterscheidet zwei grundverschiedene
/// Fehlschlags-Ursachen, damit die Fehlermeldung nicht pauschal auf den Wege-Graph-Download
/// verweist, wenn der eigentliche Grund ein anderer ist (Live-Fund 2026-08-01, Nutzer testete
/// Münster -> Dortmund: "Deutsche Fußball Route NRW" zeigte in der Ergebnisliste bereits
/// "Kartendaten hier lückenhaft" - `routeSegmentPath` findet für diesen Abschnitt schon keinen
/// durchgehenden Pfad in der Routen-Geometrie selbst, unabhängig vom Wege-Graphen. Ein
/// Wege-Graph-Download hätte daran nichts geändert).
private enum CuratedRouteStepsAvailability {
    case steps([BikeRoutingEngine.Result.Step])
    /// Echte Lücke in der Routen-Geometrie zwischen Start und Ziel (s.
    /// `RouteMatcher.routeSegmentPathAllowingGap`), aber mindestens eine Seite bis dahin ließ sich
    /// gegen einen heruntergeladenen Wege-Graphen matchen - analog zur bereits bestehenden
    /// Teil-Anzeige bei kombinierten Ketten (`ContentView.matchCuratedRouteSteps(forLegs:)`), wo
    /// einzelne Etappen ohne Geometrie übersprungen werden. `nil` auf einer Seite, wenn dort keine
    /// Geometrie vorlag oder das Matching dort scheiterte - die Sheet-Darstellung zeigt dann nur
    /// die andere Seite plus den Lücken-Hinweis.
    case partialSteps(fromStart: [BikeRoutingEngine.Result.Step]?, toEnd: [BikeRoutingEngine.Result.Step]?, gapDistanceKm: Double)
    /// `RouteMatcher.routeSegmentPathAllowingGap`/`pathCoordinates` fanden nicht einmal auf einer
    /// Seite der Lücke einen Ansatzpunkt (z. B. Anker zu weit von der Routen-Geometrie entfernt) -
    /// derselbe Grund, aus dem die Ergebnisliste an dieser Stelle "Kartendaten hier lückenhaft"
    /// zeigt (s. `ContentView.subtitle(for:)`). Ein heruntergeladener Wege-Graph würde daran nichts
    /// ändern.
    case noRouteGeometry
    /// Die Routen-Geometrie war durchgehend, aber kein heruntergeladener Wege-Graph deckte sie
    /// ausreichend ab (s. `CuratedRouteStepMatcher.minMatchedFraction`).
    case noWayGraphMatch
}

struct ContentView: View {
    @AppStorage(AppSettingsKey.averageSpeedKmh) private var averageSpeedKmh = AppSettingsDefaults.averageSpeedKmh

    /// Aus dem Eigene-Routen-Tab per "Starten" gesetzt (siehe `RootTabView`). Wird über `onChange`
    /// konsumiert (`startImportedRoute`) und danach wieder auf `nil` gesetzt.
    @Binding var routeToStart: ImportedRoute?
    /// Für die App gemeinsame Instanz aus `RootTabView`, damit eine hier beendete Fahrt im
    /// Verlauf-Tab (`HistoryView`) auftaucht.
    var drivenTourStore = DrivenTourStore()
    /// Für "Zuhause"/"Arbeit" + eigene Favoriten-Orte in den Suchfeldern (s. `favoritePlaces`).
    private let favoritePlaceStore = FavoritePlaceStore()
    /// Für die "Zuletzt gesucht"-Zeilen in den Suchfeldern (s. `recentPlaces`) - getrennt von
    /// `favoritePlaceStore`, da hier automatisch bei jeder Adressauswahl mitgeschrieben wird statt
    /// bewusst gespeichert.
    private let recentPlaceStore = RecentPlaceStore()
    /// Für die App gemeinsame Instanz, um heruntergeladene Bundesländer für die
    /// "ruhige Wege"-Offline-Routing-Engine zu finden (siehe `selectDirectRoute`).
    var wayGraphStore = WayGraphStore<Bundesland>()
    /// Analog `wayGraphStore`, aber für Länder außerhalb Deutschlands (aktuell nur Niederlande).
    var europaWayGraphStore = WayGraphStore<EuropaLand>()
    /// Analog `wayGraphStore`, aber für die 21 französischen Regionen (s. `FranceRegion`).
    var franceWayGraphStore = WayGraphStore<FranceRegion>()
    /// Analog `wayGraphStore`, aber für die 5 italienischen Makro-Regionen (s. `ItalyRegion`).
    var italyWayGraphStore = WayGraphStore<ItalyRegion>()
    /// Analog `wayGraphStore`, aber für die 18 spanischen Regionen (s. `SpainRegion`).
    var spainWayGraphStore = WayGraphStore<SpainRegion>()
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

    @State private var favoritePlaces: [FavoritePlace] = []
    @State private var recentPlaces: [RecentPlace] = []
    /// Welches Feld gerade einen Favoriten speichern will (`.start`/`.ziel`) - steuert sowohl den
    /// Auswahl-Dialog (`favoriteKindChoiceField`) als auch den Namens-Alert
    /// (`favoriteCustomNameField`), damit beide wissen, welchen `SelectedPlace` sie sichern.
    fileprivate enum FavoriteTargetField { case start, ziel }
    @State private var favoriteKindChoiceField: FavoriteTargetField?
    @State private var favoriteCustomNameField: FavoriteTargetField?
    @State private var favoriteCustomNameInput = ""

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
    /// Aktiv zwischen Antippen von "Auf Karte wählen" im Ziel-Feld und dem nächsten Kartentipp
    /// (Nutzer-Idee: Ziel per Fingertipp setzen statt nur über die Adresssuche). Bewusst ein
    /// expliziter Modus statt jeden Kartentipp automatisch als Ziel zu werten - sonst würde
    /// normales Erkunden/Verschieben der Karte versehentlich das Ziel ändern. Deaktiviert sich
    /// nach dem nächsten Tipp automatisch wieder (s. `handleMapTap`).
    @State private var isPickingZielOnMap = false
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
    /// Alle aktuell laufenden Hintergrund-Suchvorgänge der laufenden `runMatching()`-Runde
    /// (Kombinationssuche, Streckenlängen-Berechnung, EuroVelo-/D-Routen-Suche). Bisher verwarf
    /// `runMatching()` bei einer neuen Suche nur das *Ergebnis* alter Suchen über den
    /// `matchingGeneration`-Zähler, brach die eigentliche (teils mehrere Sekunden dauernde)
    /// Hintergrundberechnung selbst aber nicht ab - sie lief einfach ungenutzt weiter und
    /// verbrauchte dabei CPU-Zeit, die sich eine schnell danach gestartete neue Suche mit ihr
    /// teilen musste (Nutzer-Beobachtung 2026-07-31: schnell hintereinander ausgeführte Suchen
    /// wurden spürbar langsamer als eine einzelne). `cancelActiveSearchTasks()` bricht diese Tasks
    /// jetzt beim Start einer neuen Suche wirklich ab (s. `RouteMatcher.findCombinedMatches`s
    /// `Task.isCancelled`-Prüfung in der Hauptsuchschleife).
    @State private var activeSearchTasks: [Task<Void, Never>] = []
    /// Gefundene Verkettung mehrerer benannter Fernwege (z. B. Weser-Radweg -> Aller-Radweg ->
    /// Leine-Heide-Radweg), falls `findMatches` keine einzelne passende Route findet - Fallback
    /// noch vor `findClosestMatches` (s. `runMatching`), da eine passende Kombination nützlicher
    /// ist als eine sachlich unpassende, nur zufällig nahe Einzelroute. Geschwister-State zu
    /// `selectedMatch`/`isDirectRouteMode`, nicht in ein gemeinsames Enum zusammengeführt (folgt
    /// dem bestehenden Muster dieser Datei).
    @State private var combinedMatch: RouteMatcher.CombinedRouteMatch?
    /// Alle von `findCombinedMatches` gefundenen Alternativen (`combinedMatch` ist die aktuell
    /// ausgewählte/angezeigte davon, analog zu `matches`/`selectedMatch`) - Nutzer-Wunsch
    /// (2026-07-30): swipebare Alternativen wie beim Wisch-Pager für einzelne Treffer
    /// (`matchesPager`), da nicht immer die von der Suche bevorzugte Kette die subjektiv
    /// gewünschte ist (z. B. eine bekannte EuroVelo-Route als Alternative zu einer technisch
    /// kürzeren, aber unbekannteren Kombination).
    @State private var combinedMatches: [RouteMatcher.CombinedRouteMatch] = []
    @State private var pagedCombinedMatchIndex = 0
    /// Zeigt bei Antippen des Info-Buttons in `combinedRouteRow` ein Sheet mit allen Etappen der
    /// gewählten Kombination (Nutzer-Wunsch 2026-07-30: der Titel-Text `routeNames.joined(...)`
    /// schneidet lange Ketten in der schmalen Ergebniszeile sichtbar ab, z. B. bei München ->
    /// Nürnberg mit 8 Etappen).
    @State private var combinedRouteDetail: RouteMatcher.CombinedRouteMatch?
    /// `true`, während die Kombinationssuche (+ ggf. anschließender `findClosestMatches`-Fallback)
    /// im Hintergrund läuft - kann je nach Region/Hardware mehrere Sekunden dauern. Ohne diesen
    /// Hinweis zeigte `resultsSection` in der Zwischenzeit fälschlich schon die Leermeldung
    /// "Keine passende Radroute gefunden", obwohl die Suche noch gar nicht fertig war (Live-Test:
    /// München -> Nürnberg wirkte dadurch wie ein Fehlschlag, obwohl die Suche nur noch lief).
    @State private var isSearchingCombinedMatch = false

    /// Map-Matching-Versuch (s. ROADMAP.md, `CuratedRouteStepMatcher`): Zeigt bei Antippen des
    /// Info-Buttons in `matchRow` ein Sheet mit Straßennamen/Abbiege-Hinweisen für den gewählten
    /// Einzeltreffer, analog zu `combinedRouteDetail`. Bewusst als eigener, einfacher Info-Button
    /// statt in die Live-Navigation integriert (die zeigt Turn-by-Turn bisher nur für die
    /// "Direkte Fahrrad-Route", s. `isDirectRouteMode`/`previewedStep`) - kleinerer, risikoärmerer
    /// erster Schritt, der die bestehende Navigations-State-Machine nicht anfasst.
    @State private var curatedRouteStepsDetail: RouteMatch?
    /// `nil` = noch nicht geladen, s. `curatedRouteStepsDetailSheet`/`CuratedRouteStepsAvailability`.
    @State private var curatedRouteStepsResult: CuratedRouteStepsAvailability?
    @State private var isLoadingCuratedRouteSteps = false
    /// Straßennamen/Abbiege-Hinweise für den aktuell **ausgewählten** Einzeltreffer (`selectedMatch`),
    /// als vollwertige `DirectRoute` (Koordinaten + Schritte) - anders als `curatedRouteStepsResult` (nur
    /// für die On-Demand-Vorschau eines beliebigen, noch nicht zwingend ausgewählten Treffers) wird
    /// das hier für die tatsächlich laufende Turn-by-Turn-Navigation gebraucht (s. `activeStepRoute`).
    /// Wird proaktiv bei jeder Auswahl geladen (`.onChange(of: selectedMatch)`), nicht erst beim
    /// Start der Navigation, damit die Anzeige nicht erst nach "Los" nachzieht.
    @State private var curatedRoute: DirectRoute?
    /// Ob `curatedRoute` gerade für die aktuelle Auswahl (`selectedMatch`/`combinedMatch`) im
    /// Hintergrund geladen wird - steuert, ob der "Los"-Button (s. `isPreparingSelectedRouteForStart`)
    /// blass/deaktiviert dargestellt wird, damit die Navigation nicht ohne die kuratierten
    /// Abbiege-Hinweise startet.
    @State private var isPreparingCuratedRouteForNavigation = false
    @State private var currentCuratedStepIndex = 0
    /// Schritt-Index für die graue "Anfahrt"-Linie (`connectorRouteToStart`), solange sie während
    /// der Navigation zu einer kuratierten Route/Tour noch aktiv ist - eigener Zustand analog
    /// `currentDirectRouteStepIndex`/`currentCuratedStepIndex` (s. `activeStepRoute`), da alle drei
    /// Quellen sich gegenseitig ausschließen, aber unabhängig weiterlaufen, sobald eine andere
    /// wieder aktiv wird.
    @State private var currentConnectorStepIndex = 0
    /// Straßennamen/Abbiege-Hinweise für die kombinierte Kette in `combinedRouteDetail` (On-Demand-
    /// Vorschau, analog `curatedRouteStepsResult` für Einzeltreffer) - über alle Etappen
    /// zusammengeführt, s. `matchCuratedRouteSteps(forLegs:candidatePaths:)`.
    @State private var combinedRouteStepsResult: CuratedRouteStepsAvailability?
    @State private var isLoadingCombinedRouteSteps = false

    @State private var locationManager = LocationManager()
    @State private var voiceAnnouncer = VoiceAnnouncer()
    @State private var watchSessionManager = WatchSessionManager.shared
    @AppStorage(AppSettingsKey.isVoiceGuidanceEnabled) private var isVoiceGuidanceEnabled = AppSettingsDefaults.isVoiceGuidanceEnabled
    @State private var isNavigating = false
    @State private var showLocationDeniedAlert = false
    @State private var showEndNavigationConfirmation = false
    @State private var isResolvingCurrentLocationForStart = false
    /// Deadline für `isResolvingCurrentLocationForStart` (s. `resolveCurrentLocationAsStartIfReady`)
    /// - verhindert endloses Warten auf einen frischen GPS-Fix, z. B. bei schlechtem Empfang drinnen.
    @State private var resolvingStartLocationDeadline: Date?
    @State private var hasCenteredOnInitialLocation = false
    /// Zwingt die blaue Standort-`Annotation` bei einem größeren GPS-Sprung zu einem echten
    /// Neuzeichnen (s. `updateUserLocationMarkerTokenIfNeeded`, Kommentar an der `ForEach`-
    /// Einbindung im `Map`-Builder).
    @State private var userLocationMarkerToken = 0
    @State private var lastUserLocationMarkerCoordinate: CLLocationCoordinate2D?
    @State private var selectedRouteLines: [[CLLocationCoordinate2D]] = []
    /// Wird bei jeder Neuzuweisung von `selectedRouteLines` erhöht und fließt in die `ForEach`-
    /// Identität der Routen-`MapPolyline`s ein (s. `routeLineSlots`). Ohne das behielten zwei
    /// nacheinander gewählte Routen mit zufällig gleicher Segment-Anzahl (der Normalfall: fast
    /// jede Route ergibt nach `mergedLines` genau ein zusammenhängendes Segment) über `\.offset`
    /// dieselbe `ForEach`-Identität - SwiftUI aktualisiert dann nur die Koordinaten der
    /// bestehenden `MapPolyline` an Ort und Stelle, statt sie zu entfernen und neu hinzuzufügen.
    /// MapKits SwiftUI-Overlay-Darstellung zeichnet eine so "in place" geänderte Polyline dabei
    /// zuverlässig nicht neu (Nutzer-Beobachtung 2026-08-01: gewählte Route blieb unsichtbar, bis
    /// eine andere Route mit abweichender Segment-Anzahl zwischenzeitlich ausgewählt wurde). Der
    /// Token erzwingt bei jeder Auswahl eine neue Identität und damit ein echtes Entfernen+
    /// Hinzufügen des Overlays.
    @State private var routeSelectionToken = 0
    @State private var is3DEnabled = false
    @State private var isHeadingUpEnabled = true
    /// Nutzer-Wunsch: Anweisungs-Banner + Statistik-Leiste per Button ein-/ausblendbar - ist er
    /// ausgeblendet, geht die Karte bis an den Bildschirmrand, sonst nur bis zur Unterkante des
    /// Banners (s. `mapFillsFullScreen`). Startet bei jeder neuen Navigation wieder eingeblendet
    /// (s. `startNavigating`).
    @State private var isNavigationBannerVisible = true
    /// Nutzer-Wunsch (2026-08-09): Karte ganz sehen können (Suchfelder, Routenvorschläge und
    /// "Los"-Button ausgeblendet) - per Ziehgriff über der Karte (`routeFormCollapseGrabber`)
    /// einklappen, Tippen oder Wischen auf den Griff über der dann vollflächigen Karte
    /// (`routeFormHandle`) blendet wieder ein. Ursprünglich als Wisch-Geste auf der Karte selbst
    /// umgesetzt, aber nach Live-Test verworfen: normales Verschieben/Antippen der Karte löste das
    /// Einklappen zu leicht versehentlich mit aus - der eigene Ziehgriff kollidiert nicht mit der
    /// Kartenbedienung. Wird beim Start einer Navigation zurückgesetzt (s. `startNavigating`), damit
    /// nach deren Ende wieder die volle Ansicht erscheint.
    @State private var isRouteFormCollapsed = false
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
    /// Luftlinien-Ersatz für `connectorRouteToStart`/`connectorRouteToEnd`, falls die Online-
    /// Wegbeschreibung dafür (`Self.directions`, MKDirections) fehlschlägt (kein Netz, oder
    /// MKDirections liefert für sehr kurze Strecken mitunter gar kein Ergebnis) - der Fehler wurde
    /// bisher überall still verschluckt (`try?`), die Anfahrts-/Zielweg-Linie blieb dann komplett
    /// unsichtbar und die blaue Route endete sichtbar vor dem eigentlichen Adresspunkt (Nutzer-
    /// Beobachtung 2026-08-14, "Bückeburger Straße 9"). Eine grobe Luftlinie ist immer noch
    /// hilfreicher als gar keine Anzeige.
    @State private var connectorRouteToStartFallback: [CLLocationCoordinate2D]?
    @State private var connectorRouteToEndFallback: [CLLocationCoordinate2D]?
    /// `true`, während `connectorRouteToStart` wegen Abweichens vom ursprünglichen Startpunkt
    /// gerade neu berechnet wird (s. `checkCuratedConnectorDeviation`) - verhindert überlappende
    /// Neuberechnungen bei mehreren Standort-Updates während eine noch läuft.
    @State private var isReroutingCuratedConnector = false
    /// Zeitpunkt der letzten automatischen Neuberechnung von `connectorRouteToStart` während der
    /// Navigation - verhindert wiederholtes Neuberechnen bei jedem einzelnen Standort-Update.
    @State private var lastCuratedConnectorRerouteAt: Date?
    @State private var isDirectRouteMode = false
    @State private var isLoadingDirectRoute = false
    @State private var directRoutes: [DirectRoute] = []
    @State private var selectedDirectRouteIndex = 0
    /// `true`, während die Online-Route (`MKDirections`) für die Wisch-Seite nach den Offline-
    /// Alternativen im Hintergrund nachgeladen wird - s. `loadOnlineDirectRouteAlternative`.
    @State private var isLoadingOnlineDirectRouteAlternative = false
    /// Zeigt das Teilen-Sheet mit der per `exportRoute()` erzeugten `.gpx`-Datei der aktuell
    /// gewählten Route (Nutzer-Idee 2026-08-01: Route an einen Radcomputer übertragen oder an
    /// jemanden schicken, der sie mit einer anderen App öffnet).
    @State private var exportFile: GPXExportFile?
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
    /// `accumulateTourDistance`). Wird von `locationManager.elevationGainMeters`/
    /// `elevationLossMeters` gespiegelt, sobald ein Barometer verfügbar ist (s. dort) - nur auf
    /// Geräten ganz ohne Barometer fällt dies auf die alte, GPS-rauschanfällige Punkt-zu-Punkt-Summe
    /// aus `CLLocation.altitude` zurück.
    @State private var tourElevationGainMeters: Double = 0
    @State private var tourElevationLossMeters: Double = 0
    @State private var tourMaxSpeedKmh: Double = 0
    /// Höchste erreichte Höhe (GPS, `CLLocation.altitude`) seit Start - `nil` bis der erste Fix
    /// mit gültiger `verticalAccuracy` eintrifft (s. `accumulateTourDistance`), analog zum
    /// optionalen `currentAltitudeMeters`.
    @State private var tourMaxAltitudeMeters: Double?
    /// Distanz-/Höhen-Stichproben der letzten `gradeWindowMeters` gefahrenen Meter für
    /// `currentGradePercent` - eine reine Punkt-zu-Punkt-Ableitung wäre bei GPS-/Barometer-Rauschen
    /// unbrauchbar sprunghaft, s. `updateGradeSamples`.
    @State private var gradeSamples: [(distanceMeters: Double, altitudeMeters: Double)] = []
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
    /// Ungeglättete, zeitgestempelte Positionen der laufenden Fahrt - anders als `tourTrackPoints`
    /// (auf die aktive Route eingerastet, per Mindestabstand ausgedünnt, ohne Zeitstempel) für die
    /// `HKWorkoutRoute` in Health gedacht, die echte GPS-Punkte mit Zeitstempeln erwartet (s.
    /// `WorkoutRecorder.saveRide`).
    @State private var tourRouteLocations: [CLLocation] = []
    @State private var tourSummary: TourSummary?
    @State private var currentDirectRouteStepIndex = 0
    /// Zuletzt für ein Haptik-Signal an die Apple Watch (und die frühe Sprachansage, s.
    /// `checkTurnAnnouncementTrigger`) genutzter Schritt-Index - verhindert wiederholtes Auslösen
    /// für denselben Abbiege-Schritt.
    @State private var lastWatchHapticStepIndex: Int?
    /// Analog `lastWatchHapticStepIndex`, aber für die späte "Jetzt"-Sprachansage in
    /// `advanceDirectRouteStepIfNeeded` - eigener Merker, da früher und später Trigger
    /// unabhängig voneinander (und an unterschiedlichen Entfernungs-Schwellen) auslösen.
    @State private var lastVoiceNowAnnouncementStepIndex: Int?
    /// Hochzählender Zähler, der bei jeder ausgelösten Watch-Haptik erhöht und mit
    /// `updateWatchNavigationState` an `WatchNavState.hapticTrigger` übergeben wird - bewusst nie
    /// zurückgesetzt (auch nicht zwischen zwei Navigationen), damit die Watch eine Änderung immer
    /// zuverlässig erkennt (s. `WatchNavState.hapticTrigger`).
    @State private var watchHapticTriggerCounter = 0

    /// Karte geht bis an den Bildschirmrand (kein Rand, keine abgerundeten Ecken), solange
    /// navigiert wird und der Nutzer den Banner per Button ausgeblendet hat. Ist er eingeblendet,
    /// bleibt die Karte wie gewohnt unterhalb des Banners begrenzt (s. `isNavigationBannerVisible`).
    private var mapFillsFullScreen: Bool {
        (isNavigating && !isNavigationBannerVisible) || (!isNavigating && isRouteFormCollapsed)
    }

    /// Obergrenze für die Höhe der Ergebnisliste (Direktroute + Einzeltreffer + Kombination) -
    /// deckelt, wie viel Platz sie der Kartenvorschau darunter wegnehmen kann (s. Kommentar an der
    /// Verwendungsstelle). Deckt bequem eine Karte plus einen Ausblick auf die nächste ab; alles
    /// darüber hinaus lässt sich innerhalb der Liste erreichen, statt die Karte weiter zu verkleinern.
    private var resultsSectionMaxHeight: CGFloat { 320 }

    /// Ob für die aktuell gewählte Route (`isDirectRouteMode`/`selectedMatch`/`combinedMatch`) noch
    /// Daten im Hintergrund nachgeladen werden, die für die Turn-by-Turn-Navigation gebraucht werden
    /// (Alternativrouten bei der direkten Fahrrad-Route bzw. `curatedRoute` bei kuratierten
    /// Treffern) - lässt den "Los"-Button so lange blass/deaktiviert erscheinen, damit die Navigation
    /// nicht mit noch unvollständigen Routendaten startet. Zusätzlich bleibt der Button auch blass,
    /// solange `isSearchingCombinedMatch` noch läuft (Nutzer-Beobachtung 2026-08-07: Button stand
    /// schon aktiv/blau da, während im Hintergrund noch nach einer Routen-Kombination gesucht wurde
    /// - ohne diese Bedingung konnte man mit "Los" losfahren, bevor die eigentlich passendere
    /// Kombination überhaupt zur Auswahl stand).
    private var isPreparingSelectedRouteForStart: Bool {
        if isSearchingCombinedMatch { return true }
        if isDirectRouteMode { return isLoadingDirectRoute }
        if selectedMatch != nil || combinedMatch != nil { return isPreparingCuratedRouteForNavigation }
        return false
    }

    var body: some View {
        VStack(spacing: 12) {
            if !isNavigating && !isRouteFormCollapsed {
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 8) {
                        LocationSearchField(
                            label: "Start",
                            selectedPlace: boundStartPlace,
                            isResolvingCurrentLocation: isResolvingCurrentLocationForStart,
                            onUseCurrentLocation: useCurrentLocationAsStart,
                            onSaveFavorite: { favoriteKindChoiceField = .start },
                            onPlaceChosen: recordRecent,
                            biasCoordinate: locationManager.currentLocation?.coordinate,
                            onFocusChange: { isEditingStart = $0 }
                        )
                        LocationSearchField(
                            label: "Ziel",
                            selectedPlace: boundZielPlace,
                            onPickOnMap: { isPickingZielOnMap = true },
                            favorites: favoritePlaces,
                            onSaveFavorite: { favoriteKindChoiceField = .ziel },
                            recents: recentPlaces,
                            onDeleteRecent: deleteRecent,
                            onPlaceChosen: recordRecent,
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
                    // Gedeckelte Höhe statt frei wachsender Liste (Nutzer-Beobachtung 2026-08-11:
                    // je mehr Wisch-Karten hier erscheinen - Direktroute, Einzeltreffer,
                    // Kombination -, desto kleiner wurde die Kartenvorschau darunter, da die Map
                    // im `VStack` nur den verbleibenden Platz bekommt). `resultsSectionMaxHeight`
                    // begrenzt das; alles darüber hinaus wird innerhalb der Liste scrollbar, die
                    // Kartenvorschau behält so unabhängig von der Trefferzahl eine verlässliche
                    // Mindesthöhe.
                    ScrollView {
                        resultsSection
                    }
                    .frame(maxHeight: resultsSectionMaxHeight)
                    .padding(.horizontal)
                }

                if selectedMatch != nil || isDirectRouteMode || combinedMatch != nil {
                    HStack(spacing: 8) {
                        Button {
                            startNavigating()
                        } label: {
                            Label("Los", systemImage: "location.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isPreparingSelectedRouteForStart)

                        if exportableRoute != nil {
                            Button {
                                exportRoute()
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Route exportieren")
                            .accessibilityIdentifier("exportRoute")
                        }
                    }
                    .padding(.horizontal)
                }

                routeFormCollapseGrabber
            }

            if isNavigating && isNavigationBannerVisible {
                navigationHeaderSection
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            MapReader { proxy in
                Map(position: $cameraPosition) {
                    if let userLocationDisplayCoordinate {
                        // `ForEach` mit `userLocationMarkerToken` statt einer einzelnen `Annotation`
                        // - derselbe Grund wie bei `routeLineSlots`: MapKit zeichnet eine bestehende
                        // Annotation, deren Koordinate sich "in place" ändert, bei größeren Sprüngen
                        // mitunter nicht neu (Nutzer-Beobachtung 2026-08-01: blauer Punkt blieb nach
                        // App-Neustart an einer alten, falschen Position stehen, obwohl
                        // `locationManager.currentLocation` bereits die korrekte GPS-Position
                        // lieferte - per Debug-Log bestätigt). `userLocationMarkerToken` wird nur bei
                        // einem größeren Sprung erhöht (s. `updateUserLocationMarkerTokenIfNeeded`),
                        // damit normale, kleine GPS-Updates während der Navigation weiterhin sanft
                        // in derselben Annotation-Instanz aktualisiert werden.
                        ForEach([userLocationMarkerToken], id: \.self) { _ in
                            Annotation("Standort", coordinate: userLocationDisplayCoordinate) {
                                userLocationMarker
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                    if !isNavigating {
                        if let startPlace {
                            // `ForEach` statt einzelner `Marker`, mit `startPlace.id` (neue `UUID`
                            // bei jeder Auswahl, s. `SelectedPlace`) als Identität - derselbe Grund
                            // wie beim blauen Punkt oben: verhindert, dass der Marker bei einer neuen
                            // Auswahl an der alten Position hängen bleibt.
                            ForEach([startPlace]) { place in
                                Marker(place.title, systemImage: "flag.circle.fill", coordinate: place.coordinate)
                                    .tint(.green)
                            }
                        }
                        if let zielPlace {
                            ForEach([zielPlace]) { place in
                                Marker(place.title, systemImage: "flag.checkered.circle.fill", coordinate: place.coordinate)
                                    .tint(.red)
                            }
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
                // verhindert, dass ein einfacher Tipp (Ziel-Wahl über `handleMapTap`) fälschlich
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
                .overlay(alignment: .top) {
                    routeFormHandle
                }
                .overlay(alignment: .bottom) {
                    recenterButtonOverlay
                        .padding(.bottom, 24)
                }
                .overlay(alignment: .top) {
                    if isPickingZielOnMap {
                        pickZielOnMapBanner
                    }
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
            favoritePlaces = favoritePlaceStore.loadAll()
            recentPlaces = recentPlaceStore.loadAll()
        }
        .onChange(of: startPlace) { runMatching(); updateCamera(); loadNearbyMatches() }
        .onChange(of: zielPlace) { runMatching(); updateCamera(); loadNearbyMatches() }
        .onChange(of: isDirectRouteMode) { _, newValue in
            // Zentrale Durchsetzung der gegenseitigen Ausschließlichkeit der drei Auswahl-Zustände
            // (`isDirectRouteMode`/`selectedMatch`/`combinedMatch`) - Live-Beobachtung 2026-08-01
            // (Textsuche Hannover -> Braunschweig): Ohne diesen Handler setzten mehrere Stellen
            // (`selectDirectRoute`, `filterAndReorderMatchesByPracticalDistance`)
            // `isDirectRouteMode = true`, ohne dabei ein zuvor gesetztes `combinedMatch`
            // zurückzusetzen - beide Treffer blieben dann gleichzeitig mit Häkchen markiert, obwohl
            // sich `selectedMatch`/`combinedMatch` laut ihren eigenen `onChange`-Handlern unten
            // eigentlich gegenseitig ausschließen sollten.
            if newValue {
                selectedMatch = nil
                combinedMatch = nil
            }
        }
        .onChange(of: selectedMatch) { _, newValue in
            if newValue != nil {
                isDirectRouteMode = false
                directRoutes = []
                combinedMatch = nil
            }
            selectedRouteLines = newValue.map { Self.mergedLines($0.route.lines) } ?? []
            routeSelectionToken += 1
            loadConnectorRoute(to: newValue)
            if let newValue {
                loadCuratedRouteForNavigation(newValue)
            } else {
                curatedRoute = nil
                currentCuratedStepIndex = 0
                isPreparingCuratedRouteForNavigation = false
            }
        }
        .onChange(of: combinedMatch) { _, newValue in
            if newValue != nil {
                selectedMatch = nil
                isDirectRouteMode = false
                directRoutes = []
            }
            // Pro Etappe nur das tatsächlich genutzte Teilstück zeichnen (`pathCoordinates`),
            // nicht die komplette Geometrie der jeweiligen Route (`route.lines`) - die enthält bei
            // benannten Fernwegen oft ungenutzte Zweige/Nebenäste, was bei mehreren gestapelten
            // Etappen zu einem unübersichtlichen Liniengewirr führte (Nutzer-Beobachtung
            // 2026-07-30, Bremen -> Hannover). Fällt auf die komplette Geometrie zurück, falls
            // `routeSegmentPath` ausnahmsweise keinen Pfad fand (leeres `pathCoordinates`).
            selectedRouteLines = newValue.map {
                $0.legs.flatMap { $0.pathCoordinates.isEmpty ? Self.mergedLines($0.route.lines) : [$0.pathCoordinates] }
            } ?? []
            routeSelectionToken += 1
            loadCombinedConnectorRoute(to: newValue)
            if let newValue {
                loadCuratedRouteForNavigation(forCombined: newValue)
            } else {
                curatedRoute = nil
                currentCuratedStepIndex = 0
                isPreparingCuratedRouteForNavigation = false
            }
        }
        .onChange(of: routeToStart) { _, newValue in
            if let newValue {
                startImportedRoute(newValue)
                routeToStart = nil
            }
        }
        .onChange(of: locationManager.locationUpdateCount) { handleLocationUpdate() }
        .onChange(of: locationManager.headingUpdateCount) { updateNavigationCamera() }
        // Watch-App wird erst geöffnet, nachdem die Navigation am iPhone schon läuft: Status kommt
        // dann zwar sofort korrekt an (s. `WatchSessionManager.send`-Dokumentation), die Routen-
        // Geometrie aber ggf. erst deutlich verzögert (s. `reachabilityChangeCount`-Dokumentation) -
        // bei Wechsel zu "erreichbar" beides erneut senden, damit die Watch-Karte sofort erscheint.
        .onChange(of: watchSessionManager.reachabilityChangeCount) {
            guard isNavigating else { return }
            updateWatchNavigationState()
            sendActiveRouteToWatch()
        }
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
        .modifier(FavoriteSaveDialogsModifier(
            kindChoiceField: $favoriteKindChoiceField,
            customNameField: $favoriteCustomNameField,
            customNameInput: $favoriteCustomNameInput,
            onSave: { kind, customName, field in saveFavorite(kind: kind, customName: customName, for: field) }
        ))
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
        .sheet(item: $combinedRouteDetail) { match in
            combinedRouteDetailSheet(match)
        }
        .sheet(item: $curatedRouteStepsDetail) { match in
            curatedRouteStepsDetailSheet(match)
        }
        .sheet(isPresented: $showQuickSettings) {
            NavigationQuickSettingsView()
        }
        .sheet(item: $exportFile) { file in
            ActivityView(activityItems: [file.url])
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
        if isVoiceGuidanceEnabled {
            voiceAnnouncer.prepare()
        }
        UIApplication.shared.isIdleTimerDisabled = true
        isNavigating = true
        isFollowingUser = true
        isNavigationBannerVisible = true
        isRouteFormCollapsed = false
        isHeadingUpEnabled = navigationDefaultHeadingUp
        tourStartTime = Date()
        tourDistanceMeters = 0
        tourElevationGainMeters = 0
        tourElevationLossMeters = 0
        locationManager.resetElevationTracking()
        tourMaxSpeedKmh = 0
        tourMaxAltitudeMeters = nil
        gradeSamples = []
        tourMovingSeconds = 0
        lastMovingUpdateTimestamp = nil
        lastTourLocation = locationManager.currentLocation
        tourTrackPoints = locationManager.currentLocation.map { [$0.coordinate] } ?? []
        tourRouteLocations = locationManager.currentLocation.map { [$0] } ?? []
        lastSnapSegment = nil
        lastUserMarkerSnapSegment = nil
        isUserLocationSnapped = false
        snappedUserLocationCoordinate = locationManager.currentLocation?.coordinate
        currentDirectRouteStepIndex = 0
        currentCuratedStepIndex = 0
        currentConnectorStepIndex = 0
        lastWatchHapticStepIndex = nil
        lastVoiceNowAnnouncementStepIndex = nil
        updateWatchNavigationState()
        sendActiveRouteToWatch()
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
            // Sofortiger Abgleich mit der Live-Position beim Start: `startPlace`/die Anfahrt-Linie
            // stammen von einer einmaligen GPS-Momentaufnahme bzw. vom Zeitpunkt der Routenauswahl
            // (s. `resolveCurrentLocationAsStart`/`loadConnectorRoute`) und würden sonst erst beim
            // nächsten Standort-Update über `handleLocationUpdate` nachgeführt - bei "Aktuelle
            // Position" begann die blaue Linie beim Tippen auf "Los" deshalb sichtbar neben dem
            // blauen Punkt statt darauf (Nutzer-Beobachtung 2026-08-14). Dieselben Prüfungen wie bei
            // jedem Standort-Update, nur hier schon einmal vorgezogen statt auf den ersten
            // GPS-Tick nach Navigationsstart zu warten.
            checkDirectRouteDeviation(location)
            checkCuratedConnectorDeviation(location)
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
        voiceAnnouncer.stop()
        isNavigating = false
        lastRerouteAt = nil
        lastCuratedConnectorRerouteAt = nil
        WatchSessionManager.shared.send(.idle)
        WatchSessionManager.shared.sendImmediateIfReachable(.idle)
        if let tourStartTime {
            let tourEndTime = Date()
            let duration = tourEndTime.timeIntervalSince(tourStartTime)
            let distanceKm = tourDistanceMeters / 1000
            // Bezogen auf die reine Bewegungszeit statt `duration` (Gesamtzeit inkl. Pausen) - s.
            // `currentAverageSpeedKmh` weiter unten, dieselbe Begründung gilt hier fürs
            // Verlauf-Tab/HealthKit: Pausen sollen den Ø-Wert nicht künstlich drücken.
            let averageSpeedKmh = tourMovingSeconds > 0 ? distanceKm / (tourMovingSeconds / 3600) : 0
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
            if drivenTour != nil {
                // Anders als beim Verlauf-Eintrag (s. o.) bewusst *immer* gespeichert, unabhängig
                // von der Verlauf-Entscheidung im Sheet - Nutzerwunsch (2026-08-02): jede Fahrt soll
                // in Health landen, auch wenn sie im Verlauf-Tab nicht behalten wird.
                WorkoutRecorder.shared.saveRide(
                    start: tourStartTime, end: tourEndTime, distanceMeters: tourDistanceMeters,
                    locations: tourRouteLocations
                )
            }
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
        tourRouteLocations = []
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

    /// Übernimmt einen per Kartentipp gewählten Punkt als Ziel (s. `isPickingZielOnMap`,
    /// `handleMapTap`). Setzt zunächst einen Platzhaltertitel, damit Marker und Ergebnisliste
    /// sofort reagieren, statt auf das (u. U. langsame) Reverse Geocoding zu warten -
    /// `reverseGeocodeZielPlace` ersetzt den Titel anschließend asynchron durch eine echte Adresse.
    private func pickZielOnMap(at coordinate: CLLocationCoordinate2D) {
        isPickingZielOnMap = false
        isImportedRouteMode = false
        let place = SelectedPlace(title: "Ziel auf der Karte", subtitle: "", coordinate: coordinate)
        zielPlace = place
        reverseGeocodeZielPlace(place)
    }

    /// Löst `place.coordinate` per Reverse Geocoding in eine Adresse auf und ersetzt `zielPlace`
    /// damit - aber nur, falls der Nutzer zwischenzeitlich nicht schon ein anderes Ziel gewählt hat
    /// (Vergleich über `place.id`, das sich bei jeder neuen Auswahl ändert, s. `SelectedPlace`).
    private func reverseGeocodeZielPlace(_ place: SelectedPlace) {
        let location = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        Task {
            guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return }
            guard zielPlace?.id == place.id else { return }
            let (title, subtitle) = Self.addressComponents(from: placemark, fallbackTitle: place.title)
            zielPlace = SelectedPlace(title: title, subtitle: subtitle, coordinate: place.coordinate)
        }
    }

    /// Baut aus einem `CLPlacemark` Titel/Untertitel im selben Format wie die Adress-Suchergebnisse
    /// (Straße + Hausnummer / PLZ + Ort) - gemeinsam genutzt von `reverseGeocodeZielPlace` und
    /// `saveFavorite` (dort für Favoriten, die von der aktuellen Position statt einer echten
    /// Adresssuche stammen).
    private static func addressComponents(from placemark: CLPlacemark, fallbackTitle: String) -> (title: String, subtitle: String) {
        let title = [placemark.thoroughfare, placemark.subThoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        let subtitle = [placemark.postalCode, placemark.locality]
            .compactMap { $0 }
            .joined(separator: " ")
        return (title.isEmpty ? (placemark.name ?? fallbackTitle) : title, subtitle)
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

    /// Speichert `place` als Favorit - stammt `place` von der aktuellen Position (Titel noch der
    /// Platzhalter `Self.currentLocationTitle`, s. `resolveCurrentLocationAsStart`), wird vorher per
    /// Reverse Geocoding eine echte Adresse aufgelöst, statt sonst wörtlich "Aktueller Standort" als
    /// Favoritenname zu speichern (Live-Fund 2026-08-04: Nutzer speicherte "Arbeit" während "Aktuelle
    /// Position" als Start gewählt war, die Favoriten-Zeile zeigte danach dauerhaft "Aktueller
    /// Standort" statt der echten Adresse).
    private func saveFavorite(kind: FavoritePlace.Kind, customName: String? = nil, for field: FavoriteTargetField) {
        guard let place = field == .start ? startPlace : zielPlace else { return }
        guard place.title == Self.currentLocationTitle else {
            favoritePlaceStore.save(FavoritePlace(
                kind: kind, customName: customName,
                title: place.title, subtitle: place.subtitle, coordinate: place.coordinate
            ))
            favoritePlaces = favoritePlaceStore.loadAll()
            return
        }
        let location = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        Task {
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            let (title, subtitle) = placemark.map {
                Self.addressComponents(from: $0, fallbackTitle: place.title)
            } ?? (place.title, place.subtitle)
            favoritePlaceStore.save(FavoritePlace(
                kind: kind, customName: customName,
                title: title, subtitle: subtitle, coordinate: place.coordinate
            ))
            favoritePlaces = favoritePlaceStore.loadAll()
        }
    }

    private func recordRecent(title: String, subtitle: String, coordinate: CLLocationCoordinate2D) {
        recentPlaceStore.record(title: title, subtitle: subtitle, coordinate: coordinate)
        recentPlaces = recentPlaceStore.loadAll()
    }

    private func deleteRecent(_ place: RecentPlace) {
        recentPlaceStore.delete(place)
        recentPlaces = recentPlaceStore.loadAll()
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
        resolvingStartLocationDeadline = Date().addingTimeInterval(Self.maxLocationWaitForStart)
        locationManager.requestAuthorization()
        locationManager.startUpdating()
        if let location = locationManager.currentLocation {
            resolveCurrentLocationAsStartIfReady(location)
        }
    }

    /// Ab dieser Entfernung (Meter) zur zuletzt fürs Marker-Redraw übernommenen Position gilt ein
    /// neuer GPS-Fix als "größerer Sprung" (s. `userLocationMarkerToken`) - deutlich über normalem
    /// GPS-Rauschen/normaler Fahrgeschwindigkeit zwischen zwei Updates, aber klein genug, um einen
    /// Fall wie den beobachteten (App-Neustart, alte falsche Position weit entfernt von der neuen
    /// korrekten) zuverlässig zu erkennen.
    private static let userLocationMarkerJumpThresholdMeters: Double = 300

    private func updateUserLocationMarkerTokenIfNeeded(_ location: CLLocation) {
        if let last = lastUserLocationMarkerCoordinate {
            let distance = location.distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
            guard distance > Self.userLocationMarkerJumpThresholdMeters else { return }
        }
        lastUserLocationMarkerCoordinate = location.coordinate
        userLocationMarkerToken += 1
    }

    private func handleLocationUpdate() {
        if let location = locationManager.currentLocation {
            updateUserLocationMarkerTokenIfNeeded(location)
        }
        if isNavigating {
            if let location = locationManager.currentLocation {
                accumulateTourDistance(location)
                // Ansage-Prüfung (Haptik + frühe Sprachausgabe) bewusst VOR
                // `advanceDirectRouteStepIfNeeded`: die Schritt-Weiterschaltung (und mit ihr die
                // späte "Jetzt"-Ansage) passiert schon ab `stepAdvanceLeadDistanceMeters` vor der
                // Abbiegung - liefe die Prüfung danach, könnte ein Schritt bei schneller Fahrt/
                // seltenen GPS-Updates bereits weitergeschaltet sein, bevor sie für ihn je
                // ausgelöst wurde
                // (Nutzer-Beobachtung 2026-07-28: Vibration blieb komplett aus).
                checkTurnAnnouncementTrigger(location)
                advanceDirectRouteStepIfNeeded(location)
                checkDirectRouteDeviation(location)
                checkCuratedConnectorDeviation(location)
                updateDisplayedUserLocation(location)
                updateWatchNavigationState()
            }
            updateNavigationCamera()
        } else if isResolvingCurrentLocationForStart, let location = locationManager.currentLocation {
            resolveCurrentLocationAsStartIfReady(location)
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

    /// Name + Geometrie der aktuell gewählten Route fürs GPX-Exportieren (`exportRoute()`) - `nil`
    /// unter derselben Bedingung wie der "Los"-Button. Anders als `selectedRouteLines` beim
    /// Einzeltreffer bewusst nur das gesuchte Teilstück (Start bis Ziel, per `routeSegmentPath`),
    /// nicht die komplette Geometrie der ganzen Fernroute - sonst würde z. B. bei "Brückenradweg"
    /// die komplette Route statt nur der gesuchten Strecke Bremen -> Osnabrück exportiert
    /// (Nutzer-Idee 2026-08-01).
    private var exportableRoute: (name: String, lines: [[CLLocationCoordinate2D]])? {
        if isDirectRouteMode, directRoutes.indices.contains(selectedDirectRouteIndex) {
            let startTitle = startPlace?.title ?? "Start"
            let zielTitle = zielPlace?.title ?? "Ziel"
            return (name: "\(startTitle) – \(zielTitle)", lines: [directRoutes[selectedDirectRouteIndex].coordinates])
        }
        if let combinedMatch {
            return (name: combinedMatch.routeNames.joined(separator: " – "), lines: selectedRouteLines)
        }
        if let selectedMatch {
            let name = selectedMatch.route.name ?? "Radroute"
            if let start = startPlace?.coordinate, let end = zielPlace?.coordinate,
               let segment = RouteMatcher.routeSegmentPath(along: selectedMatch.route.lines, from: start, to: end) {
                return (name: name, lines: [segment])
            }
            return (name: name, lines: selectedRouteLines)
        }
        return nil
    }

    private func exportRoute() {
        guard let exportableRoute, let url = GPXWriter.writeTemporaryFile(name: exportableRoute.name, lines: exportableRoute.lines) else { return }
        exportFile = GPXExportFile(url: url)
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
        if location.verticalAccuracy >= 0 {
            tourMaxAltitudeMeters = max(tourMaxAltitudeMeters ?? -.infinity, location.altitude)
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
            if locationManager.isBarometerAvailable {
                tourElevationGainMeters = locationManager.elevationGainMeters
                tourElevationLossMeters = locationManager.elevationLossMeters
            } else if location.verticalAccuracy >= 0, lastTourLocation.verticalAccuracy >= 0 {
                let elevationDelta = location.altitude - lastTourLocation.altitude
                if elevationDelta > 0 {
                    tourElevationGainMeters += elevationDelta
                } else {
                    tourElevationLossMeters += -elevationDelta
                }
            }
            let gradeAltitude: Double? = locationManager.isBarometerAvailable
                ? locationManager.relativeAltitudeMeters
                : (location.verticalAccuracy >= 0 ? location.altitude : nil)
            updateGradeSamples(distanceMeters: tourDistanceMeters, altitudeMeters: gradeAltitude)
        }
        lastTourLocation = location
        tourRouteLocations.append(location)

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
    /// sobald der Nutzer nah genug (< `stepAdvanceLeadDistanceMeters`) am Ende des aktuellen
    /// Schritts ist. Offizielle Radrouten haben keine Schritt-Daten und werden hier nicht behandelt.
    ///
    /// Reicht dieser einfache Radius-Check nicht (Nutzer-Meldung: nach einem Tunnel ohne
    /// GPS-Empfang blieb die vor dem Tunnel angekündigte Abbiegung stehen, obwohl die Straße
    /// längst hinter dem Nutzer lag, und die Entfernungsanzeige wuchs nur noch), wird zusätzlich
    /// per Fortschritts-Vergleich entlang der Routen-Geometrie nachgeholt: Setzt GPS irgendwo
    /// deutlich weiter vorn auf der Strecke wieder ein (mehrere Schritt-Enden übersprungen, nicht
    /// nur eins), erkennt `nearestSegmentIndex` das am Vergleich der Segment-Indizes und
    /// überspringt alle bereits passierten Schritte auf einmal, statt für immer auf dem
    /// `stepAdvanceLeadDistanceMeters`-Radius um den ersten (längst passierten) Schritt hängen zu
    /// bleiben.
    /// Vereinheitlicht den Zugriff auf "die aktuell navigierte Route mit Turn-by-Turn-Schritten" -
    /// entweder die "Direkte Fahrrad-Route" (`directRoutes`) oder ein per Map-Matching
    /// (`CuratedRouteStepMatcher`) mit Straßennamen angereicherter kuratierter Einzeltreffer
    /// (`curatedRoute`, s. dort). Bewusst zwei getrennte Schritt-Index-Zustände
    /// (`currentDirectRouteStepIndex`/`currentCuratedStepIndex`) statt eines gemeinsamen Feldes -
    /// beide werden unabhängig voneinander befüllt/zurückgesetzt (Suche vs. Kartentipp-Auswahl),
    /// eine Vereinheitlichung hätte `isDirectRouteMode`s viele andere Verwendungsstellen (Reroute,
    /// GPX-Export, Alternativrouten-UI) mit betroffen - genau das Risiko, das dieser kleinere,
    /// additive Schritt vermeiden soll. Nur eine der beiden Quellen ist je aktiv, `setStepIndex`
    /// schreibt entsprechend in die richtige.
    private var activeStepRoute: (route: DirectRoute, stepIndex: Int)? {
        if isDirectRouteMode, directRoutes.indices.contains(selectedDirectRouteIndex) {
            return (directRoutes[selectedDirectRouteIndex], currentDirectRouteStepIndex)
        }
        // Solange die graue "Anfahrt"-Linie zur kuratierten Route noch aktiv ist (`connectorRouteToStart`,
        // von `checkCuratedConnectorDeviation` erst genullt, wenn die Route erreicht ist), zeigt die
        // Kopfzeile deren echte MKDirections-Anweisungen mit Straßennamen statt des generischen
        // "Route folgen" - die Anfahrt kommt bereits als vollwertige `MKRoute` mit `instructions`,
        // bisher wurde sie nur fürs graue Kartenoverlay genutzt, nie für die Navigations-Anzeige.
        if !isDirectRouteMode, (selectedMatch != nil || combinedMatch != nil), let connectorRouteToStart {
            return (DirectRoute(route: connectorRouteToStart), currentConnectorStepIndex)
        }
        if (selectedMatch != nil || combinedMatch != nil), let curatedRoute, !curatedRoute.steps.isEmpty {
            return (curatedRoute, currentCuratedStepIndex)
        }
        return nil
    }

    private func setActiveStepIndex(_ index: Int) {
        if isDirectRouteMode {
            currentDirectRouteStepIndex = index
        } else if connectorRouteToStart != nil {
            currentConnectorStepIndex = index
        } else {
            currentCuratedStepIndex = index
        }
    }

    /// Ab welcher Entfernung zum Ende des aktuellen Schritts auf den nächsten umgeschaltet wird
    /// (Kopfzeilen-Text, Pfeil-Icon, Watch-Anzeige, s. `setActiveStepIndex`) - ursprünglich 30 m,
    /// nach Live-Test-Feedback ("fühlt sich beim Fahren zu früh an") auf 10 m gesenkt.
    private static let stepAdvanceLeadDistanceMeters: Double = 10

    /// Eigener, früherer Auslösepunkt nur für die "Jetzt"-Sprachansage (s.
    /// `advanceDirectRouteStepIfNeeded`) - bewusst **nicht** an `stepAdvanceLeadDistanceMeters`
    /// gekoppelt: Live-Test-Feedback zeigte, dass die Ansage bei 10 m fast immer zu spät kam.
    /// Ursprünglich tempoabhängig berechnet (Tempo × geschätzte Sprechdauer), das funktionierte
    /// laut Nutzer-Feedback (2026-08-06) aber in der Praxis nicht gut - deshalb zurück auf einen
    /// festen Wert.
    private static let voiceNowAnnouncementLeadDistanceMeters: Double = 40

    private func advanceDirectRouteStepIfNeeded(_ location: CLLocation) {
        guard let (route, currentIndex) = activeStepRoute else { return }
        let steps = route.steps
        guard currentIndex < steps.count - 1 else { return }

        let stepEnd = steps[currentIndex].endCoordinate
        let stepEndLocation = CLLocation(latitude: stepEnd.latitude, longitude: stepEnd.longitude)
        let distanceToStepEnd = location.distance(from: stepEndLocation)

        // `steps[currentIndex]` beschreibt die Anweisung, mit der man den *aktuellen* Schritt
        // betreten hat (s. `previewedStep`) - für die "Jetzt"-Ansage über das *bevorstehende*
        // Manöver am Ende des aktuellen Schritts ist deshalb `steps[currentIndex + 1]` richtig
        // (analog `previewedStep`/Kopfzeile), sonst wird die bereits erledigte Abbiegung erneut
        // vorgelesen statt der kommenden (Nutzer-Meldung 2026-08-06: falscher Straßenname).
        let nextStep = steps[currentIndex + 1]
        if isVoiceGuidanceEnabled, isTurnInstruction(nextStep),
           lastVoiceNowAnnouncementStepIndex != currentIndex,
           distanceToStepEnd < Self.voiceNowAnnouncementLeadDistanceMeters {
            lastVoiceNowAnnouncementStepIndex = currentIndex
            voiceAnnouncer.speak("Jetzt \(Self.lowercasingFirstLetter(nextStep.instructions))")
        }

        if distanceToStepEnd < Self.stepAdvanceLeadDistanceMeters {
            setActiveStepIndex(currentIndex + 1)
            return
        }

        // Der erste Fix nach einer Funklücke (z. B. Tunnelausgang) ist oft noch ungenau (analog
        // `accumulateTourDistance`) - ohne diesen Filter könnte ein einzelner schlecht platzierter
        // Fix den Fortschritts-Vergleich fälschlich zu weit vorspringen lassen.
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 30,
              let locationSegmentIndex = Self.nearestSegmentIndex(of: location.coordinate, in: route.coordinates)
        else { return }
        var advanced = currentIndex
        while advanced < steps.count - 1,
              let endSegmentIndex = Self.nearestSegmentIndex(of: steps[advanced].endCoordinate, in: route.coordinates),
              locationSegmentIndex > endSegmentIndex {
            advanced += 1
        }
        if advanced != currentIndex {
            setActiveStepIndex(advanced)
        }
    }

    /// Index des Liniensegments in `coordinates`, dem `point` am nächsten liegt - Grundlage für
    /// den Fortschritts-Vergleich in `advanceDirectRouteStepIfNeeded` (ein höherer Index bedeutet
    /// "weiter auf der Route fortgeschritten"). Nutzt dieselbe ebene Punkt-zu-Segment-Projektion
    /// wie `RouteMatcher.closestPointOnSegmentMeters`, gibt zusätzlich den Index zurück statt nur
    /// die Distanz.
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
    /// Ab welchem Abstand zwischen Start-/Zielkoordinate und dem tatsächlichen Anfang/Ende der
    /// berechneten `DirectRoute` ein Connector geladen wird. Ursprünglich 50 m (angelehnt an den
    /// Schwellenwert in `loadConnectorRoute`, `distanceToStartKm/EndKm > 0.05`) - Live-Diagnose auf
    /// dem iPhone (2026-08-14, "Bückeburger Straße 9", per Debug-Logging bestätigt) zeigte eine
    /// tatsächliche Lücke von 48,5 m, die damit knapp *unter* der Schwelle blieb: gar keine
    /// Anfahrts-/Zielweg-Linie, obwohl die blaue Route auf dem Kartenausschnitt sichtbar vor dem
    /// Adresspunkt endete - eine Lücke dieser Größenordnung ist bei typischem Zoom klar erkennbar,
    /// keine Rundungs-Ungenauigkeit. Auf 15 m gesenkt (deutlich unter jede real beobachtete Lücke,
    /// aber weiterhin groß genug, um reines Snapping-Rauschen der Offline-Engine zu ignorieren).
    private static let directRouteConnectorMinDistanceMeters: CLLocationDistance = 15

    /// Spiegelt die aktuelle Navigations-Kopfzeile (Anweisung + Live-Entfernung, s.
    /// `navigationInstructionTitle`/`currentStepDistanceText`) an eine gekoppelte Apple Watch -
    /// nutzt bewusst dieselben berechneten Werte wie die iPhone-Anzeige, damit beide nie
    /// auseinanderlaufen können.
    private func updateWatchNavigationState() {
        let state = WatchNavState(
            isNavigating: true,
            instructionText: navigationInstructionTitle,
            distanceText: currentStepDistanceText ?? navigationInstructionSubtitle,
            direction: previewedStep.map { watchDirection(for: $0) } ?? .straight,
            routeName: isDirectRouteMode ? nil : (combinedMatch?.routeNames.joined(separator: " → ") ?? selectedMatch?.route.name),
            hapticTrigger: watchHapticTriggerCounter,
            currentLatitude: locationManager.currentLocation?.coordinate.latitude,
            currentLongitude: locationManager.currentLocation?.coordinate.longitude,
            heading: locationManager.currentHeading
        )
        WatchSessionManager.appendDebugLog(
            "updateWatchNavigationState: isDirectRouteMode=\(isDirectRouteMode) directRoutes.count=\(directRoutes.count) "
            + "selectedDirectRouteIndex=\(selectedDirectRouteIndex) currentDirectRouteStepIndex=\(currentDirectRouteStepIndex) "
            + "steps.count=\(directRoutes.indices.contains(selectedDirectRouteIndex) ? directRoutes[selectedDirectRouteIndex].steps.count : -1) "
            + "-> title=\(state.instructionText) distance=\(state.distanceText)"
        )
        WatchSessionManager.shared.send(state)
    }

    /// Schickt die Geometrie der aktuell aktiven Route zur Kartenanzeige auf der Watch - bewusst
    /// nur an den Stellen aufgerufen, an denen sich die aktive Route tatsächlich ändern kann
    /// (Navigationsstart, Neuberechnung), nicht bei jedem Standort-Update wie
    /// `updateWatchNavigationState` (unnötiger Datenverkehr für eine Geometrie, die sich
    /// zwischendurch nicht ändert). Über beide Kanäle gleichzeitig: `sendRoute` (zuverlässig, aber
    /// ggf. verzögert über eine Zustellwarteschlange) und `sendRouteImmediateIfReachable` (sofort,
    /// nur falls die Watch gerade erreichbar ist) - Zweiteres behebt, dass eine Neuberechnung
    /// während der Fahrt trotz bestehender Verbindung teils erst deutlich verzögert auf der Watch
    /// ankam (Live-Beobachtung Nutzer 2026-08-03). `maxPoints: 100` deutlich kleiner als der
    /// iPhone-Kartenwert (500) - auf dem winzigen Watch-Display bringt mehr Detail ohnehin nichts.
    private func sendActiveRouteToWatch() {
        let lines = activeNavigationRouteLines.map { Self.decimated($0, maxPoints: 100) }
        WatchSessionManager.shared.sendRoute(lines)
        WatchSessionManager.shared.sendRouteImmediateIfReachable(lines)
    }

    /// Schlüsselwörter, an denen eine Abbiegung im fertig formulierten `instructions`-Text einer
    /// **Online**-Route (MKDirections) erkennbar ist. Nötig, weil `DirectRoute.Step.direction` bei
    /// Online-Routen (anders als bei der Offline-Engine) immer `.straight` ist - MKDirections
    /// liefert online keine strukturierte Richtung, nur den fertigen Text (s.
    /// `DirectRoute.init(route:)`). Ohne diesen Text-Fallback würde die Haptik bei Online-Routen
    /// nie auslösen, obwohl der angezeigte Text ("Links abbiegen", "Scharf rechts abbiegen auf
    /// Willemsbrug" o. Ä.) eindeutig eine Abbiegung ankündigt (per Live-Test 2026-07-28 gefunden).
    private static let turnKeywords = ["links", "rechts", "abbiegen", "kreisverkehr", "wenden", "ausfahrt"]

    private func isTurnInstruction(_ step: DirectRoute.Step) -> Bool {
        if step.direction != .straight { return true }
        let lowered = step.instructions.lowercased()
        return Self.turnKeywords.contains { lowered.contains($0) }
    }

    /// Für Sprachansagen, die den fertigen (großgeschrieben stehenden) `instructions`-Text mitten
    /// im Satz einbetten ("Jetzt \(...)") - ohne das läse sich das grammatisch falsch vorgelesen
    /// vor ("Jetzt Rechts abbiegen...").
    private static func lowercasingFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    /// Richtung fürs Pfeil-Icon auf der Watch (analog `navigationInstructionIcon` fürs iPhone) -
    /// bei Online-Routen (strukturiert immer `.straight`, s. `isTurnInstruction`) wird ersatzweise
    /// im Text nach "links"/"rechts" gesucht, damit der Pfeil nicht bei jeder Abbiegung fälschlich
    /// geradeaus zeigt.
    private func watchDirection(for step: DirectRoute.Step) -> WatchNavState.Direction {
        switch step.direction {
        case .left: return .left
        case .right: return .right
        case .straight:
            let lowered = step.instructions.lowercased()
            if lowered.contains("links") { return .left }
            if lowered.contains("rechts") { return .right }
            return .straight
        }
    }

    /// Vorlauf-Distanz fürs Haptik-Signal auf der Apple Watch - ursprünglich 50 m, nach
    /// Nutzer-Feedback ("kommt zu spät") auf 100 m erhöht (bei 20 km/h ca. 18 statt nur 9
    /// Sekunden Vorlauf).
    private static let watchHapticLeadDistanceMeters: Double = 100

    /// Löst ein kurzes Haptik-Signal auf der Apple Watch aus, kurz bevor eine Abbiegung der
    /// "Direkten Fahrrad-Route" ansteht (< `watchHapticLeadDistanceMeters`, deutlich großzügiger
    /// als `stepAdvanceLeadDistanceMeters` in `advanceDirectRouteStepIfNeeded`, das dort
    /// zusätzlich die "Jetzt ..."-Sprachansage auslöst). Nur bei echten Abbiegungen
    /// (`isTurnInstruction`) - bei reinem Geradeausfahren (bzw. kuratierten Radrouten ohne
    /// Schritt-Daten) gibt es nichts anzukündigen. `lastWatchHapticStepIndex` verhindert
    /// wiederholtes Auslösen für denselben Schritt. Früher gab es hier zusätzlich eine frühe
    /// "In X Metern ..."-Sprachansage - auf Nutzerwunsch entfernt (2026-08-07), die "Jetzt
    /// ..."-Ansage kurz vor der Abbiegung reicht.
    private func checkTurnAnnouncementTrigger(_ location: CLLocation) {
        guard let (route, currentIndex) = activeStepRoute else { return }
        guard let previewedStep else {
            WatchSessionManager.appendDebugLog("checkTurnAnnouncementTrigger: kein previewedStep (currentIndex=\(currentIndex), steps.count=\(route.steps.count))")
            return
        }
        let turn = isTurnInstruction(previewedStep)
        guard turn else {
            WatchSessionManager.appendDebugLog("checkTurnAnnouncementTrigger: keine Abbiegung ('\(previewedStep.instructions)', direction=\(previewedStep.direction))")
            return
        }
        guard lastWatchHapticStepIndex != currentIndex else {
            return
        }
        let steps = route.steps
        guard steps.indices.contains(currentIndex) else { return }
        let stepEnd = steps[currentIndex].endCoordinate
        let stepEndLocation = CLLocation(latitude: stepEnd.latitude, longitude: stepEnd.longitude)
        let distance = location.distance(from: stepEndLocation)
        guard distance < Self.watchHapticLeadDistanceMeters else {
            WatchSessionManager.appendDebugLog("checkTurnAnnouncementTrigger: noch zu weit (\(Int(distance)) m, Schwelle \(Int(Self.watchHapticLeadDistanceMeters)) m) für '\(previewedStep.instructions)'")
            return
        }
        WatchSessionManager.appendDebugLog("checkTurnAnnouncementTrigger: AUSLÖSEN bei \(Int(distance)) m für '\(previewedStep.instructions)'")
        lastWatchHapticStepIndex = currentIndex
        watchHapticTriggerCounter += 1
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

    /// Ab welcher Entfernung zur kuratierten Route (`selectedRouteLines`) während der Navigation
    /// die graue "Anfahrt"-Linie (`connectorRouteToStart`) noch als sinnvoll gilt - identisch mit
    /// dem Schwellenwert, ab dem `loadConnectorRoute` sie überhaupt erst anlegt.
    private static let curatedConnectorRelevantThresholdKm: Double = 0.05
    /// Mindestabstand zwischen zwei automatischen Neuberechnungen der "Anfahrt"-Linie, analog
    /// `directRouteRerouteCooldown`.
    private static let curatedConnectorRerouteCooldown: TimeInterval = 15

    /// Hält `connectorRouteToStart` während der Navigation zu einer kuratierten Route/Tour
    /// (`selectedMatch`/`combinedMatch`) aktuell: `loadConnectorRoute`/`loadCombinedConnectorRoute`
    /// berechnen sie nur einmal beim Auswählen der Route, ausgehend vom damaligen `startPlace` -
    /// fährt der Nutzer danach einen anderen Weg zur Route als ursprünglich geplant, zeigte die
    /// Linie weiterhin zum alten Startpunkt statt zur aktuellen Position (Nutzer-Beobachtung
    /// 2026-08-09, Screenshot Weser Radweg/Hemelingen). Anders als `checkDirectRouteDeviation`
    /// wird hier bewusst nicht die eigentliche Route neu berechnet (s. Kommentar an
    /// `directRouteDeviationThresholdKm`), nur die Anfahrt-Wegbeschreibung dorthin.
    private func checkCuratedConnectorDeviation(_ location: CLLocation) {
        guard !isDirectRouteMode, !isReroutingCuratedConnector,
              selectedMatch != nil || combinedMatch != nil,
              !selectedRouteLines.isEmpty else { return }
        guard let nearest = RouteMatcher.nearestPoint(from: location.coordinate, toLines: selectedRouteLines)
        else { return }
        guard nearest.distanceKm > Self.curatedConnectorRelevantThresholdKm else {
            // Route erreicht - die Anfahrt-Linie hat ihren Zweck erfüllt.
            if connectorRouteToStart != nil { connectorRouteToStart = nil }
            if connectorRouteToStartFallback != nil { connectorRouteToStartFallback = nil }
            return
        }
        if let lastCuratedConnectorRerouteAt,
           Date().timeIntervalSince(lastCuratedConnectorRerouteAt) < Self.curatedConnectorRerouteCooldown { return }

        isReroutingCuratedConnector = true
        lastCuratedConnectorRerouteAt = Date()
        let start = location.coordinate
        let target = nearest.coordinate
        let matchID = selectedMatch?.id
        let combinedMatchID = combinedMatch?.id
        Task {
            defer { isReroutingCuratedConnector = false }
            let route = await Self.directions(from: start, to: target).first
            guard selectedMatch?.id == matchID, combinedMatch?.id == combinedMatchID else { return }
            guard let route else {
                // Online-Wegbeschreibung fehlgeschlagen (kein Netz o. Ä.) - Luftlinie zeigen statt
                // gar keine Anfahrts-Linie (s. Kommentar an `connectorRouteToStartFallback`).
                connectorRouteToStart = nil
                connectorRouteToStartFallback = [start, target]
                return
            }
            connectorRouteToStart = route
            connectorRouteToStartFallback = nil
            currentConnectorStepIndex = 0
            lastWatchHapticStepIndex = nil
            lastVoiceNowAnnouncementStepIndex = nil
        }
    }

    /// Berechnet die "Direkte Fahrrad-Route" vom aktuellen Standort aus neu (Ziel bleibt gleich) -
    /// ausgelöst durch `checkDirectRouteDeviation`, wenn der Nutzer während der Navigation von der
    /// Strecke abweicht. Ersetzt `directRoutes` erst, sobald die neue Route fertig berechnet ist,
    /// damit die Karte in der Zwischenzeit nicht kurz leer wird.
    private func rerouteDirectRoute(from location: CLLocationCoordinate2D) {
        guard let ziel = zielPlace?.coordinate else { return }
        isRerouting = true
        lastRerouteAt = Date()
        let candidatePaths = offlineGraphCandidatePaths(from: location, to: ziel)
        Task {
            defer { isRerouting = false }
            var newRoutes: [DirectRoute] = []
            for path in candidatePaths {
                newRoutes = await Self.offlineDirectRoutes(path: path, from: location, to: ziel)
                if !newRoutes.isEmpty { break }
            }
            // Ungefiltert (nicht `candidatePaths`) aus demselben Grund wie in `loadDirectRoute`.
            if newRoutes.isEmpty, let combined = await Self.crossRegionOfflineDirectRoute(
                candidatePaths: offlineGraphCandidatePaths(), from: location, to: ziel
            ) {
                newRoutes = [combined]
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
            lastVoiceNowAnnouncementStepIndex = nil
            loadDirectRouteConnectors(start: location, ziel: ziel)
            sendActiveRouteToWatch()
        }
    }

    /// Pfade aller heruntergeladenen Wege-Graphen (Bundesländer + weitere Länder), in der
    /// Reihenfolge, in der sie für die Offline-Engine versucht werden sollen. `path(for:)` ist eine
    /// schnelle, synchrone Existenzprüfung, daher unproblematisch außerhalb eines Tasks. Für die
    /// eigentliche Direkt-Routen-Berechnung (`loadDirectRoute`/`rerouteDirectRoute`) stattdessen
    /// `offlineGraphCandidatePaths(from:to:)` verwenden (Bounding-Box-Vorfilter, s. dort) - diese
    /// ungefilterte Variante bleibt für das Straßennamen-Matching entlang bereits bekannter, ggf.
    /// mehrere Regionen überspannender kuratierter Routen in Gebrauch (`loadCuratedRouteSteps`,
    /// `loadCuratedRouteForNavigation`, `loadCombinedRouteSteps`), wo ein Vorfilter allein nach
    /// Start-/Zielkoordinate eine mittig durchquerte Region fälschlich ausschließen könnte.
    private func offlineGraphCandidatePaths() -> [String] {
        Bundesland.allCases.compactMap { wayGraphStore.path(for: $0) }
            + EuropaLand.allCases.compactMap { europaWayGraphStore.path(for: $0) }
            + FranceRegion.allCases.compactMap { franceWayGraphStore.path(for: $0) }
            + ItalyRegion.allCases.compactMap { italyWayGraphStore.path(for: $0) }
            + SpainRegion.allCases.compactMap { spainWayGraphStore.path(for: $0) }
    }

    /// Wie `offlineGraphCandidatePaths()`, aber vorgefiltert auf Regionen, deren grobe Bounding-Box
    /// (s. `RegionBoundingBox`) Start oder Ziel enthalten könnte - für `loadDirectRoute`/
    /// `rerouteDirectRoute`, wo Start und Ziel (anders als bei einer mehrteiligen kuratierten Route)
    /// die einzig relevanten Punkte sind. Es wird bewusst nicht nur die erste gefundene Region
    /// verwendet: Sind z. B. sowohl ein deutsches Bundesland als auch die Niederlande
    /// heruntergeladen, würde sonst ein Fahrtziel in der jeweils anderen Region niemals die
    /// Offline-Engine nutzen, obwohl eine passende Region vorhanden wäre - `offlineDirectRoutes`
    /// liefert für eine nicht abgedeckte Region ohnehin ein leeres Ergebnis, wird also einfach
    /// übersprungen.
    ///
    /// Live-Beobachtung (2026-08-02): Bei acht heruntergeladenen Bundesländern lud
    /// `loadDirectRoute`/`rerouteDirectRoute` vor diesem Filter bei **jeder** Berechnung
    /// nacheinander alle acht Wege-Graphen (u. a. Baden-Württemberg mit 11,3 Mio. Knoten, s.
    /// `largeRegionMaxVisitedNodes`), bis eine Region passte - beim ersten Zugriff je Region ein
    /// spürbarer Festplatten-Lade-/Parse-Vorgang (`WayGraphCache` cached zwar ab dem zweiten
    /// Zugriff, hält dabei aber alle einmal geladenen Graphen dauerhaft im Speicher, s. dort). Der
    /// Bounding-Box-Vorfilter hier spart in aller Regel schon das erste Laden der offensichtlich
    /// nicht zutreffenden Regionen.
    private func offlineGraphCandidatePaths(
        from start: CLLocationCoordinate2D, to ziel: CLLocationCoordinate2D
    ) -> [String] {
        let bundeslaender = Bundesland.allCases.filter {
            $0.boundingBox.contains(start) || $0.boundingBox.contains(ziel)
        }
        let laender = EuropaLand.allCases.filter {
            $0.boundingBox.contains(start) || $0.boundingBox.contains(ziel)
        }
        let franceRegionen = FranceRegion.allCases.filter {
            $0.boundingBox.contains(start) || $0.boundingBox.contains(ziel)
        }
        let italyRegionen = ItalyRegion.allCases.filter {
            $0.boundingBox.contains(start) || $0.boundingBox.contains(ziel)
        }
        let spainRegionen = SpainRegion.allCases.filter {
            $0.boundingBox.contains(start) || $0.boundingBox.contains(ziel)
        }
        return bundeslaender.compactMap { wayGraphStore.path(for: $0) }
            + laender.compactMap { europaWayGraphStore.path(for: $0) }
            + franceRegionen.compactMap { franceWayGraphStore.path(for: $0) }
            + italyRegionen.compactMap { italyWayGraphStore.path(for: $0) }
            + spainRegionen.compactMap { spainWayGraphStore.path(for: $0) }
    }

    /// Ältester `timestamp`, den ein GPS-Fix für "Aktueller Standort" noch haben darf, um sofort
    /// übernommen zu werden - iOS liefert nach `startUpdating()` häufig zuerst die letzte gecachte
    /// Position (ggf. von einem früheren Aufenthaltsort, Minuten/Stunden/Tage alt), bevor der
    /// echte aktuelle Fix nachkommt. Ein frischer GPS-Fix hat dagegen praktisch immer einen
    /// `timestamp` nahe der Jetztzeit. Nutzer-Beobachtung 2026-08-01: "Aktueller Standort" landete
    /// an der Nordseeküste, obwohl das iPhone tatsächlich in Bremen war - passte zu einem
    /// übernommenen alten Cache-Wert (`resolveCurrentLocationAsStart` prüfte bisher weder Alter
    /// noch stoppte es erst nach einem guten Fix).
    private static let maxLocationAgeForStart: TimeInterval = 15
    /// Nicht endlos auf einen frischeren Fix warten (z. B. bei schlechtem GPS-Empfang drinnen) -
    /// nach dieser Wartezeit wird auch ein älterer Fix akzeptiert, statt "Aktueller Standort"
    /// unbegrenzt hängen zu lassen.
    private static let maxLocationWaitForStart: TimeInterval = 8
    /// Platzhaltertitel für `startPlace`, solange dieser von der aktuellen GPS-Position stammt statt
    /// von einer echten Adresssuche - kein sinnvoller Name für einen Favoriten (s. `saveFavorite`,
    /// das für genau diesen Titel vor dem Speichern per Reverse Geocoding eine echte Adresse holt).
    private static let currentLocationTitle = "Aktueller Standort"

    private func resolveCurrentLocationAsStartIfReady(_ location: CLLocation) {
        let isFreshEnough = Date().timeIntervalSince(location.timestamp) <= Self.maxLocationAgeForStart
        let deadlineReached = resolvingStartLocationDeadline.map { Date() >= $0 } ?? true
        guard isFreshEnough || deadlineReached else { return }
        resolveCurrentLocationAsStart(location)
    }

    private func resolveCurrentLocationAsStart(_ location: CLLocation) {
        isResolvingCurrentLocationForStart = false
        resolvingStartLocationDeadline = nil
        locationManager.stopUpdating()
        startPlace = SelectedPlace(title: Self.currentLocationTitle, subtitle: "", coordinate: location.coordinate)
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

    /// Behandelt Taps auf die Karte außerhalb der Navigation - aktuell nur noch für
    /// `isPickingZielOnMap` relevant. Die Auswahl unter mehreren `directRoutes`-Alternativen
    /// (früher hier per Punkt-zu-Linie-Hit-Testing) läuft seit Nutzer-Entscheidung 2026-08-11
    /// stattdessen einheitlich per Wischen über `directRoutePager`, genau wie bei den kuratierten
    /// Routen (`matchesPager`/`combinedMatchesPager`).
    private func handleMapTap(at point: CGPoint, proxy: MapProxy) {
        guard isPickingZielOnMap else { return }
        if let coordinate = proxy.convert(point, from: .local) {
            // Bewusst NICHT synchron im Gesten-Callback: `pickZielOnMap` setzt `zielPlace`,
            // was über `onChange` sofort `runMatching()`/`updateCamera()` auslöst - ist dabei
            // (anders als beim umgekehrten Ablauf, s. u.) bereits ein Start gesetzt, läuft die
            // volle Suche inkl. neuer Karten-Overlays (`selectedRouteLines`/`routeSelectionToken`)
            // synchron mit, während MapKit noch mitten in der Verarbeitung dieser selben
            // `SpatialTapGesture` steckt - führte beim Live-Test zu wiederholten Abstürzen
            // (Nutzer-Beobachtung 2026-08-01: nur in dieser Reihenfolge, nie wenn das Ziel
            // zuerst ohne gesetzten Start gewählt wurde). `DispatchQueue.main.async` schiebt die
            // Zustandsänderung auf den nächsten Runloop-Durchlauf, nachdem die Geste selbst
            // fertig verarbeitet ist.
            DispatchQueue.main.async {
                pickZielOnMap(at: coordinate)
            }
        }
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

    /// Schmaler Ziehgriff direkt über der Karte zum Einklappen von Suchfeldern/Routenvorschlägen/
    /// "Los"-Button (s. `isRouteFormCollapsed`) - bewusst ein eigenes kleines Ziehziel statt einer
    /// Wisch-Geste auf der Karte selbst: Nutzer-Feedback (2026-08-09) direkt nach Einführung der
    /// ursprünglichen Karten-Wisch-Geste - normales Verschieben/Antippen der Karte beim Navigieren
    /// löste das Einklappen zu leicht versehentlich mit aus. Tippen oder Wischen nach oben klappt
    /// ein, spiegelbildlich zu `routeFormHandle` weiter unten, die den Rückweg anbietet.
    private var routeFormCollapseGrabber: some View {
        Capsule()
            .fill(.tertiary)
            .frame(width: 36, height: 5)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isRouteFormCollapsed = true
                }
            }
            .gesture(
                DragGesture(minimumDistance: 15)
                    .onEnded { value in
                        guard value.translation.height < -20 else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isRouteFormCollapsed = true
                        }
                    }
            )
            .accessibilityIdentifier("collapseRouteForm")
            .accessibilityLabel("Karte ganz anzeigen")
    }

    /// Griff, solange die Karte per Wisch-Geste ganz eingeblendet ist (s. `isRouteFormCollapsed`) -
    /// Tap oder Wisch nach unten blenden Suchfelder/Routenvorschläge/"Los"-Button wieder ein, analog
    /// zu `navigationBannerHandle`.
    @ViewBuilder
    private var routeFormHandle: some View {
        if !isNavigating && isRouteFormCollapsed {
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
                        isRouteFormCollapsed = false
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onEnded { value in
                            guard value.translation.height > 20 else { return }
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isRouteFormCollapsed = false
                            }
                        }
                )
                .accessibilityIdentifier("showRouteForm")
                .accessibilityLabel("Routenvorschläge einblenden")
        }
    }

    /// Hinweis-Banner während `isPickingZielOnMap` aktiv ist (s. `handleMapTap`, `pickZielOnMap`) -
    /// erklärt den sonst unsichtbaren Modus und bietet einen expliziten Ausstieg ohne Kartentipp.
    private var pickZielOnMapBanner: some View {
        HStack {
            Image(systemName: "hand.tap.fill")
                .foregroundStyle(.secondary)
            Text("Tippe auf die Karte, um dein Ziel zu setzen")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button("Abbrechen") {
                isPickingZielOnMap = false
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
        .accessibilityIdentifier("pickZielOnMapBanner")
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
        case .currentGrade:
            guard let currentGradePercent else { return ("–", "") }
            let rounded = currentGradePercent.rounded()
            return (rounded == 0 ? "0" : String(format: "%+.0f", rounded), "%")
        case .maxAltitude:
            guard let tourMaxAltitudeMeters else { return ("–", "") }
            return (String(format: "%.0f", tourMaxAltitudeMeters), "m")
        case .pausedTime:
            return pausedTimeDisplay
        }
    }

    /// Durchschnittstempo der laufenden Fahrt, bezogen auf die reine Bewegungszeit
    /// (`tourMovingSeconds`) statt der Gesamtzeit seit `tourStartTime` - sonst würde jede Pause
    /// (Ampel, Stopp, Tippen auf Pause) den Wert künstlich nach unten ziehen, obwohl während der
    /// Pause keine Strecke zurückgelegt wird (nicht die in den Einstellungen hinterlegte
    /// Wunschgeschwindigkeit, s. `averageSpeedKmh`).
    private var currentAverageSpeedKmh: Double {
        guard tourStartTime != nil else { return 0 }
        let hours = tourMovingSeconds / 3600
        guard hours > 0 else { return 0 }
        return (tourDistanceMeters / 1000) / hours
    }

    private var currentAltitudeMeters: Double? {
        guard let location = locationManager.currentLocation, location.verticalAccuracy >= 0 else { return nil }
        return location.altitude
    }

    /// Distanzfenster für `currentGradePercent` - lang genug, dass GPS-/Barometer-Rauschen sich
    /// nicht als sprunghaft wechselnde Steigung bemerkbar macht, kurz genug, um bei einer
    /// tatsächlichen Steigungsänderung (Kuppe, Rampe) zeitnah zu reagieren.
    private static let gradeWindowMeters: Double = 30

    /// Verwirft Stichproben, die weiter als `gradeWindowMeters` hinter der aktuellen Distanz
    /// liegen - hält `gradeSamples` als gleitendes Fenster statt einer unbegrenzt wachsenden Liste.
    private func updateGradeSamples(distanceMeters: Double, altitudeMeters: Double?) {
        guard let altitudeMeters else { return }
        gradeSamples.append((distanceMeters, altitudeMeters))
        while let first = gradeSamples.first, distanceMeters - first.distanceMeters > Self.gradeWindowMeters {
            gradeSamples.removeFirst()
        }
    }

    /// Aktuelle Steigung/Gefälle in Prozent, aus der Höhenänderung über die letzten
    /// `gradeWindowMeters` gefahrenen Meter (Barometer wenn verfügbar, sonst GPS-Höhe - s.
    /// `accumulateTourDistance`). Auf ±30 % gekappt (unplausible Ausreißer statt einer erfundenen
    /// Extremsteigung); `nil` ohne genug Strecke im Fenster (z. B. gerade erst losgefahren oder im
    /// Stillstand).
    private var currentGradePercent: Double? {
        guard let first = gradeSamples.first, let last = gradeSamples.last else { return nil }
        let horizontalMeters = last.distanceMeters - first.distanceMeters
        guard horizontalMeters >= Self.gradeWindowMeters / 2 else { return nil }
        let grade = (last.altitudeMeters - first.altitudeMeters) / horizontalMeters * 100
        return min(max(grade, -30), 30)
    }

    private var elapsedTimeDisplay: (value: String, unit: String) {
        guard let tourStartTime else { return ("–", "") }
        return durationDisplay(seconds: Int(Date().timeIntervalSince(tourStartTime)))
    }

    /// Fahrtzeit minus Bewegungszeit (`tourMovingSeconds`) - beide bereits vorhanden für
    /// `elapsedTimeDisplay`/`movingTimeDisplay`. `max(0, ...)` gegen einen minimal negativen Wert
    /// durch das Zusammenspiel von rundenden Sekunden und dem 10-s-Cap in `accumulateTourDistance`.
    private var pausedTimeDisplay: (value: String, unit: String) {
        guard let tourStartTime else { return ("–", "") }
        let pausedSeconds = max(0, Date().timeIntervalSince(tourStartTime) - tourMovingSeconds)
        return durationDisplay(seconds: Int(pausedSeconds))
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
        guard let (route, currentIndex) = activeStepRoute, route.steps.indices.contains(currentIndex) else { return nil }
        let steps = route.steps
        if steps.indices.contains(currentIndex + 1) {
            return steps[currentIndex + 1]
        }
        return steps[currentIndex]
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
        guard let (route, currentIndex) = activeStepRoute, let location = locationManager.currentLocation
        else { return nil }
        let steps = route.steps
        guard steps.indices.contains(currentIndex) else { return nil }
        let end = steps[currentIndex].endCoordinate
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
        if let combinedMatch {
            return combinedMatch.routeNames.joined(separator: " → ")
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

    /// Einzelnes Linien-Segment für `routeOverlayContent`, mit einer Identität, die sich bei
    /// jeder neuen Routen-Auswahl ändert (s. `routeSelectionToken`-Kommentar an
    /// `selectedRouteLines`), auch wenn Segment-Index und -Anzahl zufällig gleich bleiben.
    private struct RouteLineSlot: Identifiable {
        let id: String
        let coordinates: [CLLocationCoordinate2D]
    }

    private var routeLineSlots: [RouteLineSlot] {
        selectedRouteLines.enumerated().map { offset, line in
            RouteLineSlot(id: "\(routeSelectionToken)-\(offset)", coordinates: line)
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
                // `ForEach` statt einer einzelnen `MapPolyline`, damit ein Wechsel zwischen
                // Alternativen (`selectedDirectRouteIndex`) die `ForEach`-Identität ändert (s.
                // `routeSelectionToken`-Kommentar) - sonst bliebe die hervorgehobene Route beim
                // Umschalten mitunter unsichtbar, da MapKit dieselbe Overlay-Instanz nur mit neuen
                // Koordinaten aktualisiert statt sie neu zu zeichnen.
                ForEach([selectedDirectRouteIndex], id: \.self) { index in
                    MapPolyline(coordinates: directRoutes[index].coordinates)
                        .stroke(.blue, lineWidth: 5)
                }
            }
            // Durchgängig blau wie die Hauptroute (anders als die graue gepunktete Anfahrt-Linie
            // bei kuratierten Routen, s. u.) - überbrückt die Lücke, die entsteht, weil die
            // Offline-Engine Start/Ziel auf den nächsten Knoten im Wege-Graphen snappt statt exakt
            // zur gesuchten Koordinate zu routen (s. `loadDirectRouteConnectors`). Anders als bei
            // kuratierten Routen (dort eine bewusst andere, vom Nutzer geplante Strecke) ist dieses
            // letzte Stück Teil derselben Route - Nutzerwunsch 2026-08-14, es soll nicht wie ein
            // separater Abschnitt wirken.
            if let connectorRouteToStart {
                MapPolyline(connectorRouteToStart.polyline)
                    .stroke(.blue, lineWidth: 5)
            } else if let connectorRouteToStartFallback {
                MapPolyline(coordinates: connectorRouteToStartFallback)
                    .stroke(.blue, lineWidth: 5)
            }
            if let connectorRouteToEnd {
                MapPolyline(connectorRouteToEnd.polyline)
                    .stroke(.blue, lineWidth: 5)
            } else if let connectorRouteToEndFallback {
                MapPolyline(coordinates: connectorRouteToEndFallback)
                    .stroke(.blue, lineWidth: 5)
            }
        } else {
            ForEach(routeLineSlots) { slot in
                MapPolyline(coordinates: slot.coordinates)
                    .stroke(.blue, lineWidth: 4)
            }
            // Grau gepunktet statt (vorher) orange gestrichelt - angelehnt an Apple Maps' eigene
            // Konvention für Fußweg-/Zubringer-Abschnitte in Transit-Wegbeschreibungen, damit die
            // reine Anfahrt zum Streckenanfang nicht wie eine zweite, konkurrierende Route wirkt
            // oder alarmierend auffällt (Nutzer-Feedback 2026-08-08).
            if let connectorRouteToStart {
                MapPolyline(connectorRouteToStart.polyline)
                    .stroke(Color.gray, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 9]))
            } else if let connectorRouteToStartFallback {
                MapPolyline(coordinates: connectorRouteToStartFallback)
                    .stroke(Color.gray, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 9]))
            }
            if let connectorRouteToEnd {
                MapPolyline(connectorRouteToEnd.polyline)
                    .stroke(Color.gray, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 9]))
            } else if let connectorRouteToEndFallback {
                MapPolyline(coordinates: connectorRouteToEndFallback)
                    .stroke(Color.gray, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 9]))
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
            title: usingCurrentLocation ? Self.currentLocationTitle : "Streckenanfang",
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
        isLoadingOnlineDirectRouteAlternative = false
        connectorRouteToStart = nil
        connectorRouteToEnd = nil
        connectorRouteToStartFallback = nil
        connectorRouteToEndFallback = nil
        guard let start = startPlace?.coordinate, let ziel = zielPlace?.coordinate else { return }
        isLoadingDirectRoute = true
        // Bevorzugt die Offline-Engine, falls eine Region (Bundesland oder Land) heruntergeladen
        // ist, die Start und Ziel abdeckt (ruhige Wege statt nur die kürzeste Verbindung) - s.
        // `offlineGraphCandidatePaths`. Die Online-Route wird in diesem Fall NICHT automatisch
        // mitberechnet (Nutzer-Entscheidung 2026-08-11: unnötige Online-Anfrage bei jeder Suche,
        // wenn ohnehin meist bei der ruhigen Offline-Route geblieben wird) - stattdessen lädt
        // `loadOnlineDirectRouteAlternative` sie erst nach, sobald in der Wisch-Karte (s.
        // `directRoutePager`) tatsächlich zu ihrer Seite gewechselt wird.
        let candidatePaths = offlineGraphCandidatePaths(from: start, to: ziel)
        Task {
            for path in candidatePaths {
                let offlineRoutes = await Self.offlineDirectRoutes(path: path, from: start, to: ziel)
                if !offlineRoutes.isEmpty {
                    isLoadingDirectRoute = false
                    if isDirectRouteMode {
                        directRoutes = offlineRoutes
                        loadDirectRouteConnectors(start: start, ziel: ziel)
                    }
                    return
                }
            }
            // Ungefiltert (nicht `candidatePaths`): Eine mittig durchquerte Region (s.
            // `CrossRegionRouteStitcher.chainedRoute`) enthält weder Start noch Ziel und würde vom
            // Bounding-Box-Filter sonst fälschlich ausgeschlossen.
            if let combined = await Self.crossRegionOfflineDirectRoute(
                candidatePaths: offlineGraphCandidatePaths(), from: start, to: ziel
            ) {
                isLoadingDirectRoute = false
                if isDirectRouteMode {
                    directRoutes = [combined]
                    loadDirectRouteConnectors(start: start, ziel: ziel)
                }
                return
            }
            let routes = await Self.directions(from: start, to: ziel, alternates: true)
            isLoadingDirectRoute = false
            if isDirectRouteMode {
                directRoutes = routes.map(DirectRoute.init(route:))
                loadDirectRouteConnectors(start: start, ziel: ziel)
            }
        }
    }

    /// Fängt den Fall ab, dass `start`/`ziel` zwar je in einer heruntergeladenen Region liegen, aber
    /// in unterschiedlichen (z. B. Bremen → Osnabrück mit Bremen + Niedersachsen heruntergeladen) -
    /// ohne diesen Schritt findet keiner der einzelnen Graphen in `candidatePaths` (jeder deckt nur
    /// eine Region ab) einen Pfad, und `loadDirectRoute`/`rerouteDirectRoute` würden komplett auf
    /// Online-Routing zurückfallen, obwohl beide Regionen offline vorliegen. Siehe
    /// `CrossRegionRouteStitcher` für das eigentliche Vorgehen (Übergangspunkt an der Luftlinie
    /// suchen, in beiden Graphen unabhängig snappen, zwei Teilrouten aneinanderreihen).
    ///
    /// Schlägt der einfache Zwei-Regionen-Versuch fehl, wird zusätzlich `chainedRoute` über **alle**
    /// `candidatePaths` probiert - für Strecken, die eine mittig durchquerte dritte Region berühren,
    /// die selbst weder Start noch Ziel enthält (Live-Fund 2026-08-02: Cuxhaven -> Hamburg über
    /// Niedersachsen -> Schleswig-Holstein -> Hamburg), und die deshalb weder im Pro-Region-Durchlauf
    /// noch im Zwei-Regionen-Versuch oben auftaucht.
    private static func crossRegionOfflineDirectRoute(
        candidatePaths: [String], from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D
    ) async -> DirectRoute? {
        await Task.detached(priority: .userInitiated) { () -> DirectRoute? in
            let repositories: [(path: String, repository: WayGraphRepository)] = candidatePaths.compactMap { path in
                guard let repository = WayGraphCache.shared.repository(for: path) else { return nil }
                return (path, repository)
            }
            let startCandidates = repositories.filter { $0.repository.nearestNode(to: start) != nil }
            let endCandidates = repositories.filter { $0.repository.nearestNode(to: end) != nil }

            for startCandidate in startCandidates {
                for endCandidate in endCandidates where endCandidate.path != startCandidate.path {
                    if let result = CrossRegionRouteStitcher.combinedRoute(
                        start: start, end: end,
                        startRepository: startCandidate.repository, endRepository: endCandidate.repository,
                        endRegionDisplayName: Self.regionDisplayName(forPath: endCandidate.path)
                    ) {
                        return DirectRoute(offlineResult: result)
                    }
                }
            }

            let namedRepositories = repositories.map {
                (repository: $0.repository, displayName: Self.regionDisplayName(forPath: $0.path))
            }
            if let result = CrossRegionRouteStitcher.chainedRoute(start: start, end: end, candidates: namedRepositories) {
                return DirectRoute(offlineResult: result)
            }
            return nil
        }.value
    }

    /// Bundesland/Land-Anzeigename aus dem Dateinamen eines Wege-Graphen (`<rawValue>.sqlite`, s.
    /// `WayGraphStore.fileURL(for:)`) - für den "Weiter in ..."-Übergangsschritt in
    /// `CrossRegionRouteStitcher`.
    private static func regionDisplayName(forPath path: String) -> String {
        let fileName = (path as NSString).lastPathComponent.replacingOccurrences(of: ".sqlite", with: "")
        if let bundesland = Bundesland(rawValue: fileName) { return bundesland.displayName }
        if let land = EuropaLand(rawValue: fileName) { return land.displayName }
        if let region = FranceRegion(rawValue: fileName) { return region.displayName }
        if let region = ItalyRegion(rawValue: fileName) { return region.displayName }
        if let region = SpainRegion(rawValue: fileName) { return region.displayName }
        return "der Nachbarregion"
    }

    /// Live-Fund 2026-08-01 (Freiburg -> Stuttgart, 214 km, beide Enden innerhalb desselben
    /// heruntergeladenen Bundeslands Baden-Württemberg): `BikeRoutingEngine`s Standard-Obergrenze
    /// (300.000 besuchte Knoten, kalibriert für lokale Stadt-Strecken) brach die Suche bei einem
    /// so großen Bundesland (11,3 Mio. Knoten) nach 2,9 s erfolglos ab, obwohl Start und Ziel
    /// beide einen Knoten fanden - `loadDirectRoute` fiel danach still auf Online-Routing zurück.
    /// Dasselbe Limit wie `CrossRegionRouteStitcher.legMaxVisitedNodes` (dort schon für
    /// Bundesland-übergreifende Teilstrecken erhöht, s. dort) hilft bei echten großen, aber
    /// zusammenhängenden Strecken - bewusst als eigene Konstante hier dupliziert statt importiert,
    /// um `CrossRegionRouteStitcher` nicht wegen eines unabhängigen Anwendungsfalls anzufassen.
    /// ⚠️ Für den konkreten Freiburg-Stuttgart-Fall selbst **kein** vollständiger Fix: Eine
    /// anschließende BFS-Erreichbarkeitsprüfung (unabhängig von Gewichtung/Zeitlimit) zeigte, dass
    /// Stuttgarts nächstgelegener Knoten in einer komplett von Freiburgs Komponente getrennten
    /// Graph-Insel liegt (11,2 von 11,3 Mio. Knoten von Freiburg aus erreichbar, Stuttgart nicht
    /// darunter) - ein echter Fehler in der Wege-Graph-Erstellung für dieses Bundesland
    /// (`Scripts/build_way_graph_v2.py`), kein Umfangsproblem. Noch nicht behoben, s. ROADMAP.md.
    private static let largeRegionMaxVisitedNodes = 1_500_000

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
                .routes(from: start, to: end, maxAlternatives: 2, maxVisitedNodes: largeRegionMaxVisitedNodes)
        }.value
        return results.map(DirectRoute.init(offlineResult:))
    }

    /// Lädt die Online-Route (`MKDirections`) nachträglich als letzte Wisch-Seite in
    /// `directRoutePager` nach, wenn `directRoutes` bisher nur Offline-Alternativen enthält (s.
    /// `loadDirectRoute`). Idempotent über die `allSatisfy(\.isOffline)`-Prüfung: Läuft ein Aufruf
    /// bereits (`isLoadingOnlineDirectRouteAlternative`) oder wurde eine Online-Route schon
    /// angehängt, passiert nichts; schlug ein vorheriger Versuch fehl (keine Route gefunden),
    /// bleibt `directRoutes` weiterhin rein offline und ein erneutes Erscheinen der Wisch-Seite
    /// versucht es einfach noch einmal.
    private func loadOnlineDirectRouteAlternative() {
        guard isDirectRouteMode, !isLoadingOnlineDirectRouteAlternative, !directRoutes.isEmpty,
              directRoutes.allSatisfy(\.isOffline),
              let start = startPlace?.coordinate, let ziel = zielPlace?.coordinate else { return }
        isLoadingOnlineDirectRouteAlternative = true
        Task {
            let routes = await Self.directions(from: start, to: ziel)
            isLoadingOnlineDirectRouteAlternative = false
            guard isDirectRouteMode, !directRoutes.isEmpty, directRoutes.allSatisfy(\.isOffline),
                  let route = routes.first else { return }
            directRoutes.append(DirectRoute(route: route))
        }
    }

    /// Zeigt Wegbeschreibungen zwischen Start/Ziel und dem jeweils nächstgelegenen Punkt der
    /// ausgewählten Route, falls dieser spürbar entfernt liegt (z. B. wenn der Radweg nicht
    /// direkt am Start- oder Zielpunkt beginnt/endet). Nutzt Fahrrad-Wegbeschreibung mit
    /// Fallback auf Fußweg, falls Radrouting für die Region nicht verfügbar ist.
    private func loadConnectorRoute(to match: RouteMatch?) {
        connectorRouteToStart = nil
        connectorRouteToEnd = nil
        connectorRouteToStartFallback = nil
        connectorRouteToEndFallback = nil
        guard let match else { return }

        if let start = startPlace?.coordinate, match.distanceToStartKm > 0.05 {
            let target = match.nearestPointToStart
            Task {
                let route = await Self.directions(from: start, to: target).first
                guard match.id == selectedMatch?.id else { return }
                guard let route else {
                    // Online-Wegbeschreibung fehlgeschlagen - Luftlinie zeigen statt gar keine
                    // Anfahrts-Linie (s. Kommentar an `connectorRouteToStartFallback`).
                    connectorRouteToStartFallback = [start, target]
                    return
                }
                connectorRouteToStart = route
                currentConnectorStepIndex = 0
            }
        }
        if let ziel = zielPlace?.coordinate, match.distanceToEndKm > 0.05 {
            let source = match.nearestPointToEnd
            Task {
                let route = await Self.directions(from: source, to: ziel).first
                guard match.id == selectedMatch?.id else { return }
                guard let route else {
                    connectorRouteToEndFallback = [source, ziel]
                    return
                }
                connectorRouteToEnd = route
            }
        }
    }

    /// Wie `loadConnectorRoute`, aber für den Direktrouten-Modus (`isDirectRouteMode`): Die
    /// Offline-Engine snappt Start/Ziel auf den nächstgelegenen Knoten im Wege-Graphen
    /// (`BikeRoutingEngine.nearestNodes`, bis zu 2 km Suchradius) und hängt die berechnete Linie
    /// (`BikeRoutingEngine.displayCoordinates`) nie an die tatsächlich gesuchte Koordinate an - ohne
    /// diesen Connector endete die blaue Linie sichtbar vor dem Adresspunkt (Nutzer-Beobachtung
    /// 2026-08-08, Bückeburger Straße 9). `start`/`ziel` werden statt `startPlace`/`zielPlace`
    /// übergeben, da `rerouteDirectRoute` hier die aktuelle Live-Position statt `startPlace` braucht.
    private func loadDirectRouteConnectors(start: CLLocationCoordinate2D, ziel: CLLocationCoordinate2D) {
        connectorRouteToStart = nil
        connectorRouteToEnd = nil
        connectorRouteToStartFallback = nil
        connectorRouteToEndFallback = nil
        guard directRoutes.indices.contains(selectedDirectRouteIndex),
              let routeStart = directRoutes[selectedDirectRouteIndex].coordinates.first,
              let routeEnd = directRoutes[selectedDirectRouteIndex].coordinates.last else { return }
        let routeID = directRoutes[selectedDirectRouteIndex].id

        func stillCurrent() -> Bool {
            isDirectRouteMode && directRoutes.indices.contains(selectedDirectRouteIndex)
                && directRoutes[selectedDirectRouteIndex].id == routeID
        }

        let startGapMeters = CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: routeStart.latitude, longitude: routeStart.longitude))
        if startGapMeters > Self.directRouteConnectorMinDistanceMeters {
            Task {
                let route = await Self.directions(from: start, to: routeStart).first
                guard stillCurrent() else { return }
                guard let route else {
                    // Online-Wegbeschreibung fehlgeschlagen - Luftlinie zeigen statt gar keine
                    // Anfahrts-Linie (s. Kommentar an `connectorRouteToStartFallback`).
                    connectorRouteToStartFallback = [start, routeStart]
                    return
                }
                connectorRouteToStart = route
            }
        }
        let endGapMeters = CLLocation(latitude: ziel.latitude, longitude: ziel.longitude)
            .distance(from: CLLocation(latitude: routeEnd.latitude, longitude: routeEnd.longitude))
        if endGapMeters > Self.directRouteConnectorMinDistanceMeters {
            Task {
                let route = await Self.directions(from: routeEnd, to: ziel).first
                guard stillCurrent() else { return }
                guard let route else {
                    connectorRouteToEndFallback = [routeEnd, ziel]
                    return
                }
                connectorRouteToEnd = route
            }
        }
    }

    /// Wie `loadConnectorRoute`, aber für eine kombinierte Route: Connector nur an den beiden
    /// äußeren Enden (Nutzer-Start -> erste Etappe, letzte Etappe -> Nutzer-Ziel) - bewusst
    /// **keine** Connectoren zwischen den Etappen selbst, da Anschlussstellen Berühr-/
    /// Kreuzungspunkte sind (keine Lücke zu überbrücken), anders als die Anfahrt zur/von der
    /// Route insgesamt.
    private func loadCombinedConnectorRoute(to match: RouteMatcher.CombinedRouteMatch?) {
        connectorRouteToStart = nil
        connectorRouteToEnd = nil
        connectorRouteToStartFallback = nil
        connectorRouteToEndFallback = nil
        guard let match, let firstLeg = match.legs.first, let lastLeg = match.legs.last else { return }

        if let start = startPlace?.coordinate, match.distanceToStartKm > 0.05 {
            let target = firstLeg.entryPoint
            Task {
                let route = await Self.directions(from: start, to: target).first
                guard match.id == combinedMatch?.id else { return }
                guard let route else {
                    // Online-Wegbeschreibung fehlgeschlagen - Luftlinie zeigen statt gar keine
                    // Anfahrts-Linie (s. Kommentar an `connectorRouteToStartFallback`).
                    connectorRouteToStartFallback = [start, target]
                    return
                }
                connectorRouteToStart = route
                currentConnectorStepIndex = 0
            }
        }
        if let ziel = zielPlace?.coordinate, match.distanceToEndKm > 0.05 {
            let source = lastLeg.exitPoint
            Task {
                let route = await Self.directions(from: source, to: ziel).first
                guard match.id == combinedMatch?.id else { return }
                guard let route else {
                    connectorRouteToEndFallback = [source, ziel]
                    return
                }
                connectorRouteToEnd = route
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
    ///
    /// **Bugfix 2026-08-06** (Nutzer-Beobachtung Bremen -> Hannover, per Screenshot): Die
    /// Live-Auswahl hing bisher an `.onChange(of: pagedMatchIndex) { selectedMatch =
    /// items[pagedMatchIndex] }` - das feuert nicht nur bei einem echten Wisch, sondern auch, wenn
    /// `resultsSection.onChange(of: matches) { pagedMatchIndex = 0 }` den Index programmatisch
    /// zurücksetzt, *falls* `pagedMatchIndex` von einer früheren Suche in derselben App-Sitzung noch
    /// auf einer anderen Seite als 0 stand (z. B. weil zuvor durch den Pager einer anderen Suche
    /// gewischt wurde) - dann sieht der Reset für SwiftUI wie ein echter Seitenwechsel aus und
    /// überschreibt eine gerade erst getroffene Auswahl (Direkte Fahrrad-Route/Kombination) mit
    /// `items[0]`, selbst wenn der - oft kilometerweit entfernte - erste Treffer nie angetippt oder
    /// bewusst angewischt wurde. Fix: eigenes `Binding`, dessen `set` (nur bei echter
    /// Nutzerinteraktion über die TabView aufgerufen) zusätzlich zur Seite auch die Auswahl setzt;
    /// der programmatische Reset schreibt dagegen direkt auf den rohen `@State`-Wert und läuft nie
    /// durch dieses `Binding` - berührt `selectedMatch` also nicht mehr.
    @ViewBuilder
    private func matchesPager(_ items: [RouteMatch], subtitle: @escaping (RouteMatch) -> String) -> some View {
        let selectingPageBinding = Binding<Int>(
            get: { pagedMatchIndex },
            set: { newIndex in
                pagedMatchIndex = newIndex
                if items.indices.contains(newIndex) {
                    selectedMatch = items[newIndex]
                }
            }
        )
        TabView(selection: selectingPageBinding) {
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

                // Nutzer-Entscheidung 2026-08-01: Die Reihenfolge der Abschnitte selbst (Einzel-
                // treffer vor Kombination) soll unverändert bleiben - unpraktikable Einzeltreffer
                // wie "[D9] Weser-Romantische Straße Teil 1" sollen stattdessen *innerhalb* des
                // Einzeltreffer-Pagers nach hinten rutschen (s. `appendNearbyWellKnownMatches`s
                // Sortierung nach `combinedDistanceKm`), nicht den ganzen Abschnitt verdrängen.
                singleMatchesSection
                combinedMatchesSection

                if matches.isEmpty && combinedMatches.isEmpty && !isSearchingCombinedMatch {
                    Divider()
                    Text("Keine passende Radroute in der Nähe gefunden")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                }
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: matches) { pagedMatchIndex = 0 }
        .onChange(of: nearbyMatches) { pagedMatchIndex = 0 }
        .onChange(of: combinedMatches) { pagedCombinedMatchIndex = 0 }
    }

    @ViewBuilder
    private var singleMatchesSection: some View {
        // Einzeltreffer (falls vorhanden) - unabhängig davon, ob zusätzlich (s. u.) noch
        // eine kombinierte Route gefunden wird. Nutzer-Wunsch (2026-07-30): mehr Auswahl,
        // auch wenn schon ein durchgehend beschilderter Einzeltreffer existiert (z. B.
        // Brückenradweg + Friedensroute als Alternative zu EuroVelo 3/D7 Pilgerroute bei
        // Bremen -> Münster) - anders als früher schließen sich Einzeltreffer und
        // Kombination jetzt nicht mehr gegenseitig aus.
        if !matches.isEmpty {
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

    @ViewBuilder
    private var combinedMatchesSection: some View {
        if isSearchingCombinedMatch {
            // Suche nach einer Routen-Kombination läuft noch (kann je nach Region einige
            // Sekunden dauern) - ohne diesen Hinweis wirkte die Suche in der Zwischenzeit
            // wie ein Fehlschlag (Live-Test München -> Nürnberg). Läuft jetzt auch neben
            // bereits vorhandenen Einzeltreffern, blockiert deren Anzeige aber nicht.
            Divider()
            HStack(spacing: 8) {
                ProgressView()
                Text("Suche nach Routen-Kombination …")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
        } else if !combinedMatches.isEmpty {
            Divider()
            combinedMatchesPager(combinedMatches)
        }
    }

    /// Zeile bzw. Wisch-Pager für die direkte Fahrrad-Route. Solange noch keine Route berechnet
    /// wurde, ein einzelner Button, der `selectDirectRoute()` auslöst; danach `directRoutePager`
    /// mit den Offline-Alternativen und - per Wischen nachgeladen - der Online-Route.
    @ViewBuilder
    private var directRouteSection: some View {
        if isDirectRouteMode, !directRoutes.isEmpty {
            directRoutePager
        } else {
            Button {
                selectDirectRoute()
            } label: {
                directRoutePlaceholderRow
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("selectDirectRoute")
        }
        Divider()
    }

    /// Wisch-Pager für die direkte Fahrrad-Route: eine Seite je Offline-Alternative
    /// (`BikeRoutingEngine`, "ruhige Wege bevorzugt"), plus - Nutzer-Wunsch 2026-08-11 - eine
    /// letzte Seite für die Online-Route (`MKDirections`, meist die direkteste/schnellste
    /// Verbindung, aber ohne Bevorzugung ruhiger Wege). Ersetzt die frühere Auswahl per Antippen
    /// der Route auf der Karte (s. `handleMapTap`) - einheitlich mit dem Wisch-Verhalten der
    /// kuratierten Routen unten (`matchesPager`/`combinedMatchesPager`). Die Online-Seite wird erst
    /// beim tatsächlichen Erscheinen nachgeladen (`onAppear` → `loadOnlineDirectRouteAlternative`),
    /// nicht schon beim ersten Laden der Offline-Route.
    @ViewBuilder
    private var directRoutePager: some View {
        let showsOnlineAlternativePage = directRoutes.allSatisfy(\.isOffline)
        let pageCount = directRoutes.count + (showsOnlineAlternativePage ? 1 : 0)
        TabView(selection: $selectedDirectRouteIndex) {
            ForEach(Array(directRoutes.enumerated()), id: \.element.id) { index, route in
                Button {
                    selectedDirectRouteIndex = index
                } label: {
                    directRouteRow(route)
                }
                .buttonStyle(.plain)
                .tag(index)
            }
            if showsOnlineAlternativePage {
                directRouteOnlineAlternativePlaceholderRow
                    .onAppear { loadOnlineDirectRouteAlternative() }
                    .tag(directRoutes.count)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: pageCount > 1 ? .automatic : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        // Zurückgesetzt auf 102pt wie `matchesPager`/`combinedMatchesPager` (Live-Fund 2026-08-11:
        // 72pt reichte nicht - die von `.indexViewStyle` am unteren Rand überlagerten Punkte
        // schnitten sich sichtbar mit der zweiten Textzeile).
        .frame(height: 102)
        .accessibilityIdentifier("selectDirectRoute")
    }

    private var directRouteOnlineAlternativePlaceholderRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Direkte Fahrrad-Route (online)")
                    .font(.subheadline.weight(.medium))
                Text("außerhalb des Radroutennetzes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ProgressView()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
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
        // Bewusst kein "N Routen – wischen zum Wechseln"-Zusatz mehr (Nutzer-Beobachtung
        // 2026-08-11): Der dadurch erzwungene Zeilenumbruch kostete zusätzlich zur neuen
        // Punkte-Reihe (s. `directRoutePager`) spürbar Höhe - die Punkte selbst zeigen bereits an,
        // dass es mehrere Seiten gibt.
        let parts = [
            "\(String(format: "%.1f", route.distanceMeters / 1000)) km",
            estimatedTravelTimeText(distanceKm: route.distanceMeters / 1000),
            route.isOffline ? "ruhige Wege bevorzugt" : "außerhalb des Radroutennetzes"
        ]
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
            Button {
                curatedRouteStepsDetail = match
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            if match.id == selectedMatch?.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    /// Zeigt eine per `findCombinedMatches` gefundene Verkettung mehrerer Fernwege als einzelne
    /// Zeile - mehrere Alternativen werden per Wisch-Pager angezeigt (s. `combinedMatchesPager`),
    /// analog zu `matches`/`matchesPager`.
    private func combinedRouteRow(_ match: RouteMatcher.CombinedRouteMatch) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(match.routeNames.joined(separator: " → "))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(combinedMatchSubtitle(for: match))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                combinedRouteDetail = match
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            if match.id == combinedMatch?.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    /// Sheet mit allen Etappen einer kombinierten Route (Name + Streckenlänge je Etappe) - Antwort
    /// auf den abgeschnittenen Titel-Text in `combinedRouteRow` bei langen Ketten.
    private func combinedRouteDetailSheet(_ match: RouteMatcher.CombinedRouteMatch) -> some View {
        NavigationStack {
            List {
                Section("Etappen") {
                    ForEach(match.legs) { leg in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(leg.route.name ?? "Unbenannte Route")
                                .font(.body.weight(.medium))
                            Text("~\(String(format: "%.1f", leg.distanceKm)) km")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                // Straßennamen über alle Etappen zusammengeführt (s. `loadCombinedRouteSteps`) -
                // eigene Sektion statt pro Etappe verschachtelt, da Etappengrenzen für die
                // Turn-by-Turn-Abfolge keine Rolle spielen (dieselbe Straße kann nahtlos über
                // eine Etappengrenze weiterlaufen).
                Section("Straßennamen") {
                    if isLoadingCombinedRouteSteps {
                        ProgressView()
                    } else if case let .steps(steps) = combinedRouteStepsResult {
                        ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                            Text(step.instructions)
                        }
                    } else {
                        Text("Keine Straßendaten verfügbar. \(Self.curatedRouteStepsUnavailableReason(combinedRouteStepsResult))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Etappen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { combinedRouteDetail = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task(id: match.id) {
            await loadCombinedRouteSteps(for: match)
        }
    }

    /// Sheet mit Straßennamen/Abbiege-Hinweisen für einen Einzeltreffer (s.
    /// `curatedRouteStepsDetail`, Map-Matching-Versuch aus ROADMAP.md) - lädt asynchron über
    /// `CuratedRouteStepMatcher`, sobald ein heruntergeladener Wege-Graph die betroffene Region
    /// abdeckt. Zeigt einen erklärenden Hinweis statt einer leeren Liste, wenn keine passende
    /// Region heruntergeladen ist oder das Matching zu lückenhaft war (s.
    /// `CuratedRouteStepMatcher.minMatchedFraction`) - bewusst kein Fehler-Alert, das ist ein
    /// erwarteter, harmloser Fall (die Kernfunktion "Route finden/anzeigen" funktioniert davon
    /// unabhängig weiter).
    private func curatedRouteStepsDetailSheet(_ match: RouteMatch) -> some View {
        NavigationStack {
            Group {
                if isLoadingCuratedRouteSteps {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if case let .steps(steps) = curatedRouteStepsResult {
                    List(Array(steps.enumerated()), id: \.offset) { _, step in
                        Text(step.instructions)
                    }
                } else if case let .partialSteps(fromStart, toEnd, gapDistanceKm) = curatedRouteStepsResult {
                    List {
                        if let fromStart {
                            Section {
                                ForEach(Array(fromStart.enumerated()), id: \.offset) { _, step in
                                    Text(step.instructions)
                                }
                            }
                        }
                        Section {
                            Label(
                                "Kartenlücke - keine Straßendaten (ca. \(String(format: "%.1f", gapDistanceKm)) km)",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        if let toEnd {
                            Section {
                                ForEach(Array(toEnd.enumerated()), id: \.offset) { _, step in
                                    Text(step.instructions)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Keine Straßendaten verfügbar",
                        systemImage: "signpost.right.and.left",
                        description: Text(Self.curatedRouteStepsUnavailableReason(curatedRouteStepsResult))
                    )
                }
            }
            .navigationTitle(match.route.name ?? "Straßennamen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { curatedRouteStepsDetail = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task(id: match.id) {
            await loadCuratedRouteSteps(for: match)
        }
    }

    /// Sucht unter allen heruntergeladenen Wege-Graphen (`offlineGraphCandidatePaths`, analog
    /// `loadDirectRoute`) den ersten, der `path` allein ausreichend abdeckt (s.
    /// `CuratedRouteStepMatcher.minMatchedFraction`), und liefert dessen Treffer als vollwertiges
    /// `BikeRoutingEngine.Result` (Distanz + Schritte) - gemeinsame Grundlage für die On-Demand-
    /// Vorschau (`loadCuratedRouteSteps`) und die aktive Navigation
    /// (`loadCuratedRouteForNavigation`), damit beide nicht getrennt durch dieselbe
    /// Kandidaten-Liste laufen.
    ///
    /// Deckt kein einzelner Graph `path` allein ausreichend ab, versucht ein zweiter Schritt, ob
    /// `path` selbst eine Regionsgrenze überquert (z. B. eine kuratierte Route wie der Weser-Radweg
    /// zwischen Bremen und Niedersachsen) - analog `CrossRegionRouteStitcher` für die direkte
    /// Fahrrad-Route, s. `CuratedRouteStepMatcher.steps(along:candidateRepositories:)`. Live-Fund
    /// 2026-08-09: Bremen -> Achim lieferte für den Weser-Radweg bisher nur den generischen Hinweis
    /// "Route folgen", weil weder das heruntergeladene Bremen- noch das Niedersachsen-Bundesland
    /// allein ≥50 % der Route abdeckte.
    private static func matchCuratedRouteSteps(
        along path: [CLLocationCoordinate2D], candidatePaths: [String]
    ) async -> BikeRoutingEngine.Result? {
        await Task.detached(priority: .userInitiated) { () -> BikeRoutingEngine.Result? in
            let repositories: [(repository: WayGraphRepository, displayName: String)] = candidatePaths.compactMap { graphPath in
                guard let repository = WayGraphCache.shared.repository(for: graphPath) else { return nil }
                return (repository, Self.regionDisplayName(forPath: graphPath))
            }

            for candidate in repositories {
                if let steps = CuratedRouteStepMatcher.steps(along: path, using: candidate.repository) {
                    return Self.curatedRouteResult(coordinates: path, steps: steps)
                }
            }

            guard repositories.count >= 2,
                  let crossRegionSteps = CuratedRouteStepMatcher.steps(along: path, candidateRepositories: repositories)
            else { return nil }
            return Self.curatedRouteResult(coordinates: path, steps: crossRegionSteps)
        }.value
    }

    /// `BikeRoutingEngine.Result` aus `coordinates` + bereits ermittelten `steps` - gemeinsame
    /// Endstufe für beide Matching-Versuche in `matchCuratedRouteSteps(along:candidatePaths:)`.
    private static func curatedRouteResult(
        coordinates: [CLLocationCoordinate2D], steps: [BikeRoutingEngine.Result.Step]
    ) -> BikeRoutingEngine.Result {
        let distanceMeters = zip(coordinates, coordinates.dropFirst()).reduce(0.0) { total, pair in
            total + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        }
        return BikeRoutingEngine.Result(coordinates: coordinates, distanceMeters: distanceMeters, steps: steps)
    }

    /// Lädt die Straßennamen/Abbiege-Hinweise für `match` zwischen `startPlace`/`zielPlace` - s.
    /// `curatedRouteStepsDetailSheet`. Der abschließende Identitäts-Check verwirft ein verspätet
    /// eintreffendes Ergebnis, falls der Nutzer das Sheet zwischenzeitlich schon geschlossen oder
    /// einen anderen Treffer geöffnet hat (analog `lastMatchingCoordinates` in `runMatching`).
    private func loadCuratedRouteSteps(for match: RouteMatch) async {
        curatedRouteStepsResult = nil
        guard let start = startPlace?.coordinate, let end = zielPlace?.coordinate,
              let pathResult = RouteMatcher.routeSegmentPathAllowingGap(along: match.route.lines, from: start, to: end)
        else {
            curatedRouteStepsResult = .noRouteGeometry
            return
        }

        isLoadingCuratedRouteSteps = true
        let candidatePaths = offlineGraphCandidatePaths()

        switch pathResult {
        case let .connected(path):
            let result = await Self.matchCuratedRouteSteps(along: path, candidatePaths: candidatePaths)
            guard curatedRouteStepsDetail?.id == match.id else { return }
            isLoadingCuratedRouteSteps = false
            curatedRouteStepsResult = result.map { .steps($0.steps) } ?? .noWayGraphMatch

        case let .gap(gap):
            var fromStartResult: BikeRoutingEngine.Result?
            if gap.fromStart.count >= 2 {
                fromStartResult = await Self.matchCuratedRouteSteps(along: gap.fromStart, candidatePaths: candidatePaths)
            }
            var toEndResult: BikeRoutingEngine.Result?
            if gap.toEnd.count >= 2 {
                toEndResult = await Self.matchCuratedRouteSteps(along: gap.toEnd, candidatePaths: candidatePaths)
            }

            guard curatedRouteStepsDetail?.id == match.id else { return }
            isLoadingCuratedRouteSteps = false
            if fromStartResult == nil, toEndResult == nil {
                curatedRouteStepsResult = .noWayGraphMatch
            } else {
                curatedRouteStepsResult = .partialSteps(
                    fromStart: fromStartResult?.steps, toEnd: toEndResult?.steps, gapDistanceKm: gap.gapDistanceKm
                )
            }
        }
    }

    /// Erklärt, warum keine Straßendaten verfügbar sind (s. `CuratedRouteStepsAvailability`) -
    /// `.none` (noch nicht geladen, sollte hier wegen `isLoadingCuratedRouteSteps` praktisch nie
    /// auftreten) fällt auf denselben Text wie `.noWayGraphMatch`, da beide für den Nutzer
    /// ununterscheidbar sind ("es gibt (noch) keine Namen").
    private static func curatedRouteStepsUnavailableReason(_ result: CuratedRouteStepsAvailability?) -> String {
        if case .noRouteGeometry = result {
            return "Für diesen Streckenabschnitt ist die Kartengeometrie selbst lückenhaft (siehe \"Kartendaten hier lückenhaft\" in der Ergebnisliste) - das lässt sich nicht durch einen Wege-Graph-Download beheben."
        }
        return "Dafür muss der Wege-Graph der betroffenen Region unter \"Offline-Karten\" heruntergeladen sein."
    }

    /// Lädt `curatedRoute` für die tatsächlich laufende Turn-by-Turn-Navigation eines ausgewählten
    /// Einzeltreffers (s. `activeStepRoute`, `curatedRoute`) - Gegenstück zu `loadCuratedRouteSteps`
    /// für die aktive Navigation statt der On-Demand-Vorschau. Wird proaktiv bei jeder Auswahl
    /// aufgerufen (`.onChange(of: selectedMatch)`), nicht erst bei "Los", damit die Anzeige beim
    /// Start der Navigation schon bereitsteht. Der abschließende Identitäts-Check verwirft ein
    /// verspätet eintreffendes Ergebnis, falls der Nutzer zwischenzeitlich einen anderen Treffer
    /// gewählt hat.
    private func loadCuratedRouteForNavigation(_ match: RouteMatch) {
        isPreparingCuratedRouteForNavigation = true
        guard let start = startPlace?.coordinate, let end = zielPlace?.coordinate,
              let path = RouteMatcher.routeSegmentPath(along: match.route.lines, from: start, to: end)
        else {
            isPreparingCuratedRouteForNavigation = false
            return
        }

        let candidatePaths = offlineGraphCandidatePaths()
        Task {
            let result = await Self.matchCuratedRouteSteps(along: path, candidatePaths: candidatePaths)
            guard selectedMatch?.id == match.id else { return }
            isPreparingCuratedRouteForNavigation = false
            if let result {
                curatedRoute = DirectRoute(offlineResult: result)
            }
        }
    }

    /// Wie `matchCuratedRouteSteps(along:candidatePaths:)`, aber für eine kombinierte Kette
    /// mehrerer Etappen (`RouteMatcher.CombinedRouteMatch`) - jede Etappe hat ihr fertig berechnetes
    /// `pathCoordinates` (s. `CombinedRouteLeg`) bereits vorliegen, kein erneutes
    /// `routeSegmentPath` nötig. Jede Etappe wird unabhängig gematcht (Etappen können in
    /// unterschiedlichen heruntergeladenen Regionen liegen, z. B. über eine Bundesland-Grenze
    /// hinweg), die Ergebnisse werden aneinandergereiht. Etappenübergänge werden wie normale
    /// Hop-Grenzen behandelt (identischer Schritt-Text an der Nahtstelle verschmolzen, analog
    /// `CuratedRouteStepMatcher.append`) - ein Etappenwechsel selbst erzeugt also keinen
    /// künstlichen Extra-Eintrag, wenn dieselbe Straße nahtlos weitergeht. `nil`, wenn weniger als
    /// die Hälfte der Etappen gematcht werden konnte (analog
    /// `CuratedRouteStepMatcher.minMatchedFraction`) - lückenhafte Namen über mehrere Etappen
    /// hinweg wären irreführender als gar keine.
    private static func matchCuratedRouteSteps(
        forLegs legs: [RouteMatcher.CombinedRouteLeg], candidatePaths: [String]
    ) async -> BikeRoutingEngine.Result? {
        var mergedCoordinates: [CLLocationCoordinate2D] = []
        var mergedSteps: [BikeRoutingEngine.Result.Step] = []
        var totalDistanceMeters = 0.0
        var matchedLegCount = 0

        for leg in legs where leg.pathCoordinates.count >= 2 {
            guard let legResult = await matchCuratedRouteSteps(along: leg.pathCoordinates, candidatePaths: candidatePaths)
            else { continue }
            matchedLegCount += 1
            totalDistanceMeters += legResult.distanceMeters
            mergedCoordinates.append(contentsOf: legResult.coordinates)
            for step in legResult.steps {
                if let last = mergedSteps.last, last.instructions == step.instructions {
                    mergedSteps[mergedSteps.count - 1] = BikeRoutingEngine.Result.Step(
                        instructions: last.instructions, endCoordinate: step.endCoordinate, direction: last.direction
                    )
                } else {
                    mergedSteps.append(step)
                }
            }
        }

        guard !mergedSteps.isEmpty, matchedLegCount * 2 >= legs.count else { return nil }
        return BikeRoutingEngine.Result(coordinates: mergedCoordinates, distanceMeters: totalDistanceMeters, steps: mergedSteps)
    }

    /// Lädt die Straßennamen/Abbiege-Hinweise für eine kombinierte Kette - s.
    /// `combinedRouteDetailSheet`. Analog `loadCuratedRouteSteps` für Einzeltreffer.
    private func loadCombinedRouteSteps(for match: RouteMatcher.CombinedRouteMatch) async {
        combinedRouteStepsResult = nil
        // Keine Etappe hat überhaupt eine nutzbare Geometrie (s. `CombinedRouteLeg.pathCoordinates`)
        // - ein Wege-Graph-Download würde daran nichts ändern, analog `.noRouteGeometry` bei
        // Einzeltreffern.
        guard match.legs.contains(where: { $0.pathCoordinates.count >= 2 }) else {
            combinedRouteStepsResult = .noRouteGeometry
            return
        }

        isLoadingCombinedRouteSteps = true
        let result = await Self.matchCuratedRouteSteps(forLegs: match.legs, candidatePaths: offlineGraphCandidatePaths())

        guard combinedRouteDetail?.id == match.id else { return }
        isLoadingCombinedRouteSteps = false
        combinedRouteStepsResult = result.map { .steps($0.steps) } ?? .noWayGraphMatch
    }

    /// Lädt `curatedRoute` für die tatsächlich laufende Turn-by-Turn-Navigation einer ausgewählten
    /// kombinierten Kette - Gegenstück zu `loadCuratedRouteForNavigation(_:)` für Einzeltreffer.
    /// Schreibt in dieselbe `curatedRoute`/`currentCuratedStepIndex`-Ablage (s. `activeStepRoute`) -
    /// unkritisch, da `selectedMatch`/`combinedMatch` sich laut bestehender Logik gegenseitig
    /// ausschließen und der abschließende Identitäts-Check ein verspätetes Ergebnis nach einem
    /// zwischenzeitlichen Moduswechsel verwirft.
    private func loadCuratedRouteForNavigation(forCombined match: RouteMatcher.CombinedRouteMatch) {
        isPreparingCuratedRouteForNavigation = true
        let candidatePaths = offlineGraphCandidatePaths()
        Task {
            let result = await Self.matchCuratedRouteSteps(forLegs: match.legs, candidatePaths: candidatePaths)
            guard combinedMatch?.id == match.id else { return }
            isPreparingCuratedRouteForNavigation = false
            if let result {
                curatedRoute = DirectRoute(offlineResult: result)
            }
        }
    }

    /// Wisch-Pager für mehrere von `findCombinedMatches` gefundene Alternativen (Nutzer-Wunsch
    /// 2026-07-30, s. `combinedMatches`) - analog zu `matchesPager` für einzelne Treffer. Wischen
    /// wählt die angezeigte Seite sofort aus (zeigt sie direkt auf der Karte), nicht erst nach
    /// Antippen. Nutzt denselben `Binding`-Trick wie `matchesPager` (s. dessen Bugfix-Doku
    /// 2026-08-06) aus identischem Grund - derselbe stale-Index-Kaskaden-Fehler war hier ebenso
    /// möglich.
    private func combinedMatchesPager(_ items: [RouteMatcher.CombinedRouteMatch]) -> some View {
        let selectingPageBinding = Binding<Int>(
            get: { pagedCombinedMatchIndex },
            set: { newIndex in
                pagedCombinedMatchIndex = newIndex
                if items.indices.contains(newIndex) {
                    selectedMatch = nil
                    isDirectRouteMode = false
                    directRoutes = []
                    combinedMatch = items[newIndex]
                }
            }
        )
        return TabView(selection: selectingPageBinding) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, match in
                Button {
                    selectedMatch = nil
                    isDirectRouteMode = false
                    directRoutes = []
                    combinedMatch = match
                } label: {
                    combinedRouteRow(match)
                        .padding(.bottom, 26)
                }
                .buttonStyle(.plain)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .automatic : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .frame(height: 102)
    }

    private func combinedMatchSubtitle(for match: RouteMatcher.CombinedRouteMatch) -> String {
        var parts: [String] = []
        parts.append("~\(String(format: "%.1f", match.totalDistanceKm)) km")
        parts.append(estimatedTravelTimeText(distanceKm: match.totalDistanceKm))
        parts.append("~\(String(format: "%.1f", match.distanceToStartKm)) km Anfahrt")
        return parts.joined(separator: " · ")
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

    /// Bricht alle noch laufenden Hintergrund-Suchvorgänge der vorigen `runMatching()`-Runde ab
    /// (s. `activeSearchTasks`), statt sie nur ihr inzwischen wertloses Ergebnis verwerfen zu
    /// lassen - sie liefen sonst einfach weiter und stahlen der neuen Suche CPU-Zeit.
    private func cancelActiveSearchTasks() {
        for task in activeSearchTasks { task.cancel() }
        activeSearchTasks.removeAll()
    }

    /// Start-/Ziel-Koordinaten der zuletzt tatsächlich ausgeführten Suche - verhindert eine
    /// überflüssige zweite Suche, wenn sich an einem bereits gesetzten `SelectedPlace` nur der
    /// Titel ändert, die Koordinate aber identisch bleibt (z. B. `reverseGeocodeZielPlace`, das
    /// nachträglich die Adresse eines per Kartentipp gesetzten Ziels einträgt - das löst über
    /// `onChange(of: zielPlace)` erneut `runMatching()` aus, obwohl sich am eigentlichen Ziel
    /// nichts geändert hat). Ohne diese Sperre konnte die zweite, redundante Suche eine bereits
    /// getroffene Auswahl (z. B. "Direkte Fahrrad-Route") mit einem inzwischen asynchron
    /// eingetroffenen `combinedMatch` der ersten Suche überlagern, statt sie sauber abzulösen -
    /// sichtbar als zwei gleichzeitig markierte Treffer in der Ergebnisliste (Nutzer-Beobachtung
    /// 2026-08-01).
    @State private var lastMatchingCoordinates: (start: CLLocationCoordinate2D, end: CLLocationCoordinate2D)?

    private func runMatching() {
        guard !isImportedRouteMode else { return }
        guard let start = startPlace?.coordinate, let end = zielPlace?.coordinate else {
            lastMatchingCoordinates = nil
            cancelActiveSearchTasks()
            matchingGeneration += 1
            routeSegmentDistances = [:]
            combinedMatch = nil
            combinedMatches = []
            isSearchingCombinedMatch = false
            matches = []
            isFallbackMatches = false
            selectedMatch = nil
            isDirectRouteMode = false
            directRoutes = []
            return
        }
        if let last = lastMatchingCoordinates,
           last.start.latitude == start.latitude, last.start.longitude == start.longitude,
           last.end.latitude == end.latitude, last.end.longitude == end.longitude {
            return
        }
        lastMatchingCoordinates = (start, end)
        cancelActiveSearchTasks()
        matchingGeneration += 1
        routeSegmentDistances = [:]
        combinedMatch = nil
        combinedMatches = []
        isSearchingCombinedMatch = false
        let strictMatches = matcher.findMatches(start: start, end: end)
        if strictMatches.isEmpty {
            matches = []
            isFallbackMatches = false
            attemptCombinedThenClosestFallback(start: start, end: end, generation: matchingGeneration)
        } else {
            matches = strictMatches
            isFallbackMatches = false
            loadRouteSegmentDistances(for: matches, generation: matchingGeneration)
            attemptCombinedSearchAsAdditionalOption(start: start, end: end, generation: matchingGeneration)
        }
        // Vorauswahl: "Direkte Fahrrad-Route" statt automatisch der ersten kuratierten Radroute
        // (Nutzer-Entscheidung) - die kuratierten Treffer bleiben im Wisch-Pager weiterhin wählbar.
        selectDirectRoute()
    }

    /// Kein (mehr) brauchbarer Einzeltreffer - vor dem "nächstgelegene Vorschläge"-Fallback erst
    /// versuchen, mehrere Fernwege zu einer Kette zu kombinieren (s. `findCombinedMatches`); eine
    /// passende Kombination ist nützlicher als eine sachlich unpassende, nur zufällig nahe
    /// Einzelroute. Läuft abseits des Main-Threads (echte SQLite-Abfragen + mehrere Pro-Route-
    /// Dijkstras) und kann je nach Region/Netzdichte mehrere Sekunden dauern - `isSearchingCombinedMatch`
    /// zeigt währenddessen einen Ladehinweis statt fälschlich schon die Leermeldung.
    ///
    /// Zwei Aufrufer: (1) `runMatching()`, wenn `findMatches` von vornherein leer bleibt, und (2)
    /// `filterAndReorderMatchesByPracticalDistance()`, wenn ein zunächst gefundener Einzeltreffer
    /// sich nachträglich als zu kurz herausstellt (z. B. beim sehr langen "Radweg D11: Ostsee <>
    /// Oberbayern" zwischen München und Nürnberg beobachtet) - ohne diesen zweiten Aufrufer
    /// verschwand der Nutzer sonst ohne jeden Vorschlag, weil `runMatching()`s Fallback-Entscheidung
    /// schon getroffen war, bevor das zu kurze Segment überhaupt bekannt wurde. Ein Treffer mit
    /// echter Kartenlücke (kein Pfad zwischen den Anschlusspunkten) landet dagegen seit 2026-07-31
    /// nicht mehr hier, sondern bleibt selbst sichtbar (s. `filterAndReorderMatchesByPracticalDistance`).
    private func attemptCombinedThenClosestFallback(
        start: CLLocationCoordinate2D, end: CLLocationCoordinate2D, generation: Int
    ) {
        isSearchingCombinedMatch = true
        let searchMatcher = matcher
        let task = Task.detached(priority: .userInitiated) {
            let combined = searchMatcher.findCombinedMatches(start: start, end: end)
            // Unabhängig vom Ergebnis zusätzlich prüfen, ob eine bekannte EuroVelo-/D-Route in der
            // Nähe von Start oder Ziel liegt - wird unten per `appendNearbyWellKnownMatches` als
            // ganz normal wählbarer Treffer ergänzt, falls sie nicht schon Teil des Ergebnisses ist.
            let nearbyWellKnown = searchMatcher.nearbyWellKnownRouteMatches(start: start, end: end)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard matchingGeneration == generation else { return }
                isSearchingCombinedMatch = false
                var usedRefs: Set<String> = []
                if !combined.isEmpty {
                    combinedMatches = combined
                    // Bewusst NICHT `combinedMatch = combined.first` (anders bis 2026-08-06) - das
                    // überschrieb die per `runMatching()` bereits synchron gesetzte "Direkte
                    // Fahrrad-Route"-Vorauswahl (Nutzer-Entscheidung 2026-08-01) sofort wieder,
                    // sobald die Kombinationssuche fertig wurde. Schlimmer noch: die direkt danach
                    // laufende `appendNearbyWellKnownMatches` füllt `matches` - deren eigener
                    // Wisch-Pager-Reset (`resultsSection.onChange(of: matches)` →
                    // `pagedMatchIndex = 0` → `matchesPager.onChange(of: pagedMatchIndex)` →
                    // `selectedMatch = items[0]`) kaskadierte über die zentrale
                    // Gegenseitige-Ausschließlichkeit (s. `onChange(of: selectedMatch)` oben) direkt
                    // danach nochmal drüber und nilte die gerade gesetzte `combinedMatch` wieder -
                    // Ergebnis war am Ende nicht die Kombination, sondern der erstbeste (oft
                    // kilometerweit entfernte) `nearbyWellKnownRouteMatches`-Treffer aktiv
                    // ausgewählt. Nutzer-Beobachtung 2026-08-06 (Bremen -> Hannover): "D7
                    // Pilgerroute" (~96 km entfernt, Richtung Osnabrück/Rheinland, also am Ziel
                    // vorbei) stand mit Häkchen da, während die eigentlich brauchbare Kette
                    // "StadtLandFluss → Weser-Romantische Straße → Energieroute Radweg →
                    // Aller-Radweg" (~156 km, plausible Größenordnung für diese echte Strecke)
                    // unmarkiert blieb. `attemptCombinedSearchAsAdditionalOption` (Geschwister-
                    // Funktion für den Fall, dass bereits Einzeltreffer vorliegen) macht genau das
                    // schon seit 2026-07-30 richtig, aus demselben Grund (s. deren Doku oben) - hier
                    // fehlte die gleiche Zurückhaltung. `combinedMatches` bleibt trotzdem befüllt
                    // und damit im Wisch-Pager sicht- und wählbar, nur eben nicht mehr automatisch
                    // aktiv.
                    pagedCombinedMatchIndex = 0
                    usedRefs = Set(combined.flatMap { $0.legs.compactMap(\.route.ref) })
                } else {
                    matches = searchMatcher.findClosestMatches(start: start, end: end)
                    isFallbackMatches = !matches.isEmpty
                    loadRouteSegmentDistances(for: matches, generation: generation)
                    usedRefs = Set(matches.compactMap { $0.route.ref })
                }
                appendNearbyWellKnownMatches(nearbyWellKnown, usedRefs: usedRefs, generation: generation)
            }
        }
        activeSearchTasks.append(task)
    }

    /// Sucht zusätzlich zu bereits gefundenen Einzeltreffern (`matches`) im Hintergrund nach einer
    /// kombinierten Route (Nutzer-Wunsch 2026-07-30: "eine größere Auswahl an Möglichkeiten hat
    /// was" - z. B. Brückenradweg + Friedensroute als Alternative zu EuroVelo 3/D7 Pilgerroute bei
    /// Bremen -> Münster). Anders als `attemptCombinedThenClosestFallback`: blockiert nicht die
    /// bereits vorhandenen Einzeltreffer (die bleiben unverändert sichtbar) und läuft keinen
    /// `findClosestMatches`-Fallback, falls nichts gefunden wird (unpassend, es liegen ja schon
    /// echte Treffer vor). Setzt bewusst nur `combinedMatches` (die Liste für den Wisch-Pager),
    /// nicht `combinedMatch` selbst - sonst würde `onChange(of: combinedMatch)` die gerade aktive
    /// Auswahl (Direkte Fahrrad-Route/Einzeltreffer) stillschweigend auf die Kombination
    /// umschalten. Der Nutzer wählt die Kombination bewusst selbst per Antippen aus, genau wie
    /// einen Einzeltreffer. Prüft ebenfalls auf nahe, noch ungenutzte bekannte Fernwege (s.
    /// `appendNearbyWellKnownMatches`) - auch wenn schon Einzeltreffer vorliegen, kann z. B. ein
    /// EuroVelo-Abschnitt nahe nur eines der beiden Punkte fehlen.
    private func attemptCombinedSearchAsAdditionalOption(
        start: CLLocationCoordinate2D, end: CLLocationCoordinate2D, generation: Int
    ) {
        isSearchingCombinedMatch = true
        let searchMatcher = matcher
        let task = Task.detached(priority: .userInitiated) {
            let combined = searchMatcher.findCombinedMatches(start: start, end: end)
            let nearbyWellKnown = searchMatcher.nearbyWellKnownRouteMatches(start: start, end: end)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard matchingGeneration == generation else { return }
                isSearchingCombinedMatch = false
                var usedRefs = Set(matches.compactMap { $0.route.ref })
                if !combined.isEmpty {
                    combinedMatches = combined
                    usedRefs.formUnion(combined.flatMap { $0.legs.compactMap(\.route.ref) })
                }
                appendNearbyWellKnownMatches(nearbyWellKnown, usedRefs: usedRefs, generation: generation)
            }
        }
        activeSearchTasks.append(task)
    }

    /// Ergänzt `matches` um bekannte, in der Nähe liegende EuroVelo-/D-Routen (s.
    /// `RouteMatcher.nearbyWellKnownRouteMatches`), die noch nicht Teil von `usedRefs` (bereits
    /// verwendete Routen-Refs aus Einzeltreffern/Kombinationen) sind, und stößt für die neu
    /// ergänzten Treffer die Streckenlängen-Berechnung an. Ersetzt den früheren reinen Text-Hinweis
    /// ("... verläuft hier in der Nähe, ist aber nicht durchgehend kartiert") - Nutzer-Wunsch
    /// (2026-07-31): die Route soll trotzdem angezeigt und auswählbar sein, nicht nur erwähnt.
    /// Eine echte Kartenlücke zwischen den Anschlusspunkten zeigt sich dann ganz normal über den
    /// bestehenden "Kartendaten hier lückenhaft"-Hinweis (s. `subtitle(for:)`,
    /// `filterAndReorderMatchesByPracticalDistance`), verhindert aber nicht mehr die Anzeige.
    ///
    /// Nach dem Ergänzen wird `matches` nach `combinedDistanceKm` (Anfahrt zu Start + Ziel
    /// zusammen) aufsteigend sortiert - Nutzer-Beobachtung 2026-08-01 (Bremen -> Münster, "[D9]
    /// Weser-Romantische Straße Teil 1", ~147 km Entfernung zur Route): Ohne Sortierung landete ein
    /// nur zufällig nah an *einem* der beiden Punkte liegender, praktisch aber unbrauchbarer
    /// Treffer als erste (Standard-)Seite im Wisch-Pager - wirkte dadurch wie die Hauptempfehlung,
    /// obwohl eine tatsächlich verbindende Route (`combinedMatches`) vorlag. Blendet weiterhin
    /// nichts aus (Nutzer-Wunsch 2026-07-31 bleibt gültig), verschiebt nur die Reihenfolge -
    /// Einzeltreffer aus `findMatches` (beide Seiten ohnehin ≤ `thresholdKm`) landen durch ihre von
    /// Natur aus kleine `combinedDistanceKm` weiterhin praktisch immer vor den nur einseitig nahen
    /// `nearbyWellKnownRouteMatches`-Ergänzungen.
    private func appendNearbyWellKnownMatches(
        _ wellKnown: [RouteMatch], usedRefs: Set<String>, generation: Int
    ) {
        let existingIds = Set(matches.map(\.id))
        let additional = wellKnown.filter { match in
            guard !existingIds.contains(match.id) else { return false }
            guard let ref = match.route.ref else { return true }
            return !usedRefs.contains(ref)
        }
        guard !additional.isEmpty else { return }
        matches.append(contentsOf: additional)
        matches.sort { $0.combinedDistanceKm < $1.combinedDistanceKm }
        loadRouteSegmentDistances(for: additional, generation: generation)
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
            let task = Task.detached(priority: .userInitiated) {
                let result = RouteMatcher.routeSegmentDistance(along: lines, from: start, to: end)
                guard !Task.isCancelled else { return }
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
            activeSearchTasks.append(task)
        }
    }

    /// Entfernt Treffer, deren Streckenabschnitt "auf der Route" zu kurz ist, um als eigenständige
    /// Routenempfehlung sinnvoll zu sein (`minimumRouteSegmentKm`). Treffer, bei denen sich mangels
    /// zusammenhängendem Pfad (Lücke in den Kartendaten) gar keine Länge ermitteln ließ, werden
    /// NICHT entfernt (Nutzer-Wunsch 2026-07-31: "ich möchte trotzdem die Route angezeigt bekommen
    /// und auswählen können", ausdrücklich nicht nur für den einen Beispielfall, sondern allgemein,
    /// da sowas häufig vorkommt) - sie bleiben sicht- und wählbar, zeigen aber statt einer km-Angabe
    /// den bestehenden "Kartendaten hier lückenhaft"-Hinweis (s. `subtitle(for:)`). Sortiert die
    /// Treffer danach nach der Gesamtstrecke, die man real fahren würde (Anfahrt zum
    /// Streckenanfang + Strecke auf der Route + Anfahrt vom Streckenende zum Ziel) statt nur nach
    /// der Anfahrtsdistanz - ein Fernweg, der nur zufällig nah an Start und Ziel vorbeikommt,
    /// dazwischen aber einen großen Umweg macht, landet dadurch weiter unten als eine Route, die
    /// beide Punkte tatsächlich direkt verbindet; Treffer ohne ermittelbare Länge (Kartenlücke)
    /// landen automatisch ganz am Ende (s. `practicalDistanceKm`). Zeigte die entfernte Auswahl
    /// selbst gerade auf einen jetzt aussortierten (zu kurzen) Treffer, fällt die Auswahl zurück
    /// auf die "Direkte Fahrrad-Route".
    private func filterAndReorderMatchesByPracticalDistance() {
        matches.removeAll { match in
            guard let segmentState = routeSegmentDistances[match.id], let segment = segmentState else {
                return false
            }
            return segment.distanceKm < Self.minimumRouteSegmentKm
        }
        matches.sort { practicalDistanceKm(for: $0) < practicalDistanceKm(for: $1) }

        if let selectedMatch, !matches.contains(where: { $0.id == selectedMatch.id }) {
            self.selectedMatch = nil
            isDirectRouteMode = true
        }

        // Alle zunächst gefundenen Einzeltreffer haben sich nachträglich als unbrauchbar
        // herausgestellt (zu kurzes Segment) - `!isFallbackMatches` verhindert eine Endlosschleife,
        // falls sogar die "nächstgelegene Vorschläge" aus dem Fallback selbst noch einmal komplett
        // aussortiert werden (dann bleibt es bei der Leermeldung, statt erneut zu kombinieren).
        if matches.isEmpty, !isFallbackMatches, combinedMatches.isEmpty,
           let start = startPlace?.coordinate, let end = zielPlace?.coordinate {
            attemptCombinedThenClosestFallback(start: start, end: end, generation: matchingGeneration)
        }
    }

    /// Realistische Gesamtstrecke für einen Treffer (Anfahrt zum Streckenanfang + Strecke auf der
    /// Route + Anfahrt vom Streckenende zum Ziel).
    ///
    /// Bei einer echten Kartenlücke (kein Pfad zwischen den Anschlusspunkten, `segment == nil` -
    /// s. `nearbyWellKnownRouteMatches`/"Kartendaten hier lückenhaft") früher `.greatestFiniteMagnitude`
    /// - sortierte solche Treffer dadurch immer ans Ende, selbst wenn beide Anschlusspunkte sehr
    /// nah an Start/Ziel liegen (Nutzer-Beobachtung 2026-08-01: "EuroVelo 3 ... Kartendaten hier
    /// lückenhaft" mit nur ~0,5 km `combinedDistanceKm` landete hinter "[D9] Weser-Romantische
    /// Straße Teil 1" mit ~147 km, weil letztere trotz praktischer Nutzlosigkeit eine *berechenbare*
    /// Zahl hatte). Fällt jetzt stattdessen auf `combinedDistanceKm` zurück (Anfahrt zu Start + Ziel
    /// ohne den unbekannten Lücken-Anteil) - reflektiert eher, wie vielversprechend die Route
    /// tatsächlich ist, auch wenn die genaue Streckenlänge wegen der Lücke unbekannt bleibt.
    private func practicalDistanceKm(for match: RouteMatch) -> Double {
        guard let segment = routeSegmentDistances[match.id], let segment else {
            return match.combinedDistanceKm
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

extension RouteMatcher.CombinedRouteMatch: Equatable {
    static func == (lhs: RouteMatcher.CombinedRouteMatch, rhs: RouteMatcher.CombinedRouteMatch) -> Bool {
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

/// Ausgelagert aus `ContentView.body` (statt zwei weitere inline `.confirmationDialog`/`.alert`-
/// Modifier anzuhängen), weil die ohnehin schon sehr lange Modifier-Kette dort sonst den
/// Type-Checker mit "unable to type-check this expression in reasonable time" scheitern ließ -
/// ein eigener `ViewModifier` bekommt einen eigenen, kleineren Type-Checking-Kontext.
private struct FavoriteSaveDialogsModifier: ViewModifier {
    @Binding var kindChoiceField: ContentView.FavoriteTargetField?
    @Binding var customNameField: ContentView.FavoriteTargetField?
    @Binding var customNameInput: String
    let onSave: (FavoritePlace.Kind, String?, ContentView.FavoriteTargetField) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Als Favorit speichern",
                isPresented: Binding(get: { kindChoiceField != nil }, set: { if !$0 { kindChoiceField = nil } }),
                titleVisibility: .visible
            ) {
                Button("Als Zuhause speichern") {
                    if let field = kindChoiceField { onSave(.home, nil, field) }
                    kindChoiceField = nil
                }
                Button("Als Arbeit speichern") {
                    if let field = kindChoiceField { onSave(.work, nil, field) }
                    kindChoiceField = nil
                }
                Button("Eigener Favorit ...") {
                    customNameField = kindChoiceField
                    kindChoiceField = nil
                }
                Button("Abbrechen", role: .cancel) { kindChoiceField = nil }
            }
            .alert(
                "Name für den Favoriten",
                isPresented: Binding(get: { customNameField != nil }, set: { if !$0 { customNameField = nil } })
            ) {
                TextField("z. B. Oma, Fähranleger", text: $customNameInput)
                Button("Speichern") {
                    if let field = customNameField, !customNameInput.isEmpty {
                        onSave(.custom, customNameInput, field)
                    }
                    customNameField = nil
                    customNameInput = ""
                }
                Button("Abbrechen", role: .cancel) {
                    customNameField = nil
                    customNameInput = ""
                }
            }
    }
}

private func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

#Preview {
    ContentView(routeToStart: .constant(nil))
}
