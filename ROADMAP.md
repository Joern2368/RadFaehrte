# RadFährte – Roadmap

Diese Datei hält den Entwicklungsstand und die geplanten nächsten Schritte fest,
damit die Arbeit auch in einem neuen Chat-Fenster nahtlos weitergehen kann.
Siehe auch [fahrradnavigation-app-spezifikation.md](fahrradnavigation-app-spezifikation.md)
für die ursprüngliche Produktidee.

## Aktueller Stand (umgesetzt)

- [x] Xcode-Projekt angelegt (SwiftUI, iOS 26.5 Target, Bundle-ID `com.frankenfeld.RadFaehrte`)
- [x] Start/Ziel-Eingabe mit Adress-Autovervollständigung (`MKLocalSearchCompleter`)
      → [LocationSearchField.swift](FahrradApp/RadFaehrte/Views/LocationSearchField.swift), [LocationSearchViewModel.swift](FahrradApp/RadFaehrte/ViewModels/LocationSearchViewModel.swift)
- [x] Radrouten-Datenpipeline: OSM-Deutschland-Extrakt (Geofabrik) → `pyosmium`-Extraktion aller
      `route=bicycle`-Relationen (alle Netzwerke inkl. `lcn`) → Douglas-Peucker-Vereinfachung →
      binär gepackte SQLite-DB. Ergebnis: **64 MB**, 50.364 Routen.
      → [Resources/routes.sqlite](FahrradApp/RadFaehrte/Resources/routes.sqlite)
      → ⚠️ Die Python-Skripte der Pipeline (`extract_routes.py`, `build_sqlite.py`,
      `simplify_routes.py`) lagen nur im Scratchpad und sind nicht mehr vorhanden. Falls die
      Datenbank neu gebaut werden muss (z. B. für Phase 3, s.u.), müssen sie neu geschrieben
      werden. Vorgehen ist in dieser Roadmap unter "Technische Referenz" grob dokumentiert.
- [x] `RouteRepository`: liest `routes.sqlite` read-only, Bounding-Box-Vorfilter per SQL-Index
      → [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift)
- [x] `RouteMatcher`: Punkt-zu-Linie-Distanzberechnung (ebene Näherung), Schwellenwert 8 km,
      sortiert nach kombinierter Distanz zu Start+Ziel
      → [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift)
- [x] Ergebnisliste + Kartenanzeige der gewählten Route (`MapPolyline`)
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift)
- [x] Unit-Tests für Repository und Matcher (Beispiel Bremen–Achim aus der Spezifikation)
      → [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift)
- [x] Standort-Berechtigung (`NSLocationWhenInUseUsageDescription`) + `LocationManager`
      → [LocationManager.swift](FahrradApp/RadFaehrte/Services/LocationManager.swift)
- [x] Navigations-Verfolgungsmodus ("Los"-Button): Kamera folgt Standort in ca. 300 m
      Distanz mit Heading, `UserAnnotation()` zeigt Position. Kamera aktualisiert sich jetzt
      auch bei reiner Heading-Änderung (Drehung ohne Positionswechsel); Alert bei verweigerter
      Standort-Berechtigung statt stillem Fehlschlag. Per XCUITest end-to-end verifiziert
      (`testNavigationMode`, `testNavigationModeShowsAlertWhenLocationDenied`).
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift), [LocationManager.swift](FahrradApp/RadFaehrte/Services/LocationManager.swift)
- [x] **Wegbeschreibung zum Streckenanfang**: Liegt der nächstgelegene Punkt der ausgewählten
      Route spürbar (>50 m) vom Startpunkt entfernt, wird automatisch eine echte Fahrrad-
      Wegbeschreibung (MKDirections, Fallback auf Fußweg) dorthin berechnet und gestrichelt
      angezeigt. `RouteMatcher` liefert dafür zusätzlich den nächstgelegenen Punkt auf der
      Routen-Geometrie (`nearestPointToStart`/`-End`).
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift), [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift)
- [x] **Direkte Fahrrad-Route** (Details zur Phase-4-Entscheidung unten): Nutzt MKDirections
      mit Alternativrouten (`requestsAlternateRoutes`); alle Alternativen werden gleichzeitig
      auf der Karte gezeigt (gewählte blau, andere grau gedimmt) und sind direkt durch
      Antippen der Kartenlinie wählbar. Nutzt dafür eigenes Punkt-zu-Linie-Hit-Testing
      (`handleMapTap`, per `MapReader` + `SpatialTapGesture`) statt MapKits eingebautem
      `Map(selection:)` + `.tag()`, das bei dünnen/überlappenden Linien nur unzuverlässig
      Taps erkannte. Der frühere Pfeiltasten-Stepper als Fallback ist damit überflüssig
      geworden und wurde entfernt.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`handleMapTap`)
- [x] **2D/3D-Kartenumschalter + Kamera-Verfolgung**: Standard 2D (pitch 0) im Navigations-
      modus, Umschalt-Button neben "Beenden". Kamera folgt dem Standort nicht mehr zwangsweise
      bei jedem GPS-/Kompass-Update – manuelles Zoomen/Schwenken pausiert die Verfolgung
      (erkannt über `onMapCameraChange`), ein "Standort"-Button zum Zurückspringen erscheint.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift)
- [x] **Abschluss-Zusammenfassung**: Nach "Beenden" erscheint ein Sheet mit gefahrener Strecke,
      Dauer und Durchschnittstempo (analog Komoot/Strava). Strecke wird während der Navigation
      aus GPS-Updates aufsummiert (`CLLocation.distance(from:)`).
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`TourSummary`)
- [x] **Tatsächliche Streckenlänge pro Match in der Ergebnisliste**: Bisher zeigte die Liste bei
      benannten Routen nur die (falls vorhandene) Gesamtlänge der kompletten Route (z. B. 501 km
      beim Weser-Radweg) statt der Strecke zwischen den eigenen Anschlusspunkten. Da die
      Liniensegmente einer Route in der DB meist unsortiert vorliegen (einzelne OSM-Way-
      Fragmente), wird jetzt pro Match ein Graph aus den Segmenten gebaut und per Dijkstra der
      kürzeste Pfad zwischen den nächstgelegenen Punkten zu Start/Ziel gesucht (async im
      Hintergrund, `RouteMatcher.routeSegmentDistance`). Findet sich nach Entfernen der Kanten
      des kürzesten Pfads noch eine spürbar längere zweite Verbindung (z. B. bei einer
      Rundstrecke die andere Richtung), wird sie mitberechnet, aber aktuell **nicht mehr in der
      UI angezeigt** (Nutzerentscheidung: „brauche ich nicht" – Netzwerk-Kürzel wie `rcn`/`lcn`
      wurden aus demselben Grund aus der Anzeige entfernt). Per Unit-Test gegen die echte DB
      sowie per XCUITest end-to-end verifiziert.
      → [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift) (`routeSegmentDistance`, `RouteSegmentDistance`), [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`loadRouteSegmentDistances`, `subtitle(for:)`)
- [x] **Navigationsstruktur (`TabView` mit 3 Tabs)**: App-Einstieg ist jetzt `RootTabView` statt
      direkt `ContentView`. Tabs: **Route** (= bisheriges `ContentView`, unverändert – Suche,
      Ergebnisliste, Karte, Navigationsmodus als Vollbild-Overlay *innerhalb* des Tabs statt
      eigenem Tab), **Verlauf** und **Einstellungen** (beide aktuell Platzhalter mit
      `ContentUnavailableView`, bekommen Inhalt erst mit Phase 2 bzw. den ersten echten
      Einstellungen). Tab-Leiste blendet sich während des Navigationsmodus aus
      (`.toolbar(.hidden, for: .tabBar)`).
      → [RootTabView.swift](FahrradApp/RadFaehrte/RootTabView.swift), [HistoryView.swift](FahrradApp/RadFaehrte/Views/HistoryView.swift), [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift), [RadFaehrteApp.swift](FahrradApp/RadFaehrte/RadFaehrteApp.swift)
- [x] **Markenfarbe Petrol statt Komoot-ähnlichem Dunkelgrün**: Entscheidung im Design-Gespräch
      (dunkel, aber nicht grell, klar von Komoot unterscheidbar) – Petrol/Tiefblau `#1C4A57`
      (`Color(red: 0.110, green: 0.290, blue: 0.341)`). Bisher nur in der Navigations-Kopfzeile
      eingebaut (Hintergrund von `navigationHeaderSection`), noch nicht als App-weite Akzentfarbe
      (`AccentColor`-Asset unverändert). Falls weitere UI-Elemente die Markenfarbe bekommen sollen,
      ist das ein separater Schritt.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`navigationHeaderSection`)
- [x] **App-Icon**: Mit externer Bild-KI erzeugt (Motiv: Tourenrad-Silhouette auf gewundenem
      Wegverlauf, cremeweiß auf Petrol-Hintergrund, passend zur Markenfarbe). Als
      `icon-1024.png` in `AppIcon.appiconset` hinterlegt, für alle drei Erscheinungsbilder
      (Standard/Dunkel/Getönt) identisch verwendet, da bisher nur ein Design existiert.
      → [Assets.xcassets/AppIcon.appiconset](FahrradApp/RadFaehrte/Assets.xcassets/AppIcon.appiconset)
- [x] **Startbildschirm passend zum App-Icon**: `LaunchScreen.storyboard` (Petrol-Hintergrund +
      zentriertes Icon, 220×220pt) ersetzt den automatisch generierten leeren Launch Screen
      (`INFOPLIST_KEY_UILaunchStoryboardName` statt `..._Generation`). Da der System-Launch-
      Screen selbst nicht künstlich verlängerbar ist (verschwindet, sobald die App startbereit
      ist), zeigt `RootTabView` zusätzlich für 1,2 s eine SwiftUI-`SplashView` mit identischem
      Aussehen direkt im Anschluss, damit der Übergang nahtlos wirkt und der Startbildschirm
      insgesamt länger sichtbar bleibt.
      → [LaunchScreen.storyboard](FahrradApp/RadFaehrte/LaunchScreen.storyboard), [SplashView.swift](FahrradApp/RadFaehrte/Views/SplashView.swift), [RootTabView.swift](FahrradApp/RadFaehrte/RootTabView.swift)
- [x] **Lücken in der Routen-Geometrie erkennbar machen**: Manche Routen (z. B. "Weser (alt.)")
      haben echte Lücken in den OSM-Daten – die Liniensegmente zerfallen dadurch in mehrere
      unzusammenhängende Teile, wodurch `routeSegmentDistance` keinen Pfad zwischen den
      Anschlusspunkten findet. Statt in diesem Fall (nicht unterscheidbar von "noch nicht
      berechnet") einfach nichts anzuzeigen, unterscheidet `routeSegmentDistances` jetzt explizit
      zwischen "noch nicht berechnet" (Key fehlt) und "berechnet, aber keine Verbindung gefunden"
      (Key mit `nil`-Wert) und zeigt im zweiten Fall "Kartendaten hier lückenhaft" statt einer
      leeren Zeile oder einer geratenen Zahl.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`routeSegmentDistances`, `subtitle(for:)`, `loadRouteSegmentDistances`)
- [x] **Heading-up vs. Nord-up Umschalter** im Navigationsmodus (Phase 1, siehe unten): Button
      neben dem 2D/3D-Umschalter, wechselt `MapCamera.heading` zwischen dem aktuellen Geräte-
      Heading (Kamera dreht sich mit der Fahrtrichtung) und `0` (Karte bleibt fest, Norden immer
      oben). Icons: Pfeil-nach-oben-Kreis (Heading-up) bzw. "N" im Kreis (Nord-up) – bewusst
      unterschiedlich von den bereits vergebenen Icons (u. a. `location.fill` beim "Standort"-
      Button), nachdem eine erste Version mit `location.fill` für Heading-up genau damit
      kollidierte und wie doppelt angezeigt aussah.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`isHeadingUpEnabled`, `updateNavigationCamera`, `navigationControlsOverlay`)
- [x] **MapKits eingebaute Kompassanzeige deaktiviert**: Da die App bereits ein eigenes
      Kompass-Badge (`compassBadge`) sowie eigene Steuerelemente hat, führte MapKits
      automatisch eingeblendeter Standard-Kompass (erscheint, sobald die Karte nicht mehr
      nordausgerichtet ist – was im Heading-up-Modus ständig der Fall ist) zu einer sichtbaren
      Überlagerung/einem Versatz mit dem eigenen Badge. Behoben über `.mapControls { }`
      (blendet alle MapKit-Standard-Overlays aus). `compassBadge` zusätzlich von 40×40 auf
      32×32 verkleinert (wirkte im Vergleich zu den `.thinMaterial`-Buttons zu dominant).
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`.mapControls`, `compassBadge`)
- [x] **Geschätzte Fahrzeit + erste echte Einstellung**: `SettingsView` ist kein Platzhalter mehr,
      sondern zeigt einen Stepper für die Durchschnittsgeschwindigkeit (8–30 km/h, Standard 15),
      persistiert über `@AppStorage` (Key zentral in `AppSettings.swift`, damit `ContentView` und
      `SettingsView` denselben Wert lesen/schreiben). Die Ergebnisliste zeigt darauf basierend
      eine geschätzte Fahrzeit (Distanz ÷ Geschwindigkeit) überall dort, wo eine "km auf der
      Route"-Distanz bekannt ist. Ursprünglich nutzte die "Direkte Fahrrad-Route" stattdessen
      MKDirections' eigene Zeitschätzung – das wirkte inkonsistent, weil sich die Einstellung
      dort sichtbar nicht auswirkte, daher rechnet jetzt auch sie einheitlich mit der
      eingestellten Durchschnittsgeschwindigkeit statt mit Apples Schätzung.
      → [AppSettings.swift](FahrradApp/RadFaehrte/Models/AppSettings.swift), [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift), [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`estimatedTravelTimeText`, `subtitle(for:)`, `directRouteSubtitle`)
- [x] **GPX-Import fertiger Touren** (Phase 2, s. u. – vorgezogen): Andere Nutzungsart als die
      normale Start/Ziel-Suche - hier lädt man eine schon fertige, komplette Tour (z. B. von einer
      Zeitung/einem Verein, Motivationsbeispiel: Weser-Kurier-Radtouren) und fährt sie direkt,
      statt nach Radrouten in der Nähe von Start/Ziel zu suchen. Bewusst **nicht** in
      `RouteMatcher.findMatches` eingespeist (anderes Nutzungsmuster), sondern als eigener
      Bereich im **Verlauf**-Tab:
      - **Laden**: `.fileImporter` zur Dateiauswahl, `GPXParser` (reines `XMLParser`, keine
        Bibliothek) liest nur `<trkpt>`/`<rtept>` (ignoriert `<wpt>` - das sind POI-Marker, nicht
        Teil der Strecke), Name aus `<name>`-Tag oder Dateiname als Fallback
      - **Speicherung**: `ImportedRouteStore` legt jede Tour als eigene JSON-Datei in
        `Documents/ImportedRoutes/` ab (die gebündelte `routes.sqlite` ist read-only) - kein
        SwiftData/Core Data nötig für eine Handvoll Nutzer-Routen
      - **Distanz**: GPX-Trackpunkte liegen (anders als die unsortierten OSM-Fragmente) schon in
        Reihenfolge vor, daher einfache Summe der Punkt-zu-Punkt-Distanzen statt Graph + Dijkstra
      - **Starten**: baut ein synthetisches `RouteMatch` (Route = importierte Punkte als eine
        Linie) und nutzt danach dieselbe Anzeige-/Wegbeschreibungs-Logik wie ein normales
        DB-Match weiter - inkl. automatischer Wegbeschreibung vom aktuellen Standort zum
        Streckenanfang über die schon vorhandene `loadConnectorRoute`-Logik. Ein
        `isImportedRouteMode`-Flag verhindert, dass die normale `runMatching()`-Suche das
        synthetische Match überschreibt; wird zurückgesetzt, sobald der Nutzer die Suchfelder
        selbst bedient (Auswahl, Löschen, Tausch, "aktuellen Standort verwenden")
      - **Löschen**: Swipe-to-delete in der Liste
      - Per Unit-Tests (Parser, Distanzberechnung) sowie XCUITest end-to-end verifiziert (Test
        seedet dafür eine Test-Tour direkt in `Documents/ImportedRoutes/`, um den System-
        Dateiauswahl-Dialog nicht automatisieren zu müssen)
      → [ImportedRoute.swift](FahrradApp/RadFaehrte/Models/ImportedRoute.swift), [GPXParser.swift](FahrradApp/RadFaehrte/Services/GPXParser.swift), [ImportedRouteStore.swift](FahrradApp/RadFaehrte/Services/ImportedRouteStore.swift), [HistoryView.swift](FahrradApp/RadFaehrte/Views/HistoryView.swift), [RootTabView.swift](FahrradApp/RadFaehrte/RootTabView.swift), [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`startImportedRoute`, `isImportedRouteMode`, `boundStartPlace`/`boundZielPlace`)
- [x] **Fallback-Vorschläge bei überschrittenem Schwellenwert**: Bisher zeigte die Ergebnisliste
      bei "Keine passende Radroute in der Nähe gefunden" gar nichts an, selbst wenn ein
      Radfernweg nur knapp außerhalb der 8-km-Schwelle lag (Beispiel: Pasewalk → Frankfurt
      (Oder) findet den D12 Oder-Neiße-Radweg nicht, weil Pasewalk selbst ~16 km vom nächsten
      Streckenpunkt entfernt liegt - Löcknitz als Start liegt dagegen nur ~4 km entfernt und
      findet ihn). `RouteMatcher.findClosestMatches` sucht jetzt (ohne Schwellenwert-Filter,
      dafür mit größerem 50-km-Suchradius) die 3 nächstgelegenen benannten Routen und wird in
      `ContentView.runMatching()` als Fallback aufgerufen, wenn `findMatches` leer bleibt. Die
      Ergebnisliste zeigt in diesem Fall einen Hinweis ("Keine Radroute in der Nähe -
      nächstgelegene Vorschläge:") statt der Leermeldung; die angezeigte "~X km Entfernung zur
      Route" macht die tatsächliche Anfahrt transparent, sodass der Nutzer selbst entscheidet,
      ob sie sich lohnt.
      → [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift) (`findClosestMatches`),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`isFallbackMatches`, `runMatching`, `resultsSection`)
- [x] **Sortierung nach real zu fahrender Gesamtstrecke statt nur Anfahrtsdistanz**: Beispiel
      Bochum → Essen zeigte bis zu 15 Treffer, sortiert nur danach, wie nah Start/Ziel an der
      jeweiligen Routen-Linie liegen (`combinedDistanceKm`). Dadurch landeten auch Fernwege oben,
      die zwar zufällig nah an beiden Städten vorbeikommen, aber zwischen den Anschlusspunkten
      einen riesigen Umweg entlang der Strecke machen (z. B. der Emscherparkradweg: Anfahrt
      zusammen nur ~2,9 km, aber ~180 km tatsächliche Streckenlänge zwischen den Punkten bei
      ~14,5 km Luftlinie). Nutzer-Erwartung (gemeinsam hergeleitet): "bring mich möglichst direkt,
      aber auf einer beschilderten Route von A nach B" - die relevante Zahl ist also die reale
      Gesamtstrecke (Anfahrt zum Streckenanfang + Strecke auf der Route + Anfahrt vom
      Streckenende), nicht nur die Anfahrt. Da diese Gesamtstrecke erst nach der asynchronen
      `routeSegmentDistance`-Berechnung (Dijkstra, s. o.) bekannt ist, zeigt die Liste zunächst
      weiterhin die schnelle Anfangssortierung nach Anfahrtsdistanz, wird aber automatisch einmalig
      neu sortiert, sobald für alle Treffer die tatsächliche Streckenlänge vorliegt. Treffer ohne
      auffindbaren Pfad (Kartenlücke) landen dabei ans Ende. Die aktuelle Auswahl (`selectedMatch`)
      wird beim Nachsortieren bewusst nicht verändert, um eine bereits getroffene Nutzerauswahl
      nicht zu überschreiben.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`loadRouteSegmentDistances`, `reorderMatchesByPracticalDistance`, `practicalDistanceKm`)
- [x] **"Öffnen mit"/Teilen-Menü-Integration für GPX-Dateien**: Ursprünglich bewusst
      zurückgestellt ("brauche ich nicht"), dann doch gewünscht, nachdem der Nutzer den Vergleich
      zu Komoots Teilen-Menü-Eintrag sah. RadFährte erscheint jetzt direkt im iOS-Teilen-Menü/bei
      "Öffnen mit" für `.gpx`-Dateien (z. B. aus der Dateien-App), genau wie beim manuellen
      Import über den Dateiauswahl-Dialog. Technisch: eigener UTI `com.frankenfeld.radfaehrte.gpx`
      (Apple hat keinen offiziellen GPX-Typ) über `UTExportedTypeDeclarations` +
      `CFBundleDocumentTypes` deklariert. Da das Projekt `GENERATE_INFOPLIST_FILE = YES` nutzt
      (kein physisches Info.plist), reichen die einfachen `INFOPLIST_KEY_*`-Build-Settings dafür
      nicht (keine verschachtelten Arrays/Dicts) - stattdessen zusätzlich `INFOPLIST_FILE` auf
      eine kleine Ergänzungs-Datei gesetzt, die Xcode automatisch mit dem generierten Info.plist
      zusammenführt. Da der synchronisierte Ordner diese Datei sonst automatisch auch als Bundle-
      Ressource einbindet (Xcode-Warnung), ist sie zusätzlich per
      `PBXFileSystemSynchronizedBuildFileExceptionSet` davon ausgenommen. `RootTabView.onOpenURL`
      speichert die per Teilen-Menü übergebene Datei genau wie der manuelle Import und wechselt
      danach zum Verlauf-Tab, damit sichtbar wird, dass es geklappt hat. `HistoryView` bekommt
      den `ImportedRouteStore` jetzt von `RootTabView` injiziert (statt eine eigene Instanz zu
      halten) und lädt bei einem Versions-Zähler neu, damit ein per Teilen-Menü importierter
      Eintrag auch sichtbar wird, wenn der Tab schon offen ist.
      → [Supplemental-Info.plist](FahrradApp/RadFaehrte/Supplemental-Info.plist), [RootTabView.swift](FahrradApp/RadFaehrte/RootTabView.swift) (`onOpenURL`, `importSharedGPX`), [HistoryView.swift](FahrradApp/RadFaehrte/Views/HistoryView.swift)
- [x] **Vierter Tab "Eigene Routen" + echter Fahr-Verlauf**: Der bisherige "Verlauf"-Tab
      vermischte zwei unterschiedliche Konzepte - importierte Ziel-Touren zum Nachfahren (GPX) und
      ein Protokoll tatsächlich gefahrener Strecken. Aufgeteilt in zwei Tabs: **Eigene Routen**
      (der bisherige GPX-Import/Start/Löschen-Flow 1:1 übernommen, nur umbenannt) und **Verlauf**
      (neu: zeigt jetzt echte, automatisch nach jeder beendeten Navigation gespeicherte Touren -
      Datum, Distanz, Dauer, Ø-Tempo, mit Detailansicht inkl. Karte der gefahrenen Strecke).
      Aufzeichnung: `ContentView` sammelt während der Navigation die GPS-Punkte
      (`tourTrackPoints`), `stopNavigating()` speichert sie (dezimiert über das bestehende
      `decimated`-Helper) als `DrivenTour` über `DrivenTourStore` (JSON-Dateien in
      `Documents/DrivenTours/`, analog `ImportedRouteStore`).
      → [DrivenTour.swift](FahrradApp/RadFaehrte/Models/DrivenTour.swift), [DrivenTourStore.swift](FahrradApp/RadFaehrte/Services/DrivenTourStore.swift), [HistoryView.swift](FahrradApp/RadFaehrte/Views/HistoryView.swift), [OwnRoutesView.swift](FahrradApp/RadFaehrte/Views/OwnRoutesView.swift), [RootTabView.swift](FahrradApp/RadFaehrte/RootTabView.swift), [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`tourTrackPoints`, `stopNavigating`)
- [x] **Bugfix: Route-Eingabe blieb nach "Beenden" in inkonsistentem Zustand**: `LocationSearchField`
      existiert nur `if !isNavigating` im View-Baum - beim Start/Ende der Navigation wird es damit
      neu erzeugt und verliert seinen internen Text-Status (`viewModel.queryFragment`), obwohl
      `startPlace`/`zielPlace` (Zustand von `ContentView`) unverändert weiterbestehen. Ergebnis:
      Nach "Beenden" zeigte das Ziel-Feld leer, obwohl im Hintergrund noch die letzte Route aktiv
      war (per Live-Test mit angehängter Gerätekonsole nachvollzogen). Behoben, indem `stopNavigating()`
      die Suche jetzt aktiv zurücksetzt (`startPlace`/`zielPlace`/`isImportedRouteMode` auf
      nil/false), passend zur Nutzererwartung "Beenden soll die Eingabe wieder leeren" - der
      bestehende `onChange`-Mechanismus räumt darüber automatisch auch `matches`/`selectedMatch`/
      `isDirectRouteMode` mit auf.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`stopNavigating`)
- [x] **Navigations-Steuerelemente neu gestaltet (Vorbild Komoot)**: Der "Standort"-Button (Kamera
      zurück zum Nutzer) saß direkt neben dem Heading/Nord-up-Umschalter und sah - trotz
      unterschiedlicher Icons - wie ein zweiter, redundanter Schalter aus, sobald beide gleichzeitig
      sichtbar waren (z. B. nach leichtem Kartenversatz während der Fahrt). Jetzt: eigener Anker
      unten rechts (`recenterButtonOverlay`), unabhängig von den anderen drei Steuerelementen.
      Beenden/2D-3D/Heading-Umschalter stecken jetzt außerdem in einem gemeinsamen abgerundeten
      Kasten mit dünnen Trennlinien statt drei einzelnen schwebenden Kreisen; die Kompass/Fahrtrichtung-
      Zeile ist orange hervorgehoben (Signalfarbe wie bei Komoot). Der 2D/3D-Button zeigte zudem
      immer dasselbe Icon unabhängig vom Zustand (kein sichtbarer Unterschied zwischen 2D/3D) - er
      zeigt jetzt als Text den **Zielzustand** (worauf ein Tap umschaltet): in der 2D-Ansicht steht
      "3D" und umgekehrt.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`navigationControlsOverlay`, `recenterButtonOverlay`, `navigationControlsBoxRow`)
- [x] **Ruhige-Wege-Offline-Routing pro Bundesland** (Phase 4, s. u. - das früher verworfene
      Zwischenexperiment wurde wiederaufgegriffen und diesmal fertig umgesetzt): "Direkte
      Fahrrad-Route" nutzt jetzt automatisch eine eigene A*-Engine statt MKDirections, wenn ein
      Bundesland heruntergeladen ist und Start/Ziel in dessen Abdeckung liegen - bevorzugt dabei
      gezielt Radwege/ruhige Straßen statt nur die kürzeste Verbindung. Ohne heruntergeladenes
      Bundesland (oder außerhalb seiner Reichweite) bleibt es wie bisher bei MKDirections online.
      - **Git/GitHub-Infrastruktur neu eingerichtet**: Es gab bereits ein lokales Git-Repo
        (verschachtelt in `FahrradApp/FahrradApp/.git`, mit der Historie des alten
        Zwischenexperiments), aber keinen Remote. Jetzt verbunden mit
        [github.com/Joern2368/RadFaehrte](https://github.com/Joern2368/RadFaehrte) (**öffentlich** -
        musste von privat auf öffentlich umgestellt werden, weil Release-Assets aus privaten
        Repos ohne eingebettetes Auth-Token nicht herunterladbar sind).
      - **Pipeline neu geschrieben** (`Scripts/build_way_graph.py`, `Scripts/venv` mit
        `osmium`/`shapely` - PyPI-Paketname ist `osmium`, nicht `pyosmium`): pro Bundesland ein
        gewichteter Wege-Graph aus dem Geofabrik-Extrakt (`HIGHWAY_WEIGHTS`-Tabelle bevorzugt
        Radwege/ruhige Straßen, meidet Hauptstraßen/Autobahnen; `oneway:bicycle=no` erlaubt
        Gegenrichtung in Einbahnstraßen).
      - **Kompaktes Binärformat statt normaler SQL-Tabellen mit Indizes**: Erster Versuch
        (`nodes`/`edges`-Tabellen mit `idx_edges_from`/`idx_edges_to`) ergab für
        Baden-Württemberg **1,8 GB** - `dbstat`-Analyse zeigte, dass allein die beiden Indizes
        ~700 MB ausmachten, obwohl die App sie nie nutzt (sie lädt beim Start ohnehin den
        kompletten Graphen in den Speicher, nie per SQL-Abfrage einzeln). Umgestellt auf ein
        einzeiliges `graph`-Table mit zwei Blobs (dichte 0-basierte Knoten-Indizes statt langer
        OSM-IDs, Float32 statt SQLite REAL) - Baden-Württemberg damit auf **448 MB** (Faktor 4).
        `VACUUM` + Datei vorher löschen nicht vergessen, sonst bläht eine wiederverwendete
        SQLite-Datei sich weiter auf.
      - **Alle 16 Bundesländer generiert und als GitHub-Release-Assets hochgeladen** (Tag
        `way-graphs-v1`, Dateiname `<bundesland>_ways.sqlite`), zusammen ~3 GB:
        Bremen 7,4 MB, Saarland 30 MB, Hamburg 19 MB, Berlin 26 MB, Schleswig-Holstein 81 MB,
        Mecklenburg-Vorpommern 60 MB, Sachsen-Anhalt 105 MB, Thüringen 123 MB, Brandenburg 132 MB,
        Sachsen 159 MB, Rheinland-Pfalz 220 MB, Hessen 231 MB, Niedersachsen 259 MB,
        Nordrhein-Westfalen 432 MB, Baden-Württemberg 448 MB, Bayern 650 MB.
      - **App-Seite**: `WayGraphRepository` (liest das Blob-Format, lädt Knoten/Kanten komplett
        in Arrays statt Dictionaries/SQL-Abfragen), `BikeRoutingEngine` (A* mit zulässiger
        Heuristik `minWeightMultiplier`, plus bis zu 2 Alternativrouten nach demselben
        Kanten-Ausschluss-Prinzip wie `RouteMatcher.routeSegmentDistance`), `WayGraphStore`
        (Dateiverwaltung in `Documents/WayGraphs/`), `WayGraphDownloadManager`
        (`URLSessionDownloadTask` mit KVO-Fortschritt, `@Observable`).
      - **Einstellungen-Tab**: neuer Bereich "Offline-Routing" mit Liste aller 16 Bundesländer
        (Herunterladen/Löschen, Fortschrittsbalken, Größenangabe). Bugfix unterwegs: `isDownloaded`
        prüfte ursprünglich bei jedem UI-Zugriff frisch das Dateisystem statt eine
        `@Observable`-Property zu lesen - SwiftUI bekam nach "Löschen" nie mit, dass sich etwas
        geändert hatte (kein Property-Zugriff = kein Re-Render). Behoben durch eine echte
        `downloaded: Set<Bundesland>`-Property, die bei Download/Löschen aktiv aktualisiert wird.
      - **`ContentView`**: `DirectRoute` (eigener Typ statt `[MKRoute]`, da `MKRoute` keinen
        öffentlichen Initializer hat) vereinheitlicht online (MKDirections, mit
        Schritt-für-Schritt-Anweisungen) und offline (Engine - seit dem v4-Wege-Graph-Format
        ebenfalls mit echten Turn-by-Turn-Anweisungen, s. u. "Straßennamen + Abbiege-Hinweise für
        die Offline-Routing-Engine"). Alle Alternativen (online wie offline) nutzen dieselbe
        Kartenanzeige/Tipp-Auswahl (`handleMapTap`, grau/blau).
      - ⚠️ **Bekannte Lücke, teilweise behoben (2026-07-26)**: Ursprünglich probierte der Code
        bei mehreren heruntergeladenen Bundesländern nur das **erste** in `Bundesland.allCases`
        (`.compactMap { ... }.first`) und schaltete bei Nichtabdeckung sofort auf Online um, statt
        die anderen zu probieren. Im Zuge der Niederlande-Erweiterung (s. u. "Offline-Routing auf
        die Niederlande erweitert") behoben: `ContentView.offlineGraphCandidatePaths()` sammelt
        jetzt die Pfade **aller** heruntergeladenen Regionen (Bundesländer + Länder) und
        `loadDirectRoute`/`rerouteDirectRoute` probieren sie der Reihe nach, bis eine passt. Es
        gibt weiterhin **keine Bounding-Box-Vorprüfung** für diesen ersten Durchlauf, jede Region
        wird bei Bedarf komplett geladen und erst dann geprüft (bei vielen heruntergeladenen
        Regionen entsprechend langsamer, aber dank `WayGraphCache` nur beim allerersten Zugriff).
      - ✅ **Routing über Bundesland-/Landesgrenzen hinweg, behoben (2026-07-31)**: Nutzer-Meldung
        "Route Bremen → Osnabrück (Bremen + Niedersachsen heruntergeladen) nutzt nicht die ruhige
        Offline-Route, sondern die direkte Online-Route". Ursache: Jeder heruntergeladene Graph ist
        vollständig isoliert (eigener dichter 0-basierter Knoten-Index pro Region, keinerlei
        Verbindung zum Nachbargraphen an der Grenze) - `BikeRoutingEngine.routes` fand nie einen
        Pfad, wenn Start und Ziel nicht im selben Graphen lagen, und die gesamte Strecke fiel dann
        auf Online-Routing zurück. Echtes Graph-Stitching (Grenz-Knoten aus zwei unabhängig
        zugeschnittenen Geofabrik-Extrakten einander per Koordinate zuordnen) wäre deutlich
        aufwendiger gewesen - stattdessen: **`CrossRegionRouteStitcher`** sucht näherungsweise die
        Stelle, an der die Luftlinie Start→Ziel von "Start-Region hat den näheren Knoten" zu
        "Ziel-Region hat den näheren Knoten" wechselt (`findHandoverCoordinate`, ~60 Abtastpunkte).
        Am gefundenen Übergangspunkt wird dann unabhängig in beiden Graphen auf den nächstgelegenen
        Knoten gesnappt, und `BikeRoutingEngine` berechnet zwei Teilrouten (Start → Übergang,
        Übergang → Ziel), die zu einer Route aneinandergereiht werden (`combinedRoute`). Bricht
        sauber ab (→ bisheriger Online-Fallback) wenn kein Übergang gefunden wird, keiner der
        beiden Graphen dort einen nahen Knoten hat, die beiden gesnappten Punkte über 1,5 km
        auseinanderliegen (Zeichen für eine unplausible Übergangsstelle, z. B. querfeldein ohne
        Wegedaten), oder eine der beiden Teilrouten selbst fehlschlägt.
        - **Drei Live-Test-Funde am eigentlichen Bremen → Osnabrück-Fall, alle noch am
          Einführungstag behoben** (Vorgehen: `xcrun devicectl device process launch --console`
          mit temporären `print()`-Aufrufen, analog zum bereits früher genutzten Verfahren, s. o.
          "Navigationskamera folgt jetzt zuverlässig der Fahrt"): (1) Erster Entwurf prüfte pro
          Abtastpunkt nur "hat Region X einen Knoten näher als Bounding-Box"/"näher als ein fester
          Radius" dran - schlug fehl, weil Bremen als Enklave innerhalb Niedersachsens so klein ist,
          dass praktisch jeder Punkt darin bereits innerhalb jedes plausiblen Radius auch "von
          Niedersachsen abgedeckt" war (nie ein reiner "nur Bremen"-Punkt, stiller Fallback auf
          Online-Routing). Behoben durch direkten Distanzvergleich statt Schwellenwert: pro
          Abtastpunkt zählt, welche der beiden Regionen den näheren Knoten hat, der Übergang ist die
          Stelle, an der sich das umdreht - funktioniert unabhängig von der Überlappung. (2) Live
          auf dem Gerät hing die Berechnung danach >40 s, weil `WayGraphRepository.nearestNode` bis
          dahin bei jedem Aufruf **alle** Knoten linear durchsuchte (für eine einzelne Routensuche
          mit 2 Aufrufen unproblematisch, aber `findHandoverCoordinate` ruft es beim Abtasten über
          100 Mal auf, bei Niedersachsens mehreren Millionen Knoten spürbar) - behoben durch ein
          grobes Rasterindex (`WayGraphRepository.spatialGrid`, ~1,1-km-Zellen, einmalig beim Laden
          aufgebaut), `nearestNode` durchsucht seitdem nur noch die wenigen Zellen um die
          Zielkoordinate statt aller Knoten (Nebeneffekt: beschleunigt auch alle bestehenden
          Einzel-Regionen-Suchen). (3) Danach lief die Suche schnell, fand aber trotzdem keine
          Route: Die zweite Teilstrecke (Übergang → Osnabrück, ~97 km quer durch Niedersachsen)
          überschritt `BikeRoutingEngine`s bestehendes `maxVisitedNodes`-Limit (300.000, ursprünglich
          nur grob für lokale Städte-Routen geschätzt, s. dort) und schlug deshalb still fehl, obwohl
          ein Pfad existierte - behoben durch einen neuen, überschreibbaren `maxVisitedNodes`-
          Parameter an `BikeRoutingEngine.route(s)`, `CrossRegionRouteStitcher` nutzt für seine
          beiden Teilstrecken jetzt testweise 1.500.000 (`legMaxVisitedNodes`) statt des Standards.
        In `ContentView` neue `crossRegionOfflineDirectRoute` (in `loadDirectRoute` und
        `rerouteDirectRoute` als zusätzlicher Versuch zwischen dem bestehenden Pro-Region-Durchlauf
        und dem Online-Fallback) probiert alle Paare aus Regionen, die Start bzw. Ziel abdecken -
        die dafür nötigen Graphen sind zu diesem Zeitpunkt bereits über `WayGraphCache` geladen (der
        vorherige Pro-Region-Durchlauf hat sie alle schon durchprobiert), also keine zusätzlichen
        Festplattenzugriffe. Per Unit-Test (`findHandoverCoordinate` mit synthetischen
        Distanz-Closures, ohne echte Graph-Dateien, inkl. Regressionstest für Fund 1) sowie live auf
        dem Gerät (Bremen → Osnabrück) verifiziert. Nicht abgedeckt: Ketten aus drei oder mehr
        Regionen (nur ein Übergang wird gesucht) - für diesen selteneren Fall bleibt der
        Online-Fallback bestehen. `HowItWorksView` entsprechend aktualisiert.
        ⚠️ Update 2026-08-02: Ketten aus drei oder mehr Regionen werden seitdem ebenfalls
        unterstützt, s. u. "Bounding-Box-Vorfilter für die Offline-Kandidatenliste der
        Direkt-Route".
        → [CrossRegionRouteStitcher.swift](FahrradApp/RadFaehrte/Services/CrossRegionRouteStitcher.swift),
        [WayGraphRepository.swift](FahrradApp/RadFaehrte/Services/WayGraphRepository.swift)
        (`spatialGrid`, `nearestNode`),
        [BikeRoutingEngine.swift](FahrradApp/RadFaehrte/Services/BikeRoutingEngine.swift)
        (`maxVisitedNodes`-Parameter an `route`/`routes`),
        [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift)
        (`crossRegionOfflineDirectRoute`, `regionDisplayName`)
      - **Offene Idee (nicht umgesetzt)**: Server-seitige On-Demand-Berechnung (ähnlich
        BRouter/GraphHopper), damit die ruhige Route auch ohne vorherigen Download nutzbar wäre,
        solange das Handy online ist. Bewusst zurückgestellt - bräuchte einen eigenen Server
        (Kosten/Wartung), während der aktuelle Ansatz ganz ohne Backend auskommt und dem
        eigentlichen Ziel (echte Offline-Fähigkeit) besser entspricht.
      → [Scripts/build_way_graph.py](FahrradApp/Scripts/build_way_graph.py), [WayGraphRepository.swift](FahrradApp/RadFaehrte/Services/WayGraphRepository.swift), [BikeRoutingEngine.swift](FahrradApp/RadFaehrte/Services/BikeRoutingEngine.swift), [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift), [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift), [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`DirectRoute`, `loadDirectRoute`, `offlineDirectRoutes`)
- [x] **Bugfix: Kamera-Verfolgung im Navigationsmodus blieb irgendwann stehen**: Nutzer-Meldung
      "der blaue Punkt bewegt sich aus dem Bildschirm heraus" beim Fahren/Laufen. Ursache: Ein
      Merker (`isProgrammaticCameraUpdate`), der eigene Kamera-Änderungen von Nutzer-Gesten
      unterscheiden sollte, wurde bei Kompass-Updates (mehrmals pro Sekunde, `.onChange(of:
      headingUpdateCount)`) mit vielen überlappenden animierten Kamera-Wechseln überflutet - der
      Merker wurde dadurch irgendwann in falscher Reihenfolge "verbraucht", die App hielt eine
      eigene Änderung fälschlich für eine Nutzer-Geste und schaltete die Verfolgung dauerhaft ab,
      ohne dass die Karte angefasst worden war. Behoben durch zwei Änderungen:
      1. `handleMapCameraChange` vergleicht jetzt direkt die gemeldete Kamera (`context.camera`:
         Mittelpunkt, Zoom-Distanz, Richtung) mit der zuletzt selbst gesetzten
         (`camerasRoughlyMatch`, mit Toleranzen) statt sich auf einen Merker zu verlassen - erkennt
         dadurch auch reines Herauszoomen (Mittelpunkt bleibt gleich) oder kleine manuelle Schwenks
         zuverlässig als Nutzer-Geste.
      2. Automatische Verfolgungs-Updates sind jetzt auf max. 2×/Sekunde gedrosselt
         (`lastAutomaticCameraUpdate`), damit nicht mehr so viele überlappende Animationen
         entstehen wie ursprünglich.
      - Nebenbefund: Der "Standort"-Button (Zurückspringen nach manuellem Verschieben) ließ das
        blaue Standort-Symbol nach einem größeren *animierten* Kamerasprung komplett verschwinden
        (MapKit-Eigenheit) - behoben, indem dieser gezielte Sprung jetzt unanimiert
        (`animated: false`) erfolgt.
      - Das eigentlich zuerst gemeldete Verschwinden nur der Pfeilspitze (Richtungsanzeige) war
        dagegen kein Bug: iOS zeigt den Richtungspfeil nur bei zuverlässiger Kompass-Bewegung,
        im Stillstand (0,0 km/h) erscheint erwartungsgemäß nur ein einfacher Punkt.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`updateNavigationCamera`, `handleMapCameraChange`, `camerasRoughlyMatch`)
- [x] **Ergebnisliste: Zwei kompakte Zeilen statt scrollbarer Liste + Radrouten-Vorschau ohne Ziel**:
      Die Ergebnisliste nahm bei mehreren Treffern viel vertikalen Platz weg, wodurch die Karte sehr
      klein wurde (Nutzer-Beobachtung). Umgesetzt wurde eine kompakte Variante innerhalb der
      bestehenden Struktur (Alternative dazu verworfen, s. u.):
      - **Wisch-Pager statt scrollbarer Liste**: `resultsSection` zeigt immer nur eine Ergebniszeile
        gleichzeitig – "Direkte Fahrrad-Route" fest oben, alle Radrouten-Treffer (`matches`)
        darunter als `TabView` mit `.tabViewStyle(.page(...))` durchwischbar statt einer
        `ScrollView`/`LazyVStack`-Liste. Seiten-Punkte-Indikator zeigt die Anzahl Treffer. Wischen
        wählt die angezeigte Seite sofort aus (zeigt sie direkt auf der Karte), nicht erst nach
        Antippen (`matchesPager`, `onChange(of: pagedMatchIndex)`).
      - **Radrouten in der Nähe schon vor Zieleingabe**: Sobald nur der Start gesetzt ist (z. B.
        "Aktueller Standort"), zeigt dieselbe Zeile automatisch die nächstgelegenen benannten
        Radrouten rund um den Startpunkt (`RouteMatcher.findNearby`, 15 km Suchradius, bis zu 20
        Treffer nach Filterung/Deduplizierung - s. u. "Bugfix: Brückenradweg/Friedensroute
        fehlten je nach Suchrichtung in der Nähe-Vorschau", ursprünglich 10) – vorher wurde erst
        nach vollständiger Start+Ziel-Eingabe überhaupt etwas angezeigt. Sobald ein Ziel eingegeben
        wird, übernimmt automatisch wieder die normale Start+Ziel-Suche (`loadNearbyMatches`,
        `onChange(of: zielPlace)`). Da `RouteMatch` eigentlich für Start+Ziel-Paare gedacht ist,
        nutzt dieser Modus einen eigenen Untertitel-Text (`nearbySubtitle`) statt der normalen
        `combinedDistanceKm`-Anzeige (die hier doppelt gezählt hätte). Löst damit einen Teil der
        Idee "Radwege in der Nähe anzeigen" (s. u. bei den Ideen) – als Vorschau-Zeile mit den
        nächsten Treffern, nicht als vollständige Kartendarstellung aller Routen.
      - **Ergebnisliste blendet sich beim Tippen aus**: Solange Start- oder Ziel-Suchfeld aktiv
        fokussiert ist (Adress-Vorschlagsliste sichtbar), wird `resultsSection` komplett
        ausgeblendet, damit sich die Vorschlagsliste nicht mit der "Radrouten in der Nähe"-Karte um
        den begrenzten Platz über der Tastatur streiten muss. `LocationSearchField` meldet
        Fokus-Änderungen dafür über einen neuen `onFocusChange`-Callback nach außen.
      - **Verworfen: Bottom-Sheet-Ansatz** – als erste Idee gegen die kleine Karte wurde
        Suche/Ergebnisliste probeweise in ein aufziehbares `.sheet` mit `.presentationDetents` über
        der (dadurch vollflächigen) Karte verschoben. Funktionierte technisch (Apple-Maps-artiges
        Muster), verdeckte aber dauerhaft die App-eigene Tab-Leiste unten (Route/Verlauf/Eigene
        Routen/Einstellungen), da ein permanent präsentiertes System-Sheet den darunterliegenden
        Tab-Bar-Bereich überlagert – für die 4-Tab-Struktur der App nicht passend. Nutzer-
        Entscheidung: zurück zum vorherigen Stand, stattdessen der Wisch-Pager-Ansatz oben.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`resultsSection`,
      `matchesPager`, `loadNearbyMatches`, `nearbySubtitle`, `isEditingStart`, `isEditingZiel`),
      [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift) (`findNearby`),
      [LocationSearchField.swift](FahrradApp/RadFaehrte/Views/LocationSearchField.swift) (`onFocusChange`)
- [x] **Gefahrene Strecke rot einzeichnen (Vorbild Komoot)**: Im Navigationsmodus wird die bereits
      zurückgelegte Strecke jetzt als rote Linie über der blauen Routen-Linie angezeigt, statt nur
      unsichtbar im Hintergrund für die Abschluss-Zusammenfassung mitgezählt zu werden. Nutzt dafür
      die ohnehin schon vorhandenen `tourTrackPoints` (werden per `accumulateTourDistance` bei jedem
      GPS-Update gesammelt, s. o. unter "Vierter Tab 'Eigene Routen'..."), einfach zusätzlich als
      eigenes `MapPolyline` gerendert (`.stroke(.red, lineWidth: 5)`), solange `isNavigating` und
      mindestens 2 Punkte vorliegen. Da es direkt nach `routeOverlayContent` im `Map`-Content-Block
      steht, liegt es im Z-Order über der blauen Route.
      - Per simulierter GPS-Fahrt im Simulator (`xcrun simctl location start` mit Wegpunkten
        entlang der Teststrecke Bremen→Achim) verifiziert: rote Linie wächst sichtbar mit der
        zurückgelegten Distanz. Bei der stark herausgezoomten Streckenübersicht des Simulator-Tests
        war sie größtenteils vom Standort-Punkt selbst verdeckt (nur wenige Meter simulierte
        Fahrt) – bei einer echten Fahrt mit der üblichen ~300-m-Verfolgungskamera (s. o. unter
        "Navigations-Verfolgungsmodus") sollte sie deutlich sichtbarer sein. Noch nicht auf einer
        echten Fahrt mit echtem GPS gegengetestet.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`tourTrackPoints`,
      `accumulateTourDistance`, `body` – roter `MapPolyline`-Block direkt nach `routeOverlayContent`)
- [x] **Bugfix: Wege-Graph-Download schlug nach erstem Löschen zuverlässig fehl**: Nutzer-Meldung
      "Speichern fehlgeschlagen: '...tmp' couldn't be moved to 'WayGraphs' because either the
      former doesn't exist, or the folder containing the latter doesn't exist" – nach dem ersten
      erfolgreichen Download+Löschen eines Bundeslands schlugen alle weiteren Downloads fehl.
      Ursache: klassischer `URLSessionDownloadTask`-Fehler – die von URLSession übergebene
      temporäre Datei wird sofort gelöscht, sobald der Completion-Handler zurückkehrt, das
      tatsächliche Verschieben (`WayGraphStore.save`) passierte aber verzögert in einem
      nachgelagerten `Task { @MainActor in ... }` (nötig, weil die Projekteinstellung
      `-default-isolation=MainActor` `WayGraphStore` sonst implizit MainActor-isoliert hätte).
      Reine Race Condition – deshalb klappte der allererste Download, spätere dann nicht mehr
      zuverlässig. Behoben durch zwei Änderungen: `WayGraphStore` ist jetzt `nonisolated`
      (enthält nur reine `FileManager`-Aufrufe auf einer unveränderlichen `directory`-URL, braucht
      keinen Actor-Schutz) und `WayGraphDownloadManager.download` ruft `store.save(...)` jetzt
      synchron direkt im Completion-Handler auf, bevor überhaupt auf den MainActor gehoppt wird
      (der Hop passiert danach nur noch fürs Aktualisieren von `downloaded`/`progress`/
      `errorMessage`). Vom Nutzer nach dem Fix mit mehreren Bundesländern (laden/löschen/erneut
      laden) verifiziert.
      → [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift),
      [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift) (`download`)
- [x] **Navigationskamera folgt jetzt zuverlässig der Fahrt (mehrere Bugfixes, live auf echtem
      Gerät gefunden/verifiziert)**: Nutzer-Meldung "die Karte bewegt sich nicht mit mir, blauer
      Punkt verschwindet aus dem Bild, die Karte dreht sich nicht". Drei unabhängige Ursachen,
      nacheinander gefunden:
      1. **Kaltstart-Race**: Lag beim Tippen auf "Los" noch kein GPS-Fix vor, setzte
         `startNavigating()` zunächst nur eine grobe Übersichts-Region (`cameraPosition = .region(...)`)
         statt der Kamera über `updateNavigationCamera` - `lastSetCamera` blieb dadurch `nil`.
         MapKit meldete das Einschwingen dieser Region über `handleMapCameraChange` als "das war
         der Nutzer" (der `lastSetCamera`-Vergleich schlägt bei `nil` fehl), schaltete
         `isFollowingUser` sofort dauerhaft ab - die Karte folgte danach nie mehr. Behoben mit
         einer kurzen Schonfrist (2 s) nach Navigationsstart, in der `handleMapCameraChange`
         Kamera-Berichte ignoriert (`navigationStartedAt`).
      2. **MapKit-Rundungseffekt bei der Zoom-Distanz** (per Live-Debug-Logging auf dem echten
         Gerät gefunden, s. u. "Technische Referenz"): Bei gesetzten `distance: 300` meldete
         MapKits `MapCameraUpdateContext.camera` teils `dist=613` zurück - Mittelpunkt (~6 m) und
         Richtung (~1,4°) stimmten dabei fast exakt überein, nur die Zoom-Distanz war (grundlos)
         um den Faktor ~2 daneben. Die bisherige 30-m-Toleranz beim Distanz-Abgleich in
         `camerasRoughlyMatch` hielt das für eine Nutzer-Geste (Pinch-Zoom) und schaltete die
         Verfolgung ab. Behoben, indem `camerasRoughlyMatch` die Zoom-Distanz gar nicht mehr
         vergleicht, nur noch Mittelpunkt und Richtung (die beide zuverlässig übereinstimmten).
      3. **Ruckelige/verzögerte Drehung**: Ursprünglich wurde die rohe Kompass-Richtung
         (`currentHeading`) ungefiltert direkt auf die Kartendrehung übertragen - jede kleine
         Magnetometer-Schwankung beim Gehen (Armschwung o. Ä.) wirkte sich sofort aus, sichtbar
         "unruhig" im Test-Video. Erster Fix (fester Tiefpassfilter, `alpha = 0.25`, plus
         `manager.headingFilter = 2`) behob das Wackeln, führte aber zu spürbarer Verzögerung bei
         echten Richtungswechseln (mehrere Sekunden, bis die Karte nachzog - Nutzer-Meldung "dreht
         sich nicht mehr"/"dauert ein wenig"). Durch adaptive Glättung ersetzt: kleine Abweichungen
         (< 8°, vermutlich Rauschen) weiterhin stark geglättet (`alpha = 0.2`), große (≥ 30°,
         eindeutig eine echte Drehung) fast verzögerungsfrei übernommen (`alpha = 1.0`), mittlere
         dazwischen (`alpha = 0.5`).
      - **Vorgehen bei Fund 2**: Live-Konsolen-Logging über `xcrun devicectl device process launch
        --console` (Ausgabe in eine Datei umgeleitet, da `print()` beim Piping gepuffert wird und
        erst nach genug Zeilen/Prozessende sichtbar wurde) plus temporäre `print()`-Aufrufe in
        `updateNavigationCamera`/`handleMapCameraChange` - Nutzer musste dafür nur kurz per Kabel
        verbinden, konnte danach ohne Rechner in der Hand im selben WLAN weitertesten. Alle
        Debug-Ausgaben nach dem Fund wieder entfernt.
      - Alle drei Fixes einzeln durch Video-Aufnahmen des Nutzers verifiziert (Frames per
        `AVAssetImageGenerator`-Skript extrahiert und geprüft, s. u. "Technische Referenz").
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`startNavigating`,
      `updateNavigationCamera`, `handleMapCameraChange`, `camerasRoughlyMatch`,
      `navigationStartedAt`), [LocationManager.swift](FahrradApp/RadFaehrte/Services/LocationManager.swift)
      (`smoothed`, `headingFilter`)
- [x] **Rote "gefahrene Strecke"-Linie: geglättet und auf die Straße eingerastet**: Zwei
      Nachbesserungen zur ersten Version (s. o.), beide per Live-Test/Video-Auswertung bestätigt:
      - Mindestabstand für einen neuen Aufzeichnungspunkt von 8 m auf 18 m erhöht (`8` reichte in
        dicht bebauter Umgebung nicht, um GPS-Rauschen bei langsamer Fahrt/zu Fuß auszugleichen).
      - Neu: Liegt eine bekannte Routen-Geometrie vor (kuratierte Radroute über
        `selectedRouteLines`, oder "Direkte Fahrrad-Route" über `directRoutes`), wird jeder Punkt
        vor dem Aufzeichnen auf die nächstgelegene Stelle dieser Geometrie "eingerastet"
        (`RouteMatcher.nearestPoint`, nur bei < 50 m Abstand, damit ein echtes Abweichen nicht
        künstlich verdeckt wird) - wie bei Apple/Google Maps. Nutzer-Beobachtung vorher: "ich bin
        exakt auf der Straße gegangen, aber die Linie sah trotzdem daneben aus" (Ursache: das
        eingebaute `UserAnnotation()` verwendet vermutlich eine eigene, von uns nicht
        konfigurierbare interne Standortabfrage, unabhängig von unserem `LocationManager` -
        deshalb wirkt die Positionsgenauigkeit in unserer App schlechter als in Apple/Google Maps,
        obwohl dieselbe Hardware genutzt wird). Das Einrasten löst das nur für die aufgezeichnete
        Linie, nicht für den angezeigten blauen Punkt selbst (der bleibt System-gesteuert) - siehe
        "Offene Idee" unten.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`accumulateTourDistance`,
      `activeNavigationRouteLines`, `minTrackPointDistanceMeters`)
      - **Offene Idee (nicht umgesetzt)**: Den angezeigten blauen Punkt selbst durch eine eigene
        Markierung (`Annotation(coordinate:)` statt `UserAnnotation()`) ersetzen, die während der
        Navigation ebenfalls auf die Route eingerastet wird - damit wäre auch der sichtbare Punkt
        (nicht nur die rote Aufzeichnungslinie) so präzise wie bei Apple/Google Maps. Größerer
        Umbau, bewusst zurückgestellt.
- [x] **Automatische Neuberechnung bei Abweichen von der "Direkten Fahrrad-Route" (wie Apple/Google
      Maps)**: Gilt bewusst **nur** für die "Direkte Fahrrad-Route", nicht für kuratierte Radrouten
      (`RouteMatch`) - dort will man die Strecke genau entlangfahren, ein Abweichen soll per
      `loadConnectorRoute` zurück zur Strecke führen statt die Route zu ändern. Bei jedem
      Standort-Update wird der Abstand zur aktuell gewählten direkten Route geprüft
      (`RouteMatcher.nearestPoint`); ab Überschreiten eines Schwellenwerts wird vom aktuellen
      Standort aus neu zum Ziel berechnet (online via `MKDirections` oder offline via
      `BikeRoutingEngine`, je nachdem was gerade aktiv ist), ohne die alte Route sofort zu
      verwerfen (kein kurzes Leerbild, `directRoutes` wird erst ersetzt, wenn die neue fertig ist).
      Cooldown von 15 s zwischen zwei automatischen Neuberechnungen gegen Netzwerk-/Rechenlast bei
      einem an der Schwelle schwankenden GPS-Punkt. Schwellenwert ursprünglich 50 m, nach
      Live-Test auf 25 m gesenkt (Nutzer-Feedback: bei Fußgeschwindigkeit fühlten sich 50 m
      spürbar spät an - ~40-60 s, bis die Abweichung erkannt wurde).
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`checkDirectRouteDeviation`,
      `rerouteDirectRoute`, `directRouteDeviationThresholdKm`, `directRouteRerouteCooldown`)
- [x] **"Direkte Fahrrad-Route" ist jetzt die Standard-Auswahl statt automatisch der ersten
      kuratierten Radroute**: Nutzer-Entscheidung. Bisher wählte `runMatching()` nach einer
      Start+Ziel-Suche automatisch `matches.first` (die nach praktischer Distanz beste kuratierte
      Radroute) aus; jetzt wird stattdessen `selectDirectRoute()` aufgerufen, sobald Treffer
      vorliegen. Die kuratierten Treffer werden weiterhin im Hintergrund geladen (Segmentdistanzen
      inklusive) und bleiben im Wisch-Pager durchstöber- und wählbar - nur die automatische
      Vorauswahl hat sich geändert.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`runMatching`, `selectDirectRoute`)
- [x] **Splash-Screen neu gestaltet mit KI-generierter Illustration statt kleinem zentriertem
      Icon**: Motiv (per ChatGPT-Bild-KI erzeugt, cremeweiße Linien auf Petrol, passend zur
      bestehenden Markenfarbe): geschwungener Weg durch Hügel zu einem aufgehenden/untergehenden
      Sonnenkreis, ein Fahrrad steht am Wegrand. Ersetzt das bisherige, kleine (220×220pt)
      zentrierte App-Icon auf einfarbigem Hintergrund durch ein bildschirmfüllendes Motiv
      (`.scaleAspectFill`/`.scaledToFill()`, an allen vier Kanten fixiert statt zentriert mit
      fester Größe). Bild bewusst mit Sicherheitszone gestaltet (wichtige Elemente in der
      mittleren ~65 % der Fläche, Ränder eher schlicht) und Petrol-Hintergrund direkt im Bild
      hinterlegt (nicht transparent) - so fällt ein unterschiedlicher Zuschnitt auf verschiedenen
      iPhone-Seitenverhältnissen (SE bis Pro Max) nicht auf. Neues Bild-Set `SplashArt`
      (864×1821px, ein Bild für alle Skalierungsfaktoren wie schon bei `LaunchIcon`). Anzeigedauer
      der SwiftUI-Nachbildung (`SplashView`, s. o. "Startbildschirm passend zum App-Icon") von
      1,2 s auf 2 s erhöht (Nutzer-Feedback: fühlte sich zu kurz an).
      → [Assets.xcassets/SplashArt.imageset](FahrradApp/RadFaehrte/Assets.xcassets/SplashArt.imageset),
      [LaunchScreen.storyboard](FahrradApp/RadFaehrte/LaunchScreen.storyboard),
      [SplashView.swift](FahrradApp/RadFaehrte/Views/SplashView.swift),
      [RootTabView.swift](FahrradApp/RadFaehrte/RootTabView.swift)
- [x] **Navigationskamera: weitere Nachbesserungen nach Live-Tests (Drehung/Zoom)**:
      - **Stetige statt gestufte Kompass-Glättung**: Die erste adaptive Glättung (s. o.) hatte feste
        Stufen (< 8° / < 30° / darüber), was an der 30°-Grenze einen spürbaren Sprung in der
        Glättungsstärke verursachte ("holprig" im Live-Test). Jetzt linear zwischen 5° (stark
        geglättet) und 35° (verzögerungsfrei) statt gestuft.
      - **Lineare statt gefederte Kamera-Animation**: Automatische Updates (alle 0,5 s) nutzten
        SwiftUIs Standardanimation, die zum Ende jedes Segments abbremste, bevor das nächste
        begann - fühlte sich dadurch zusätzlich "holprig" an. Jetzt `.linear(duration: 0.5)`,
        exakt passend zur Drossel-Dauer, verbindet die Segmente nahtloser.
      → [LocationManager.swift](FahrradApp/RadFaehrte/Services/LocationManager.swift) (`smoothed`)
- [x] **Bugfix: Manuelles Zoomen während der Navigation funktionierte nicht (mehrere Anläufe,
      live per Debug-Log auf den genauen Grund zurückgeführt)** + **"Zentrieren"-Banner statt
      kleinem Standort-Icon (Vorbild Komoot)**:
      - **Erster Versuch (nicht ausreichend)**: Zoom-Distanz sollte bei automatischen Updates
        einfach nicht mehr angefasst werden (`resetDistance`-Parameter, zuletzt gesetzten Wert
        beibehalten). Fehlschlug strukturell - `lastSetCamera` wurde nur von uns selbst
        geschrieben, nie vom tatsächlichen (durch Kniff veränderten) Kamerazustand, blieb also
        praktisch immer bei 300 m. Wieder entfernt.
      - **Zweiter Versuch (nicht ausreichend)**: Eine `MagnificationGesture` sollte die
        Verfolgung bei Kniff-Beginn pausieren - vorschnell wieder entfernt, weil fälschlich
        angenommen wurde, MapKit beanspruche Zwei-Finger-Gesten exklusiv für sich und die Geste
        käme nie an. Stattdessen die Distanz-Toleranz in `camerasRoughlyMatch` auf 400 m
        aufgeweitet (in der Annahme, ein "erkannter" Kniff reiche aus).
      - **Gefundene Ursache (per Live-Konsolen-Log auf dem Gerät, `--console` +
        `print()`-Aufrufe, s. u. "Technische Referenz")**: Die `MagnificationGesture` feuerte die
        ganze Zeit zuverlässig - das eigentliche Problem war ein Wettlauf: Ein automatisches
        Verfolgungs-Update (bis zu alle 0,5 s) konnte mitten in einen laufenden Kniff hineinlaufen
        und die Zoom-Distanz auf 300 m zurücksetzen, *bevor* `handleMapCameraChange` (feuert nur
        mit `.onEnd`-Häufigkeit, also erst nach Loslassen) den Kniff überhaupt als Geste hätte
        erkennen können - das erklärte auch das vom Nutzer beobachtete "geht manchmal, meistens
        nicht" (reine Timing-Frage). Log-Beispiel: automatisches Update setzt `dist=300`, direkt
        danach meldet MapKit den echten (gekniffenen) Zustand `dist=445` - noch innerhalb der
        400-m-Toleranz, also nicht als Geste erkannt -, das nächste automatische Update setzt
        prompt wieder auf `300` zurück.
      - **Behoben**: `MagnificationGesture().onChanged` setzt `isFollowingUser = false` **sofort**
        bei den ersten Anzeichen eines Kniffs - verhindert das automatische Update von vornherein,
        statt hinterher (zu spät) zu erkennen, dass eins passiert ist. Zusätzlich dieselbe Logik
        für eine allgemeine `DragGesture(minimumDistance: 10)`, damit auch Ein-Finger-Gesten (z. B.
        MapKits eingebautes "Doppeltippen-und-Halten-dann-Ziehen"-Zoom, das keine
        `MagnificationGesture` auslöst) sauber greifen, nicht nur "am Ende doch irgendwie"
        (Nutzer-Beobachtung dazu: "sperrig, aber geht"). Die 400-m-Distanztoleranz in
        `camerasRoughlyMatch` bleibt als zusätzliches Sicherheitsnetz gegen den bekannten
        MapKit-Meldefehler (s. o.) bestehen.
      - **"Zentrieren"-Banner**: Das bisherige kleine Icon unten rechts (`recenterButtonOverlay`)
        wurde nach Nutzer-Vergleich mit Komoot-Screenshots durch einen auffälligeren orangen
        Pillen-Banner ("Zentrieren" + Symbol) unten mittig ersetzt - erscheint weiterhin nur,
        wenn die Verfolgung pausiert ist.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`updateNavigationCamera`,
      `handleMapCameraChange`, `camerasRoughlyMatch`, `recenterButtonOverlay`, `MagnificationGesture`-
      und `DragGesture`-Aufrufe im `Map`-Block)
- [x] **Rote Linie: kein Versatz mehr zum blauen Punkt, keine Ausreißer-Spitzen bei Stillstand**:
      - **Durchgehend statt nachhinkend**: Da `tourTrackPoints` erst alle `minTrackPointDistanceMeters`
        (18 m) fortgeschrieben wird, blieb die gezeichnete Linie bis zu ~18 m hinter dem blauen
        Punkt zurück (Nutzer-Meldung: "die rote Linie erscheint immer versetzt"). Neue
        `displayedTourTrackPoints`-Eigenschaft hängt beim Zeichnen zusätzlich die aktuelle
        Live-Position (ebenfalls auf die Route eingerastet, aber nicht dauerhaft gespeichert) an -
        die Linie reicht dadurch immer bis zum aktuellen Standort, ohne die für
        Distanzberechnung/Tour-Speicherung genutzten `tourTrackPoints` selbst dichter zu machen.
      - **Stillstands-Sperre gegen Ausreißer**: Bei echtem Stillstand (z. B. kurz in einem Geschäft)
        kann die gemeldete Position ohne Bewegung um mehrere Zehnermeter "wandern" - zusammen mit
        dem Einrasten auf die Route entstand dadurch im Live-Test eine deutlich sichtbare
        Dreieck-Spitze in der Linie. Updates mit verlässlich niedriger gemeldeter Geschwindigkeit
        (`location.speed >= 0 && < 0.5 m/s`) werden jetzt ignoriert.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`displayedTourTrackPoints`,
      `accumulateTourDistance`)
- [x] **Bildschirm bleibt während der Navigation an + Hintergrund-Standort-Tracking mit blauem
      System-Indikator (wie Komoot/Google Maps)**: Zwei Ergänzungen, beide nur während aktiver
      Navigation aktiv (nicht bei einmaligen Standortabfragen wie "aktuellen Standort verwenden"):
      - `UIApplication.shared.isIdleTimerDisabled` wird in `startNavigating()`/`stopNavigating()`
        gesetzt - das iPhone sperrte sich bisher während der Fahrt automatisch nach der üblichen
        Bildschirm-Zeitüberschreitung.
      - `LocationManager.setBackgroundUpdatesEnabled(_:)` schaltet
        `manager.allowsBackgroundLocationUpdates` um - dafür `UIBackgroundModes: [location]` neu in
        `Supplemental-Info.plist` deklariert (Pflicht, sonst Absturz beim Setzen auf `true`). Läuft
        bewusst mit "Bei Nutzung"- statt "Immer"-Standortzugriff: iOS erlaubt das für aktives
        Tracking über den blauen Statusleisten-Indikator, den man antippen kann, um zur App
        zurückzuspringen - genau das von Komoot/Google Maps bekannte Verhalten, keine zusätzliche
        Berechtigung nötig. Zusätzlich `activityType = .otherNavigation` und
        `pausesLocationUpdatesAutomatically = false` (sonst pausiert iOS Updates automatisch bei
        vermeintlichem Stillstand, z. B. an einer Ampel).
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`startNavigating`,
      `stopNavigating`), [LocationManager.swift](FahrradApp/RadFaehrte/Services/LocationManager.swift)
      (`setBackgroundUpdatesEnabled`), [Supplemental-Info.plist](FahrradApp/RadFaehrte/Supplemental-Info.plist)
- [x] **Einstellungen neu organisiert (waren durch 16 Bundesland-Zeilen auf einem Screen zu lang) +
      zwei neue Info-Screens**: `SettingsView` zeigt jetzt nur noch die
      Durchschnittsgeschwindigkeit direkt, alles andere über `NavigationLink` in eigene
      Unterseiten:
      - **`OfflineMapsView`** (neu, ausgelagert): die bisherige Bundesländer-Liste 1:1 übernommen,
        inkl. `WayGraphDownloadManager` und Fehler-Alert.
      - **`HowItWorksView`** (neu): kurze Erklärung der Kernfunktionen für Nutzer, die die App zum
        ersten Mal sehen oder eine Funktion vergessen haben (Route suchen, Navigation, Steuerung
        während der Fahrt, Eigene Routen, Verlauf, Offline-Karten - je ein Absatz mit Icon). Bewusst
        über Einstellungen erreichbar statt als erzwungenes Onboarding beim ersten Start.
        ⚠️ **Wichtig für künftige Änderungen**: Wird ein neues, für Nutzer sichtbares Feature
        ergänzt, soll auch dieser Screen entsprechend aktualisiert werden (s. `CLAUDE.md`).
      - **`AboutView`** (neu): App-Icon, Versionsnummer (liest `CFBundleShortVersionString`/
        `CFBundleVersion` direkt aus dem Bundle - kein manuelles Nachpflegen bei neuer Version
        nötig) und eine antippbare Kontakt-`mailto:`-Zeile mit der Nutzer-E-Mail-Adresse.
      → [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift),
      [OfflineMapsView.swift](FahrradApp/RadFaehrte/Views/OfflineMapsView.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [AboutView.swift](FahrradApp/RadFaehrte/Views/AboutView.swift)
- [x] **Rote Linie: Einrast-Schwelle auf die Route deutlich verkleinert**: Nach einer echten
      Fahrt (5:44 Uhr) Nutzer-Meldung: Bei Abweichen von der Route "springt" die rote Linie
      sichtbar auf die blaue Routen-Linie, statt die tatsächliche Position zu zeigen - die
      bisherige 50-m-Schwelle (s. o. "Rote Linie: kein Versatz mehr...") war zu großzügig.
      Eigene Konstante `routeSnapThresholdKm` eingeführt und auf 15 m gesenkt (in
      `accumulateTourDistance` und `displayedTourTrackPoints`).
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`routeSnapThresholdKm`)
- [x] **"Direkte Fahrrad-Route" folgt jetzt dem tatsächlichen Radweg statt der Straßenmitte, wenn
      OSM einen baulich getrennten Radweg kennt (`cycleway=track/lane`)**: Nutzer-Beobachtung nach
      derselben Fahrt: Die blaue Linie lag auf der Straße, gefahren wurde aber auf dem daneben
      liegenden Radweg (Beispiel: Richtweg, Bremen). Gemeinsame Diagnose (auf Nutzer-Wunsch "erst
      zusammen überlegen" vor jeder Umsetzung):
      - Erste Hypothese (falsch, vom Nutzer widerlegt: "ich hatte nur Bremen geladen") - dass
        `loadDirectRoute()`s `Bundesland.allCases.compactMap { wayGraphStore.path(for: $0) }.first`
        bei mehreren heruntergeladenen Bundesländern das falsche (nicht abdeckende) auswählt (s.
        "Bekannte Lücke" oben, weiterhin unbehoben, war hier aber nicht die Ursache).
      - Per Live-Recherche (OpenStreetMap-Web-Oberfläche, `way/4079518`) bestätigt: Der Richtweg
        ist als `highway=residential` + `cycleway=track` getaggt - ein baulich getrennter Radweg,
        aber **nicht als eigene, seitlich versetzte Geometrie** gezeichnet, sondern nur als
        Attribut an der Straßen-Mittellinie. `Scripts/build_way_graph.py`s Gewichtung
        (`weight_multiplier`) reagierte darauf korrekt (0.85 × `CYCLE_INFRA_BONUS` 0.7 = 0.595,
        fast wie ein reiner Radweg) - der Weg wurde also bereits bevorzugt gewählt, es gab in den
        Daten nur schlicht keine zweite Linie, auf die stattdessen geroutet werden konnte. Zweiter
        Hinweis, dass tatsächlich die Offline-Engine (nicht ein stiller Online-Fallback) aktiv
        war: Der Navigations-Titel zeigte durchgehend generisch "Route folgen" statt einer echten
        MKDirections-Abbiegeanweisung mit Straßennamen (Offline-Routen haben keine Turn-by-Turn-
        Schritte, s. "Bekannte Lücke" oben).
      - **Umsetzung (Nutzer-Entscheidung: "sauber", trotz größerem Aufwand)**: Seitlicher
        Kartenversatz für Kanten mit `cycleway=track/lane`, rein für die Anzeige-Geometrie (Routing-
        Gewichtung/Knoten-Konnektivität unverändert):
        - `Scripts/build_way_graph.py`: neue `offset_side(tags)` - 0 (kein Versatz), 1 (rechts)
          oder 2 (links), bezogen auf die digitalisierte Richtung des Ways. `cycleway:right`/
          `cycleway:left` sind eindeutig; bei `cycleway:both` oder unqualifiziertem
          `cycleway=track/lane` (wie beim Richtweg) ist die Seite in OSM nicht angebbar - dort wird
          vereinfachend **rechts** angenommen (häufigste Lage in Deutschland, aber keine Garantie -
          ggf. später gegen echte Fahrten kalibrieren). Kanten-Binärformat um 1 Byte pro Kante
          erweitert (`<IIff>` → `<IIffB>`, 16 → 17 Byte); bei der jeweils jetzt zusätzlich erzeugten
          Rückwärts-Kante wird die Seite gespiegelt (rechts↔links), da sich "rechts des Wegs"
          bei umgekehrter Fahrtrichtung geografisch auf die andere Seite bezieht.
        - `WayGraphRepository.Edge` liest das neue Byte (`offsetSide`), Parsing-Schrittweite auf 17
          Byte angepasst.
        - `BikeRoutingEngine`: A* merkt sich pro Knoten zusätzlich die `offsetSide` der Kante, über
          die er auf dem besten Pfad erreicht wurde (`cameFromOffsetSide`); die Ergebnis-Koordinaten
          werden jetzt kantenweise (nicht mehr pro Knoten) über eine neue `offsetPoint`-Funktion
          gebaut, die die Strecke senkrecht zu ihrer Richtung um 3,5 m verschiebt (grobe Schätzung
          für den typischen Abstand eines getrennten Radwegs, keine echte Vermessung). An
          Übergängen zwischen versetzten und nicht versetzten Kanten entstehen dadurch kleine
          Sprünge in der Linie - bewusst so belassen, da der reale Radweg dort tatsächlich beginnt
          bzw. endet.
        - **Format-Versionierung**: Da alte, bereits heruntergeladene `.sqlite`-Dateien (16-Byte-
          Kanten) sonst mit falscher Schrittweite fehlinterpretiert würden, prüft `WayGraphStore`
          beim Start eine `.format-version`-Markerdatei und löscht bei Änderung automatisch alle
          heruntergeladenen Graphen (Nutzer muss dann nur neu herunterladen, nichts manuell
          löschen). Download-URL zeigt jetzt auf einen neuen GitHub-Release-Tag `way-graphs-v2`
          statt Assets im alten `way-graphs-v1` zu überschreiben.
        - Verifiziert: `offset_side()` liefert für den Richtweg wie erwartet 1 (rechts); nach
          Neubau + Upload von Bremen und Neuinstallation auf dem Gerät zeigte die Linie am Richtweg
          sichtbar seitlich versetzt statt mittig auf der Straße (vom Nutzer per Screenshot
          bestätigt). Alle 16 Bundesländer wurden anschließend im neuen Format neu gebaut und nach
          `way-graphs-v2` hochgeladen (`Scripts/rebuild_and_upload_v2.sh`, neues Hilfsskript für den
          Bulk-Rebuild/-Upload aller Bundesländer außer Bremen).
          ⚠️ **Überholt**: Der Screenshot-Vergleich erkannte nur "es gibt einen Versatz", nicht
          zuverlässig "auf der richtigen Seite" - eine echte Fahrt zeigte später, dass es genau
          umgekehrt war. `offset_side()` gibt seit dem Fix weiter unten ("Offline-Routing verließ
          gelegentlich...") bewusst vertauschte Werte zurück (`cycleway:right` -> `OFFSET_LEFT`
          usw.) - diese Zeile hier beschreibt nur den historischen Ausgangszustand.
      → [Scripts/build_way_graph.py](FahrradApp/Scripts/build_way_graph.py) (`offset_side`,
      `OFFSET_NONE`/`OFFSET_RIGHT`/`OFFSET_LEFT`), [Scripts/rebuild_and_upload_v2.sh](FahrradApp/Scripts/rebuild_and_upload_v2.sh),
      [WayGraphRepository.swift](FahrradApp/RadFaehrte/Services/WayGraphRepository.swift) (`Edge.offsetSide`),
      [BikeRoutingEngine.swift](FahrradApp/RadFaehrte/Services/BikeRoutingEngine.swift)
      (`cameFromOffsetSide`, `displayCoordinates`, `offsetPoint`, `cycleOffsetMeters`),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift) (`formatVersion`,
      `invalidateIfFormatChanged`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift)
      (`downloadURL`)
- [x] **Abschluss-Zusammenfassung: Speichern im Verlauf ist jetzt eine bewusste Entscheidung statt
      automatisch**: Nutzer-Wunsch - bisher landete jede beendete Fahrt mit ≥ 2 aufgezeichneten
      Punkten ungefragt im Verlauf-Tab. `stopNavigating()` baut den `DrivenTour`-Datensatz zwar
      weiterhin sofort (Distanz/Dauer/Ø-Tempo/Trackpunkte stehen ja nur zu diesem Zeitpunkt zur
      Verfügung), hängt ihn aber nur noch unpersistiert an `TourSummary` an; erst ein Tap auf
      **"Im Verlauf speichern"** im Abschluss-Sheet ruft `drivenTourStore.save(...)` auf. Ein
      zweiter Button **"Verwerfen"** verwirft die Tour ersatzlos. Das Sheet ist in diesem Fall
      `interactiveDismissDisabled()` (kein versehentliches Wegwischen ohne Entscheidung) - bei zu
      wenigen Punkten (`drivenTour == nil`, z. B. sofortiges Beenden ohne Bewegung) bleibt es beim
      einzelnen "Fertig"-Button ohne Auswahl, da es dort ohnehin nichts zu speichern gibt.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`TourSummary.drivenTour`,
      `stopNavigating`, `tourSummarySheet`)
- [x] **Ungültige Kompass-Updates werden jetzt verworfen statt verarbeitet**: Nutzer-Meldung nach
      einem echten Fußtest in dicht bebauter Umgebung (Philosophenweg/Hillmannstraße, Bremen): Die
      Richtungsanzeige "hing" für ca. 2 Minuten fest, danach ging es von selbst wieder - typisches
      Symptom einer Magnetometer-Störung durch Gebäude/parkende Autos/Metall in der Nähe (kein
      App-Bug, dieselbe Störung träte bei jeder Kompass-App auf). Dabei aber eine echte kleine
      Lücke gefunden: `didUpdateHeading` prüfte `newHeading.headingAccuracy` bisher nicht - ein
      negativer Wert bedeutet laut Apple-Doku "diese Messung ist gerade unzuverlässig", wurde aber
      trotzdem ungefiltert in die Glättung (`smoothed`) übernommen. Jetzt werden solche Updates
      komplett verworfen (`guard newHeading.headingAccuracy >= 0 else { return }`) - behebt die
      Störung selbst nicht (Hardware/Umgebung), sollte aber die Erholung danach etwas ruhiger statt
      springend machen. Noch nicht erneut live gegengetestet.
      → [LocationManager.swift](FahrradApp/RadFaehrte/Services/LocationManager.swift) (`didUpdateHeading`)
- [x] **Navigations-Politur nach Live-Tests (Buttons, Kamera, Dialoge)**: Mehrere kleine, per
      Live-Test am Nutzer verifizierte Verbesserungen an einer Sitzung:
      - **Beenden-Button räumlich getrennt**: Saß vorher direkt neben 2D/3D in einer gemeinsamen
        Box, wurde beim Bedienen der anderen Buttons leicht versehentlich getroffen. Jetzt eigener
        Kreis oben links (`endNavigationButton`), 2D/3D und Heading-up/Nord-up als zwei einzelne
        Kreise oben rechts statt der gemeinsamen Box. Sicherheitsabfrage ergänzt
        (`confirmationDialog`, Titel "Navigation pausiert", Pause- statt X-Symbol, Buttons
        "Navigation beenden"/"Fortsetzen" - `role: .cancel` wurde von iOS in diesem Dialog-Stil
        unsichtbar behandelt, deshalb bewusst ohne Rolle als normaler Button).
      - **Kamera-Nachführung spürbar flüssiger**: Kompass-Richtung kommt jetzt über CoreMotion
        (`CMDeviceMotion.heading`, gyroskop-stabilisiert) statt reinem `CLLocationManager`-
        Magnetometer, das bei Störungen sichtbar einfrieren und dann ruckartig aufholen konnte
        (per Frame-Vergleich zweier Bildschirmaufnahmen - eigene App vs. Komoot - nachgewiesen).
        Kamera-Update-Takt von 0,5 s auf 0,2 s erhöht. GPS-Position zusätzlich leicht geglättet
        (`LocationManager.smoothedCameraCoordinate`). "Zentrieren"-Sprung jetzt sanft animiert
        (`recenterAnimation`) statt hart, mit Hinweis im Code auf den früheren Grund für "ohne
        Animation" (verschwindender Standort-Punkt bei großen animierten Sprüngen - falls das
        wieder auftritt, dort nachsehen).
      - **Fälschliches Auslösen von "Zentrieren" behoben**: Der alte Vergleich der von MapKit
        gemeldeten Kamera mit der zuletzt selbst gesetzten (`camerasRoughlyMatch`) schaltete die
        Verfolgung auch ohne echte Nutzer-Geste ab (nach längerem Stillstand, oder bei einer
        zügigen echten Kurve). Entfernt und durch einen expliziten `RotationGesture`-Handler
        ersetzt (neben den schon bestehenden für Pan/Zoom) - Gesten-Erkennung läuft jetzt
        vollständig über direkte Gesten-Handler, nicht mehr über Kamera-Vergleich.
      - **Rote "gefahrene Strecke"-Linie**: Einrasten auf die Routen-Geometrie zunächst komplett
        entfernt (verursachte Zickzack in Kurven durch abruptes Springen zwischen Segmenten),
        dann wieder eingeführt mit engerem Radius (7 m statt 15 m) und Trägheit
        (`snapToActiveRoute`: bevorzugt das zuletzt genutzte Segment, wechselt nur bei >30 %
        Verbesserung) - behebt sowohl das Kurven-Zickzack als auch leichten seitlichen Versatz auf
        geraden Abschnitten.
      - **Icons**: Heading-up/Nord-up-Umschalter nach Komoot-Vorbild überarbeitet (Kompass-Pfeil
        bzw. "N"-Buchstabe statt zwei ähnlich aussehender Pfeile), 2D/3D- und Beenden-Button von
        `.thinMaterial` auf `.regularMaterial` (etwas dunkler, auf hellen Kartenfarben besser
        sichtbar, aber nicht komplett schwarz).
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift), [LocationManager.swift](FahrradApp/RadFaehrte/Services/LocationManager.swift)
- [x] **Straßennamen + Abbiege-Hinweise für die Offline-Routing-Engine (Wege-Graph-Format v4)**:
      Die "Direkte Fahrrad-Route" zeigt bei heruntergeladenem Bundesland jetzt echte
      Turn-by-Turn-Anweisungen ("Links abbiegen auf Bahnhofstraße", "Weiter auf X") statt nur
      "Route folgen" - Nutzer-Wunsch nach Live-Test der Kamera-Verbesserungen.
      - **`Scripts/build_way_graph.py`**: erfasst jetzt `tags.get("name")` pro Way, dedupliziert in
        einer Namenstabelle (`names`-Blob: `UInt16 byteLength` + UTF-8 pro Name), pro Kante ein
        Index darauf. **Erster Versuch mit UInt16-Index (2 Byte, max. 65.534 Namen) schlug beim
        echten Bau fehl**: Baden-Württemberg erreichte exakt diese Grenze (später mit korrektem
        Format bestätigt: tatsächlich 86.500 eindeutige Namen) - der Rest wäre fälschlich als
        unbenannt behandelt worden. Auf UInt32 (4 Byte) umgestellt, Kantengröße dadurch 17→21
        Byte. Format-Version dafür zweimal hochgezählt (v2→v3→v4, v3 nie wirklich ausgeliefert,
        Release wieder gelöscht).
      - **`WayGraphRepository`**: liest die Namenstabelle, `Edge.nameIndex` (`UInt32`,
        `noNameIndex`-Sentinel für unbenannte Wege), `wayName(forIndex:)`.
      - **`BikeRoutingEngine`**: `buildSteps` gruppiert den A*-Pfad in Abschnitte mit gleichem
        Straßennamen, schätzt aus der Bearing-Differenz zwischen letzter Kante des vorherigen und
        erster Kante des neuen Abschnitts grob eine Richtung (< 20° = geradeaus, 20-120° =
        abbiegen, > 120° = scharf abbiegen) - Heuristik ohne die Kreuzungs-Logik echter
        Navigations-Engines, nicht gegen echte Kreuzungen kalibriert.
      - **Kopfzeile zeigt den *nächsten*, nicht den aktuellen Schritt**: `Step.instructions`
        beschreibt (wie bei `MKRoute.Step`) das Manöver am *Anfang* eines Schritts - beim
        Live-Test fiel auf, dass die Anzeige dadurch die schon erledigte Anweisung zeigte, während
        die Entfernung schon zur nächsten Abbiegung zählte. Behoben: `previewedStep` schaut einen
        Schritt voraus, `currentStepDistanceText` bleibt beim aktuellen Schritt (dessen Ende der
        Punkt ist, an dem das angekündigte Manöver passiert). Ergebnis z. B. "Links abbiegen auf
        Birkenstraße" / "In 70 m".
      - **Entfernungs-Rundung dreistufig** nach Live-Test-Feedback (10-m-Schritte über die ganze
        Strecke fühlten sich beim Radfahren zu unruhig an): ≥ 1000 m → 100-m-Schritte (als km
        angezeigt), 100-999 m → 50-m-Schritte, < 100 m → 10-m-Schritte.
      - **Pfeil-Icon** in der Kopfzeile zeigt jetzt die geschätzte Richtung (`arrow.up`/
        `arrow.turn.up.left`/`arrow.turn.up.right`) - nur bei Offline-Routen tatsächlich
        links/rechts, bei MKDirections (online) immer geradeaus, da Apple keine strukturierte
        Richtung liefert (nur fertigen Text).
      - **Alle 16 Bundesländer neu gebaut und als neues GitHub-Release hochgeladen** (Tag
        `way-graphs-v4`, `Scripts/rebuild_and_upload_v4.sh`). Größen ca. 20-27 % über den
        v2-Werten (Namenstabelle + 4-Byte-Index pro Kante): Bremen 9 MB, Saarland 38 MB,
        Hamburg 23 MB, Berlin 33 MB, Schleswig-Holstein 102 MB, Mecklenburg-Vorpommern 75 MB,
        Sachsen-Anhalt 132 MB, Thüringen 154 MB, Brandenburg 165 MB, Sachsen 200 MB,
        Rheinland-Pfalz 276 MB, Hessen 290 MB, Niedersachsen 326 MB, Nordrhein-Westfalen 543 MB,
        Baden-Württemberg 563 MB, Bayern 815 MB.
      - `gh` CLI lokal ohne Homebrew installiert (`~/.local/bin/gh`, Binary-Release von GitHub),
        war bereits über den System-Schlüsselbund authentifiziert (aus einer früheren Sitzung).
      - **Weiterhin offen**: Straßennamen/Abbiege-Hinweise nur für die Offline-Engine, nicht für
        kuratierte Radrouten aus `routes.sqlite` (s. Phase 3 unten) - andere Datenquelle, andere
        Einschränkung. Bearing-basierte Abbiege-Erkennung ist eine grobe Heuristik, noch nicht an
        echten Kreuzungen live kalibriert.
      → [Scripts/build_way_graph.py](FahrradApp/Scripts/build_way_graph.py), [Scripts/rebuild_and_upload_v4.sh](FahrradApp/Scripts/rebuild_and_upload_v4.sh), [WayGraphRepository.swift](FahrradApp/RadFaehrte/Services/WayGraphRepository.swift), [BikeRoutingEngine.swift](FahrradApp/RadFaehrte/Services/BikeRoutingEngine.swift) (`buildSteps`, `stepDetails`, `bearingDegrees`), [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift) (`formatVersion`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift) (`downloadURL`, `approximateSizeMB`), [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`previewedStep`, `navigationInstructionTitle`, `navigationInstructionIcon`, `currentStepDistanceText`)
- [x] **Bugfix: Abbiege-Anweisung blieb nach GPS-Ausfall (Tunnel) stehen**: Nutzer-Meldung mit
      Screenshot - nach einer Tunneldurchfahrt (GPS-Signal komplett verloren) zeigte die
      Navigations-Kopfzeile bei der "Direkten Fahrrad-Route" weiterhin die vor dem Tunnel
      angekündigte Abbiegung ("Links abbiegen auf Beim Handelsmuseum"), obwohl diese Straße
      längst hinter dem Nutzer lag - die Entfernungsanzeige wuchs dabei immer weiter, statt zu
      verschwinden. Ursache: `advanceDirectRouteStepIfNeeded` rückte `currentDirectRouteStepIndex`
      nur einzeln vor, ausgelöst durch einen reinen Radius-Check (< 30 m zum Ende des *aktuellen*
      Schritts). Setzte GPS nach dem Tunnel weiter vorn auf der Strecke wieder ein (mehrere
      Schritt-Enden übersprungen, nicht nur eins), lag der Nutzer nie wieder innerhalb der 30 m um
      das längst passierte erste Schritt-Ende - der Index blieb für den Rest der Fahrt hängen.
      Behoben durch einen Fortschritts-Vergleich als Fallback, wenn der Radius-Check fehlschlägt:
      Neue Hilfsfunktion `nearestSegmentIndex` findet das nächstgelegene Segment einer Koordinate
      auf der Routen-Geometrie; liegt der aktuelle Standort (per Segment-Index) weiter vorn auf der
      Strecke als das Ende eines oder mehrerer kommender Schritte, werden diese auf einen Schlag
      übersprungen statt nur einzeln. Dieser Fallback prüft zusätzlich `location.horizontalAccuracy
      < 30` (analog `accumulateTourDistance`), bevor er einen Sprung vornimmt - der erste Fix nach
      einer Funklücke ist oft ungenau, ein einzelner schlecht platzierter Fix soll den
      Fortschritts-Vergleich nicht fälschlich zu weit vorspringen lassen. Bewusst **nicht**
      zusätzlich per Zeit×Geschwindigkeit-Plausibilitätsgrenze abgesichert (mit Nutzer besprochen
      und verworfen) - würde eigenen Zustand (Zeitpunkt/Position des letzten guten Fixes)
      brauchen, sich mit dem Accuracy-Filter in der Aufgabe überschneiden und ein noch nicht
      beobachtetes Problem lösen (falsch platzierter, aber technisch "genauer" Fix); bei Bedarf
      später nachrüstbar, falls ein Live-Test das zeigt. Per Xcode-Build verifiziert (`xcodebuild
      build`), noch nicht auf einer echten Fahrt mit echtem Tunnel gegengetestet.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`advanceDirectRouteStepIfNeeded`, `nearestSegmentIndex`)
- [x] **Offline-Routing verließ gelegentlich einen vorhandenen Radweg unnötig / zeigte ihn auf der
      falschen Straßenseite an**: Nutzer-Meldung nach echten Fahrten in Bremen an drei Stellen -
      zwei unabhängige, nacheinander gefundene und behobene Ursachen:
      1. **Straßen-Abstecher statt auf dem Radweg zu bleiben** (Findorffstraße, Richtung "Beim
         Handelsmuseum") - Ursache per Overpass-API-Recherche konkret gefunden (`way/4755118`
         u. a.): Die Straße selbst ist mit `bicycle=use_sidepath` markiert ("Radfahrer sollen den
         danebenliegenden Weg benutzen, nicht die Fahrbahn"), das Skript kannte dieses Tag aber
         nicht und gewichtete die Straße normal. Der tatsächliche Weg daneben (`highway=path`,
         `bicycle=designated`, `segregated=yes`) wurde pauschal wie irgendein `path` gewichtet,
         nicht wie ein echter Radweg. Behoben: `bicycle=designated` auf `path`/`footway`/
         `pedestrian` wie `cycleway` gewichten (0,6 statt 0,9/1,2); `bicycle=use_sidepath` auf
         einer Straße mit ×2 bestrafen.
      2. **Linie auf der falschen (linken statt rechten) Straßenseite** (Findorffstraße,
         Crüsemannallee, Richtweg - alle drei gleich betroffen): Ein systematischer Links/Rechts-
         Vorzeichenfehler irgendwo in der Verarbeitungskette (genaue Stelle nicht abschließend
         geklärt - Python `offset_side()` oder Swift `offsetPoint()`). Per Live-Test an allen
         drei Stellen bestätigt behoben, indem die Rückgabewerte in `offset_side()` bewusst
         gegenüber der eigentlichen OSM-Tag-Bedeutung vertauscht wurden (`cycleway:right` ->
         `OFFSET_LEFT` statt `OFFSET_RIGHT` usw., s. Warnhinweis im Code).
      - Beide Fixes sind reine Datenänderungen (Gewichte/Versatz-Werte, keine Format-Byte-
        Layout-Änderung) - trotzdem wurde `WayGraphStore.formatVersion` beide Male hochgezählt
        (5, dann 6), rein damit bereits heruntergeladene Bundesländer automatisch neu geladen
        werden, da die App sonst nicht erkennen kann, dass sich nur Zahlenwerte geändert haben.
        Alle 16 Bundesländer beide Male neu gebaut und unter demselben Tag `way-graphs-v4`
        hochgeladen (`--clobber`).
      - **Offene, bewusst zurückgestellte Idee**: Falls trotz dieser Fixes künftig wieder ein
        Radweg unnötig verlassen wird, wäre der robustere (aber deutlich größere) nächste Schritt
        eine **Übergangs-Bestrafung direkt in der A*-Suche** (nicht nur in den Gewichtsdaten) -
        die Suche merkt sich, ob die zuletzt genutzte Kante "gute Rad-Infrastruktur" war, und
        berechnet einen Aufschlag, sobald sie verlassen wird (analog zur Trägheit beim Einrasten
        der roten Linie, `ContentView.snapToActiveRoute`). Bräuchte zusätzlich zu Python-
        Änderungen auch Swift-Code in `BikeRoutingEngine.search()` und nochmal eine
        Formatänderung - deshalb zurückgestellt, bis ein konkreter neuer Fall das nötig macht.
      → [Scripts/build_way_graph.py](FahrradApp/Scripts/build_way_graph.py) (`is_bikeable`,
      `weight_multiplier`, `offset_side`), [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift) (`formatVersion`)
- [x] **Zu kurze Routenabschnitte aus der Ergebnisliste gefiltert**: Nutzer-Beobachtung anhand
      eines Screenshots: Bei der Start+Ziel-Suche tauchten Treffer wie "Premiumroute D15" auf,
      bei denen nur ~1,3 km zwischen den nächstgelegenen Punkten zu Start und Ziel auf der Route
      lagen (plus ~1,9 km Anfahrt) - kein Datenqualitätsproblem (D15 ist eine echte, benannte
      `rcn`-Route, keine unbenannte `lcn`-Fragment-Route, die schon vorher gefiltert wird, s. o.
      "Unbenannte Radrouten..."), aber für die App-Idee ("bring mich möglichst direkt, aber auf
      einer beschilderten Route") nicht sinnvoll: Ein Umweg zu einer Route lohnt sich nicht, wenn
      man sie danach nur ein kurzes Stück nutzt. Nutzer-Entscheidung (gemeinsam hergeleitet):
      Schwellenwert 5 km für das tatsächlich genutzte Streckenstück. Da diese Länge erst
      asynchron per Dijkstra bekannt ist (`RouteMatcher.routeSegmentDistance`, s. o.), werden
      betroffene Treffer erst nachträglich aus `matches` entfernt, sobald für alle Treffer die
      Streckenlänge feststeht - inklusive Treffer ohne auffindbaren Pfad (Kartenlücke), da sich
      für die nicht prüfen lässt, ob der Abschnitt lang genug wäre. Zeigte die aktuelle Auswahl
      dabei gerade auf einen jetzt aussortierten Treffer, fällt sie automatisch zurück auf die
      "Direkte Fahrrad-Route". Gilt bewusst nur für die Start+Ziel-Suche, nicht für die ziellose
      "Radrouten in der Nähe"-Vorschau (`findNearby`), die kein Start→Ziel-Teilstück kennt. Vom
      Nutzer live auf dem iPhone getestet und für gut befunden.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`minimumRouteSegmentKm`,
      `filterAndReorderMatchesByPracticalDistance`)
- [x] **Bugfix: Datum im Verlauf zeigte englisches "at" statt "um"**: Die App-Oberfläche ist
      komplett hart auf Deutsch codiert (keine Lokalisierung/`.lproj`), `HistoryView` nutzte für
      die Datumsanzeige aber `.formatted(date:time:)` ohne explizite Locale - dadurch richtete
      sich das Format nach der Sprach-/Regionseinstellung des Geräts, nicht nach der (deutschen)
      App-Sprache. Behoben mit einem festen `Date.FormatStyle(locale: Locale(identifier: "de_DE"))`.
      Auf dem iPhone des Nutzers gebaut und verifiziert.
      → [HistoryView.swift](FahrradApp/RadFaehrte/Views/HistoryView.swift) (`dateFormat`)
- **Verworfener Versuch: Magnetometer-Bias-Korrektur fürs Navigations-Heading** (2026-07-25):
      Ausgangspunkt war eigentlich eine Beobachtung an Apples eigener Maps-App (nicht RadFährte!):
      Kartenausrichtung zeigte bei nur 1,5 km/h nach Nordwesten, obwohl das Rad geradeaus fuhr -
      vermutlich unzuverlässiger GPS-Kurs bei geringer Geschwindigkeit. Als vorsorgliche Maßnahme
      gegen einen *vermuteten* (nie direkt bestätigten) ähnlichen Effekt in RadFährte selbst wurde
      versuchsweise eine Korrektur eingebaut: `LocationManager` sollte einen dauerhaften
      Magnetometer-Versatz des CoreMotion-Headings gegen den GPS-Kurs (`CLLocation.course`)
      ausgleichen, nachgeführt bei ≥ 9 km/h und guter `courseAccuracy`. Live-Test des Nutzers beim
      Fahren zeigte aber eine **Verschlechterung**: Die Kartendrehung (Heading-up) blieb über
      weite Strecken der Fahrt bei einer ungefähr konstanten Nordost-Ausrichtung stehen, obwohl
      geradeaus/mit echten Kurven gefahren wurde - der eigene Richtungspfeil am blauen Punkt
      (`userLocationMarker`, s. u.) täuschte dabei fälschlich "alles in Ordnung" vor, weil seine
      Rotation rein rechnerisch relativ zur (angenommenen, nicht tatsächlich geprüften)
      Kamera-Ausrichtung berechnet wird - unabhängig davon, ob die Kamera sich in Wirklichkeit noch
      mitdreht. Naheliegende Ursache: GPS-Kurs war an der befahrenen Stelle (Kreuzungsbereich nahe
      einer Brücke/Auffahrtsrampen) vermutlich selbst durch Mehrwegeausbreitung ungenau, wodurch die
      Korrektur einen falschen Wert "eingefroren" hat, statt einen echten Versatz auszugleichen.
      Da zum Diagnostizieren (geplantes Live-Konsolen-Logging, s. "Technische Referenz") das iPhone
      gerade nicht per Kabel/entsperrt verfügbar war, wurde die Korrektur komplett zurückgebaut
      (`LocationManager` wieder auf reines, unverändertes `CMDeviceMotion.heading` gesetzt) statt
      ohne Messdaten weiter daran zu justieren. **Offen**: Falls das schiefe Verhalten erneut
      auftritt, zuerst per Live-Konsolen-Logging (roher Heading-Wert vs. `CLLocation.course` vs.
      `courseAccuracy` an der betroffenen Stelle) klären, ob GPS-Kurs dort überhaupt zuverlässig
      ist, bevor eine Korrektur erneut versucht wird.
      → [LocationManager.swift](FahrradApp/RadFaehrte/Services/LocationManager.swift)
- [x] **Sichtbarer blauer Standort-Punkt rastet jetzt ebenfalls auf die Route ein**: Setzt die
      "Offene Idee" von oben (bei der eingerasteten roten Strecke) um. Nutzer-Beobachtung per
      Screenshot 2026-07-25: Der blaue Punkt lag oft sichtbar neben der blauen Routen-Linie.
      MapKits `UserAnnotation()` lässt sich nicht einrasten (eigene, nicht konfigurierbare interne
      Standortabfrage) - deshalb ersetzt durch eine eigene `Annotation(coordinate:)` mit
      selbstgezeichnetem Punkt + Richtungspfeil (`userLocationMarker`), deren Position
      (`userLocationDisplayCoordinate`) während der Navigation aus `snappedUserLocationCoordinate`
      kommt. Nutzt dieselbe `snapToActiveRoute`-Projektion wie die rote Strecke, aber mit eigenem
      Schwellenwert und **Hysterese** statt eines einzelnen Grenzwerts: Einrasten ab < 10 m,
      Lösen erst wieder ab > 20 m (`userLocationSnapEngageThresholdKm`/`...ReleaseThresholdKm`) -
      verhindert Hin-und-Herspringen, wenn die GPS-Position genau um einen einzelnen Schwellenwert
      pendelt. Richtungspfeil nur bei Bewegung (> 1 km/h) mit bekanntem Heading sichtbar (analog
      MapKits Verhalten), Rotation berücksichtigt, ob die Karte bereits selbst mitdreht
      (Heading-up: Pfeil zeigt fix nach oben) oder nicht (Nord-up: volle Kompass-Rotation).
      Auf dem iPhone des Nutzers gebaut und installiert. **Live-verifiziert** (Nutzer-Feedback
      2026-07-26: "es klappt jetzt alles super"). Das sichtbare Text-Label "Standort" über dem
      Punkt wurde per `.annotationTitles(.hidden)` ausgeblendet (Titel-Parameter selbst bleibt für
      VoiceOver/Barrierefreiheit erhalten). Der anfangs mitgebaute Richtungspfeil (Heading-Kegel)
      wurde auf Nutzer-Wunsch wieder entfernt (kaum Zusatznutzen im Standard-Heading-up-Modus, wo
      er ohnehin fast immer nur nach oben zeigt) - nur noch schlichter Punkt.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`userLocationMarker`,
      `userLocationDisplayCoordinate`, `updateDisplayedUserLocation`, `snapToActiveRoute`)
- [x] **Bugfix: Rote "gefahrene Strecke"-Linie lag neben statt exakt hinter dem blauen Punkt**:
      Direkte Folge des vorherigen Punkts - blauer Punkt und rote Linie rasteten bis dahin
      **unabhängig voneinander** auf die Routen-Geometrie ein (unterschiedliche Schwellenwerte:
      `userLocationSnapEngageThresholdKm`/`...ReleaseThresholdKm` mit Hysterese für den Punkt,
      enger einzelner `routeSnapThresholdKm` für die Linie), konnten an Kreuzungen/Rampen mit
      mehreren nah beieinanderliegenden Segmenten dadurch auf unterschiedliche Segmente springen -
      genau beobachtet auf einem Nutzer-Screenshot an einer Autobahnrampen-Kreuzung (Bremen,
      Stephanibrücke-Zufahrt). Behoben, indem `displayedTourTrackPoints` für den Linien-Endpunkt
      jetzt dieselbe Koordinate wie der blaue Punkt (`userLocationDisplayCoordinate`) übernimmt,
      statt selbst nochmal `snapToActiveRoute` aufzurufen - beide zeigen dadurch immer exakt
      dieselbe Stelle. Auf dem iPhone des Nutzers gebaut und installiert, **Live-Verifikation an
      der beobachteten Stelle noch ausstehend**.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`displayedTourTrackPoints`)
- [x] **Einstellbare Sichtweite in der 2D-Navigationsansicht**: Nutzer-Beobachtung: Eine
      bevorstehende Richtungsänderung (z. B. Linksabbiegen) wird auf der Karte erst sichtbar, wenn
      sie unter ~100 m entfernt ist - manche Nutzer möchten sie lieber schon früher sehen. Neue
      Einstellung "Sichtweite beim Navigieren" (50-200 m, 10-m-Schritte, Stepper analog
      Durchschnittsgeschwindigkeit) steuert jetzt die `distance` der Navigations-Kamera, **nur in
      der 2D-Ansicht** (Nutzer-Entscheidung) - im 3D-Modus bleibt die bisherige feste Distanz 300,
      da der gekippte Blickwinkel (`pitch: 60`) den Zusammenhang zwischen `distance` und
      tatsächlich sichtbaren Metern anders verzerrt und dafür eine eigene Kalibrierung bräuchte.
      Default 80 m ist bewusst so gewählt, dass er exakt der bisherigen festen Distanz 300
      entspricht - für Nutzer, die den Regler nie anfassen, ändert sich also nichts.
      - Auf dem iPhone des Nutzers gebaut, installiert und getestet - der Unterschied zwischen
        niedrigen und hohen Werten des Reglers fühlt sich richtig an. Der Skalierungsfaktor
        (`lookaheadMetersToDistanceScale = 300 / 80 = 3.75`, aus der Nutzer-Beobachtung "<100 m
        sichtbar bei aktuell fest 300" zurückgerechnet statt aus MapKit-Dokumentation) bleibt eine
        Schätzung, ist aber live bestätigt "gut" - keine weitere Kalibrierung angefragt.
      → [AppSettings.swift](FahrradApp/RadFaehrte/Models/AppSettings.swift),
      [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`navigationCameraDistance`,
      `updateNavigationCamera`), [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **Konfigurierbare Statistik-Leiste in der Navigations-Kopfzeile**: Bisher fest verdrahtet auf
      genau drei Werte (Aktuell/Strecke/Ziel). Nutzer-Wunsch: 3 oder 6 Felder wählbar, jedes davon
      frei aus einem Katalog belegbar. Neuer Katalog `NavigationStatKind` (aktuelles Tempo,
      zurückgelegte Strecke, Entfernung zum Ziel, Ankunftszeit auf Basis der eingestellten
      Ø-Geschwindigkeit, Ankunftszeit auf Basis des bisherigen Ø-Tempos der Fahrt,
      Durchschnittsgeschwindigkeit seit Start, Fahrtzeit seit Start, Höhenmeter bergauf seit
      Start) - die beiden Ankunftszeit-Varianten lösen die ursprünglich offene Frage "eingestellte
      oder tatsächliche Geschwindigkeit als Basis?" auf, indem beide als getrennt wählbare Felder
      angeboten werden statt sich für eine Basis zu entscheiden. Persistierung: 6 Slots werden
      immer gespeichert (`navigationStatSlots`, kommagetrennte Rohwerte), unabhängig von der
      eingestellten Feld-Anzahl (`navigationStatFieldCount`, 3 oder 6) - so geht beim Umschalten
      zwischen 3 und 6 keine bereits getroffene Auswahl verloren. In den Einstellungen unter
      "Anzeige während der Navigation": Segmented Control für die Anzahl, darunter je ein Picker
      pro Feld über den vollen Katalog.
      - **Höhenmeter neu erfasst**: Bisher wurde nur horizontale Distanz aufsummiert
        (`tourDistanceMeters`); `tourElevationGainMeters`/`tourElevationLossMeters` summieren jetzt
        zusätzlich positive bzw. negative `CLLocation.altitude`-Differenzen zwischen
        aufeinanderfolgenden Tour-Punkten (nur bei gültiger `verticalAccuracy` auf beiden Seiten).
        Naive Punkt-zu-Punkt-Summe wie bei der Distanz - ohne Barometer entsprechend
        GPS-rauschanfällig, für eine grobe Anzeige aber als erster Wurf akzeptiert; noch nicht
        gegen echte Höhenmeter (z. B. Komoot/Strava derselben Fahrt) verifiziert.
      - **Katalog um fünf weitere Werte erweitert** (Nutzer-Wunsch nach einem Vergleich mit
        Garmin/Wahoo/Komoot/Strava): maximale Geschwindigkeit (`tourMaxSpeedKmh`, einfaches Maximum
        über alle gültigen Speed-Readings), Höhenmeter bergab (s. o.), aktuelle Höhe
        (`currentAltitudeMeters`, direkt aus `CLLocation.altitude`), Restzeit bis Ziel (Dauer statt
        Uhrzeit, in derselben eingestellt/gefahren-Aufteilung wie die Ankunftszeit -
        `remainingHours` als gemeinsame Grundlage für beide), sowie reine Fahrzeit ohne Stopps
        ("Moving Time", `tourMovingSeconds`). Für Moving Time war ein einfacher "Zeit seit letztem
        *verarbeiteten* Update"-Ansatz falsch: Ein `lastTourLocation`, das während einer Pause
        unverändert bleibt (bestehendes Verhalten, s. o. Stillstandsfilter), hätte die Pausenzeit
        beim nächsten Loslegen fälschlich als Bewegung mitgezählt. Stattdessen aktualisiert
        `accumulateTourDistance` einen eigenen Zeitstempel (`lastMovingUpdateTimestamp`) bei
        *jedem* Update unabhängig vom Bewegungszustand und zählt nur das Intervall selbst, wenn es
        gerade als Bewegung gilt (Cap bei 10 s gegen große Lücken, z. B. App im Hintergrund).
      - **Konfiguration in eigene Unterseite ausgelagert**: Die Feld-Anzahl + bis zu 6 Picker direkt
        inline im Haupt-Einstellungen-Screen hätten dort bei 6 Feldern bis zu 7 Zeilen belegt -
        Nutzer-Nachfrage, ob der Screen dadurch unübersichtlich wird. Analog zu "Offline-Karten"
        jetzt eigene `NavigationStatSettingsView`, im Hauptscreen nur noch ein einzelner
        `NavigationLink`-Eintrag "Statistik-Leiste".
      - Build lokal erfolgreich (`xcodebuild ... build`), auf dem iPhone des Nutzers installiert und
        gestartet - **inhaltliche Live-Verifikation der neuen Werte (v. a. Höhenmeter-Plausibilität,
        Moving-Time-Verhalten bei echten Stopps) noch ausstehend**.
      → [NavigationStat.swift](FahrradApp/RadFaehrte/Models/NavigationStat.swift),
      [AppSettings.swift](FahrradApp/RadFaehrte/Models/AppSettings.swift) (`navigationStatFieldCount`,
      `navigationStatSlots`), [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift)
      (`navigationStatsRow`, `navigationStatKinds`, `statDisplay`, `currentAverageSpeedKmh`,
      `durationDisplay`, `remainingHours`, `arrivalTimeText`, `remainingTimeDisplay`,
      `accumulateTourDistance`, `tourElevationGainMeters`, `tourElevationLossMeters`,
      `tourMaxSpeedKmh`, `tourMovingSeconds`),
      [NavigationStatSettingsView.swift](FahrradApp/RadFaehrte/Views/NavigationStatSettingsView.swift),
      [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **Anweisungs-Banner während der Navigation ein-/ausblendbar, Karte dann bildschirmfüllend**:
      Nutzer-Wunsch war zunächst, dass Banner + Statistik-Leiste die Karte generell nicht mehr nach
      unten verdrängen (Overlay-Ansatz), dann per eigenem Button umschaltbar - nach weiterem
      Nutzer-Feedback ("ein Button weniger auf der Karte") schließlich durch eine Wisch-Geste
      ersetzt: Nach oben über den Banner wischen (`DragGesture(minimumDistance: 20)`,
      `translation.height < -30`) blendet ihn aus, ein schmaler Griff (`navigationBannerHandle`,
      44×20pt Capsule mit Chevron-Symbol, kein "richtiger" Button) erscheint dafür oben auf der
      Karte - Tippen oder Wischen nach unten darauf (`translation.height > 20`) holt den Banner
      zurück (Tap zusätzlich zur Geste, da das schmale Ziel per Wisch weniger zuverlässig zu treffen
      ist). Neuer State `isNavigationBannerVisible` (setzt bei jedem `startNavigating()` wieder auf
      `true`). Bei sichtbarem Banner steht `navigationHeaderSection` wie ursprünglich als eigenes
      Element vor der Karte im `VStack` (drückt sie nach unten), Beenden-Button/Kompass/2D3D/
      Heading-up bleiben unabhängige `.overlay(alignment: .topLeading/.topTrailing)`-Direktkinder
      der Karte. Ist der Banner ausgeblendet (`mapFillsFullScreen = isNavigating &&
      !isNavigationBannerVisible`), entfallen Rand und abgerundete Ecken um die Karte. Ein-/
      Ausblenden animiert (`withAnimation(.easeInOut(duration: 0.25))`, `.transition(.move(edge:
      .top).combined(with: .opacity))` am Banner) statt abrupt zu erscheinen/verschwinden.
      Build lokal erfolgreich - **Live-Verifikation der Wisch-Geste auf dem iPhone (Treffergenauigkeit
      des schmalen Griffs, Zuverlässigkeit der Schwellenwerte) noch ausstehend**.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`body`, `navigationHeaderSection`,
      `navigationBannerHandle`, `mapFillsFullScreen`, `isNavigationBannerVisible`),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **Verlauf-Liste optisch überarbeitet (Routenform-Vorschau + Icon-Stats + Monatsgruppierung)**:
      Nutzer-Wunsch nach einer weniger "langweiligen" Darstellung. Vorab per `mcp__visualize`-Mockup
      abgestimmt (erst reine Vektor-Routenform, dann auf Nutzerwunsch mit echtem Kartenhintergrund
      erweitert), dann umgesetzt:
      - **`TourMapSnapshotCache`** (neuer Service): erzeugt per `MKMapSnapshotter` ein kleines
        96×96pt-Kartenbild pro Tour (Kartenausschnitt über `DrivenTour.region(padding:)`, neu als
        Extension aus der bisherigen `HistoryView`-eigenen `regionToFit`-Logik herausgezogen, damit
        Detailkarte und Vorschaubild dieselbe Berechnung nutzen), zeichnet die Route mit weißem Rand
        + blauer Linie sowie Start-/Endpunkt-Markern darüber (`UIGraphicsImageRenderer`) und cached
        das Ergebnis als PNG unter `Documents/DrivenTours/Snapshots/<Touren-ID>.png` - ohne Cache
        würde jedes Scrollen der Liste erneut ein Snapshot-Rendering auslösen. Wird beim Löschen
        einer Tour mitgelöscht.
      - **`HistoryView`**: jede Zeile zeigt jetzt links das gecachte Kartenbild (`TourThumbnailView`,
        lädt asynchron per `.task(id:)`), rechts Datum + eine Icon-Zeile (Lineal/Uhr/Tacho) statt der
        bisherigen reinen Fließtext-Zeile. Liste ist zusätzlich nach Monat gruppiert
        (`monthGroups`/`MonthGroup`, Section-Header zeigt Monat + Gesamtkilometer), Löschen bleibt
        Swipe-to-delete, jetzt über die Touren-IDs statt über einen einzelnen globalen Index gemappt
        (nötig, weil `onDelete`-Offsets sich durch die Sections nur noch auf die jeweilige
        Monatsgruppe beziehen).
      - Build lokal erfolgreich, auf dem iPhone des Nutzers installiert und gestartet -
        **inhaltliche Live-Verifikation der neuen Verlauf-Darstellung (Kartenbilder, Gruppierung)
        noch ausstehend**.
      → [TourMapSnapshotCache.swift](FahrradApp/RadFaehrte/Services/TourMapSnapshotCache.swift),
      [HistoryView.swift](FahrradApp/RadFaehrte/Views/HistoryView.swift),
      [DrivenTour.swift](FahrradApp/RadFaehrte/Models/DrivenTour.swift) (`region`)
- [x] **Xcode-Build-Warnungen vor dem ersten App-Store-Connect-Upload behoben** (10 Issues im
      Issue Navigator + 1 weitere nur im Build-Log sichtbare Warnung, alle per `xcodebuild clean
      build` einzeln verifiziert):
      - **Swift-6-Concurrency in `WayGraphDownloadManager.download`**: Zwei "captured var in
        concurrently-executing code"-Warnungen. Der lokale `var errorMessage` im
        Download-Completion-Handler wird jetzt vor dem Sprung in den `Task { @MainActor ... }`
        als `let resolvedErrorMessage` eingefroren; im `progress`-Observer wird `taskProgress.
        fractionCompleted` vorher in ein `let fraction` gelesen und `self` im verschachtelten
        `Task { @MainActor ... }` erneut explizit `[weak self]` erfasst statt implizit über den
        äußeren `[weak self]`-Closure-Parameter.
      - **Main-Actor-Isolationsfehler in `ContentView.offlineDirectRoutes`**: Der `Task.detached`-
        Block rief `WayGraphRepository(path:)` sowie (als `.map`-Closure) `DirectRoute.init
        (offlineResult:)` auf - beide implizit `@MainActor`-isoliert durch die Projekteinstellung
        `-default-isolation=MainActor`, aber ein `Task.detached`-Block läuft außerhalb jedes
        Actors. `WayGraphRepository` und `BikeRoutingEngine` (reine Berechnungsklassen ohne
        UI-Zustand, analog dem früheren `WayGraphStore`-Fix, s. o.) sowie die interne
        `AStarQueue` sind jetzt `nonisolated`; das `DirectRoute.init(offlineResult:)`-Mapping
        passiert jetzt nach dem `await` außerhalb des detached Blocks (auf dem Aufrufer-Actor).
      - **`placemark`/`MKPlacemark`-Deprecations (iOS 26)**: In `LocationSearchViewModel.resolve`
        und `ContentView.directions` durch `MKMapItem.location`/`init(location:address:)` ersetzt
        (neue MapKit-API, verfügbar da Deployment-Target bereits iOS 26).
      - **Fehlender `LSSupportsOpeningDocumentsInPlace`-Info.plist-Key**: Ergänzt in
        `Supplemental-Info.plist` mit `false` (die App kopiert geteilte/importierte GPX-Dateien
        in den eigenen Sandbox-Speicher statt sie am Originalort zu bearbeiten, `true` wäre
        also fachlich falsch gewesen).
      - Nach jedem Fix per `xcodebuild clean build` erneut geprüft; abschließend zusätzlich
        `RadFaehrteTests` durchlaufen lassen (alle bestanden, ein Offline-Routing-Test wegen
        fehlendem heruntergeladenen Wege-Graphen im Testsystem übersprungen - unabhängig von
        diesen Fixes).
      → [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift)
      (`download`), [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift)
      (`offlineDirectRoutes`, `directions`), [WayGraphRepository.swift](FahrradApp/RadFaehrte/Services/WayGraphRepository.swift),
      [BikeRoutingEngine.swift](FahrradApp/RadFaehrte/Services/BikeRoutingEngine.swift) (`AStarQueue`),
      [LocationSearchViewModel.swift](FahrradApp/RadFaehrte/ViewModels/LocationSearchViewModel.swift)
      (`resolve`), [Supplemental-Info.plist](FahrradApp/RadFaehrte/Supplemental-Info.plist)
- [x] **Erster Upload zu App Store Connect (Version 1.0 (1)), 2026-07-26**: Product → Archive →
      Distribute App → App Store Connect → Upload, erfolgreich ("Uploaded to Apple" im Organizer).
      App Store Connect-Eintrag für `com.frankenfeld.RadFaehrte` wurde dabei von Xcode automatisch
      angelegt (Name korrigiert auf "RadFährte" mit ä, Xcode hatte "RadFaehrte" ohne Umlaut
      vorgeschlagen). Signing ist "Automatic" mit vorhandenem `DEVELOPMENT_TEAM`.
      - **Stolperstein unterwegs**: Erster Upload-Versuch schlug mit "Invalid Signature ... not
        properly signed ... distribution certificate" (Fehlercode 90035) fehl. Ursache: In Xcode
        → Settings → Accounts → Manage Certificates existierten zwar zwei ältere "Apple
        Distribution"-Zertifikate, aber deren private Schlüssel lagen nicht im lokalen
        Schlüsselbund ("Not in Keychain" - vermutlich von einem anderen Mac/einer alten
        Installation). Behoben durch ein neu auf diesem Mac erzeugtes Apple-Distribution-
        Zertifikat (über das "+" im Manage-Certificates-Fenster), danach lief der Upload durch.
      - **Export-Compliance-Frage** (Build zeigte zunächst "Fehlende Compliance" im TestFlight-
        Tab): "Welche Art von Verschlüsselungsalgorithmus verwendest du?" mit "Keinen der oben
        genannten Algorithmen" beantwortet - die App nutzt nur Standard-HTTPS über `URLSession`/
        `MapKit`, keinen eigenen Verschlüsselungscode.
      - **Tester hinzugefügt**: Zwei externe Tester (nicht Teil des Entwickler-Accounts) direkt
        auf Build 1 eingetragen (E-Mail-Adressen, nicht als "Interne Tests"-Gruppe). Da beide
        außerhalb des Dev-Accounts sind, zählt das automatisch als **externer Test** - Build-
        Status wechselte von "Keine Builds verfügbar" (Zwischenstand direkt nach Hinzufügen) zu
        **"Warten auf Prüfung"**, Apples Beta App Review läuft (Stand 2026-07-26, noch kein
        Ergebnis). Für künftige schnelle Solo-Tests ohne Review-Wartezeit stattdessen "Interne
        Tests" nutzen (eigener Entwickler-Account, sofort verfügbar).
      - **Testinformationen** (allgemeine Beta-App-Beschreibung, nicht die build-spezifische
        Notiz) ausgefüllt: Feedback-E-Mail `frankenfeld@icloud.com`, Kontaktperson Jörn
        Frankenfeld, "Anmeldung erforderlich" deaktiviert (App hat kein Login/Benutzerkonto, nur
        Standort-Berechtigung).
      - **Nächste Schritte (noch nicht gemacht)**: Ergebnis der Beta App Review abwarten (bei
        externen Testern einmalig nötig, meist wenige Stunden bis 1-2 Tage), dann sollten die
        beiden Tester automatisch die Einladungsmail bekommen.

- [x] **Kuratierte Radrouten-Datenbank auf die Niederlande erweitert (netherlands.sqlite)**:
      Anlass: Nutzer fährt am 2026-07-27 nach Rotterdam und wollte das gleich live testen. Die
      ursprüngliche Deutschland-Pipeline (`extract_routes.py`/`build_sqlite.py`/
      `simplify_routes.py`) war nicht mehr vorhanden (s. o.) - stattdessen neues, wiederverwendbares
      Skript [Scripts/extract_bicycle_routes.py](FahrradApp/Scripts/extract_bicycle_routes.py)
      geschrieben, das denselben Ablauf in einer Datei abdeckt: Pass 1 sammelt alle
      `type=route`/`superroute`-Relationen mit `route=bicycle` (inkl. rekursiver Auflösung von
      Sub-Relationen bei Superrouten), Pass 2 löst die referenzierten Way-Geometrien auf
      (`FileProcessor(...).with_locations()`), Douglas-Peucker-Vereinfachung via
      `shapely.simplify()` (Toleranz 0.0001°, wie beim Deutschland-Datensatz), binär gepackt ins
      identische Schema wie `routes.sqlite`. Eingabe: `netherlands-latest.osm.pbf` von Geofabrik
      (~1,3 GB). Ergebnis: **17.521 Routen, 9,4 MB** (u. a. alle LF-Routen, EuroVelo 2/12/15/19,
      Provinz-`rcn`/lcn`-Netze) - deutlich kompakter als der Deutschland-Datensatz, u. a. weil
      Fläche/Streckendichte kleiner sind.
      - **Architektur-Entscheidung**: Bewusst als eigene, zusätzliche Bundle-Ressource
        (`netherlands.sqlite`) statt Merge in die bestehende `routes.sqlite` - vermeidet jedes
        Risiko für die per Hand kuratierte 64-MB-Deutschland-Datenbank, deren Original-Pipeline ja
        nicht mehr reproduzierbar ist. `RouteRepository` lädt jetzt eine Liste bekannter
        Bundle-Ressourcennamen (aktuell `["routes", "netherlands"]`), öffnet jede vorhandene Datei
        separat und führt die Bounding-Box-Treffer aller geöffneten Datenbanken zusammen -
        `routes.sqlite` bleibt Pflicht (Assertion bei Fehlen), weitere Länder sind optional. OSM-
        Relations-IDs sind planetweit eindeutig, daher keine Kollisionsgefahr zwischen den
        Datenbanken. Für ein weiteres Land reicht damit: Extrakt laden, Skript laufen lassen,
        Ergebnis nach `Resources/<land>.sqlite` kopieren, Namen in
        `RouteRepository.bundledResourceNames` ergänzen.
        → [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift)
      - **Verifiziert**: `xcodebuild build` (Device-Ziel) erfolgreich, beide `.sqlite`-Dateien
        landen im App-Bundle. Neuer Unit-Test `routeRepositoryFindsEuroVeloRouteNearRotterdam`
        (Bounding Box um Rotterdam, erwartet EuroVelo 15) grün, bestehender Bremen-Test weiterhin
        grün (Merge verändert die Deutschland-Ergebnisse nicht).
        → [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift)
      - ⚠️ **Noch nicht live getestet**: Der Nutzer testet das erst beim Rotterdam-Trip
        (2026-07-27). "Direkte Fahrrad-Route" nutzt außerhalb heruntergeladener Bundesländer/Länder
        ohnehin automatisch Online-`MKDirections` (funktioniert unabhängig vom Land, war schon vor
        dieser Änderung so) - die neue kuratierte Radrouten-Suche/-Anzeige sowie das direkt im
        Anschluss ergänzte Offline-Routing für die Niederlande (s. u.) sind das eigentlich Neue,
        das vor Ort verifiziert werden muss.
      - **Rohdaten nicht versioniert**: `netherlands-latest.osm.pbf` liegt in `Scripts/data/`
        (per `.gitignore` ausgeschlossen, wie bei den Bundesland-Extrakten), nur das fertige
        `netherlands.sqlite` in `Resources/` ist Teil des Bundles/Repos.
- [x] **Offline-Routing ("ruhige Wege") auf die Niederlande erweitert + Einstellungen in
      "Offline-Karten Deutschland"/"Offline-Karten Europa" aufgeteilt**: Direkte Folge der
      kuratierten-Routen-Erweiterung (s. o.) - Nutzer wollte die Niederlande "so wie die einzelnen
      Bundesländer" herunterladbar haben, nicht nur die kuratierte Routen-Suche. Bisher war die
      gesamte Offline-Routing-Architektur (`WayGraphStore`, `WayGraphDownloadManager`,
      `OfflineMapsView`) fest auf den Typ `Bundesland` zugeschnitten.
      - **Generalisiert auf ein `DownloadableRegion`-Protokoll** (`rawValue`, `displayName`,
        `downloadURL`, `approximateSizeMB`): `WayGraphStore<Region>` und
        `WayGraphDownloadManager<Region>` sind jetzt generisch, `Bundesland` (Deutschland) und neu
        `EuropaLand` (bisher nur `.niederlande`) konformen beide dazu. `OfflineMapsView<Region>`
        ist ebenfalls generisch (Titel/Footer als Parameter), damit dieselbe Lade-/Download-Liste
        für beide Regionstypen wiederverwendet wird statt zweier Fast-Duplikate.
        → [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift),
        [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
        [OfflineMapsView.swift](FahrradApp/RadFaehrte/Views/OfflineMapsView.swift)
      - **Einstellungen zeigen jetzt zwei getrennte Einträge** ("Offline-Karten Deutschland" mit
        den bisherigen 16 Bundesländern, "Offline-Karten Europa" mit bisher nur den Niederlanden)
        statt einer einzigen Liste - `SettingsView`/`RootTabView`/`ContentView` halten dafür je
        eine `WayGraphStore<Bundesland>`- und eine `WayGraphStore<EuropaLand>`-Instanz (analog
        zueinander, eine gemeinsame App-weite Instanz pro Typ wie zuvor bei `Bundesland` allein).
        → [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift),
        [RootTabView.swift](FahrradApp/RadFaehrte/RootTabView.swift)
      - **Nebenbei behobene Lücke**: `ContentView` probierte für die Offline-Engine bisher nur das
        *erste* gefundene heruntergeladene Bundesland (`Bundesland.allCases.compactMap{...}.first`)
        und fiel bei einer nicht abgedeckten Region sofort auf Online-Routing zurück, statt weitere
        heruntergeladene Regionen zu versuchen (bereits als "Bekannte Lücke" dokumentiert gewesen,
        s. Historie). Mit einer zweiten Region (Niederlande) wäre das sofort aufgefallen - z. B.
        hätte ein zusätzlich heruntergeladenes deutsches Bundesland die Niederlande-Offline-Engine
        in Rotterdam nie benutzt, obwohl vorhanden. Neue Methode
        `offlineGraphCandidatePaths()` sammelt die Pfade aller heruntergeladenen Regionen
        (Bundesländer + Länder), `loadDirectRoute`/`rerouteDirectRoute` probieren sie jetzt der
        Reihe nach durch, bis eine tatsächlich Ergebnisse liefert (eine nicht abgedeckte Region
        liefert ohnehin ein leeres Ergebnis, wird also einfach übersprungen) - funktioniert
        weiterhin unabhängig von der Downloadreihenfolge/Anzahl heruntergeladener Regionen.
        → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`offlineGraphCandidatePaths`,
        `loadDirectRoute`, `rerouteDirectRoute`)
      - **Niederlande-Wege-Graph gebaut und veröffentlicht**: `Scripts/build_way_graph.py`
        unverändert auf `netherlands-latest.osm.pbf` angewendet (Skript war bereits
        länder-/regionsunabhängig, nur bisher nur für Bundesländer genutzt) - **466 MB**,
        9.600.034 Knoten, 19.479.994 Kanten, 149.845 eindeutige Straßennamen (Baubefehl brauchte
        ca. 13 Minuten und zeitweise >6 GB RAM - deutlich mehr als die kuratierte Routen-Extraktion,
        da hier *alle* fahrradtauglichen Wege des ganzen Landes verarbeitet werden, nicht nur die
        Radfernweg-Relationen). Als Release-Asset hochgeladen unter einem **neuen, eigenen Tag**
        `way-graphs-eu-v1` (statt `way-graphs-v4` der Bundesländer) - Format ist identisch
        (dieselbe `wayGraphFormatVersion`), aber unabhängig von den Bundesland-Assets versioniert/
        gepflegt. Downloadgröße `EuropaLand.niederlande.approximateSizeMB` (466) ist die tatsächlich
        gemessene Größe, nicht geschätzt.
        → [Scripts/build_way_graph.py](FahrradApp/Scripts/build_way_graph.py) (unverändert),
        [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
      - **Verifiziert**: `xcodebuild build` (Device-Ziel) erfolgreich, App auf dem iPhone des
        Nutzers installiert/gestartet, Download-URL des neuen Release-Assets per `curl -I`
        gegengeprüft (200, korrekte Content-Length). Vollständige Test-Suite lief zusätzlich im
        Simulator durch (nur zur Code-Verifikation, nicht als Feature-Test, s. `CLAUDE.md`) - alle
        `RadFaehrteTests` grün; drei `RadFaehrteUITests`
        (`testImportedRouteAppearsInHistoryAndCanBeStarted`,
        `testNavigationModeShowsAlertWhenLocationDenied`, `testUseCurrentLocationAsStart`) schlugen
        fehl, betreffen aber Standort-Berechtigung/GPX-Import - unabhängige Bereiche, die durch
        diese Änderung nicht berührt wurden, vermutlich Simulator-Flakiness bei parallel
        laufenden Testklonen (nicht weiter verfolgt, s. u. ggf. bei Gelegenheit prüfen).
      - ⚠️ **Bug gefunden und behoben (2026-07-26, noch am selben Tag)**: `EuropaLand.niederlande`
        hatte (anders als bei `Bundesland`, wo die deutschen Fallnamen zufällig mit den
        Geofabrik-Bezeichnern übereinstimmen) einen deutschen Fallnamen ("niederlande"), während
        das hochgeladene Release-Asset auf den englischen Geofabrik-Namen hört
        (`netherlands_ways.sqlite`) - `downloadURL` baute daraus also eine falsche, nicht
        existierende URL (`niederlande_ways.sqlite`, 404). Erst beim echten Download-Versuch auf
        dem Gerät aufgefallen. Behoben, indem die Fallnamen auf Englisch umgestellt wurden
        (`case netherlands`, `case poland`, s. u.) - `displayName` liefert weiterhin die deutschen
        UI-Bezeichnungen ("Niederlande"/"Polen"). Lehre: Bei einem neuen `DownloadableRegion`-Typ
        immer prüfen, ob der Swift-Fallname zufällig mit dem Namensschema übereinstimmt, das für
        Download-URL/Asset-Dateinamen verwendet wird - nicht einfach vom `Bundesland`-Muster
        annehmen, dass es automatisch passt.
      - **Danach live getestet**: Download der Niederlande (466 MB) über echtes Heim-WLAN
        durchgelaufen (lief anfangs langsam an, beschleunigte sich dann - kein tatsächliches
        Hängenbleiben). Dabei auffällig: Es gab **keine Möglichkeit, einen laufenden Download
        abzubrechen** (die Lösch-/Herunterladen-Buttons werden nur angezeigt, solange kein Download
        läuft) - bei einem wirklich hängenden Download wäre nur ein Force-Quit der ganzen App ein
        Ausweg gewesen. Behoben: `WayGraphDownloadManager` hält jetzt eine Referenz auf den
        laufenden `URLSessionDownloadTask` und bekommt eine `cancel(_:)`-Methode (ignoriert im
        Completion-Handler gezielt den "abgebrochen"-Fehler, damit kein Fehler-Alert für eine vom
        Nutzer selbst gewollte Aktion erscheint); `OfflineMapsView` zeigt während eines laufenden
        Downloads jetzt einen "Abbrechen"-Button statt der Lösch-/Herunterladen-Buttons.
        → [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift)
        (`cancel`, `tasks`), [OfflineMapsView.swift](FahrradApp/RadFaehrte/Views/OfflineMapsView.swift)
- [x] **Polen als drittes Land ergänzt** (kuratierte Radrouten + Offline-Wege-Graph, analog
      Niederlande direkt im Anschluss auf Nutzerwunsch): Gleicher Ablauf wie bei den Niederlanden,
      diesmal mit `poland-latest.osm.pbf` von Geofabrik (~1,9 GB, deutlich größer als der
      Niederlande-Extrakt).
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **3.187
        Routen** (u. a. EuroVelo 4, Green Velo/Wschodni Szlak Rowerowy, Wiślana Trasa Rowerowa),
        **8,2 MB** als `Resources/poland.sqlite` gebündelt, `"poland"` in
        `RouteRepository.bundledResourceNames` ergänzt. Deutlich weniger Routen als bei den
        Niederlanden trotz ~7x größerer Fläche - Polens Radfernwege sind in OSM einfach nicht so
        dicht kartiert wie die niederländische Fahrradinfrastruktur. Getestet per neuem Unit-Test
        `routeRepositoryFindsEuroVeloRouteNearKrakow` (analog zum Rotterdam-Test).
      - **Offline-Wege-Graph**: `build_way_graph.py` unverändert angewendet - **1,5 GB**
        (1.610.043.392 Byte genau), 31.458.044 Knoten, 64.562.904 Kanten, 52.595 eindeutige
        Straßennamen. Baubefehl brauchte **~42 Minuten** und zeitweise ~2,6 GB RAM (weniger als
        beim Niederlande-Build befürchtet, trotz insgesamt mehr Knoten/Kanten - vermutlich weil die
        Spitzenlast beim Sammeln der Rohdaten in Python-Objekten liegt, nicht linear mit der
        Endgröße skaliert). Als weiteres Release-Asset zum bestehenden Tag `way-graphs-eu-v1`
        hochgeladen (`poland_ways.sqlite`, nicht wieder ein neuer Tag - Format identisch).
        `EuropaLand.poland.approximateSizeMB` auf den tatsächlich gemessenen Wert (1535) gesetzt.
        → [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, App mehrfach auf dem iPhone des Nutzers
        installiert/gestartet (dabei einmal `devicectl`-Fehler "device disconnected"/"locked" -
        Gerät war gesperrt, nach Entsperren lief Install+Start durch), neuer Unit-Test grün. Vom
        Nutzer noch nicht live in Polen getestet (kein konkreter Reiseanlass wie bei den
        Niederlanden, einfach auf Zuruf ergänzt).
      → [Scripts/extract_bicycle_routes.py](FahrradApp/Scripts/extract_bicycle_routes.py),
      [Scripts/build_way_graph.py](FahrradApp/Scripts/build_way_graph.py) (beide unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift) (`EuropaLand.poland`),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift)
- [x] **Bugfix: Offline-Routing-Engine wurde bei großen Ländern (Niederlande) von iOS
      wegen Speicherüberlastung gekillt (Live-Test Rotterdam, 2026-07-26)**: Nutzer-Meldung "die
      App stürzt ab" beim Berechnen der "Direkten Fahrrad-Route" (Rotterdam Centraal → citizenM)
      mit heruntergeladenem Niederlande-Wege-Graphen. Drei Funde nacheinander:
      1. **Erster Verdacht (behoben, aber nicht die Hauptursache)**: `BikeRoutingEngine.search`
         hatte keine Obergrenze für besuchte Knoten - eine erfolglose Suche hätte im Extremfall
         fast den ganzen Graphen durchlaufen können. Behoben mit `maxVisitedNodes = 300_000`
         (Suche bricht ab und liefert `nil`, `loadDirectRoute` fällt dann auf Online-Routing
         zurück). Zusätzlich `WayGraphRepository.nearestNode` von `CLLocation.distance(from:)`
         (ein neues Objekt + volle geodätische Berechnung pro der bis zu 31 Mio. Knoten) auf eine
         lokale ebene Näherung mit quadrierten Distanzen umgestellt (kein `sqrt`, keine
         Objekt-Allokation pro Knoten) - analog zum bereits vorhandenen Muster in
         `RouteMatcher.nearestPoint`.
      2. **Tatsächliche Ursache gefunden**: Trotz Fund 1 stürzte die App beim erneuten Live-Test
         weiterhin ab. Per Live-Konsolen-Logging (`xcrun devicectl device process launch
         --console`) festgestellt: **"App terminated due to signal 9"** - ein Speicher-Kill durch
         iOS (Jetsam), kein Swift-Laufzeitfehler/Crash im klassischen Sinn (deshalb erschien dazu
         auch kein normaler Crash-Report unter `systemCrashLogs`). Ursache: `WayGraphRepository`
         hielt pro Knoten ein eigenes `[Edge]`-Array (`adjacency: [[Edge]]`) - bei 9,6 Mio. Knoten
         kostet allein der Buffer-Overhead von Millionen einzelner kleiner Array-Allokationen in
         Swift mehrere hundert MB zusätzlich, unabhängig von den eigentlichen Kantendaten (40 Byte/
         Kante bei durchgängig `Int`/`Double`-Feldern, obwohl das Disk-Format nur 21 Byte/Kante
         braucht) - grobe Schätzung: ~1,5 GB allein für die Kantenstruktur bei den Niederlanden,
         auf einem iPhone 13 (4 GB RAM) zusammen mit App/MapKit/iOS genug, um Jetsam auszulösen.
         Dieselbe Lehre wie beim SQLite-Dateiformat selbst (s. Historie: "eine einzelne Zeile mit
         zwei Blobs" statt einer Zeile pro Knoten/Kante), nur diesmal für die In-Memory-Struktur.
      3. **Behoben durch CSR-Umstellung ("compressed sparse row")**: `adjacency: [[Edge]]` ersetzt
         durch ein **einziges** flaches `edges`-Array (nach `fromNode` gruppiert) plus
         `edgeOffsets` (Startindex pro Knoten) - `edges(from:)` liefert ein `ArraySlice` in diesen
         Bereich. Aufbau in zwei Durchläufen über die Kanten-Rohdaten (erst Out-Degree pro Knoten
         zählen für die Präfixsumme, dann jede Kante an ihre endgültige Position schreiben) -
         kostet die doppelte Parse-Zeit, spart aber die Allokations-Kosten von Millionen
         Pro-Knoten-Arrays. Zusätzlich `Edge`-Felder auf dieselbe Größe wie das Disk-Format
         verkleinert (`Int32`/`Float`/`UInt8`/`UInt32` statt `Int`/`Double` - 40 → ~20 Byte/Kante).
         Zusammen ca. **60 % weniger Speicher** für die Kantenstruktur. `BikeRoutingEngine`
         entsprechend angepasst (`repository.edges(from:)` statt `repository.adjacency[node]`,
         Typ-Konvertierungen an den Zugriffsstellen).
      - **Verifiziert**: Bestehender Bremen-Unit-Test (`bikeRoutingEnginePrefersQuietPathsOver
        ShortestDistance`) nach jeder der drei Änderungen weiterhin grün (liefert unverändert
        plausible Ergebnisse) - für den eigentlichen Speicher-Fix gibt es aber keinen
        automatisierten Test (bräuchte einen Millionen-Knoten-Graphen im Testlauf); die
        entscheidende Verifikation war der erneute Live-Test durch den Nutzer in Rotterdam nach
        dem Fix.
      - **Noch nicht geprüft**: Ob die CSR-Umstellung allein für Polen (31 Mio. Knoten, 64,5 Mio.
        Kanten - gut das Dreifache der Niederlande) tatsächlich ausreicht, oder ob dort weitere
        Optimierungen nötig werden (z. B. `nodeLocations` von `[CLLocationCoordinate2D]`, also
        `Double`-Paaren, auf `Float` umstellen - bisher nicht angefasst, macht laut grober
        Schätzung bei Polen allein ~500 MB aus). Kein akuter Anlass wie bei den Niederlanden, daher
        zurückgestellt, bis tatsächlich getestet wird.
      → [WayGraphRepository.swift](FahrradApp/RadFaehrte/Services/WayGraphRepository.swift)
      (`Edge`, `edgeOffsets`, `edges`, `edges(from:)`, `nearestNode`),
      [BikeRoutingEngine.swift](FahrradApp/RadFaehrte/Services/BikeRoutingEngine.swift)
      (`maxVisitedNodes`, `search`, `buildSteps`)
- [x] **Wege-Graph wird gecached statt bei jeder Berechnung neu geladen**: Nutzer-Meldung beim
      Live-Test in Rotterdam (2026-07-26, direkt im Anschluss an den Speicher-Fix oben): Der
      Absturz war zwar behoben, aber jede "Direkte Fahrrad-Route"-Berechnung dauerte spürbar lange.
      Ursache: `ContentView.offlineDirectRoutes` erzeugte bei **jedem** Aufruf (Erstberechnung,
      jede automatische Neuberechnung bei Abweichen während der Navigation, alle 15 s möglich, s.
      `rerouteDirectRoute`) eine neue `WayGraphRepository` - lud also bei den Niederlanden jedes
      Mal erneut alle 466 MB von der Festplatte und baute die CSR-Struktur neu auf, statt den
      einmal geladenen Graphen wiederzuverwenden. Neue Klasse `WayGraphCache` (Singleton,
      `nonisolated` mit eigenem Lock wie `WayGraphStore`/`RouteRepository`) hält geladene Graphen
      geschlüsselt nach Dateipfad im Speicher; `offlineDirectRoutes` fragt jetzt dort nach statt
      selbst `WayGraphRepository(path:)` aufzurufen. `WayGraphDownloadManager.delete(_:)`
      invalidiert den passenden Cache-Eintrag mit (Pfad vor dem Löschen gemerkt, da `path(for:)`
      danach `nil` liefert) - sonst würde ein erneuter Download nach einem Löschen unbemerkt mit
      dem alten, im Cache gehaltenen Graphen weiterrechnen.
      - Nur die **erste** Berechnung pro Region bleibt dadurch langsam (Graph muss einmal geladen
        werden), jede weitere in derselben App-Sitzung sollte spürbar schneller sein. Cache lebt
        nur im Arbeitsspeicher - nach einem App-Neustart wird beim ersten Zugriff wieder neu
        geladen.
      → [WayGraphCache.swift](FahrradApp/RadFaehrte/Services/WayGraphCache.swift) (neu),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`offlineDirectRoutes`),
      [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift)
      (`delete`)
- [x] **Einstellungen während der Navigation erreichbar (Zahnrad-Button)**: Nutzer-Feedback: Die
      Tab-Leiste blendet sich während der Navigation komplett aus (s. o. "Navigationsstruktur"), der
      Einstellungen-Tab war damit unterwegs nicht erreichbar (z. B. um das Tempo mitten in der Fahrt
      anzupassen). Von drei besprochenen Optionen (Mini-Sheet mit nur den fahrtrelevanten Werten /
      komplette `SettingsView` als Sheet / Tab-Leiste auch während der Navigation sichtbar lassen)
      wurde die erste gewählt - am wenigsten Risiko für die bestehende Kamera-/GPS-Logik, die auf
      dem sichtbaren Route-Tab aufbaut. Neuer Zahnrad-Button in `navigationControlsOverlay` (vierter
      Button, unter dem Banner-Ein-/Ausblende-Button) öffnet `NavigationQuickSettingsView` als
      Sheet - enthält nur Durchschnittsgeschwindigkeit, Sichtweite beim Navigieren und den
      Statistik-Leiste-Link (dieselben `@AppStorage`-Keys wie `SettingsView`, also sofort wirksam),
      bewusst ohne die Offline-Karten-Downloads. Navigation/GPS-Tracking läuft währenddessen
      unverändert im Hintergrund weiter.
      → [NavigationQuickSettingsView.swift](FahrradApp/RadFaehrte/Views/NavigationQuickSettingsView.swift),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`showQuickSettings`,
      `navigationControlsOverlay`)
- [x] **Erscheinungsbild-Einstellung (System/Hell/Dunkel) + Einstellungen neu geordnet**: Neuer
      Picker in `SettingsView` (segmentiert, direkt inline statt eigener Unterseite - nur 3
      Optionen). Persistiert als Rohwert über `AppearanceMode` (neues Model, `ColorScheme?`-Mapping)
      unter `AppSettingsKey.appearanceMode`; `RadFaehrteApp` wendet `.preferredColorScheme(...)` auf
      `RootTabView` an der App-Wurzel an. Im Zuge dessen auf Nutzerwunsch die bisher einzeln auf dem
      Einstellungen-Hauptscreen stehenden Durchschnittsgeschwindigkeit/Sichtweite/Statistik-Leiste in
      eine neue Unterseite `NavigationSettingsView` ("Navigation") zusammengefasst - gehören
      inhaltlich zusammen, Hauptscreen bleibt dadurch kurz (jetzt 4 statt 5 Abschnitte).
      `HowItWorksView` entsprechend ergänzt (neuer Punkt "Erscheinungsbild") und der Pfad-Verweis bei
      "Statistik-Leiste anpassen" korrigiert (jetzt "Einstellungen > Navigation > Statistik-Leiste").
      → [AppearanceMode.swift](FahrradApp/RadFaehrte/Models/AppearanceMode.swift),
      [AppSettings.swift](FahrradApp/RadFaehrte/Models/AppSettings.swift),
      [RadFaehrteApp.swift](FahrradApp/RadFaehrte/RadFaehrteApp.swift),
      [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift),
      [NavigationSettingsView.swift](FahrradApp/RadFaehrte/Views/NavigationSettingsView.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **Kartenstil + Standard-Kartenausrichtung als Einstellung**: Neue Sektion "Karte" in
      `SettingsView` mit zwei inline Segmented-Pickern. Kartenstil (`MapStyleOption`: Standard/
      Satellit/Hybrid) wird über `.mapStyle(...)` direkt auf die `Map`-View in `ContentView`
      angewendet - dafür in eine eigene computed property (`currentMapStyle`) ausgelagert, weil der
      Ausdruck inline im Modifier-Aufruf den Swift-Typchecker in der ohnehin schon sehr komplexen
      `Map`-Builder-Kette zum Timeout brachte ("unable to type-check this expression in reasonable
      time"). Standard-Kartenausrichtung (Fahrtrichtung oben/Norden oben, `Bool` unter
      `AppSettingsKey.navigationDefaultHeadingUp`) legt nur den **Start-Zustand** von
      `isHeadingUpEnabled` bei jedem `startNavigating()`-Aufruf fest - während einer laufenden Fahrt
      bleibt der bestehende Umschalt-Button unverändert nutzbar, ändert aber wie bisher nur den
      aktuellen Ritt, nicht die gespeicherte Voreinstellung.
      → [MapStyleOption.swift](FahrradApp/RadFaehrte/Models/MapStyleOption.swift),
      [AppSettings.swift](FahrradApp/RadFaehrte/Models/AppSettings.swift),
      [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`currentMapStyle`,
      `startNavigating`), [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **Kartenstil auch im Schnell-Einstellungen-Sheet während der Navigation**: Nutzer-Feedback -
      der Kartenstil-Picker steckte zunächst nur in der vollständigen `SettingsView`, die während
      der Navigation (ausgeblendete Tab-Leiste) nicht erreichbar ist. Derselbe Segmented-Picker
      jetzt zusätzlich in `NavigationQuickSettingsView` (liest/schreibt denselben
      `AppSettingsKey.mapStyle`-Wert, also sofort auf der Karte wirksam).
      → [NavigationQuickSettingsView.swift](FahrradApp/RadFaehrte/Views/NavigationQuickSettingsView.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **Zwei weitere Ladezeit-Optimierungen für die Offline-Routing-Engine** (Nutzerwunsch direkt
      im Anschluss an den Cache-Fix oben: "noch schneller kann man die Touren bei größeren Karten
      nicht laden?"):
      1. **Unnötige Zwischenkopie beim Parsen entfernt**: `WayGraphRepository.init` kopierte den
         SQLite-Blob bisher erst per `Data(bytes:count:)` in ein eigenes `Data`, bevor daraus die
         eigenen Arrays gebaut wurden - bei Polen (1,5 GB Kanten-Blob) eine komplette zusätzliche
         Speicherkopie der gesamten Datei ohne Nutzen. Arbeitet jetzt direkt mit dem von SQLite
         gelieferten `UnsafeRawBufferPointer` (gültig, solange `statement` lebt, also für den
         kompletten restlichen Initializer).
      2. **Vorladen im Hintergrund**: Neu `RootTabView.preloadDownloadedWayGraphs()` (per `.task`
         beim App-Start, `.background`-Priorität) lädt alle bereits heruntergeladenen Regionen
         (Bundesländer + Länder) direkt in den `WayGraphCache` vor, statt erst bei der ersten
         tatsächlichen Routenanfrage. Zusätzlich lädt `WayGraphDownloadManager.download` direkt
         nach einem erfolgreichen Download im Hintergrund vor (der Nutzer verweilt danach ohnehin
         meist noch kurz in den Einstellungen). Damit ist der Graph im Idealfall schon fertig
         geladen, bevor überhaupt eine Route angefragt wird - reduziert nicht die absolute
         Ladezeit, verschiebt sie aber aus dem Moment, in dem der Nutzer aktiv wartet.
      - **Größere, zurückgestellte Option besprochen**: Der Wege-Graph direkt per `mmap` aus einer
        eigenen Flachdatei (statt über SQLite-Blob + eigener Parse-Schritt) lesen, mit auf der
        Platte bereits vorsortierten CSR-Daten - würde die erste Ladezeit nochmal deutlich senken
        (keine Kopie, kein Zwei-Pass-Aufbau in Swift), erfordert aber einen Neuaufbau **aller**
        bereits veröffentlichten Wege-Graphen (16 Bundesländer + Niederlande + Polen). Nutzer war
        mit den beiden oben umgesetzten, risikoärmeren Optimierungen erstmal zufrieden - größere
        Umstellung bewusst zurückgestellt, bis tatsächlich wieder Bedarf gemeldet wird.
      → [WayGraphRepository.swift](FahrradApp/RadFaehrte/Services/WayGraphRepository.swift) (`init`),
      [RootTabView.swift](FahrradApp/RadFaehrte/RootTabView.swift) (`preloadDownloadedWayGraphs`),
      [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift)
      (`download`)
- [x] **Bugfix: Navigationskamera "kroch" beim Start minutenlang langsam zur echten Position statt
      sofort dort zu sein (Live-Test Rotterdam→München-Spaßroute, 2026-07-27)**: Nutzer-Meldung
      "bewegt sich die ganze Zeit, landet aber nicht in München" (eigentlich richtig, da Navigation
      immer der echten GPS-Position folgt, nie dem Ziel - das eigentliche Problem war die Bewegung
      selbst). Per Screen-Recording des Nutzers diagnostiziert: Video-Frames per
      `AVAssetImageGenerator`-Skript extrahiert (analog früherer Kompass-Diagnose, s. Historie) und
      verglichen - der Kartenausschnitt zoomte über ~20 Sekunden hinweg sichtbar kontinuierlich von
      einer weiten Übersicht auf die enge Navigationsdarstellung, statt sofort zu springen.
      Ursache im Code gefunden (ohne Live-Logging nötig, das Muster war eindeutig): `LocationManager.
      smoothedCameraCoordinate` glättet die Kameraposition per Tiefpassfilter (`alpha = 0.4`, s.
      `smoothed(_:previous:)`) - wird aber zwischen Navigations-Sitzungen **nie zurückgesetzt**.
      Bei `previous == nil` gibt der Filter die neue Position sofort ungeglättet zurück (richtiges
      Verhalten für den allerersten Fix überhaupt) - lag aber schon ein alter Wert aus einer
      früheren Sitzung/einem früheren GPS-Fix vor (z. B. von einem ungenauen Kaltstart-Fix oder
      einem früheren Testlauf), näherte sich die Kamera stattdessen über viele Updates hinweg nur
      schrittweise (40 % der Reststrecke pro Update) der echten Position an - wirkte wie
      andauerndes, nie ankommendes Wandern. Erster Fix: `LocationManager.startUpdating()` setzt
      `smoothedCameraCoordinate` jetzt explizit auf `nil` zurück, bevor Updates erneut gestartet
      werden - jede neue Sitzung beginnt so garantiert ungeglättet beim ersten echten Fix.
      - **Reichte allein nicht - Nutzer-Rückmeldung "sie kriecht immer noch" nach diesem ersten
        Fix**: Auch mit zurückgesetztem `previous` bleibt das Problem bestehen, wenn ein GPS-
        Kaltstart mehrere aufeinanderfolgende, jeweils *echte* Fixes liefert, die sich stark
        unterscheiden (erst grob über WLAN/Zellfunk, dann zunehmend präzise über Satelliten) -
        jeder einzelne Sprung ist keine Sitzungs-Altlast, wird vom Filter aber trotzdem als
        "Rauschen" behandelt und nur zu 40 % nachvollzogen, bevor der nächste (wieder nur teils
        nachvollzogene) Fix eintrifft - über mehrere Updates hinweg optisch identisch zum
        ursprünglichen Symptom. Zweiter, eigentlich entscheidender Fix: `smoothed(_:previous:)`
        übernimmt einen Sprung jetzt **direkt ohne Glättung**, sobald er einen
        `snapThresholdMeters`-Schwellenwert (50 m) überschreitet - übliche GPS-Ungenauigkeit
        während der Fahrt liegt weit darunter, ein Kaltstart-Sprung meist deutlich darüber. Damit
        bleibt die Glättung für ihren eigentlichen Zweck (Rauschen während der Fahrt dämpfen)
        erhalten, ohne echte, große Neupositionierungen künstlich zu verlangsamen.
      - **Nebenbei gewünscht, dann wieder verworfen**: Nutzer wollte ursprünglich einen animierten
        (aber zügigen) Zoom zum blauen Punkt beim Start - zunächst `recenterAnimation: true`
        (dieselbe 0,6-s-Ease-In-Out-Animation wie der "Zentrieren"-Button) eingebaut. Reichte aber
        nicht: Beim Live-Test mit der 660-km-Route blieb das "Kriechen" bestehen, unabhängig von
        Glättungs-Fix und Animationsdauer - MapKit scheint den Kamerawechsel von einer
        Ganze-Route-Übersicht (`.region(...)`) auf die enge Navigationsansicht (`.camera(...)`,
        300 m) bei so großem Zoom-Unterschied selbst über mehrere Sekunden zu "strecken", egal
        welche SwiftUI-Animationsdauer angegeben wird (weder 0,6 s noch die kurze lineare
        Verfolgungs-Animation griffen). Deshalb letztlich `animated: false` (sofortiges Setzen ganz
        ohne Animation) - Geschwindigkeit war dem Nutzer wichtiger als der animierte Übergang.
      → [LocationManager.swift](FahrradApp/RadFaehrte/Services/LocationManager.swift) (`startUpdating`),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`startNavigating`)
- [x] **Wege-Graph-Format v2 (mmap, kein SQLite mehr) - Pilotversuch Niederlande** (Nutzerwunsch
      2026-07-27/28, direkt im Anschluss an die zuvor als "größere, zurückgestellte Option"
      dokumentierte Idee, s. u. bei "Wege-Graph per mmap statt über SQLite lesen" - dieser Eintrag
      hier ist deren Umsetzung für die Niederlande als Testlauf, bevor alle 18 Regionen
      umgestellt werden).
      - **Neues Skript `Scripts/build_way_graph_v2.py`** (importiert die Gewichtungs-/
        Richtungs-Logik aus `build_way_graph.py`, um keine Kartierungs-Regeln zu duplizieren):
        baut denselben Graphen, schreibt ihn aber als reine Flachdatei ohne SQLite-Container -
        Kanten liegen bereits auf der Platte nach `fromNode` sortiert/gruppiert vor (CSR-Layout
        schon in Python hergestellt, `edge_rows.sort(key=lambda e: e[0])`), jede Kante spart sich
        das `fromNode`-Feld (17 statt 21 Byte/Kante, da die Position im sortierten Array es
        bereits codiert). Format: `"RFG2"`-Magic (4 Byte) + drei `UInt32`-Zähler im Header, dann
        Nodes-/EdgeOffsets-/Edges-/Names-Sektionen hintereinander (genaues Layout im
        Datei-Docstring). Für die Niederlande: **428 MB** (kleiner als die alten 466 MB trotz
        gleicher Rohdaten - die kompaktere Kantendarstellung überwiegt den kleinen
        EdgeOffsets-Overhead), 9.602.097 Knoten, 19.484.069 Kanten, Bauzeit **7:44 Min** (schneller
        als der alte SQLite-Build mit 13 Min, da nur ein Parse-Durchlauf + ein Sortierschritt statt
        der bisherigen Zwei-Pass-Logik zur Laufzeit).
      - **`WayGraphRepository` liest jetzt beide Formate**, per Magic-Bytes am Dateianfang
        automatisch erkannt (`"RFG2"` → v2, sonst SQLite-Header → v1/"legacy") - dieselbe Instanz
        deckt beide ab, kein separater Typ nötig. Bei v1 unverändert wie bisher: kompletter Graph
        wird beim Laden in eigene `eagerEdges`-/`nodeLocations`-Arrays kopiert. Bei v2: Datei wird
        per `Data(contentsOf:options:.alwaysMapped)` gemappt, `nodeLocations`/`edgeOffsets` (klein)
        werden eagerly gelesen, die eigentlichen Kanten aber **nicht** - `edges(from:)` dekodiert
        sie jetzt direkt aus der gemappten Datei, nur für den einen angefragten Knoten, in dem
        Moment, in dem `BikeRoutingEngine.search` ihn tatsächlich besucht. Bei einer lokalen
        Stadt-Route (typischerweise nur ein winziger Bruchteil aller Knoten besucht) muss die App
        dadurch nur einen entsprechend winzigen Teil der Datei überhaupt anfassen, statt beim Laden
        immer den kompletten Graphen zu verarbeiten - das war laut vorherigen Live-Tests der
        dominante Anteil der spürbaren ersten Ladezeit bei großen Ländern.
        `edges(from:)`s Rückgabetyp musste dafür von `ArraySlice<Edge>` auf `[Edge]` geändert
        werden (bei v1 ein kleiner, günstiger Kopier-Schritt aus dem bereits geladenen Array; bei
        v2 die direkt aus der Mmap-Datei dekodierten paar Kanten) - `BikeRoutingEngine` brauchte
        dafür keine Änderung (iteriert nur, unabhängig vom konkreten Collection-Typ).
      - **Bewusst kein Format-Versions-Bump** (`WayGraphStore.wayGraphFormatVersion` unverändert):
        Da `WayGraphRepository` beide Formate gleichzeitig unterstützt, bleibt eine bereits
        heruntergeladene v1-Datei weiterhin gültig und funktioniert unverändert (nur ohne den
        neuen Geschwindigkeitsvorteil) - ein Bump hätte unnötig *alle* heruntergeladenen Regionen
        (auch die noch nicht auf v2 umgestellten wie Polen/Bundesländer) zwangsweise gelöscht.
        Um die neue Niederlande-Datei tatsächlich zu bekommen, muss sie einmalig manuell über
        Einstellungen → Offline-Karten Europa → Löschen, dann erneut Herunterladen ausgetauscht
        werden (Downloadgröße dort entsprechend auf die tatsächlichen 428 MB aktualisiert).
      - **Datei bewusst weiterhin `netherlands_ways.sqlite` genannt** (Release-Asset unter
        `way-graphs-eu-v1` mit `--clobber` ersetzt, keine neue URL/kein neuer Tag) - der Dateiname
        ist nur ein Downloadname, die App erkennt das tatsächliche Format an den Magic-Bytes im
        Inhalt, nicht an der Endung. Dadurch mussten `WayGraphStore`/`WayGraphDownloadManager`/die
        Download-URL-Konstruktion überhaupt nicht angefasst werden.
      - **Rollout-Stand**: Alle 16 Bundesländer + Niederlande + Schweden sind auf Format v2
        umgestellt - **nur noch Polen ist offen** (auf Format v1/SQLite). Bewusst nicht sofort
        alle 18 Regionen auf einmal
        umgestellt, sondern zuerst Niederlande + Bremen als Testlauf, damit der Nutzer die
        tatsächliche Beschleunigung und unveränderte Routenqualität live/automatisiert prüfen
        konnte, bevor der Rollout auf die übrigen Regionen (mehrere Stunden Rechenzeit insgesamt)
        angegangen wird.
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (neu),
      [WayGraphRepository.swift](FahrradApp/RadFaehrte/Services/WayGraphRepository.swift)
      (`parseV2`, `parseLegacy`, `mappedFile`, `edges(from:)`),
      [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift)
      (`approximateSizeMB`),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
      - **Zusätzlich Bremen auf v2 umgestellt** (Nutzerwunsch direkt im Anschluss: "kannst du es
        auch einmal für Bremen machen, da waren die Ladezeiten zwar gut, aber so kann ich
        überprüfen ob das neue Built immer noch die schönen Radwege vorschlägt") - **8,6 MB**
        (vorher 9 MB), 191.439 Knoten, 391.152 Kanten, Bauzeit 7 s. Release-Asset unter
        `way-graphs-v4` (Bundesland-Tag, nicht `way-graphs-eu-v1`) mit `--clobber` ersetzt.
        Wichtigste Verifikation dabei: Die v2-Datei nach `Scripts/data/bremen_ways.sqlite` kopiert
        (der von `RadFaehrteTests.bremenWayGraphPath` erwartete Pfad) und den bestehenden Test
        `bikeRoutingEnginePrefersQuietPathsOverShortestDistance` laufen lassen (vorher wegen
        fehlender lokaler Datei übersprungen) - **grün**, bestätigt automatisiert, dass Format v2
        weiterhin dieselbe "ruhige Wege statt kürzeste Verbindung"-Routenqualität liefert wie
        Format v1, nicht nur schneller lädt. Kein neuer App-Build nötig, da die
        Formaterkennung bereits mit dem Niederlande-Fix ausgeliefert wurde - nur die
        GitHub-Datei musste sich ändern.
        → [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4)
- [x] **Hinweis zur Umkreis-Suche in "Wie funktioniert's" ergänzt**: Live-Fund des Nutzers in
      Rotterdam (2026-07-28): Adresssuche nach "Bückeburger Straße" (Bremen) fand die Straße nicht,
      zeigte stattdessen zwei gleichnamige Straßen in anderen Orten. Ursache identifiziert:
      `LocationSearchViewModel.updateRegion` grenzt die `MKLocalSearchCompleter`-Vorschläge bewusst
      auf ca. 111 km um den aktuellen Standort ein (`LocationSearchField`s `biasCoordinate`, aus
      `locationManager.currentLocation`) - sinnvoll für "in meiner Nähe zuerst", bricht aber genau
      dann, wenn von unterwegs eine weit entfernte Adresse (z. B. zu Hause) gesucht wird. Mit
      Ortsname in der Sucheingabe (z. B. "Bückeburger Straße, Bremen") fand der Nutzer die Adresse
      trotzdem - ob das Komma dafür zwingend nötig ist oder auch ein Leerzeichen reicht, ist nicht
      sicher geklärt (Apples interne Textverarbeitung, nicht dokumentiert, von hier aus nicht
      testbar). **Nutzer-Entscheidung**: Radius vorerst nicht ändern (Trade-off zwischen "in der
      Nähe zuerst" und "auch von weit weg findbar" bewusst nicht angetastet) - stattdessen nur ein
      Hinweis in `HowItWorksView` ergänzt, dass in diesem Fall der Ort mit in die Sucheingabe
      gehört.
      → [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift) ("Route suchen"),
      [LocationSearchViewModel.swift](FahrradApp/RadFaehrte/ViewModels/LocationSearchViewModel.swift)
      (`updateRegion`), [LocationSearchField.swift](FahrradApp/RadFaehrte/Views/LocationSearchField.swift)
      (`biasCoordinate`)
- [x] **Apple-Watch-Anbindung (Grundfunktion)**: Nutzerwunsch 2026-07-28, direkt im Anschluss an
      die Idee umgesetzt. Neues watchOS-App-Target zeigt während der Navigation die aktuelle
      Anweisung + Live-Entfernung (bei kuratierten Routen ohne Schritt-Daten stattdessen den
      Routennamen) und vibriert kurz vor einer Abbiegung bei der "Direkten Fahrrad-Route"
      (< 50 m vor Schrittende, einmal pro Schritt).
      - **Architektur**: Neuer geteilter Ordner `RadFaehrteShared/` (nicht Teil des
        FileSystemSynchronizedRootGroup-Mechanismus der übrigen App, sondern eine klassische
        Xcode-Gruppe, die bewusst in beide Targets eingebunden ist) mit `WatchNavState` - flaches,
        Property-List-kompatibles Dictionary statt `Codable`/JSON, weil
        `WCSession.updateApplicationContext` genau das verlangt. Je ein `WatchSessionManager`
        pro Seite: iOS (`RadFaehrte/Services/WatchSessionManager.swift`) sendet bei jedem
        Standort-Update in `ContentView.handleLocationUpdate` per `updateApplicationContext`
        (kommt auch an, wenn die Watch-App nicht im Vordergrund ist) sowie das Haptik-Signal per
        `sendMessage` (braucht ein erreichbares Gegenstück, verpufft sonst folgenlos); Watch-Seite
        (`RadFaehrte Watch App/WatchSessionManager.swift`, `ObservableObject`) empfängt beides und
        übersetzt das Haptik-Signal in `WKInterfaceDevice.play(.directionUp)`.
      - **Xcode-Projekt**: Da das Projekt objectVersion 77 (Xcode 26) mit den neuen
        `PBXFileSystemSynchronizedRootGroup`-Ordnern nutzt, für das neue Target aber bewusst
        **klassische** `PBXGroup`/`PBXFileReference`/`PBXBuildFile`-Einträge verwendet (per
        `xcodeproj`-Gem, `project.new_target` - robuster/besser getestet als der neuere
        Sync-Group-Mechanismus von Hand nachzubauen; beide Formen dürfen im selben Projekt
        gemischt vorkommen). Watch-Target: `com.frankenfeld.RadFaehrte.watchkitapp`,
        `WATCHOS_DEPLOYMENT_TARGET = 26.5` (passend zum SDK-Stand), `INFOPLIST_KEY_
        WKCompanionAppBundleIdentifier` auf die iOS-Bundle-ID gesetzt, App-Icon vom iOS-Icon
        wiederverwendet. iOS-Target bekam eine "Embed Watch Content"-Copy-Files-Phase
        (`dstSubfolderSpec = 16`, `dstPath = $(CONTENTS_FOLDER_PATH)/Watch`) + Target-Dependency.
      - ⚠️ **Wichtige Falle beim Einrichten des Targets**: `project.new_target` setzt `SDKROOT`
        bereits korrekt auf `watchos` - ein initialer Versuch, das Setting testweise zu entfernen
        (`bs.delete("SDKROOT")`), ließ es fälschlich auf den iOS-Projekt-Standard (`iphoneos`)
        zurückfallen (`PLATFORM_NAME` zeigte dann `iphoneos` statt `watchos` in
        `xcodebuild -showBuildSettings`) - Ziel-Auflösung schlug entsprechend fehl. Behoben durch
        explizites `SDKROOT = "watchos"` statt Löschen.
      - ⚠️ **Zweite Falle, live beim Nutzer gefunden (2026-07-28): `WATCHOS_DEPLOYMENT_TARGET`
        zu hoch angesetzt**: Anfangs auf `26.5` gesetzt (passend zum in Xcode installierten SDK-
        Stand), die tatsächliche Uhr des Nutzers lief aber noch auf watchOS **26.0.2** - die
        Watch-App ließ sich dadurch in der Watch-App auf dem iPhone nicht installieren
        ("This app could not be installed at this time." - eine bewusst nichtssagende
        Fehlermeldung, die iOS bei allen möglichen Install-Fehlschlägen zeigt, nicht nur bei
        Versions-Mismatches). Der eigentliche Grund kam erst über
        `xcodebuild -showdestinations` zum Vorschein (dort explizit als "doesn't match ... watchOS
        deployment target" benannt). Behoben durch Absenken auf `WATCHOS_DEPLOYMENT_TARGET = 26.0`
        und Neu-Build+Neuinstallation der iOS-App (embeddet die neu gebaute Watch-App automatisch
        mit). **Lehre**: Das Deployment-Target eines neuen Targets nicht blind am installierten
        SDK ausrichten, sondern am tatsächlich ältesten Gerät, das unterstützt werden soll -
        gerade bei der Watch (eigenes Update-Tempo, oft hinter der neuesten iOS-Version) kann das
        deutlich auseinanderlaufen. Bei "could not be installed"-Fehlern auf der Watch lohnt sich
        `xcodebuild -showdestinations` für das Watch-Scheme als erster Diagnoseschritt.
      - ⚠️ **Dritte Falle: Watch-App-Installation über die "Watch"-App auf dem iPhone
        ("Verfügbare Apps" → Installieren) schlug hartnäckig mit der nichtssagenden Meldung
        "This app could not be installed at this time." fehl - auch nachdem
        `WATCHOS_DEPLOYMENT_TARGET` korrigiert war UND das automatisch generierte
        Provisioning-Profil die Watch nachweislich in `ProvisionedDevices` enthielt** (per
        `security cms -D -i embedded.mobileprovision` geprüft). Ursache letztlich zweigeteilt:
        1. **Entwicklermodus auf der Watch selbst war aus** - der Menüpunkt dafür (Einstellungen
           → Datenschutz & Sicherheit → Entwicklermodus) taucht auf der Watch offenbar erst auf,
           nachdem Xcode einmal erfolgreich eine Geräte-Verbindung aufgebaut hat (auf der Watch
           anfangs schlicht nicht auffindbar). Der erste Verbindungsversuch in Xcodes
           "Devices and Simulators"-Fenster schlug dafür wiederum mit "A connection to this
           device could not be established. Timed out while attempting to establish tunnel
           using negotiated network parameters" fehl - behoben, indem die Watch selbst (nicht nur
           per Bluetooth am iPhone) ins gleiche WLAN wie der Mac gebracht wurde. Danach erschien
           in Xcode die klare Fehlermeldung "Developer Mode disabled" statt des generischen
           Tunnel-Timeouts, der Menüpunkt auf der Watch war danach vorhanden, Aktivieren + Neustart
           der Watch behob es.
        2. **Automatisches Signieren registriert ein neues Gerät nicht von selbst bei einem
           reinen `xcodebuild`-CLI-Build** - dafür ist zusätzlich das Flag
           `-allowProvisioningUpdates` (idealerweise zusammen mit
           `-allowProvisioningDeviceRegistration`) nötig, das `xcodebuild` anweist, wie Xcodes
           GUI mit der App Store Connect API zu sprechen und Gerät+Profil selbst zu
           aktualisieren. Ohne dieses Flag baute das Watch-Target zwar (mit der alten, die Watch
           noch nicht enthaltenden Wildcard-Profil-Version), scheiterte aber an
           `ValidateEmbeddedBinary`/`doesn't include the currently selected device`.
        - **Selbst mit korrektem Profil installierte sich die Watch-App über die "Watch"-App auf
          dem iPhone zunächst weiterhin nicht** (identische generische Fehlermeldung wie ganz am
          Anfang - vermutlich lag es schlicht noch am zu diesem Zeitpunkt gerade erst aktivierten
          Entwicklermodus, s. o., der noch nicht überall durchgereicht war). Als Zwischenlösung
          wurde die Watch-App stattdessen direkt und gezielt auf die Uhr installiert (analog zum
          iPhone) - `xcrun devicectl device install app --device <Watch-UDID>
          ".../Build/Products/Debug-watchos/RadFaehrte Watch App.app"` gefolgt von
          `xcrun devicectl device process launch --device <Watch-UDID>
          com.frankenfeld.RadFaehrte.watchkitapp`. Lief auf Anhieb, die App startete und zeigte den
          Leerzustand korrekt.
        - ⚠️ **Wichtige, spät gefundene Falle: Dieser direkte `devicectl`-Installationsweg reicht
          NICHT aus, damit `WatchConnectivity` funktioniert.** Beim ersten echten Navigations-Test
          (Live-Fahrt in Rotterdam) blieb die Watch-Anzeige auf einem alten/generischen Stand
          hängen ("Route folgen" statt echter Anweisungen) - Ursache über eigenes Datei-Logging
          gefunden (`WatchSessionManager.appendDebugLog`, `Documents/watch_debug.log`, ausgelesen
          per `devicectl device copy from --domain-type appDataContainer`): **jeder
          `updateApplicationContext`-Aufruf scheiterte mit `WCErrorDomain Code=7006 "Watch app is
          not installed."`**, weil `WCSession.isWatchAppInstalled` nur die **offizielle**
          App-Store-artige Installation über die "Watch"-App auf dem iPhone kennt, nicht eine per
          `devicectl` direkt auf die Uhr geschobene Kopie - die App lief zwar sichtbar auf der
          Watch, war für WatchConnectivity aber unsichtbar. Behoben, indem in der "Watch"-App auf
          dem iPhone nochmal explizit auf "Installieren" getippt wurde (diesmal erfolgreich, da
          Entwicklermodus + Geräte-Registrierung inzwischen vollständig durch waren) - danach
          zeigte das Log sofort `watchAppInstalled=true` und `send: OK`.
        - **Lehre für nächstes Mal**: Für reines Kompilieren/Debuggen reicht
          `devicectl device install app` auf die Watch-UDID. Für **WatchConnectivity**
          (`WCSession`) ist das **nicht ausreichend** - die App muss zusätzlich (oder
          stattdessen) einmal über die offizielle Route installiert werden (Watch-App auf dem
          iPhone → "Installieren", oder Xcode direkt gegen die Watch als Run-Destination). Bei
          "Watch app is not installed"-Fehlern trotz sichtbar laufender App zuerst
          `session.isWatchAppInstalled` prüfen/loggen, nicht am Provisioning suchen.
      - ⚠️ **Zweiter Funktionsbug, ebenfalls per Live-Test gefunden: Haptik löste bei Online-Routen
        nie aus.** `checkWatchHapticTrigger` prüfte `previewedStep.direction != .straight` - dieses
        Feld ist aber laut `DirectRoute.init(route:)` bei **Online**-Routen (MKDirections) immer
        hart auf `.straight` gesetzt (MKDirections liefert online keine strukturierte
        Abbiege-Richtung, nur fertigen Text wie "Links abbiegen"/"Scharf rechts abbiegen auf
        Willemsbrug" - genau das stand im Log, während trotzdem keine Vibration kam). Nur die
        Offline-Engine (`BikeRoutingEngine`) liefert echtes `.left`/`.right`. Behoben durch
        `isTurnInstruction`/`watchDirection(for:)`: bei `.straight` zusätzlich der Anweisungstext
        nach den Wörtern "links"/"rechts"/"abbiegen"/"kreisverkehr"/"wenden"/"ausfahrt"
        durchsucht - funktioniert dadurch für Online- und Offline-Routen einheitlich. Betrifft nur
        die Watch-Anzeige (Pfeil-Icon + Haptik-Auslösung); die iPhone-eigene
        `navigationInstructionIcon` hat dieselbe Einschränkung, war aber bereits vor der
        Watch-Anbindung so und bewusst nicht angetastet (zeigt bei Online-Routen ohnehin den
        vollen Anweisungstext daneben, der Pfeil ist dort nur Zusatzschmuck).
      - ⚠️ **Dritter Funktionsbug (2026-07-30, echte Fahrt durch Bremen): Haptik löste zuverlässig
        aus, kam aber auf der Watch nie an.** Log zeigte den exakten Grund:
        `checkWatchHapticTrigger: AUSLÖSEN bei 97 m für 'Rechts abbiegen'` gefolgt von
        `sendHapticTurnEvent: SKIPPED, not reachable`. Das ursprüngliche Haptik-Signal nutzte
        `WCSession.sendMessage`, das laut Apple-Doku eine **aktiv erreichbare** Gegenseite braucht
        (Watch-App im Vordergrund) - beim Radfahren hat man die Watch-App aber normalerweise nicht
        durchgehend offen, man schaut nur gelegentlich hin. Kompletter Architekturwechsel statt
        Parameter-Fix: `WatchNavState` bekam ein neues Feld `hapticTrigger: Int`, das bei jeder
        Abbiegung hochgezählt und ganz normal mit dem ohnehin per `updateApplicationContext`
        übertragenen (und zuverlässig auch im Hintergrund ankommenden) Status mitgeschickt wird -
        die Watch erkennt selbst, wenn sich der Zähler gegenüber dem zuletzt gesehenen Wert
        geändert hat, und löst dann die Haptik aus (`WatchSessionManager.apply`, Watch-Seite).
        `sendMessage`/`WatchMessageKey` komplett entfernt. Per Live-Test (20 Abbiegungen auf einer
        Fahrt durch Bremen, alle mit `send: OK` protokolliert) bestätigt.
      - **Nachbesserung Haptik-Muster (2026-07-31, Nutzer-Feedback nach dem ersten erfolgreichen
        Live-Test)**: Vibration kam an, aber zu schwach und links/rechts fühlten sich gleich an.
        Erster Versuch - eigenes Muster durch mehrfaches `WKInterfaceDevice.play(.notification)`
        (2× für links, 5× für rechts, mit kurzen Pausen) - brachte zwar spürbar mehr Kraft, aber
        keine Unterscheidbarkeit: watchOS scheint zu schnell aufeinanderfolgende eigene
        `play()`-Aufrufe zu einem einzigen Vibrations-Eindruck zusammenzufassen (nicht
        dokumentiert, nur beobachtet). Ersetzt durch Apples eigene, extra für Turn-by-Turn-
        Navigation vorgesehene System-Haptiken (`WKHapticType.navigationLeftTurn`/
        `.navigationRightTurn`/`.navigationGenericManeuver` - von Apple selbst bereits als
        unterscheidbare Muster abgestimmt, u. a. von Apple Maps genutzt), plus ein zusätzliches
        `.notification` nach 0,7 s Pause für mehr Kraft (Pause verhindert das oben beobachtete
        Verschlucken). Noch nicht live gegengetestet, ob dieses Muster tatsächlich unterscheidbar
        ist.
      - **Kartenansicht auf der Watch ergänzt (2026-07-31, Nutzerwunsch)**: Zeigt während der
        Navigation eine kleine, eng um die aktuelle Position gezoomte `Map` mit der Routen-Linie
        (SwiftUI-`Map`/`MapPolyline`, auf watchOS seit Version 10 verfügbar) unterhalb einer
        kompakten Anweisungs-Kopfzeile. Bewusst zwei getrennte Übertragungskanäle statt alles in
        `WatchNavState`: Die Routen-Geometrie ändert sich während einer Fahrt kaum (nur bei
        Auswahl/Neuberechnung) und wird deshalb separat per `WCSession.transferUserInfo`
        übertragen (`WatchSessionManager.sendRoute`, aufgerufen in `startNavigating`/nach
        erfolgreicher `rerouteDirectRoute`) - eine erneute `updateApplicationContext`-Nutzung dafür
        hätte den ohnehin schon dort transportierten Navigationsstatus überschrieben (nur ein
        einziger Kontext pro App). Die aktuelle Position (`currentLatitude`/`currentLongitude`)
        ist dagegen ein winziger Zusatz im ohnehin bei jedem Standort-Update gesendeten
        `WatchNavState`. Auf max. 100 Punkte pro Linie herunterskaliert (`decimated`, deutlich
        kleiner als der iPhone-Kartenwert von 500 - fürs winzige Watch-Display irrelevant).
        Kuratierte Routen mit mehreren getrennten Liniensegmenten (Kartenlücken) werden als
        mehrere separate `MapPolyline`s gerendert statt fälschlich verbunden.
        - ⚠️ **Erste Version bewegte sich nicht mit**: Kamera-Position über ein separates
          `@State cameraPosition` + `.onChange(of: session.state)` nachgeführt - beim Live-Test
          blieb die Karte auf dem anfänglichen `.automatic`-Zoom (gesamte Route sichtbar) hängen,
          der blaue Punkt bewegte sich kaum sichtbar mit. `.onChange` feuerte im Zusammenspiel mit
          `@StateObject`/`@Published` offenbar nicht zuverlässig. Behoben durch einen reinen
          Lese-Binding, der bei jedem Rendern frisch aus `session.state` berechnet wird (kein
          `@State`/`.onChange` mehr nötig) - dabei gleich auch Fahrtrichtung ergänzt
          (`WatchNavState.heading`, gespiegelt von `LocationManager.currentHeading`), damit sich
          die Watch-Karte wie beim iPhone in Fahrtrichtung dreht statt starr nordausgerichtet zu
          bleiben (`MapCamera(heading:)` statt `MKCoordinateRegion`, das keine Drehung kennt). Per
          Live-Test bestätigt: Kamera folgt jetzt zuverlässig und dreht sich mit.
      - **Dritter Anlauf beim Haptik-Muster (2026-07-31)**: Weder das eigene Muster (2×/5×
        `.notification` mit `asyncAfter`-Pausen) noch Apples eigene Navigations-Haptiken
        (`navigationLeftTurn`/`.navigationRightTurn` + verzögerter `.notification`-Nachschlag)
        fühlten sich beim Live-Test links/rechts unterschiedlich an - beide Varianten wirkten wie
        ein einzelner Impuls. Naheliegender gemeinsamer Verdacht: Das kurze
        Hintergrund-Zeitfenster nach `didReceiveApplicationContext` reicht nicht für einen per
        `asyncAfter` **verzögerten** zweiten `play()`-Aufruf - die App pausiert vermutlich schon
        wieder, bevor die Verzögerung abgelaufen ist (nicht dokumentiert, aber die einzige
        Erklärung, die für beide unabhängigen Fehlschläge gleichermaßen passt).
      - **Manuelle Test-Buttons ergänzt und wieder entfernt** (2026-08-01, TEMP-DEBUG -
        Nutzerwunsch, das Muster zu testen ohne dafür eine echte Fahrt mit Abbiegung zu brauchen):
        Im Leerzustand der Watch-App ("Keine Navigation aktiv") kurzzeitig Buttons "Links
        testen"/"Rechts testen" (`testHaptic(direction:)` → direkt `playTurnHaptic`, ganz ohne
        Navigation/GPS) sowie "Basis-Vibration testen" (`testBasicNotificationHaptic`, reines
        `.notification` als Sanity-Check). Nachdem das Muster damit live bestätigt war (s. u.),
        auf Nutzerwunsch wieder entfernt - `WatchContentView` zeigt im Leerzustand wieder nur
        Icon + Text, `testHaptic`/`testBasicNotificationHaptic` aus `WatchSessionManager`
        gelöscht.
      - **Durchbruch beim Live-Test (2026-08-01)**: Der Sanity-Check-Button zeigte, dass
        `.navigationLeftTurn`/`.navigationRightTurn`/`.navigationGenericManeuver` auf diesem Gerät
        (Apple Watch Series 8, watchOS 26.5) **komplett stumm** blieben - kein Impuls spürbar,
        nicht nur unentscheidbar wie zuvor vermutet -, während `.notification` zuverlässig
        vibrierte. `playTurnHaptic` deshalb umgestellt: Unterscheidung über die **Anzahl** der
        `.notification`-Impulse (1× links, 2× geradeaus, 3× rechts) statt über den (hier
        wirkungslosen) Haptik-Typ.
      - **Mehrere Anläufe zum Impuls-Abstand nötig**: 0,35 s und danach 0,6 s Pause zwischen den
        Impulsen verschmolzen beim Live-Test zuverlässig zu **einem** gefühlten Impuls (3 geplante
        Impulse fühlten sich nur wie 2 an) - auch ein Wechsel auf unterschiedliche Haptik-Typen
        (`.notification`/`.directionDown`/`.notification`) änderte daran nichts. Ein Test mit 0,6 s
        gefolgt von 2,6 s Gesamt-Pause vor dem letzten Impuls zeigte dagegen klar **zwei** getrennte
        Impulse - der nötige Mindestabstand lag also irgendwo zwischen 0,6 s und 2,6 s, unabhängig
        von Anzahl oder Typ. **1,2 s Abstand zwischen allen Impulsen bestätigt**: alle 3 Impulse
        bei "rechts" kommen zuverlässig einzeln an, links (1 Impuls) und rechts (3 Impulse) fühlen
        sich **klar unterscheidbar** an (per Live-Test am Handgelenk bestätigt, manueller
        Test-Button, App im Vordergrund).
      - **Noch offen**: Ob das Muster auch während einer **echten** Navigation zuverlässig ankommt
        (Watch-App im Hintergrund) - frühere `asyncAfter`-Versuche scheiterten dort spezifisch am
        kurzen Zeitfenster nach `didReceiveApplicationContext` (s. o., zweiter Funktionsbug), und
        1,2 s × 2 Pausen (rechts braucht insgesamt 2,4 s bis zum letzten Impuls) ist ein spürbar
        größeres Zeitfenster als die früher gescheiterten Versuche. Sollte dank
        `watchHapticLeadDistanceMeters` (100 m Vorlauf, mehrere Sekunden bei Radtempo) zeitlich
        passen, ist aber nur im Vordergrund (manueller Button-Tap) verifiziert - eine echte Fahrt
        mit mindestens einer Abbiegung steht noch aus, um das für den Hintergrund-Fall zu
        bestätigen.
      → [RadFaehrte Watch App/WatchSessionManager.swift](FahrradApp/RadFaehrte%20Watch%20App/WatchSessionManager.swift)
      (`playTurnHaptic`), [RadFaehrte Watch App/WatchContentView.swift](FahrradApp/RadFaehrte%20Watch%20App/WatchContentView.swift)
      - **Offene Ideen für später**: Complication (Zifferblatt-Anzeige von Tempo/Distanz),
        "Beenden"-Button direkt von der Watch aus, Herzfrequenz vom Watch-Sensor in `DrivenTour`
        aufnehmen (s. u. "Gefahrene Touren nach Apple Health übertragen" für eine verwandte,
        noch offene Idee).
      - **Hintergrund-Pausieren behoben durch `HKWorkoutSession` (2026-08-02, Nutzerwunsch, direkt
        im Anschluss an die Idee umgesetzt)**: Die zuvor als "erstmal okay" zurückgestellte
        Einschränkung (Watch-App pausiert im Hintergrund gelegentlich und muss manuell neu
        geöffnet werden) ist behoben. Mit Navigationsstart beginnt die Watch jetzt automatisch ein
        echtes Radfahr-Training über `HKWorkoutSession`/`HKLiveWorkoutBuilder`
        (`WorkoutSessionManager`, activityType `.cycling`, locationType `.outdoor`) - genau der in
        der vorherigen Notiz skizzierte Ansatz von Komoot/Strava/Google Maps. Bewusste
        Nutzer-Entscheidung (2026-08-02, zwei Rückfragen vor der Umsetzung): Ein **echtes** Training
        wird in Health gespeichert (zählt zu den Aktivitätsringen, erscheint in der
        Health-/Trainings-App) statt nur eine folgenlose Hintergrund-Session zu öffnen - Letzteres
        wäre eine Zweckentfremdung der HealthKit-API gewesen. Start/Stop läuft **automatisch** mit
        dem Navigationsstatus mit (kein zusätzlicher Button auf der Watch).
        - **Xcode-Projekt**: HealthKit-Capability nur für das Watch-Target (nicht das iOS-Target,
          da nur die Watch-Seite `HKWorkoutSession` nutzt) - neues
          `RadFaehrte Watch App.entitlements` (`com.apple.developer.healthkit` = true,
          `com.apple.developer.healthkit.access` = leeres Array, wie von Xcode selbst generiert)
          plus `CODE_SIGN_ENTITLEMENTS`-Build-Setting. Da das Watch-Target `GENERATE_INFOPLIST_FILE`
          nutzt (kein physisches Info.plist, s. o.), `NSHealthShareUsageDescription`/
          `NSHealthUpdateUsageDescription` sowie die Background-Mode-Capability "Workout
          Processing" (`WKBackgroundModes = workout-processing`) als `INFOPLIST_KEY_`-Build-Settings
          gesetzt statt über ein Info.plist - funktioniert genau wie bei den bestehenden
          `INFOPLIST_KEY_WKCompanionAppBundleIdentifier` u. Ä. (Leerzeichen-getrennte Liste bei
          mehreren Werten, hier nur einer). Noch nicht auf dem Gerät gegengetestet, ob die neue
          HealthKit-Capability beim ersten Build ohne weitere Provisioning-Überraschungen
          durchgeht (s. bereits dokumentierte Signing-Fallen bei der ursprünglichen
          Watch-Einrichtung, oben) - dafür beim nächsten Build besonders auf
          `-allowProvisioningUpdates`-Fehler achten.
        - **Architektur `WorkoutSessionManager`** (`RadFaehrte Watch App/WorkoutSessionManager.swift`):
          Berechtigung wird beim App-Start angefragt (`requestAuthorizationIfNeeded`), nicht erst
          bei Navigationsbeginn - ein dort erst angestoßener Dialog käme zu spät für den Start der
          Fahrt. `start()`/`stop()` werden von `WatchSessionManager.apply` aufgerufen, sobald sich
          `state.isNavigating` ändert. Mehrfacher `DispatchQueue.main.async`-Rücksprung nötig, da
          `HKWorkoutSessionDelegate`/`HKLiveWorkoutBuilderDelegate`-Callbacks laut Apple-Doku auf
          einer beliebigen Queue laufen, `session`/`builder` als einfache Properties aber sonst
          nebenläufig mit dem Main-Thread-Pfad (`apply`) verändert würden.
        - **Verwaiste Sessions**: Wird die Watch-App durch Speicherdruck/Ruhezustand beendet,
          während ein Training läuft, bliebe es sonst unsichtbar aktiv hängen (Akkuverbrauch,
          späterer "Training beenden?"-Systemdialog). Deshalb beim App-Start zusätzlich
          `recoverActiveWorkoutSession` aufgerufen und eine gefundene Session sofort sauber
          beendet+gespeichert - ob danach ein neues Training nötig ist, entscheidet der normale
          Start/Stop-Pfad anhand des frisch vom iPhone synchronisierten Navigationsstatus. Ein
          kleines Restrisiko bleibt: Beide App-Start-Aufrufe (`recoverActiveWorkoutSession` und der
          erste `WCSession`-Sync) laufen unabhängig voneinander asynchron nebeneinander - kommt der
          Sync vor der Recovery durch, könnte `start()` versuchen, eine neue Session zu öffnen,
          während intern noch eine alte offen ist, und dabei scheitern (stiller Fehlschlag über
          `catch`). Für den seltenen Fall (App-Neustart mitten in einer laufenden Fahrt) als
          akzeptabel eingeschätzt statt zusätzlicher Synchronisierung.
        - **Korrektur noch am selben Tag (2026-08-02): "automatisch mit jeder Navigation" war die
          falsche Annahme.** Erster Live-Test auf dem iPhone erfolgreich (Build+Installation über
          `xcodebuild`/`devicectl`, s. u.), danach aber Nutzer-Feedback zum tatsächlichen
          Nutzungsmuster: Navigation wird immer nur auf dem iPhone gestartet, die Watch soll dabei
          bewusst *nicht* automatisch mitlaufen (Akkuverbrauch) - nur wenn der Nutzer zusätzlich
          selbst die Watch-App öffnet, soll dort ein Training beginnen. Start deshalb umgebaut: In
          `WatchSessionManager.apply` startet das Training nur noch, wenn beim
          Navigationsstatus-Wechsel `WKApplication.shared().applicationState == .active` ist (App
          gerade tatsächlich geöffnet), nicht mehr bei jedem im Hintergrund empfangenen
          `WatchNavState`-Update. Zusätzlich in `RadFaehrteWatchApp` ein `.onChange(of: scenePhase)`
          ergänzt, das beim Öffnen der App (`.active`) prüft, ob gerade schon navigiert wird (Fall:
          Navigation lief bereits auf dem iPhone, bevor die Watch-App geöffnet wurde) und dann erst
          startet. `stop()` bleibt bewusst unverändert an den Navigationsstatus gekoppelt (auch im
          Hintergrund), damit ein einmal gestartetes Training beim Navigationsende zuverlässig endet.
        - **Ergänzend: Fahrten landen jetzt auch ganz ohne Apple Watch in Health** (gleicher
          Nutzerwunsch 2026-08-02) - neuer, eigenständiger `WorkoutRecorder`
          (`RadFaehrte/Services/WorkoutRecorder.swift`, iOS-Target) speichert nach jeder
          Navigation mit ausreichend Trackpunkten (`tourTrackPoints.count >= 2`, derselbe Schwellwert
          wie für einen `DrivenTour`-Verlaufseintrag) ein Radfahr-Training in Health - **unabhängig**
          von der Verlauf-Entscheidung im Abschluss-Sheet (auch verworfene Fahrten werden in Health
          gespeichert, Nutzerwunsch: "jede Fahrt soll in Health landen"). Anders als auf der Watch
          ohne live laufende `HKWorkoutSession`, sondern per (nicht-live) `HKWorkoutBuilder` direkt
          nach Fahrtende befüllt und gespeichert - das iPhone braucht den
          Hintergrund-Wachhalte-Trick nicht (Standortverfolgung läuft dort bereits zuverlässig
          weiter, s. o. "Bildschirm & Hintergrund"). Aufruf in `ContentView.stopNavigating()`, an
          derselben Stelle, an der auch der `DrivenTour`-Verlaufseintrag gebaut wird. Dafür
          zusätzlich HealthKit-Capability + `RadFaehrte.entitlements` **auch für das iOS-Target**
          ergänzt (bisher nur am Watch-Target, s. o.) - da `RadFaehrte/` als
          `PBXFileSystemSynchronizedRootGroup` eingebunden ist, musste die neue Entitlements-Datei
          zusätzlich in die Membership-Exceptions dieser Gruppe eingetragen werden (analog zu
          `Supplemental-Info.plist`), sonst wäre sie fälschlich als Bundle-Ressource kopiert worden
          statt nur beim Signieren verwendet zu werden.
        - **Vermeintlicher vierter Funktionsbug, per Live-Test entkräftet (2026-08-02): iPhone
          fragte nie nach Health-Zugriff.** Erste Vermutung - `requestAuthorizationIfNeeded()` liefe
          in `RadFaehrteApp.init()` zu früh, bevor ein Fenster für den Systemdialog existiert -
          führte zum vorsorglichen Verschieben des Aufrufs nach
          [RootTabView.swift](FahrradApp/RadFaehrte/RootTabView.swift) in einen zusätzlichen
          `.task`-Modifier (analog zum bereits vorhandenen `preloadDownloadedWayGraphs`-`.task`).
          Der Dialog blieb aber **auch danach** aus - Blick in Einstellungen → Health → Zugriff &
          Geräte → "RadFährte" zeigte die Erklärung: **Schreibrechte werden zwischen einer
          Watch-App und ihrer iPhone-Begleit-App geteilt** (von Apple als eine
          Berechtigungs-Einheit behandelt). Die zuvor auf der Watch bestätigte Anfrage hatte damit
          bereits alle vier benötigten Typen (Aktivitätsenergie, Herzfrequenz, Strecke (Fahrrad),
          Trainings - Vereinigung aus beiden Targets' `shareTypes`) für **beide** Apps zugleich
          freigegeben; für das iPhone gab es beim eigenen `requestAuthorization`-Aufruf schlicht
          nichts Neues mehr zu erfragen, kein Bug. Der `.task`-Umzug bleibt trotzdem drin (robuster
          für den Fall einer Neuinstallation ohne vorherige Watch-Zustimmung), war aber nicht die
          eigentliche Ursache des beobachteten Verhaltens.
        - **Trainingseintrag am Fahrtende bestätigt (2026-08-02, Live-Test), aber ohne Karte -
          Route ergänzt.** Eine zu Ende gefahrene Tour landet zuverlässig mit korrekter
          Distanz/Dauer in Health/Fitness. Die Fitness-App zeigte dabei aber "GPS-Daten fehlen"
          statt einer Karte - lag nicht an Apple, sondern daran, dass `WorkoutRecorder.saveRide`
          bisher nur eine Distanz-`HKQuantitySample` speicherte, keine `HKWorkoutRoute` (eigener
          HealthKit-Datentyp fürs Streckenprofil, den jede App befüllen kann, nicht nur Apples
          eigene). Ergänzt: `ContentView` sammelt jetzt zusätzlich zu `tourTrackPoints`
          (eingerastet auf die Route, ausgedünnt, ohne Zeitstempel - fürs Verlauf-Tab/GPX-Export)
          ein separates `tourRouteLocations: [CLLocation]` mit echten, unveränderten GPS-Fixen
          samt Zeitstempel (in `accumulateTourDistance`, gleiche Genauigkeits-/Bewegungsfilter wie
          `tourTrackPoints`, aber ohne Routen-Einrasten und ohne Mindestabstands-Ausdünnung - dafür
          war bisher nirgends in der App ein Zeitstempel pro Punkt nötig, `DrivenTour.Coordinate`
          hat keinen). `WorkoutRecorder.saveRide` bekam einen `locations`-Parameter, baut nach
          `finishWorkout` bei mindestens 2 Punkten zusätzlich per `HKWorkoutRouteBuilder` eine
          `HKWorkoutRoute` und verknüpft sie mit dem gespeicherten Workout. Dafür `HKSeriesType.
          workoutRoute()` zu den angefragten `shareTypes` ergänzt - löst beim nächsten Mal
          einen weiteren (diesmal echten) Berechtigungs-Dialog aus, da dieser Typ in der zuvor
          erteilten Freigabe noch nicht enthalten war. Noch nicht live gegengetestet, ob die Karte
          danach tatsächlich erscheint. Bewusst nur für den iPhone-Pfad umgesetzt - die
          Watch-seitige `HKWorkoutSession` (`WorkoutSessionManager` im Watch-Target) hat vermutlich
          dieselbe Lücke (keine Route), aber die Watch kennt selbst keine fortlaufende
          Positionshistorie (nur die jeweils aktuelle Position aus `WatchNavState`) - bräuchte
          eigene Aufzeichnung oder eine vom iPhone mitgesendete Historie, als eigener Punkt
          zurückgestellt.
        - **Doppelter Health-Eintrag entdeckt und behoben (2026-08-02, Nutzer-Beobachtung nach dem
          erfolgreichen Live-Test).** Da die Navigation immer auf dem iPhone gestartet wird und
          dieses ohnehin bei jedem Fahrtende ein Training speichert (s. o.), erzeugte die
          zusätzliche, *live speichernde* Watch-Session einen **zweiten**, redundanten
          Health-Eintrag für dieselbe Fahrt, sobald die Watch-App währenddessen geöffnet war -
          Nutzer-Einschätzung "die Watch braucht das gar nicht", geteilt. Die Watch-Session bleibt
          bestehen (weiterhin nötig für den Hintergrund-Wachhalte-Trick, s. o.), wird am Ende aber
          über `builder.discardWorkout()` verworfen statt über `endCollection`+`finishWorkout`
          gespeichert - das iPhone bleibt die einzige Quelle für den Health-Eintrag. Dadurch auch
          `shareTypes` auf der Watch auf nur noch `HKObjectType.workoutType()` reduziert (Freigabe
          fürs bloße *Starten* einer Session ist weiterhin nötig, auch ohne Speicherabsicht) sowie
          `HKLiveWorkoutDataSource` auf dem Builder entfernt (ohne Speicherabsicht keine
          automatische Sample-Sammlung mehr nötig) - dadurch entfällt implizit auch die zuvor
          eingeplante Herzfrequenz-/Energie-Aufzeichnung auf der Watch. `NSHealthUpdateUsageDescription`
          im Watch-Target entsprechend korrigiert (behauptete zuvor fälschlich, Dauer/Distanz/
          Kalorien/Herzfrequenz würden gespeichert).
        - **Noch offen**: Ob das Watch-Training wirklich nur bei geöffneter Watch-App startet, und
          ob eine bereits laufende Navigation beim nachträglichen Öffnen der Watch-App korrekt
          nachzieht - dafür noch kein Live-Test. Ebenfalls offen: ob die `HKWorkoutRoute` beim
          nächsten Live-Test tatsächlich eine Karte in der Fitness-App zeigt, und ob der Discard-Umbau
          auf der Watch (kein zweiter Health-Eintrag mehr) live funktioniert.
        → [WorkoutSessionManager.swift](FahrradApp/RadFaehrte%20Watch%20App/WorkoutSessionManager.swift),
        [WatchSessionManager.swift](FahrradApp/RadFaehrte%20Watch%20App/WatchSessionManager.swift)
        (`apply`), [RadFaehrteWatchApp.swift](FahrradApp/RadFaehrte%20Watch%20App/RadFaehrteWatchApp.swift),
        [RadFaehrte Watch App.entitlements](FahrradApp/RadFaehrte%20Watch%20App/RadFaehrte%20Watch%20App.entitlements),
        [WorkoutRecorder.swift](FahrradApp/RadFaehrte/Services/WorkoutRecorder.swift),
        [RadFaehrte.entitlements](FahrradApp/RadFaehrte/RadFaehrte.entitlements),
        [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`stopNavigating`),
        [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift) ("Apple Watch",
        "Verlauf")
      - **Watch-Karte blieb leer, wenn die Watch-App erst nach Navigationsstart geöffnet wurde
        (Nutzer-Beobachtung 2026-08-03, behoben).** Reihenfolge "Route am iPhone starten, danach
        Watch-App öffnen" zeigte auf der Watch zwar korrekt die Anweisungen, aber keine Karte;
        umgekehrte Reihenfolge (erst Watch-App, dann Route starten) funktionierte. Ursache: Status
        (Anweisung/Distanz) läuft über `updateApplicationContext` - das hält einen "letzten Stand",
        den die Watch bei jedem Start sofort über `receivedApplicationContext` abholt, unabhängig
        vom Zeitpunkt. Die Routen-Geometrie fürs die Karte läuft dagegen über `transferUserInfo`
        (`WatchSessionManager.sendRoute`), aufgerufen nur einmal bei Navigationsstart/Neuberechnung
        - das ist keine "letzter Stand"-Abholung, sondern eine Warteschlangen-Übertragung, die iOS
        erst zustellt, wenn es passt. War die Watch-App beim `sendRoute`-Aufruf noch nicht offen,
        blieb die Übertragung unbestimmt lange hängen, ohne dass irgendetwas sie erneut anstieß.
        Fix: Neuer `reachabilityChangeCount`-Zähler in `RadFaehrte/Services/WatchSessionManager.swift`
        (iOS-Target jetzt `@Observable`), hochgezählt in `sessionReachabilityDidChange`, sobald
        `session.isReachable` auf `true` wechselt (passiert zuverlässig, wenn die Watch-App in den
        Vordergrund kommt). `ContentView` reagiert per `onChange(of: watchSessionManager.
        reachabilityChangeCount)` und sendet bei laufender Navigation Status + Route erneut
        (`updateWatchNavigationState`/`sendActiveRouteToWatch`). **Per Live-Test bestätigt
        (2026-08-03)**: Route am iPhone gestartet, danach Watch-App geöffnet - Karte erscheint jetzt
        korrekt.
        → [RadFaehrte/Services/WatchSessionManager.swift](FahrradApp/RadFaehrte/Services/WatchSessionManager.swift)
        (`reachabilityChangeCount`, `sessionReachabilityDidChange`),
        [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`watchSessionManager`,
        `onChange(of: watchSessionManager.reachabilityChangeCount)`)
      - **Watch zeigte nach einem Reroute während der Fahrt trotz durchgehend bestehender Verbindung
        noch die alte Streckengeometrie (Nutzer-Beobachtung 2026-08-03, per Foto belegt, behoben).**
        Anders als der Fall oben (Watch-App erst nach Navigationsstart geöffnet, kein
        `isReachable`-Wechsel während der laufenden Fahrt) gab es hier keinen Erreichbarkeits-Wechsel,
        der den `reachabilityChangeCount`-Fix erneut ausgelöst hätte - die eine `transferUserInfo`-
        Übertragung aus `sendActiveRouteToWatch` blieb einfach unbestimmt lange in der
        Zustellwarteschlange hängen. Fix: `WatchSessionManager.sendRouteImmediateIfReachable`
        (iOS) - Pendant zum bereits bestehenden `sendImmediateIfReachable` fürs "Navigation
        beendet"-Ereignis, sofortiger `sendMessage`-Versuch zusätzlich zum weiterhin bestehenden,
        aber langsameren `sendRoute`/`transferUserInfo`-Kanal, nur falls die Watch gerade
        erreichbar ist. Da `sendMessage` denselben Übertragungsweg wie die regulären
        `WatchNavState`-Status-Updates nutzt, musste `WatchSessionManager.session(_:
        didReceiveMessage:)` auf der Watch-Seite zuerst auf `WatchRouteTransferKey.lines` prüfen,
        bevor es den Rest als `WatchNavState` interpretiert (sonst hätte eine Routen-Nachricht
        fälschlich einen leeren Navigationsstatus ausgelöst) - Zeilen-Parsing dafür in neues
        `applyRouteLines` ausgelagert, von `didReceiveMessage` und `didReceiveUserInfo` gemeinsam
        genutzt. Gebaut und aufs Gerät übertragen - **noch nicht live auf einer echten Fahrt mit
        Reroute bestätigt**.
        → [RadFaehrte/Services/WatchSessionManager.swift](FahrradApp/RadFaehrte/Services/WatchSessionManager.swift)
        (`sendRouteImmediateIfReachable`), [RadFaehrte Watch App/WatchSessionManager.swift](FahrradApp/RadFaehrte%20Watch%20App/WatchSessionManager.swift)
        (`applyRouteLines`, `didReceiveMessage`), [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift)
        (`sendActiveRouteToWatch`)
      → [RadFaehrteShared/WatchNavState.swift](FahrradApp/RadFaehrteShared/WatchNavState.swift),
      [RadFaehrte/Services/WatchSessionManager.swift](FahrradApp/RadFaehrte/Services/WatchSessionManager.swift),
      [RadFaehrte Watch App/](FahrradApp/RadFaehrte%20Watch%20App/),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`updateWatchNavigationState`,
      `checkWatchHapticTrigger`), [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
      ("Apple Watch")
- [x] **Schweden als viertes Land ergänzt** (Nutzerwunsch, direkt im neuen v2-Format statt erst v1
      und später umzustellen wie bei den Niederlanden): Vorher Größenabschätzung per `curl -I`
      gegen den Geofabrik-Extrakt gecheckt - mit ~774 MB kleiner als Polen (1,9 GB) und sogar die
      Niederlande (1,3 GB), trotz größerer Fläche Schwedens (~450.000 km² vs. Polens ~313.000 km²) -
      geringere Kartierungsdichte durch niedrigere Bevölkerungsdichte.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **991 Routen**
        (u. a. EuroVelo 7/10, Sverigeleden, Cykelspåret), **4,2 MB** als `Resources/sweden.sqlite`
        gebündelt, `"sweden"` in `RouteRepository.bundledResourceNames` ergänzt. Getestet per
        neuem Unit-Test `routeRepositoryFindsEuroVeloRouteNearStockholm` (analog Rotterdam/Krakau).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`, kein Umweg über das
        alte SQLite-Format) - **1,0 GB**, 23.765.289 Knoten, 48.485.495 Kanten, 104.733 eindeutige
        Straßennamen. ⚠️ **Überraschung**: Trotz kleinerer Rohdatei (774 MB) deutlich mehr Knoten/
        Kanten als die Niederlande (9,6 Mio./19,5 Mio.) und dadurch auch eine deutlich größere
        Ausgabedatei (1,0 GB statt der ursprünglich grob geschätzten ~280 MB) - Schwedens
        physisches Straßennetz ist trotz dünnerer Attribut-Kartierung (weniger Namen, kleinere
        Rohdatei) flächenmäßig einfach viel ausgedehnter. Baudauer **19:27 Min** (deutlich länger
        als bei den Niederlanden mit 7:44 Min trotz kleinerer Eingabedatei - passt zum selben
        Befund: Fläche/Knotenzahl bestimmt die Baudauer stärker als die reine PBF-Dateigröße).
        `EuropaLand.sweden.approximateSizeMB` entsprechend auf den tatsächlich gemessenen Wert
        (1060) korrigiert (war zunächst grob auf 280 geschätzt).
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, neuer Unit-Test grün, App auf dem iPhone
        des Nutzers installiert/gestartet, Release-Asset-URL per `curl -I` gegengeprüft (200,
        korrekte Content-Length). Live-Offline-Routing in Schweden vom Nutzer noch nicht getestet
        (kein konkreter Reiseanlass wie bei den Niederlanden).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift) (`EuropaLand.sweden`),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Bayern auf Format v2 umgestellt** (erstes Bundesland im Rollout, nach dem Niederlande-
      /Bremen-Testlauf, s. o.) - **747 MB** (vorher 815 MB), 16.471.217 Knoten, 34.332.115 Kanten,
      96.920 eindeutige Straßennamen. Baudauer 7:31 Min.
      - ⚠️ **Erster Download-Versuch schlug fehl**: `curl` mit `--progress-bar` meldete "100.0%"
        und Exit-Code 0, die heruntergeladene `bayern-latest.osm.pbf` war aber trotzdem
        abgeschnitten (655 statt der erwarteten 808 MB laut vorherigem `curl -I`-Check) -
        `build_way_graph_v2.py` brach dadurch mit `RuntimeError: PBF error: unexpected EOF` ab.
        Behoben durch erneuten Download mit `--fail --retry 3` (kein `--progress-bar`, damit
        eventuelle Fehlermeldungen sichtbar bleiben) plus expliziter Größenprüfung per `stat -f%z`
        gegen den erwarteten Wert vor dem eigentlichen Build - zweiter Versuch lieferte 847 MB
        (minimal abweichend vom ursprünglichen `curl -I`-Wert, plausibel durch Geofabriks
        täglichen Extrakt-Rebuild zwischen Größen-Check und Download) und lief danach durch.
        **Lehre für die restlichen 14 Bundesländer + Polen**: Vor jedem Wege-Graph-Build die
        heruntergeladene Datei explizit auf plausible Größe prüfen, nicht nur auf Exit-Code 0
        vertrauen.
      - Release-Asset unter `way-graphs-v4` mit `--clobber` ersetzt (gleicher Tag wie die anderen
        Bundesländer, kein neuer Tag nötig). `Bundesland.bayern.approximateSizeMB` auf 747
        aktualisiert.
      → [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4)
- [x] **Baden-Württemberg auf Format v2 umgestellt**: **515 MB** (vorher 563 MB), 11.346.909
      Knoten, 23.685.434 Kanten, 86.516 eindeutige Straßennamen. Baudauer 4:13 Min. Diesmal von
      Anfang an mit der aus dem Bayern-Fund gelernten Größenprüfung heruntergeladen (`curl --fail
      --retry 3` + `stat -f%z`-Abgleich gegen den erwarteten Wert) - kein abgeschnittener Download
      diesmal. Release-Asset unter `way-graphs-v4` mit `--clobber` ersetzt,
      `Bundesland.badenWuerttemberg.approximateSizeMB` auf 515 aktualisiert.
      → [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4)
- [x] **Nordrhein-Westfalen auf Format v2 umgestellt**: **498 MB** (vorher 543 MB), 11.004.581
      Knoten, 22.823.296 Kanten, 102.668 eindeutige Straßennamen. Baudauer 5:55 Min. Größenprüfung
      beim Download (`curl --fail --retry 3` + `stat -f%z`) wieder unauffällig. Release-Asset unter
      `way-graphs-v4` mit `--clobber` ersetzt, `Bundesland.nordrheinWestfalen.approximateSizeMB`
      auf 498 aktualisiert.
      → [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4)
- [x] **Niedersachsen auf Format v2 umgestellt**: **298 MB** (vorher 326 MB), 6.490.654 Knoten,
      13.720.744 Kanten, 81.135 eindeutige Straßennamen. Baudauer 3:04 Min. Größenprüfung beim
      Download exakt getroffen (500.869.095 Byte). Release-Asset unter `way-graphs-v4` mit
      `--clobber` ersetzt, `Bundesland.niedersachsen.approximateSizeMB` auf 298 aktualisiert.
      → [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4)
- [x] **Hessen auf Format v2 umgestellt**: **266 MB** (vorher 290 MB), 5.847.264 Knoten,
      12.225.238 Kanten, 47.316 eindeutige Straßennamen. Baudauer 2:07 Min. Release-Asset unter
      `way-graphs-v4` mit `--clobber` ersetzt, `Bundesland.hessen.approximateSizeMB` auf 266
      aktualisiert.
      → [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4)
- [x] **Rheinland-Pfalz auf Format v2 umgestellt**: **253 MB** (vorher 276 MB), 5.599.229 Knoten,
      11.618.006 Kanten, 37.481 eindeutige Straßennamen. Baudauer 1:44 Min. Release-Asset unter
      `way-graphs-v4` mit `--clobber` ersetzt, `Bundesland.rheinlandPfalz.approximateSizeMB` auf
      253 aktualisiert.
      → [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4)
- [x] **Sachsen auf Format v2 umgestellt**: **183 MB** (vorher 200 MB), 4.050.492 Knoten,
      8.397.814 Kanten, 28.156 eindeutige Straßennamen. Baudauer 1:34 Min. Release-Asset unter
      `way-graphs-v4` mit `--clobber` ersetzt, `Bundesland.sachsen.approximateSizeMB` auf 183
      aktualisiert.
      → [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4)
- [x] **Sachsen-Anhalt auf Format v2 umgestellt**: **121 MB** (vorher 132 MB), 2.677.766 Knoten,
      5.540.232 Kanten, 21.000 eindeutige Straßennamen. Baudauer 1:04 Min. Release-Asset unter
      `way-graphs-v4` mit `--clobber` ersetzt, `Bundesland.sachsenAnhalt.approximateSizeMB` auf 121
      aktualisiert.
      - ⚠️ **Install/Start-Besonderheit**: `devicectl device process launch` scheiterte diesmal
        nicht mit dem üblichen "Locked"-Fehler, sondern mit "invalid code signature ... profile
        has not been explicitly trusted by the user" - ein anderer, selteneres Problem als die
        Sperrbildschirm-Fälle zuvor. Erfordert manuelles Vertrauen des Entwicklerprofils auf dem
        Gerät (Einstellungen → Allgemein → VPN & Geräteverwaltung → Profil antippen → "Vertrauen"),
        kann nicht per CLI behoben werden. Installation selbst war erfolgreich, nur der Start
        schlug fehl.
      → [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4)
- [x] **Schleswig-Holstein auf Format v2 umgestellt**: **93 MB** (vorher 102 MB), 2.038.952
      Knoten, 4.273.320 Kanten, 27.693 eindeutige Straßennamen. Baudauer 0:58 Min. Release-Asset
      unter `way-graphs-v4` mit `--clobber` ersetzt, `Bundesland.schleswigHolstein.
      approximateSizeMB` auf 93 aktualisiert.
      - ⚠️ **"invalid code signature ... profile has not been explicitly trusted by the user"**
        trat beim ersten Startversuch wiederholt (zweimal direkt hintereinander) auf - zunächst
        als echtes Vertrauens-Problem eingeordnet, Nutzer gebeten, in Einstellungen → Allgemein →
        "VPN & Geräteverwaltung" das Profil manuell zu bestätigen. Nutzer fand den Menüpunkt nicht.
        **Klarstellung beim erneuten Versuch**: Ein einfacher `devicectl device process launch`-
        Retry (ohne jede manuelle Aktion auf dem Gerät) hat direkt funktioniert - war also doch nur
        derselbe Übergangs-Fehler wie die bekannten "Locked"/"disconnected"-Fälle, keine echte
        Vertrauensproblematik. Installation selbst war in allen Fällen bereits beim ersten Versuch
        erfolgreich, nur der Start brauchte einen zweiten Anlauf. Kein Handlungsbedarf beim Nutzer.
      → [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4)
- [x] **Thüringen auf Format v2 umgestellt**: **141 MB** (vorher 154 MB), 3.130.222 Knoten,
      6.485.305 Kanten, 22.058 eindeutige Straßennamen. Baudauer 1:00 Min. Release-Asset unter
      `way-graphs-v4` mit `--clobber` ersetzt, `Bundesland.thueringen.approximateSizeMB` auf 141
      aktualisiert.
      → [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4)
- [x] **Mecklenburg-Vorpommern auf Format v2 umgestellt**: **68,8 MB** (vorher 75 MB), 1.510.745
      Knoten, 3.160.718 Kanten, 14.470 eindeutige Straßennamen. Baudauer 0:45 Min. Release-Asset
      unter `way-graphs-v4` mit `--clobber` ersetzt, `Bundesland.mecklenburgVorpommern.
      approximateSizeMB` auf 69 aktualisiert.
      → [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4)
- [x] **Saarland auf Format v2 umgestellt**: **34,7 MB** (vorher 38 MB), 770.110 Knoten, 1.585.826
      Kanten, 9.921 eindeutige Straßennamen. Baudauer 0:20 Min - kleinstes Flächenland,
      entsprechend der bisher schnellste Build. Release-Asset unter `way-graphs-v4` mit
      `--clobber` ersetzt, `Bundesland.saarland.approximateSizeMB` auf 35 aktualisiert.
      → [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4)
- [x] **Brandenburg auf Format v2 umgestellt**: **151 MB** (vorher 165 MB), 3.341.538 Knoten,
      6.952.404 Kanten, 29.108 eindeutige Straßennamen. Baudauer 1:45 Min. Release-Asset unter
      `way-graphs-v4` mit `--clobber` ersetzt, `Bundesland.brandenburg.approximateSizeMB` auf 151
      aktualisiert.
      → [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4)
- [x] **Berlin auf Format v2 umgestellt**: **30,6 MB** (vorher 33 MB), 705.271 Knoten, 1.378.003
      Kanten, 10.852 eindeutige Straßennamen. Baudauer 0:31 Min. Release-Asset unter
      `way-graphs-v4` mit `--clobber` ersetzt, `Bundesland.berlin.approximateSizeMB` auf 31
      aktualisiert.
      → [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4)
- [x] **🎉 Hamburg auf Format v2 umgestellt - alle 16 Bundesländer jetzt fertig**: **21,6 MB**
      (vorher 23 MB), 487.736 Knoten, 977.089 Kanten, 8.803 eindeutige Straßennamen. Baudauer
      0:16 Min - zusammen mit Saarland einer der schnellsten Builds. Release-Asset unter
      `way-graphs-v4` mit `--clobber` ersetzt, `Bundesland.hamburg.approximateSizeMB` auf 22
      aktualisiert.
      - **Meilenstein**: Damit sind **alle 16 deutschen Bundesländer** auf Format v2 (mmap statt
        SQLite) umgestellt - Baden-Württemberg, Bayern, Berlin, Brandenburg, Bremen, Hamburg,
        Hessen, Mecklenburg-Vorpommern, Niedersachsen, Nordrhein-Westfalen, Rheinland-Pfalz,
        Saarland, Sachsen, Sachsen-Anhalt, Schleswig-Holstein, Thüringen. Zusammen mit den drei
        Ländern (Niederlande, Schweden direkt in v2 angelegt; Polen weiterhin offen) ergibt das
        **nur noch Polen** von ursprünglich 18 Regionen im alten Format v1/SQLite - einzige
        verbleibende Region für den vollständigen Rollout.
      - **Größenbilanz nebenbei**: Alle 16 Bundesländer zusammen sind durch v2 spürbar kleiner
        geworden (durchgängig 8-13 % kleiner als die alten v1-Werte, ohne fromNode-Feld pro
        Kante und CSR-Layout statt SQL-Overhead) - kein einziger Build ist größer geworden.
      → [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-v4)
- [x] **Kombinierte Radrouten (mehrere Fernwege verketten)**: Nutzer-Idee, ausgelöst durch eigene
      Erfahrung - Bremen → Hannover per Rad über Weser-Radweg → Aller-Radweg →
      Leine-Heide-Radweg gefahren, die App fand das bisher nicht, weil `RouteMatcher.findMatches`
      immer nur eine einzelne Route matcht. Machbarkeit vorab geprüft (Analyse-Skripte gegen die
      echte `routes.sqlite`): von 7.018 benannten `rcn`/`ncn`/`icn`-Fernwegen haben 99 % mind.
      eine Anschlussstelle (≤30 m) zu einer anderen Route - ein kleiner Graph (~7.000 Knoten),
      winzig verglichen mit dem bereits existierenden Wege-Graphen für `BikeRoutingEngine`.
      - **Datenschicht**: Neues Skript [Scripts/find_route_junctions.py](FahrradApp/Scripts/find_route_junctions.py)
        berechnet Anschlussstellen zwischen benannten Fernwegen (segmentweise STRtree-Suche,
        30-m-Schwellenwert) über alle vier gebündelten Routen-DBs hinweg (auch grenzüberschreitend
        NL/PL/SE) und schreibt sie in eine neue Sidecar-Datei
        [RadFaehrte/Resources/route_junctions.sqlite](FahrradApp/RadFaehrte/Resources/route_junctions.sqlite)
        (Schema `junctions(route_a, route_b, lon, lat, route_a_name, route_b_name)`, beide
        Richtungen gespeichert). ⚠️ **Manuell zu regenerierendes Derivat** - ändert sich eine der
        vier Quell-DBs (neue Relationen, neues Land), muss das Skript erneut laufen, sonst
        veraltet die Kombinationssuche unbemerkt (gleiches Prinzip wie bei den Wege-Graphen).
      - **Wichtiger Datenqualitäts-Fund unterwegs**: Der erste Testlauf verlor sich in Bremens
        eigenem lokalen Knotenpunkt-Wegenetz ("Grüner Ring") statt über den Weser-Radweg zu
        laufen - Ursache: viele Regionen taggen ihr lokales Knotenpunktnetz mit `network=rcn`
        statt `lcn`, am Netzwerk-Tag allein nicht von einem echten Fernweg zu unterscheiden. Zwei
        Namensmuster identifiziert und ausgeschlossen: rein numerisch ("31-32", 812 von 7.018
        Treffern) und Ort+Knotennummer ("Lohne (76) - Dinklage (78)", **3.586 von 7.018 Treffern -
        über die Hälfte aller benannten `rcn`/`ncn`/`icn`-Routen in Deutschland!**). Nach Filter:
        3.676 "echte" Fernwege, 96,5 % davon vernetzt, ⌀ 13,7 Anschluss-Partner.
      - **`RouteRepository`**: neue `route(withId:)`-Einzel-Lookup (gab es bisher nicht, nur
        Bounding-Box-Abfrage) sowie `junctions(forRouteId:)` gegen die neue, optionale
        Sidecar-DB (fehlt sie, leeres Ergebnis statt Absturz). Dafür jetzt `nonisolated final
        class` (wie `WayGraphRepository`/`BikeRoutingEngine`), damit die Kombinationssuche
        abseits des Main-Threads laufen kann.
      - **`RouteMatcher`**: `routeSegmentDistance`s bisher inline in Closures gebauter
        Streckengraph in einen wiederverwendbaren privaten `RouteGraph`-Typ ausgelagert
        (verhaltensgleich, bestehende Tests bestätigen das), dazu eine neue
        `dijkstraDistances`/`routeSegmentDistances`-Variante, die von einem Punkt aus in einem
        Rutsch die Distanzen zu mehreren Zielen liefert statt pro Ziel einzeln zu rechnen. Neue
        `findCombinedMatches(start:end:)`: echter gewichteter Dijkstra über den
        Anschluss-Graphen (Knoten = Route+Einstiegspunkt, Kanten = reale Streckenlänge zur
        nächsten Anschlussstelle) - **bewusst ohne feste Obergrenze an Etappen** (Nutzer-
        Entscheidung, nachdem klar wurde, dass z. B. Bremen → Leipzig plausibel mehr als 2-3
        Etappen braucht), stattdessen zwei Sicherheitsgrenzen gegen ausufernde Suchen (max. 500
        besuchte Routen, Abbruch beim 3-fachen der Luftlinie Start-Ziel).
      - **`ContentView`**: Kombinationssuche greift in `runMatching()` nur als Fallback, wenn
        `findMatches` leer bleibt - und zwar **vor** dem bisherigen `findClosestMatches`-Fallback
        (eine passende Kombination ist nützlicher als eine sachlich unpassende, nur zufällig nahe
        Einzelroute). Neuer `combinedMatch`-State (Geschwister zu `selectedMatch`/
        `isDirectRouteMode`, kein Enum-Umbau der bestehenden Struktur), eigene Ergebniszeile
        (`combinedRouteRow`, z. B. "Weser-Radweg → Aller-Radweg → Leine-Heide-Radweg · 168 km ·
        ca. 11 h"), Kartenlinie über das bestehende `selectedRouteLines`/`routeOverlayContent`
        wiederverwendet (keine Änderung nötig), Connector (`loadCombinedConnectorRoute`) bewusst
        nur an den beiden äußeren Enden, nicht zwischen den Etappen (Anschlüsse sind
        Berühr-/Kreuzungspunkte, keine Lücke zu überbrücken). Navigations-Kopfzeile und
        Apple-Watch-Anbindung zeigen die verkettete Routenbezeichnung statt des generischen
        Platzhalters "Radroute".
      - **Tests**: Per Unit-Test gegen die echte gebundelte Datenbank verifiziert - Bremen →
        Hannover findet die Kette Weser-Radweg → Aller-Radweg → Leine-Heide-Radweg (exakt das
        real gefahrene Nutzerbeispiel), Junction-Sidecar-Daten sowie die Sicherheitsgrenzen sind
        eigens abgesichert.
      - **Live auf dem iPhone verifiziert (2026-07-29)**: München → Nürnberg als zweites
        Testbeispiel ergab unterwegs zwei weitere, direkt behobene Funde:
        1. **Fehlender Ladehinweis**: Die Kombinationssuche kann je nach Region mehrere Sekunden
           dauern (München-Nürnberg: 3,5-4,3 s) - währenddessen zeigte die Ergebnisliste
           fälschlich schon "Keine passende Radroute gefunden" statt eines Ladehinweises, wirkte
           dadurch wie ein Fehlschlag. Neuer `isSearchingCombinedMatch`-State blendet stattdessen
           "Suche nach Routen-Kombination …" mit Fortschrittsanzeige ein.
        2. **Wichtigerer Fund**: `findMatches` fand für München→Nürnberg zunächst einen
           scheinbaren Einzeltreffer (den sehr langen "Radweg D11: Ostsee ↔ Oberbayern"), der sich
           aber erst nachträglich (asynchron, per `routeSegmentDistance`) als unbrauchbar
           herausstellte (Kartenlücke zwischen den beiden Anschlusspunkten) und dann still von
           `filterAndReorderMatchesByPracticalDistance` verworfen wurde - **ohne dass die
           Kombinationssuche oder der `findClosestMatches`-Fallback danach je versucht wurden**,
           weil `runMatching()`s Fallback-Entscheidung schon getroffen war, bevor die Lücke
           überhaupt bekannt war. Das ist ein bereits vorher in der App bestehendes Verhalten
           (nicht neu durch diese Funktion), nur bisher unbemerkt, weil es zuvor einfach zu einer
           leeren Liste ohne jeden Vorschlag führte, statt sichtbar zu werden. **Genereller Fix**
           (nicht auf dieses Beispiel beschränkt): Neue gemeinsame Funktion
           `attemptCombinedThenClosestFallback` wird jetzt aus zwei Stellen aufgerufen - wie
           bisher, wenn `findMatches` von vornherein leer bleibt, und neu zusätzlich aus
           `filterAndReorderMatchesByPracticalDistance`, sobald alle zunächst gefundenen
           Einzeltreffer nachträglich aussortiert werden. `!isFallbackMatches`-Schutz gegen eine
           Endlosschleife, falls sogar die daraus resultierenden "nächstgelegene Vorschläge"
           selbst wieder komplett verworfen werden.
        - Per Live-Debug-Logging (`Documents/combined_match_debug.log`, über `devicectl device
          copy from` ausgelesen - dieselbe kabellose Technik wie beim `heading_debug.log`-Fund,
          s. o. "Bekannte Probleme") auf dem echten Gerät nachvollzogen und beide Fixes dort
          bestätigt: München → Nürnberg findet jetzt eine Kombination (Isar-Radweg → Abens-Radweg
          → Hallertauer Hopfentour → Große-Laber-Radweg → Laber-Abens-Radweg → Zusatzroute
          Laber-Abens-Radweg → Radweg Kelheim-Abensberg → Fünf-Flüsse-Radweg) statt gar nichts.
          Debug-Logging nach Bestätigung wieder vollständig entfernt.
      → [Scripts/find_route_junctions.py](FahrradApp/Scripts/find_route_junctions.py),
      [RadFaehrte/Resources/route_junctions.sqlite](FahrradApp/RadFaehrte/Resources/route_junctions.sqlite),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift)
      (`route(withId:)`, `junctions(forRouteId:)`),
      [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift) (`RouteGraph`,
      `dijkstraDistances`, `routeSegmentDistances`, `CombinedRouteMatch`, `CombinedRouteLeg`,
      `findCombinedMatches`), [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift)
      (`combinedMatch`, `isSearchingCombinedMatch`, `runMatching`,
      `attemptCombinedThenClosestFallback`, `combinedRouteRow`, `combinedMatchSubtitle`,
      `loadCombinedConnectorRoute`), [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift)
- [x] **Bugfix: Doppelte Routen-IDs an Ländergrenzen konnten Treffer duplizieren**: Beim Bau von
      `Scripts/find_route_junctions.py` (s. o.) fiel auf, dass über 150 OSM-Relations-IDs in mehr
      als einer der vier gebündelten DBs auftauchen (`routes.sqlite`/`netherlands.sqlite`/
      `poland.sqlite`/`sweden.sqlite`) - grenzüberschreitende Relationen landen in den
      Geofabrik-Länder-Extrakten mehrfach, jeweils unterschiedlich zugeschnitten. Die bis dahin
      geltende Doku-Annahme "OSM-IDs sind global eindeutig, keine Kollisionsgefahr" war damit
      falsch. `RouteRepository.routesOverlapping(...)` führte Treffer aller vier DBs bisher per
      `flatMap` ohne Deduplizierung zusammen - bei einer grenznahen Suche konnte dieselbe Route
      dadurch als zwei `RouteMatch`-Einträge mit identischer `id` in derselben Trefferliste
      landen: doppelte Zeile im Wisch-Pager (`ForEach(..., id: \.element.id)` verletzt damit die
      SwiftUI-Eindeutigkeitsannahme), Auswahl-Häkchen (`match.id == selectedMatch?.id`) markierte
      beide Duplikate gleichzeitig, und `routeSegmentDistances` (nach `route.id` indiziert) zeigte
      beiden Duplikaten dieselbe (für eines der beiden ggf. falsche) Distanz an. Behoben durch
      Deduplizierung nach `id` beim Zusammenführen in `routesOverlapping(...)` (erster Treffer
      gewinnt, konsistent mit dem bereits bestehenden Verhalten von `route(withId:)`). Bewusst
      unabhängig von der Kombinationssuche oben behoben (eigener, kleiner Fix).
      → [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift)
      (`routesOverlapping`)
- [x] **Kombinationssuche auf A* umgestellt (grenzüberschreitend nutzbar)**: Live-Test
      Vreden→Arnhem (2026-07-29) zeigte, dass die Kombinationssuche zwar technisch schon
      länderübergreifend funktioniert (alle vier Routen-DBs sind immer geladen, die
      Anschluss-Sidecar-DB deckt Grenzübergänge NL/PL/SE mit ab), aber bei sehr weiten
      internationalen Strecken versagen konnte: Bei Berlin→Amsterdam blieb der bisherige reine
      Dijkstra nach Streckenlänge zuverlässig bei `maxVisitedRoutes` (500) hängen, OHNE jemals
      Fortschritt Richtung Ziel zu machen (kumulierte Streckenlänge blieb über alle 500 besuchten
      Routen hinweg bei 0 km) - Ursache: Am Startpunkt Berlin überlagern sich dutzende Fernwege
      (EuroVelo 2, Europaroute D-Route 3, Europaradweg R1, D-Netz Route 3 u. a.) auf denselben
      Wegen mit ~0 km Abstand zueinander, ein reiner Dijkstra erkundet diese alle zuerst, bevor er
      sich überhaupt geografisch bewegt. Behoben durch Umstellung auf A*: Warteschlangen-Priorität
      ist jetzt Streckenlänge **plus** Luftlinie zum Ziel (`CombinedSearchEntry.priority`) statt
      nur der reinen Streckenlänge - Luftlinie ist als Schätzwert zulässig (kann die reale
      Reststrecke nie überschätzen), das Ergebnis bleibt also weiterhin nachweislich die kürzeste
      Kette (bestehende Tests inkl. Bremen→Hannover unverändert bestanden), die Suche bewegt sich
      aber gezielter Richtung Ziel.
      - **Wichtiger Nebenbefund beim Testen**: Berlin→Amsterdam war als Testfall irreführend - die
        real kartierte niederländische EuroVelo-2-Geometrie endet gar nicht in Amsterdam, sondern
        bei Hoek van Holland (~0,4 km Abstand) bzw. Den Haag (~3,3 km), Amsterdam liegt ~26 km
        entfernt (weit außerhalb der 8-km-Schwelle) - passt auch zum echten EuroVelo-2-Verlauf
        (Dublin → London → Hoek van Holland → Berlin → Warschau → Moskau). Amsterdam war also nie
        erreichbar, unabhängig vom Algorithmus. Mit A* + dem korrigierten, fairen Ziel **Berlin→Den
        Haag** klappt die Suche jetzt zuverlässig mit dem regulären `maxVisitedRoutes`-Standardwert
        (500, keine Erhöhung nötig) in ca. 7 s.
      - **Erkenntnis zu `maxVisitedRoutes` als Stellschraube**: Vor der A*-Umstellung testweise
        probiert, das Limit statt A* einfach zu erhöhen - 500 scheiterte nach 8,2 s, 1500 scheiterte
        sogar nach 18,5 s (noch länger, aber immer noch kein Treffer), 5000 fand einen Treffer nach
        17,8 s. Die Dauer skaliert nicht sauber mit der Anzahl besuchter Routen, weil einzelne
        Fernwege stark unterschiedlich große Geometrien haben (z. B. Europaradweg R1 mit 7.359
        Punkten) - ein höheres Limit ist also ein unvorhersehbares Werkzeug (Dauer nicht
        garantiert), A* an der Wurzel des Problems (Prioritätsfunktion) war die deutlich robustere
        Lösung.
      → [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift)
      (`CombinedSearchEntry.priority`, `findCombinedMatches`),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift)
      (`combinedMatchBerlinToDenHaagFindsEuroVelo2Chain`)
- [x] **Kombinationssuche: drei weitere Fixes nach Live-Tests (2026-07-29/30)**:
      - **Knotenpunkt-Netz-Fragmente bereinigt**: Live-Test Berlin→Den Haag zeigte "Knotenpunkt-
        wegweisung Oberhavel", "Knotenpunktnetz Landkreis Ostprignitz-Ruppin" und die Mischform
        "71 - Rübehorst (72)" als Etappen einer gefundenen Kette - lokale Knotenpunkt-Netze, fälschlich
        als Fernweg getaggt, von den beiden bisherigen Namensmustern (s. o.) nicht erfasst. Ergänzt:
        Namen mit "Knotenpunkt" sowie die Mischform "Zahl - Text (Zahl)"/"Text (Zahl) - Zahl", in
        `RouteMatcher.isNodeToNodeSegment` UND `Scripts/find_route_junctions.py` (müssen laut
        Doku-Kommentar synchron bleiben) - Anschluss-Sidecar-DB danach neu gebaut. Nebeneffekt:
        `maxVisitedRoutes` musste von 500 auf 2000 angehoben werden (ohne die (jetzt
        ausgeschlossenen) Kurzschluss-Verbindungen der Knotenpunkt-Fragmente braucht Berlin→Den
        Haag mehr besuchte Routen, um durchgehend "echte" Fernwege zu finden - ~12s statt ~7s).
      - **Ref-Tag-Bonus**: Nutzer-Wunsch, dass die Suche nach Möglichkeit auf demselben bekannten
        Fernweg bleibt (z. B. durchgehend "EV2"), statt rein nach kürzester Gesamtstrecke zu
        optimieren. Neues `RouteRepository.ref(forRouteId:)` (liest nur das `ref`-Tag, ohne
        Geometrie zu dekodieren - günstig für den Aufruf pro Nachbar-Kandidat), 20-km-Bonus in
        `CombinedSearchEntry.priority` bei gleichem `ref` zwischen aufeinanderfolgenden Etappen.
        Hilft nur, wo die Daten mitspielen (bestätigt an einem Fall, wo kein Ref-durchgehender Pfad
        verfügbar war - dort blieb das Ergebnis unverändert, wie erwartet) - kein Ersatz für
        fehlende Konnektivität in den Rohdaten.
      - **Kritischer Bugfix: ID-Kollision führte zu falscher (zu kurzer) Streckenlänge**: Live-Test
        Berlin→Vreden zeigte eine offensichtlich falsche Gesamtstrecke von nur ~134 km (Luftlinie
        allein schon ~451 km!). Ursache: "Europaradweg R1" existiert als ID-Kollision sowohl nahe
        der polnischen als auch der niederländischen Grenze (unterschiedliche Geometrie, s.
        RouteRepository-Header zu Ländergrenz-Kollisionen). Die Kombinationssuche cachte Routen nur
        nach ID (`routeCache: [Int64: BikeRoute]`) - war die ID einmal z. B. als Ziel-Kandidat mit
        der niederländischen Kopie gecacht, nutzte ein späteres Wiederbetreten über eine ganz
        andere (polnische) Verzweigung fälschlich weiter diese falsche Kopie.
        `routeSegmentDistances` projizierte den polnischen Einstiegspunkt dabei stillschweigend auf
        die (Hunderte km entfernte) niederländische Geometrie und wies eine ~500-km-Etappe als
        ~0 km aus. Zwei Fixes: (1) `RouteMatcher.nearestPoint`-Anker in `routeSegmentDistance`/
        `routeSegmentDistances` werden jetzt gegen `maxPlausibleAnchorDistanceKm` (20 km) geprüft -
        ein zu weit entfernter Projektionspunkt ergibt "kein Pfad" statt einer unsinnig kleinen
        Distanz. (2) Neues `RouteRepository.allRoutes(withId:)` (alle Kopien über alle vier DBs,
        statt `route(withId:)`s blindem "erster Treffer gewinnt") - `findCombinedMatches`s
        `route(withId:near:)` löst bei einer ID-Kollision jetzt anhand des aktuellen
        Einstiegspunkts neu auf, statt eine möglicherweise falsche Kopie zu cachen (bewusst kein
        Cache über die ID allein mehr - `finalized` sorgt ohnehin dafür, dass jede ID höchstens
        einmal verarbeitet wird, ein Cache hätte hier nichts eingespart, aber genau diesen Fehler
        ermöglicht). Nach dem Fix: Berlin→Vreden korrekt bei ~838 km über 20 durchgehend plausible
        Etappen. Per Regressionstest abgesichert (prüft: Gesamtstrecke nie kürzer als Luftlinie,
        keine einzelne Etappe überbrückt eine unplausibel große Lücke).
      → [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift)
      (`isNodeToNodeSegment`, `maxPlausibleAnchorDistanceKm`, `sameRefPriorityBonusKm`,
      `route(withId:near:)`), [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift)
      (`ref(forRouteId:)`, `allRoutes(withId:)`), [Scripts/find_route_junctions.py](FahrradApp/Scripts/find_route_junctions.py),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift)
      (`combinedMatchBerlinToVredenHasPlausibleTotalDistance`)
- [x] **Hinweis, wenn eine bekannte EuroVelo-/D-Route in der Nähe liegt, aber nicht nutzbar war**:
      Nutzer-Beobachtung (2026-07-30, mehrere Live-Tests: Berlin↔Vreden, Münster↔Aachen,
      Münster↔Leverkusen): Erwartete "berühmte" Fernwege (EuroVelo 2, EuroVelo 3) tauchen in der
      gefundenen Kombination nicht auf, obwohl sie in der Nähe liegen - Ursache (bereits weiter
      oben dokumentiert) sind echte Lücken in deren OSM-Kartierung, kein Bug. Damit das nicht wie
      ein Versäumnis der App wirkt, prüft `RouteMatcher.nearbyWellKnownRoutes(around:)` jetzt
      unabhängig vom Suchergebnis, ob eine Route mit bekanntem `ref`-Muster ("EV1"-"EV19",
      "D1"-"D12") in der Nähe von Start oder Ziel liegt. Taucht ihr `ref` nicht unter den
      tatsächlich verwendeten Etappen/Treffern auf, zeigt `ContentView` einen kleinen Hinweistext
      ("EuroVelo 3 verläuft hier in der Nähe, ist an dieser Stelle aber nicht durchgehend
      kartiert."). Nur relevant, wenn `findMatches` keinen sauberen Direkttreffer fand (dann stellt
      sich die Frage nicht) - berechnet in `attemptCombinedThenClosestFallback`, unabhängig davon,
      ob am Ende eine Kombination, nächstgelegene Vorschläge oder gar nichts gefunden wurde.
      → ⚠️ **Überholt (2026-07-31)**: Der reine Text-Hinweis wurde durch einen echten, wählbaren
      Treffer ersetzt (s. u. "Routen mit Kartenlücke bleiben sicht- und wählbar...") -
      `nearbyWellKnownRoutes`/`nearbyWellKnownRouteHint`/`nearbyWellKnownRouteHintView` existieren
      nicht mehr.
- [x] **Kombinationssuche: mehrere Alternativen statt nur der einen besten Kette**: Nutzer-Wunsch
      (2026-07-30) - genau wie bei einzelnen Radrouten (`matches`/`matchesPager`, z. B. Bremen →
      Achim) soll man auch bei einer Kombination mehrerer Fernwege durch Alternativen wischen
      können, z. B. um eine bekannte EuroVelo-Route zu wählen, auch wenn eine andere Kombination
      technisch (marginal) kürzer ist. `findCombinedMatches` bricht jetzt nicht mehr beim ersten
      Erreichen des Ziels ab, sondern sammelt bis zu `maxAlternatives` (Standard 3) verschiedene
      Ketten weiter (jede endet zwangsläufig über eine andere letzte Etappen-Route, da `finalized`
      ein erneutes Verarbeiten derselben Route-ID verhindert - Alternativen unterscheiden sich also
      immer mindestens im letzten Wegstück), sortiert nach Gesamtstrecke. Rückgabetyp geändert von
      `CombinedRouteMatch?` zu `[CombinedRouteMatch]` (leeres Array statt `nil`). `ContentView`:
      neuer `combinedMatches`-State (alle Alternativen) neben `combinedMatch` (aktuell
      ausgewählte/angezeigte, wie schon `selectedMatch` bei `matches`), neuer `combinedMatchesPager`
      analog zu `matchesPager`. **Preis dafür: spürbar längere Suchzeit** bei den ohnehin schon
      langsamen internationalen Extremfällen (Berlin→Vreden: ~10s → ~23s, Berlin→Den Haag: ~15s →
      ~19s, im Simulator gemessen) - normale/kürzere Kombinationen (Bremen→Hannover: 2,9s) bleiben
      dagegen schnell, da dort ohnehin früh ein Ergebnis gefunden wird und kaum zusätzliches Budget
      für Alternativen verbraucht wird.
      → [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift) (`findCombinedMatches`),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`combinedMatches`,
      `combinedMatchesPager`, `pagedCombinedMatchIndex`),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **Anschluss-Schwellenwert der Kombinationssuche von 30 auf 75 m angehoben**: Nutzer-Beispiel
      (2026-07-30) Lübeck → Wismar fand keine Kombination, obwohl naheliegend gewesen wäre: "Alte
      Salzstraße" (Lübeck → Travemünde) und der "Ostseeküsten-Radweg"/D2 (Travemünde → Wismar)
      treffen sich in Travemünde erkennbar. Per Analyse-Skript gegen die echte Geometrie gemessen:
      tatsächliche Distanz dort **60,6 m** (vermutlich unterschiedliche Straßenseiten/Hafen- bzw.
      Fähranleger-Bereich in Travemünde) - knapp über dem bisherigen `JUNCTION_THRESHOLD_M` von
      30 m in [find_route_junctions.py](FahrradApp/Scripts/find_route_junctions.py). Anders als der
      EuroVelo-Fund oben (echte Lücke in der OSM-Kartierung selbst) war das hier also ein zu strikt
      gewählter Schwellenwert im eigenen Analyse-Skript, kein Datenproblem.
      - Auf 75 m angehoben, `route_junctions.sqlite` neu regeneriert. Kanten wachsen dabei nur
        moderat (24.067 → 24.314 ungerichtete Kanten, +8 zusätzlich vernetzte Routen von 3.517 auf
        3.525) - Stichprobe der neu hinzugekommenen Kanten zeigte ausschließlich plausible,
        geografisch benachbarte Fernweg-Paare (u. a. Fluss-Zusammenflüsse wie Unstrutradweg/
        Saaleradweg), keine erkennbaren Fehlverbindungen. Bestehende Sanity-Check-Referenzbeispiele
        (Weser-/Aller-/Leine-Heide-Radweg) weiterhin unverändert gefunden.
      - Per Regressionstest gegen die echte Datenbank abgesichert
        (`combinedMatchLuebeckToWismarFindsRouteChainViaTravemuende`) - Start-/Zielpunkte liegen
        rechnerisch bestätigt innerhalb der 8-km-Matching-Schwelle (Lübeck ~600 m, Wismar ~121 m zur
        jeweiligen Route).
      - **Zweiter, unabhängiger Fund beim Live-Test auf dem iPhone**: Trotz der neuen Anschlussstelle
        blieb `findCombinedMatches` zunächst leer. Per temporärem Debug-Logging (`print`, direkt im
        Testlauf auf dem Gerät, danach wieder entfernt) nachvollzogen: Die Kette erreichte "D2
        Ostseeküsten-Radweg - Abschnitt MV-Nordwest" (die Wismar abdeckt), aber diese Route zerfiel
        selbst intern in mehrere unzusammenhängende Teile - der Übergangspunkt aus Richtung
        Travemünde lag in einer 117-Knoten-Komponente, der Punkt bei Wismar in einer separaten
        482-Knoten-Komponente, realer Abstand dazwischen nur **~4 m**. Ursache: Die Douglas-Peucker-
        Vereinfachung läuft pro OSM-Way einzeln (`extract_bicycle_routes.py`/`build_way_graph.py`);
        liegt der Berührpunkt zweier Wege nicht exakt an einem Way-Anfang/-Ende (die immer erhalten
        bleiben), sondern mitten in einem Way, können beide Vereinfachungen ihn unabhängig
        voneinander um bis zu ~11 m verschieben. `RouteMatcher.RouteGraph.snapKey` rundete bisher
        nur auf ~1,1 m (5 Nachkommastellen) - zu fein, um solche Fast-Treffer als denselben Knoten
        zu erkennen. Auf ~11 m angehoben (4 Nachkommastellen, passend zu `SIMPLIFY_TOLERANCE_DEG`).
        Kompletter bestehender Test-Suite-Lauf (17 Tests, u. a. Weser/Aller/Leine-Heide-,
        Bremen/Hannover-, Berlin/Vreden-, Berlin/Den-Haag-Ketten) blieb dabei unverändert grün -
        keine erkennbaren Regressionen.
      - **Live auf dem iPhone verifiziert (2026-07-30)**: Lübeck → Wismar zeigt jetzt zwei
        plausible, durchgehende Einzeltreffer statt "keine Route gefunden" - "EuroVelo 13 - Iron
        Curtain Trail - Inner German part" (~91,2 km auf der Route, ~4,0 km Anfahrt, Verlauf
        entlang der Ostseeküste über Travemünde/Boltenhagen) und "Radrundwege zwischen Ostsee und
        Seenplatte" (~91,5 km, ~6,7 km Anfahrt, südlicherer Verlauf über Gadebusch/Zarrentin).
        Bemerkenswert: Nicht die ursprünglich gesuchte kombinierte Kette "Alte Salzstraße →
        Ostseeküsten-Radweg" wird angezeigt, sondern zwei bereits vorher in der DB vorhandene
        Einzelrouten, die durch denselben `snapKey`-Fix jetzt an einer *anderen* Stelle intern
        durchgängig wurden - `findMatches` (Einzeltreffer) hat in `ContentView.runMatching()`
        ohnehin Vorrang vor der Kombinationssuche, das Ergebnis ist hier sogar besser (echte
        durchgehend beschilderte Route statt selbst zusammengesetzter Kette).
      → [Scripts/find_route_junctions.py](FahrradApp/Scripts/find_route_junctions.py)
      (`JUNCTION_THRESHOLD_M`), [RadFaehrte/Resources/route_junctions.sqlite](FahrradApp/RadFaehrte/Resources/route_junctions.sqlite),
      [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift) (`RouteGraph.snapKey`),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift)
      (`combinedMatchLuebeckToWismarFindsRouteChainViaTravemuende`)
- [x] **Etappen-Übersicht für kombinierte Routen**: Nutzer-Beobachtung (2026-07-30, Beispiel
      Bremen → München mit 4 Etappen): Der Titel-Text in `combinedRouteRow`
      (`routeNames.joined(separator: " → ")`) schneidet bei langen Ketten in der schmalen
      Ergebniszeile sichtbar ab ("Weser - Romantische Straße → Energieroute Radweg → Aller-Radweg
      → Leine-Hei…"), ohne dass man die vollständige Kette einsehen kann. Mehrere Ansätze
      durchdacht (mehrzeiliger Titel, interaktive Kartensegmente, eigener Navigations-Screen) -
      Nutzer-Entscheidung: Info-Button (`list.bullet`-Icon) neben der Ergebniszeile öffnet ein
      Sheet mit allen Etappen untereinander (Routenname + Streckenlänge je Etappe), analog zum
      bestehenden `tourSummarySheet`-Muster. Neuer `combinedRouteDetail`-State (Geschwister zu
      `tourSummary`, gleiches `.sheet(item:)`-Muster). Live auf dem iPhone verifiziert.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`combinedRouteDetail`,
      `combinedRouteRow`, `combinedRouteDetailSheet`), [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **Kartenlinie bei kombinierten Routen: nur genutztes Teilstück statt komplette Routen-
      Geometrie**: Nutzer-Beobachtung (2026-07-30, Bremen → Hannover): Die Karte zeigte für die
      4-Etappen-Kette ein unübersichtliches Liniengewirr statt einer klaren Strecke. Ursache:
      `ContentView`s `selectedRouteLines` zeichnete pro Etappe die komplette Geometrie der
      jeweiligen benannten Route (`route.lines`, inkl. aller Zweige/Nebenäste), nicht nur das
      zwischen Ein- und Ausstiegspunkt tatsächlich genutzte Teilstück - bei vier gestapelten
      kompletten Routen samt Nebenästen entsteht dadurch das Gewirr. Nutzer-Erwartung (bestätigt):
      eine einzelne durchgehende Linie, die exakt der befahrenen Strecke folgt - wie bei einer
      Einzelroute. Bewusst nur für kombinierte Routen behoben, nicht für einzelne `RouteMatch`es
      (dort bislang keine Beschwerde, zeigt weiterhin die komplette offizielle Routen-Geometrie).
      - Neue Funktion `RouteMatcher.routeSegmentPath` (Gegenstück zu `routeSegmentDistance`) gibt
        den per Dijkstra gefundenen Pfad als Koordinatenliste zurück statt nur die Länge - dafür
        `RouteGraph` um eine Knoten→Koordinate-Rückabbildung (`coordinates`) ergänzt.
      - `CombinedRouteLeg` bekommt ein neues `pathCoordinates`-Feld, `CombinedRouteMatch.legs` von
        `let` auf `var` geändert. Bewusst **nicht** während der eigentlichen A*-Suche berechnet
        (wäre für jeden erkundeten Kandidaten unnötig teuer), sondern erst nachträglich für die am
        Ende tatsächlich zurückgegebenen Ketten (`maxAlternatives`, Standard 3) - hält die Suche
        selbst unverändert schnell.
      - `ContentView.selectedRouteLines` nutzt für kombinierte Routen jetzt `pathCoordinates` statt
        `route.lines`, mit Fallback auf die komplette Geometrie, falls `routeSegmentPath`
        ausnahmsweise `nil` liefert.
      - Komplette Test-Suite (17 Tests) blieb dabei unverändert grün. Live auf dem iPhone
        verifiziert (Bremen → Hannover zeigt jetzt eine klare durchgehende Linie).
      → [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift) (`RouteGraph.coordinates`,
      `routeSegmentPath`, `CombinedRouteLeg.pathCoordinates`), [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift)
      (`selectedRouteLines`)
- [x] **`RouteGraph`-Rundungsraster von ~11 m auf ~28 m angehoben (bundesweite Auswirkung)**:
      Nutzer-Beobachtung (2026-07-30): Bremen → Osnabrück zeigte früher "Brückenradweg Westroute"
      als Treffer, nach dem München-Nürnberg-Fix vom 29.07. (verwirft Treffer ohne auffindbaren
      Pfad) aber nicht mehr. Auf Nutzer-Wunsch näher untersucht, ob derselbe Simplification-
      Artefakt-Fehler wie beim Ostseeküsten-Radweg (s. o.) auch andernorts auftritt.
      - **Bundesweite Stichprobe** über alle 7.018 benannten rcn/ncn/icn-Fernwege in
        `routes.sqlite`: 1.243 (17,7 %) zerfallen intern in mehr als eine Komponente, davon 705
        (10 % aller Fernwege!) mit einer kleinsten Lücke unter 40 m - also vermutlich Simplification-
        Artefakt statt echter Datenlücke (u. a. Deutscher Limes-Radweg, Bodensee-Radweg,
        Rhein-Route, Radfernweg Hamburg-Bremen, Spreeradweg betroffen). Konkret: "Brückenradweg
        Westroute" hat mehrere 7-26-m-Übergänge zwischen sonst identifizierten "Komponenten" -
        alles Simplification-Artefakte, keine echte Lücke. "Brückenradweg Ostroute" dagegen hat
        eine tatsächliche ~67-km-Lücke zwischen zwei Teilstücken.
      - Toleranz in `RouteGraph.snapKey` von 0,0001° (~11 m) auf 0,00025° (~28 m) angehoben -
        theoretisch begründet, weil zwei unabhängig vereinfachte Ways sich am selben Berührpunkt
        um je bis zu 11 m in entgegengesetzte Richtungen verschieben können (~22 m Gesamtabstand
        im ungünstigsten Fall), plus kleine Sicherheitsmarge.
      - ⚠️ **Wichtiger Befund unterwegs**: Grid-Rundung ist nicht streng monoton - eine testweise
        noch größere Toleranz (~44 m) verschmolz die Brückenradweg-Ostroute fälschlich über die
        tatsächlich ~67 km entfernte zweite Komponente hinweg (Zufallstreffer durch
        Raster-Ausrichtung an den Koordinatenwerten, keine echte Verbindung) - deshalb bewusst bei
        ~28 m geblieben statt weiter zu erhöhen. Bei ~28 m bleibt die Ostroute korrekt bei
        2 getrennten Komponenten.
      - Bei ~28 m lösen sich 407 der 1.243 fragmentierten Routen vollständig zu einer Komponente
        auf (u. a. "Brückenradweg Westroute", "Eiszeitroute"), 404 weitere verbessern sich
        zumindest (u. a. "Deutscher Limes-Radweg" 9→4, "Wasserburgen-Route" 9→2). Stichprobe der
        stärksten Verschmelzungen gegengecheckt (Bounding-Boxes ergeben geografisch plausible,
        zusammenhängende Korridore, keine erkennbaren Fehlverschmelzungen unabhängiger Strecken).
      - Komplette Test-Suite (18 Tests, neu: `routeSegmentDistanceFindsBridgeCyclewayWestrouteBremenToOsnabrueck`)
        blieb grün. Live auf dem iPhone verifiziert: Bremen → Osnabrück findet jetzt wieder
        "Brückenradweg Westroute" (~162 km) als Treffer, "Ostroute" bleibt korrekt ausgeschlossen.
      → [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift) (`RouteGraph.snapKey`),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift)
      (`routeSegmentDistanceFindsBridgeCyclewayWestrouteBremenToOsnabrueck`)
- [x] **Kombinationssuche läuft jetzt immer zusätzlich, auch wenn schon Einzeltreffer existieren**:
      Nutzer-Beobachtung (2026-07-30, Bremen → Münster): EuroVelo 3 und D7 Pilgerroute wurden
      korrekt gefunden, Nutzer-Idee: zusätzlich auch Kombinationen (z. B. Brückenradweg +
      Friedensroute) als Alternative anbieten, falls die kürzer/direkter sind als die gefundenen
      kompletten Fernwege. Bisher lief `findCombinedMatches` ausschließlich als Fallback, wenn
      `findMatches` leer blieb (`attemptCombinedThenClosestFallback`) - beide Zweige schlossen sich
      in `resultsSection` gegenseitig aus.
      - Abwägung durchdacht (Performance: Kombinationssuche kann bei internationalen Extremfällen
        10-35 s dauern, s. o.) - Entscheidung: nicht blockierend vorschalten, sondern nach
        gefundenen Einzeltreffern **zusätzlich** im Hintergrund laufen lassen und als eigene
        Sektion unterhalb ergänzen, sobald fertig - kein gefühltes Warten für den Normalfall.
      - Neue Funktion `attemptCombinedSearchAsAdditionalOption` (Geschwister zu
        `attemptCombinedThenClosestFallback`, aber ohne dessen `findClosestMatches`-Fallback, der
        hier unpassend wäre) - setzt bewusst nur `combinedMatches` (Liste für den Pager), nicht
        `combinedMatch` selbst, damit die gerade aktive Auswahl (Direkte Fahrrad-Route/
        Einzeltreffer) nicht durch `onChange(of: combinedMatch)` stillschweigend auf die
        Kombination umspringt - der Nutzer wählt sie bewusst per Antippen aus.
      - `resultsSection` zeigt Einzeltreffer und (falls gefunden) Kombination jetzt als zwei
        getrennte, untereinanderstehende Sektionen statt sich gegenseitig auszuschließen - bewusst
        nicht in einer gemeinsam sortierten Liste gemischt, damit transparent bleibt, was eine
        echte beschilderte Route ist und was die App selbst zusammengesetzt hat.
      - Komplette Test-Suite (18 Tests) blieb grün, live auf dem iPhone installiert.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`runMatching`,
      `attemptCombinedSearchAsAdditionalOption`, `resultsSection`),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **Knotenpunkt-Namensfilter robuster gemacht (Vorbereitung für einen evtl. größeren
      Anschluss-Schwellenwert)**: Nutzer-Beispiel (2026-07-30) Bremen → Münster - "Brückenradweg"
      und "Friedensroute" verbinden sich in den OSM-Daten tatsächlich nicht (echte ~280-290 m
      Lücke bei Osnabrück, keine Simplification-Artefakt). Naheliegender erster Impuls, den
      `JUNCTION_THRESHOLD_M` einfach weiter hochzusetzen (z. B. auf 300 m), wurde geprüft und
      **bewusst verworfen**: Testlauf bei 300 m ergab 1.067 neue Anschlusskanten bundesweit -
      Stichprobe von 50 zeigte zwar meist plausible echte Fernweg-Kreuzungen, aber auch konkrete
      Fehltreffer wie "OSL 37-46" ↔ "OSL36-58" oder die nackte Zahl "37" ↔ "Paneuropa Route" -
      lokale Knotenpunkt-Netz-Fragmente, die der bestehende `is_node_to_node_segment`-Filter
      (zuletzt erweitert beim Berlin→Den-Haag-Fund) nicht erfasste.
      - Zwei neue, gezielt geprüfte Muster ergänzt: nackte Zahl (`^\d+$`, 1 Treffer in der
        gesamten DB) und Präfix+Zahl-Bindestrich-Zahl (`^[A-Za-zÄÖÜäöüß]{1,6}\d+-\d+$`, z. B.
        "OSL 37-46"/"Route 14-15", 40 Treffer) - beide gegen alle 7.018 benannten Routen
        gegengeprüft, keiner der Treffer sieht wie eine echte Fernweg-Route aus.
      - Ein drittes, breiteres Muster ("beliebiger Name, endet auf '(Zahl)'", 21 Treffer) bewusst
        **nicht** ergänzt - darunter "Fünf-Flüsse-Radweg (07)", eine Route, die nachweislich schon
        Teil einer echten Kombination war (München→Nürnberg). Ob "(07)" eine Etappennummer oder
        ein Knotenpunkt-Verweis ist, ließ sich ohne die zugrundeliegenden OSM-Tags nicht sicher
        klären - Risiko eines Fehlausschlusses höher als bei den beiden engen Mustern.
      - `route_junctions.sqlite` mit dem erweiterten Filter neu regeneriert (weiterhin bei
        `JUNCTION_THRESHOLD_M = 75.0`, **nicht** auf 300 m erhöht - der Filter allein reduziert das
        Risiko, beseitigt es aber nicht vollständig, da vermutlich noch nicht alle regionalen
        Knotenpunkt-Namenskonventionen bekannt sind). Sanity-Check unverändert (Weser/Aller/
        Leine-Heide weiterhin gefunden), komplette Test-Suite (18 Tests) blieb grün.
      → [Scripts/find_route_junctions.py](FahrradApp/Scripts/find_route_junctions.py)
      (`NODE_TO_NODE_NAME_PATTERNS`), [RadFaehrte/Resources/route_junctions.sqlite](FahrradApp/RadFaehrte/Resources/route_junctions.sqlite)
- [x] **Korrektur + robusterer Fix: "Brückenradweg Ostroute" hatte doch nur eine 4-m-Lücke, nicht
      ~67 km wie oben fälschlich dokumentiert**: Die ~67-km-Angabe im Eintrag "`RouteGraph`-
      Rundungsraster von ~11 m auf ~28 m angehoben" oben war ein **eigener Rechenfehler** bei der
      Diagnose (Raster-Indizes statt echter Koordinaten in eine Distanzformel eingesetzt - ergab
      eine sinnlose, zu große Zahl). Auf Nutzer-Nachfrage ("warum wird die Ostroute nicht
      angezeigt") mit voller Präzision (shapely) neu nachgerechnet: tatsächliche Lücke nur **~4 m**
      - exakt derselbe Simplification-Artefakt wie bei der Westroute, keine echte Kartenlücke.
      - **Warum die reine Rasterrundung (auch bei ~28 m Zellgröße) das trotzdem nicht verband**:
        Grid-Rundung prüft nicht "sind zwei Punkte näher als X Meter", sondern "fallen beide in
        dieselbe Rasterzelle" - zwei Punkte nur 4 m auseinander, aber auf entgegengesetzten Seiten
        einer Zellgrenze, landen trotzdem in unterschiedlichen Zellen. Ein grundsätzliches Problem
        der Methode, nicht nur eine Frage der Zellgröße.
      - **Fix**: `RouteGraph.node(for:)` durchsucht jetzt beim Einfügen eines Punkts die 3×3
        umliegenden Rasterzellen (nicht nur die eigene) und vergleicht Kandidaten per echter
        Distanz (`toleranceMeters = 28`) statt reiner Zellzugehörigkeit - eliminiert die
        Grenzfall-Empfindlichkeit. `cellIndex` (Zelle -> mehrere Knoten möglich) ersetzt das
        bisherige `nodeIndex` (Zelle -> genau ein Knoten).
      - **Zwei Nachbesserungen unterwegs, beide durch Testläufe gefunden**: (1) Erste
        Zellgröße (0,0003°) war zu klein - Meter pro Längengrad schrumpft mit `cos(Breite)`, bei
        deutschen Breiten (~52-55°N) deckte die Zelle in Ost-West-Richtung die 28-m-Toleranz nicht
        mehr ab (~20-24 m statt 28 m), wodurch die ±1-Zellen-Nachbarschaft echte Treffer verpasste
        (Regression: Lübeck→Wismar- und Brückenradweg-Tests schlugen erst fehl). Auf 0,001° erhöht
        - deckt auch bei den nördlichsten unterstützten Breiten (Schweden, ~69°N) noch zuverlässig
        mehr als die Toleranz pro Zelle ab. (2) `CLLocation.distance` (echte Geodäten-Berechnung)
        für den Kandidaten-Vergleich war zu teuer (Berlin→Vreden 22s → 69s) - durch eine ebene
        Näherung (`approxMeters`) ersetzt, auf dieser Skala (~28 m) vom Ergebnis nicht
        unterscheidbar, aber deutlich schneller. Die eigentlichen Kantengewichte (`addEdge`)
        nutzen weiterhin die exakte `CLLocation`-Distanz.
      - ⚠️ **Bekannte Regression, bewusst zurückgestellt statt weiter untersucht (Nutzer-
        Entscheidung)**: `combinedMatchBerlinToDenHaagFindsEuroVelo2Chain` findet seitdem keine
        Kette mehr (Suche läuft komplett durch, ~50-57s, bleibt aber leer - auch mit
        `maxVisitedRoutes` testweise auf 4000 verdoppelt unverändert). Vermutete Ursache: Die jetzt
        bundesweit verbesserte interne Verbindungsfähigkeit vieler Routen ändert die Reihenfolge,
        in der Routen während der A*-Suche als `finalized` markiert werden - eine für die Kette
        nötige Route wird vermutlich vorzeitig über einen ungünstigen Einstiegspunkt finalisiert.
        Berlin → Den Haag ist ein extremer, seltener Randfall (mehrere Länder, dutzende sich in
        Berlin überlagernde internationale Fernwege) - der reale Nutzen der Nachbarschaftssuche für
        alltägliche deutsche Regionalfälle wiegt höher. Test bewusst deaktiviert
        (`.disabled(...)`) statt gelöscht, damit er bei einer künftigen Untersuchung der
        `finalized`-Reihenfolge sofort wieder verfügbar ist.
      - Komplette Test-Suite (18 Tests, davon 1 bewusst deaktiviert) blieb sonst grün, inkl. neuem
        `routeSegmentDistanceFindsBothBridgeCyclewayRoutesBremenToOsnabrueck` (ersetzt den alten,
        auf der falschen 67-km-Annahme basierenden Test - findet jetzt für **beide**
        Brückenradweg-Varianten einen durchgehenden Pfad). Live auf dem iPhone installiert.
      → [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift) (`RouteGraph.node(for:)`,
      `RouteGraph.cellIndex`, `RouteGraph.approxMeters`, `RouteGraph.toleranceMeters`),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift)
      (`routeSegmentDistanceFindsBothBridgeCyclewayRoutesBremenToOsnabrueck`,
      `combinedMatchBerlinToDenHaagFindsEuroVelo2Chain` - deaktiviert)
- [x] **Bugfix: Brückenradweg/Friedensroute fehlten je nach Suchrichtung in der Nähe-Vorschau**:
      Nutzer-Meldung: Bei "Bremen" als Start zeigte `findNearby` (Vorschau vor Zieleingabe, s. o.)
      beide Brückenradweg-Varianten, bei "Osnabrück" als Start keine - obwohl der Brückenradweg
      genau dazwischen verläuft und an beiden Enden nah genug liegt. Dasselbe bei Osnabrück/
      Münster mit der Friedensroute. Ursache: An Fernwege-Knotenpunkten wie Osnabrück/Münster
      liegen sehr viele benannte Routen fast exakt am Suchpunkt (0-0,5 km) - darunter (1)
      Knotenpunkt-Wegstücke lokaler Netze, die als scheinbar eigenständige Route auftauchen (z. B.
      "Münster (1) - Münster (74)"), und (2) dieselbe Route mehrfach in der Datenbank (Land-/
      Relationsgrenzen, z. B. "Friedensroute", "Friedensroute (West)", "Friedensroute (Ost)" -
      alle mit `ref` "FR"). Das feste `limit` (ursprünglich 10) füllte sich damit, bevor der
      gesuchte Fernweg an die Reihe kam - und zwar unterschiedlich stark je nach Endpunkt, daher
      die Asymmetrie. Per Python-Nachbau des Algorithmus gegen die echte `routes.sqlite`
      nachgerechnet und die genaue Rangfolge bestätigt (Brückenradweg Ostroute lag von Osnabrück
      aus z. B. auf Rang 21).
      - **Fix, zwei Schritte**: Zuerst Knotenpunkt-Fragmente ausgeschlossen (`isNodeToNodeSegment`,
        wie schon in `combinableRoutes`) und Mehrfach-Einträge nach `ref` dedupliziert (nächster
        Treffer pro Schlüssel gewinnt) - das brachte beide Brückenradweg-Varianten zurück, ließ
        aber von der Friedensroute nur noch die zusammenfassende "Friedensroute" übrig, nicht
        mehr "(West)"/"(Ost)" (Nutzer-Nachtest deckte das auf: anders als beim Brückenradweg, wo
        Ost-/Westroute unterschiedliche `ref`-Werte haben, teilen sich alle drei Friedensroute-
        Einträge denselben `ref` "FR"). Nachgebessert: Namen mit Richtungs-/Etappen-Zusatz (Muster
        `isSubRouteVariant`, z. B. "(West)"/"(Ost)"/"(Nord)"/"(Süd)" am Ende oder "Teil "/"Etappe "/
        "Part " + Zahl) sind von der Ref-Deduplizierung ausgenommen und bleiben immer als eigener
        Treffer erhalten.
      - Diese Ausnahme verbraucht an Orten mit mehreren solchen Richtungsvarianten-Familien
        gleichzeitig (Münster: "100 Schlösser Route" Nord/Süd, "Historische Stadtkerne" mit
        mehreren Etappen, zusätzlich zur Friedensroute) selbst wieder Plätze - `limit` deshalb in
        einem zweiten Schritt von 15 auf 20 angehoben, nachdem ein erneuter Nachbau-Testlauf
        zeigte, dass sonst wieder einzelne Treffer knapp herausfielen.
      - Regressionstest `findNearbyShowsBridgeCyclewayAndPeaceRouteFromBothEndpoints` ergänzt
        (prüft alle vier Fälle: beide Brückenradweg-Varianten von Bremen/Osnabrück aus, beide
        Friedensroute-Teiletappen von Osnabrück/Münster aus). Komplette Test-Suite blieb grün,
        vom Nutzer live auf dem iPhone in beiden Suchrichtungen (Brücken­radweg, Friedensroute)
        verifiziert.
      → [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift) (`findNearby`,
      `isSubRouteVariant`, `subRouteVariantPatterns`),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift)
      (`findNearbyShowsBridgeCyclewayAndPeaceRouteFromBothEndpoints`)
- [x] **Routen mit Kartenlücke bleiben sicht- und wählbar statt zu verschwinden/nur als Text-Hinweis
      zu erscheinen**: Nutzer-Meldung 2026-07-31 (Beispiel Münster -> Köln): "EuroVelo 3 - Pilgrim's
      Route - part Germany verläuft hier in der Nähe, ist an dieser Stelle aber nicht durchgehend
      kartiert" wurde nur als reiner Text-Hinweis unterhalb der Ergebnisse gezeigt, die Route selbst
      war nicht antippbar - ausdrücklich nicht nur für diesen einen Fall gemeldet, sondern als
      allgemeines Problem ("solche Hinweise gibt es ganz häufig"). Zwei unabhängige Ursachen
      gefunden und behoben:
      1. **`filterAndReorderMatchesByPracticalDistance` entfernte Treffer ohne auffindbaren Pfad
         zwischen den Anschlusspunkten komplett** (`matches.removeAll { ... return true ...}` bei
         `nil`-Segment) - obwohl der bestehende Code-Kommentar/die Roadmap-Notiz zur vorherigen
         Änderung ("Sortierung nach real zu fahrender Gesamtstrecke...") bereits das gegenteilige
         Verhalten beschrieb ("Treffer ohne auffindbaren Pfad landen dabei ans Ende"). Der schon
         vorhandene "Kartendaten hier lückenhaft"-Hinweis in `subtitle(for:)` (s. o. "Lücken in der
         Routen-Geometrie erkennbar machen") wurde dadurch faktisch nie sichtbar, da der Treffer im
         selben synchronen Callback-Durchlauf entfernt wurde, bevor ein UI-Frame gerendert werden
         konnte. Jetzt werden nur noch zu kurze Segmente entfernt (`< minimumRouteSegmentKm`);
         Treffer mit echter Kartenlücke bleiben erhalten und landen (wie schon dokumentiert, jetzt
         auch tatsächlich umgesetzt) durch `practicalDistanceKm`s Unendlich-Rückgabe automatisch am
         Ende der Liste.
      2. **Der EuroVelo-/D-Routen-Hinweis selbst war nur Text, kein Treffer**: `RouteMatcher.
         nearbyWellKnownRoutes` lieferte nur `(ref, name)`-Tupel für die Anzeige eines Hinweistextes
         (`ContentView.nearbyWellKnownRouteHint`/`nearbyWellKnownRouteHintView`). Ersetzt durch
         `nearbyWellKnownRouteMatches(start:end:)`, das vollwertige `RouteMatch`-Einträge liefert
         (Distanz zu Start/Ziel wie bei `findClosestMatches` ohne Schwellenwert-Prüfung berechnet,
         da die Route ja oft nur an einem Ende in der Nähe liegt). Diese werden jetzt über die neue
         Hilfsfunktion `ContentView.appendNearbyWellKnownMatches` an `matches` angehängt (dedupliziert
         gegen bereits verwendete `ref`s aus Einzeltreffern/Kombinationen sowie gegen schon
         vorhandene Treffer-IDs) - sowohl im ursprünglichen Fallback-Pfad
         (`attemptCombinedThenClosestFallback`, wenn `findMatches` leer blieb) als auch im
         parallelen Kombinationssuche-Pfad (`attemptCombinedSearchAsAdditionalOption`, wenn schon
         Einzeltreffer vorlagen - z. B. Bremen -> Münster, wo EuroVelo 3 nur an einem Ende in
         Reichweite liegt). Die Text-Hinweis-Variante (`nearbyWellKnownRouteHint`-State,
         `nearbyWellKnownRouteHintView`) komplett entfernt, da die Route jetzt als normaler,
         wählbarer Eintrag im Wisch-Pager erscheint - zeigt bei echter Kartenlücke automatisch
         "Kartendaten hier lückenhaft" statt einer Streckenlänge (Fix 1), bleibt aber sichtbar und
         antippbar. `HowItWorksView` entsprechend aktualisiert.
      → [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift)
      (`nearbyWellKnownRouteMatches`), [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift)
      (`appendNearbyWellKnownMatches`, `attemptCombinedThenClosestFallback`,
      `attemptCombinedSearchAsAdditionalOption`, `filterAndReorderMatchesByPracticalDistance`),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **Bugfix: Schnell hintereinander ausgeführte Suchen wurden spürbar langsamer**: Nutzer-
      Beobachtung 2026-07-31 beim Live-Test der obigen EuroVelo-3-Änderung: Münster -> Köln lieferte
      zügig Ergebnisse, löschte man danach Start/Ziel und gab eine neue Route ein, dauerte diese
      zweite Suche spürbar länger. Ursache: Die Hintergrundsuchen (`attemptCombinedThenClosestFallback`,
      `attemptCombinedSearchAsAdditionalOption`, `loadRouteSegmentDistances`, alle als
      `Task.detached`) wurden bei einer neuen Suche zwar über den `matchingGeneration`-Zähler als
      veraltet markiert, liefen dabei aber einfach bis zum Ende weiter, statt tatsächlich
      abgebrochen zu werden - nur ihr (dann verworfenes) Ergebnis wurde ignoriert. War die vorige
      Suche noch nicht fertig (v. a. die A*-Kombinationssuche `findCombinedMatches`, die laut
      Testlauf `combinedMatchBerlinToVredenHasPlausibleTotalDistance` bis zu ~28 s dauern kann),
      konkurrierte sie mit der neu gestarteten Suche um CPU-Zeit. Behoben durch zwei Änderungen:
      1. Neuer `ContentView`-State `activeSearchTasks: [Task<Void, Never>]` sammelt alle laufenden
         Hintergrund-Tasks der aktuellen Suchrunde; `cancelActiveSearchTasks()` ruft beim Start
         einer neuen Suche (`runMatching()`) auf jedem `.cancel()` auf, statt sie nur zu ignorieren.
      2. Reines `.cancel()` allein hätte nichts gebracht, da die A*-Hauptschleife in
         `RouteMatcher.findCombinedMatches` (bis zu `maxVisitedRoutes` = 2000 Iterationen, je mit
         SQLite-Abfragen + Dijkstra-Teilsuchen) `Task.isCancelled` nie geprüft hat - ein
         abgebrochener Task wäre trotzdem bis zum Ende durchgelaufen. Jetzt prüft die Schleife das
         am Anfang jeder Iteration und bricht sofort ab.
      Komplette Test-Suite blieb grün (inkl. des 28-s-Tests, der bewusst ungekürzt weiterläuft, da
      er keinen konkurrierenden Task hat).
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`activeSearchTasks`,
      `cancelActiveSearchTasks`, `runMatching`, `attemptCombinedThenClosestFallback`,
      `attemptCombinedSearchAsAdditionalOption`, `loadRouteSegmentDistances`),
      [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift) (`findCombinedMatches`)
- [x] **Bugfix: Kombinationssuche fand für Bremen -> Münster gar keine Kette mehr (Brückenradweg +
      Friedensroute)**: Nutzer-Meldung 2026-07-31 (direkt nach dem Laden des NRW-Wege-Graphen -
      per Debug-Test bestätigt aber unabhängig davon, betrifft nicht das Offline-Routing). Ursache
      per gezieltem Debug-Logging gegen die echte `routes.sqlite`/`route_junctions.sqlite`
      gefunden: `findCombinedMatches` markierte jede Routen-ID bisher **global genau einmal** als
      "erledigt" (`finalized`-`Set`), unabhängig vom Einstiegspunkt. "D7 Pilgerroute" liegt (per
      reiner Umkreisprüfung ohne Pfad-Check, wie schon bei früheren Funden z. B. "Radweg D11" bei
      München-Nürnberg) sowohl nahe Bremen als auch nahe Münster und wurde deshalb selbst als
      Start-Kandidat der Kombinationssuche verwendet - mit Einstiegspunkt bei Bremen. Von dort aus
      hat die Route aber (eigene Geometrie-Fragmentierung, ~10 % aller benannten Fernwege
      betroffen) keinen durchgehenden Pfad zu ihrer eigenen Anschlussstelle bei Osnabrück - wurde
      trotzdem dauerhaft als "erledigt" markiert und blockierte damit den eigentlich
      funktionierenden zweiten Zugang über "Brückenradweg" bei Osnabrück (dieselbe Route-ID,
      anderer, gut angebundener Einstiegspunkt), über den "Friedensroute" laut
      `route_junctions.sqlite` direkt erreichbar gewesen wäre.
      - **Fix**: `finalized: Set<Int64>` durch `visitedEntryPoints: [Int64: [Koordinate]]`
        ersetzt - erlaubt bis zu drei klar getrennte (≥ 5 km auseinanderliegende) Einstiegspunkte
        pro Route, bevor sie als erschöpft gilt. `maxVisitedRoutes` (2000) bleibt die harte
        Obergrenze für die Gesamtsuche, kein unbegrenztes Blow-up.
      - **Zwei Nachbesserungen, beide durch den vollen Test-Suite-Lauf gefunden**: (1) Ohne
        zusätzliche Prüfung konnte eine einzelne Kette dieselbe (stark fragmentierte) Route
        zweimal nutzen (Route verlassen, später an anderer Stelle wieder einsteigen) - geometrisch
        pro Etappe zwar gültig, als Vorschau aber eine verwirrende Zickzack-Route statt einer
        sinnvollen Verkettung. Neue Prüfung verhindert die Wiederverwendung derselben Routen-ID
        *innerhalb einer einzelnen Kette* (Mehrfach-Einstiege bleiben nur *über verschiedene
        Ketten hinweg* erlaubt, genau wie für den Bremen-Fund nötig). (2) `combinedMatchLuebeckToWismarFindsRouteChainViaTravemuende`
        schlug fehl: Die jetzt bessere Erreichbarkeit ließ mehrere Alternativen-Plätze
        (`maxAlternatives`, 3) mit nur im Einstiegspunkt variierenden Varianten derselben
        "EuroVelo 13"-Kette belegen, bevor die vorher einzig gefundene Alte-Salzstraße/
        Ostseeküsten-Kette in Betracht gezogen wurde - Alternativen werden jetzt zusätzlich nach
        der Menge der genutzten Routen-IDs dedupliziert (`resultRouteIdSets`). Test danach
        angepasst: findet jetzt eine kürzere Kette über "EuroVelo 13"/"Elbetal-Schaalsee Rundweg"
        (~90-96 km statt der alten Alte-Salzstraße-Kette) - plausibel (Luftlinie ~53 km), aber
        anders als beim ursprünglichen Fund **nicht live auf dem iPhone nachverifiziert**.
      - Neuer Regressionstest `combinedMatchBremenToMuensterFindsRouteChainViaOsnabrueck` (erwartet
        eine Etappe mit "Brückenradweg" und eine mit "Friedens" im Namen). Komplette Test-Suite
        (macOS-Unit-Tests) blieb sonst grün (bis auf die vorbestehende, unabhängige
        `bikeRoutingEnginePrefersQuietPathsOverShortestDistance` - fehlt lokal die
        Test-Fixture-Datei `Scripts/data/bremen_ways.sqlite`, nicht Teil dieser Änderung). Auf dem
        iPhone installiert, **live vom Nutzer bestätigt (2026-08-01): Bremen -> Münster
        funktioniert jetzt**.
      - **Probeweise erneut aktiviert**: der seit 2026-07-30 wegen eines ähnlich klingenden
        Symptoms deaktivierte Test `combinedMatchBerlinToDenHaagFindsEuroVelo2Chain` (s. o.
        "Kombinationssuche auf A* umgestellt") - bleibt nach diesem Fix weiterhin leer (~49 s,
        `nil`), also ein anderer/zusätzlicher Grund als der hier behobene. Test danach bewusst
        wieder deaktiviert (Kommentar ergänzt: "erneut probiert, bleibt leer"), Berlin -> Den Haag
        also weiterhin ein offener Sonderfall (extreme Routen-Überlagerungsdichte in Berlin).
        Live-Beobachtung des Nutzers dazu (2026-08-01, Berlin -> Den Haag, ~1 Min. Suche): findet
        dabei erwartungsgemäß keine Kette, fällt stattdessen auf den bestehenden
        `nearbyWellKnownRouteMatches`-Vorschlag zurück ("Europaradweg R1 - Abschnitt Deutschland",
        "Kartendaten hier lückenhaft") - inkl. gestrichelter oranger Verbindungslinie von der
        Lücke (deutsch-niederländische Grenze) bis Den Haag, da die Niederlande als Offline-Region
        geladen sind und `loadConnectorRoute` die Lücke deshalb jetzt per `BikeRoutingEngine`
        überbrücken kann - **kein neuer Bug, funktioniert wie vorgesehen** (s. o. "Routen mit
        Kartenlücke bleiben sicht- und wählbar").
      → [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift)
      (`maxEntryPointsPerRoute`, `minEntryPointSeparationKm`, `findCombinedMatches`,
      `visitedEntryPoints`, `resultRouteIdSets`), [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift)
      (`combinedMatchBremenToMuensterFindsRouteChainViaOsnabrueck`,
      `combinedMatchLuebeckToWismarFindsRouteChainViaTravemuende`,
      `combinedMatchBerlinToDenHaagFindsEuroVelo2Chain` - weiterhin deaktiviert)
- [x] **"Alle Routen"-Übersicht**: neuer Einstellungs-Screen zum Durchsuchen des kompletten
      Routenbestands (~13.800 benannte Routen über alle gebündelten Länder-Datenbanken) - beantwortet
      die Frage "kennt die App die mir bekannten lokalen Radwege?". Bewusst keine alphabetische Liste
      (bei der Menge unbrauchbar, da man ja gerade nicht weiß, unter welchem Buchstaben eine lokale
      Route steht), stattdessen zwei Sucharten: Umkreissuche um einen Ort/die aktuelle Position
      (nutzt dieselbe Bbox-Überlappung wie die Navigations-Kernfunktion) und Namenssuche. Neue
      leichtgewichtige `RouteRepository`-Abfragen (`routeSummaries(...)`) dekodieren dafür bewusst
      nicht die volle Geometrie.
      - **Nachbesserung nach Live-Test (Nutzer, 2026-08-01, Umkreis Bremen)**: Ohne Filter waren
        134 von 205 Treffern gar keine echten Radrouten, sondern einzelne Segmente des
        Knotenpunkt-Wegenetzes (jede Verbindung zwischen zwei nummerierten Knoten ist in OSM eine
        eigene `name`/`ref`-gleiche Relation wie "43-94", `network=rcn`) - haben durch
        alphabetisches Sortieren (Zahlen vor Buchstaben) die komplette sichtbare Liste vor den
        echten Routen gefüllt. Fix: beide SQL-Abfragen filtern Namen im Muster `"<Zahl>-<Zahl>"`
        per `NOT GLOB '[0-9]*-[0-9]*'` heraus. **Live vom Nutzer bestätigt (2026-08-01)**: mit
        Filter erscheinen echte Routen (Weser-Radweg u. a.) statt der Knotenpunkt-Nummern.
      - **Ergänzung**: Tippt man einen Treffer an, öffnet sich `RouteDetailSheet` mit einer Karte
        des Streckenverlaufs (lädt die volle Geometrie erst dort nach, da `RouteSummary` sie
        bewusst nicht enthält). Nutzt `BikeRoute.region(padding:)` (neu, analog
        `DrivenTour.region(padding:)`) zum Einpassen der Kamera. **Live vom Nutzer bestätigt
        (2026-08-01)**.
      → [AllRoutesView.swift](FahrradApp/RadFaehrte/Views/AllRoutesView.swift),
      [BikeRoute.swift](FahrradApp/RadFaehrte/Models/BikeRoute.swift),
      [RouteSummary.swift](FahrradApp/RadFaehrte/Models/RouteSummary.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift)
- [x] **🎉 Polen auf Format v2 umgestellt - Rollout aller 19 Regionen abgeschlossen**: **1.409 MB**
      (vorher 1.535 MB, v1/SQLite), 31.489.089 Knoten, 64.626.453 Kanten, 52.606 eindeutige
      Straßennamen. Baudauer 32:47 Min (`Scripts/build_way_graph_v2.py`, unverändert) - mit Abstand
      der größte bisherige Build, entsprechend der mit Abstand größte Geofabrik-Extrakt
      (`poland-latest.osm.pbf`, ~1,94 GB).
      - Download mit der aus dem Bayern-Fund gelernten Größenprüfung (`curl --fail --retry 3` +
        `stat -f%z`-Abgleich gegen den `curl -I`-Wert) - exakter Treffer (2.081.106.493 Byte), kein
        abgeschnittener Download.
      - Release-Asset unter `way-graphs-eu-v1` (nicht `way-graphs-v4` - Polen ist ein Land, kein
        Bundesland, s. o. "Offline-Routing auf die Niederlande erweitert") mit `--clobber` ersetzt,
        `EuropaLand.poland.approximateSizeMB` auf 1409 aktualisiert. Upload per `curl -I`
        gegengeprüft (200, korrekte Content-Length).
      - **Meilenstein**: Damit sind alle 19 Regionen (16 Bundesländer + Niederlande, Schweden,
        Polen) auf Format v2 (mmap statt SQLite) umgestellt - der unter "Wege-Graph per `mmap`
        statt über SQLite lesen" (s. u., Phase 4) offene Rollout-Punkt ist damit vollständig
        erledigt.
      - **Noch nicht live getestet**: Der Nutzer hat Offline-Routing in Polen noch nicht vor Ort
        ausprobiert (kein konkreter Reiseanlass bisher) - Umstellung rein am Rechner gebaut und
        verifiziert.
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift)
      (`EuropaLand.poland.approximateSizeMB`),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Bounding-Box-Vorfilter für die Offline-Kandidatenliste der Direkt-Route**: Nutzer-Meldung
      (2026-08-02): Die Berechnung der "Direkten Fahrrad-Route" war spürbar langsamer geworden als
      früher. Ursache: Bei inzwischen acht heruntergeladenen Bundesländern probierten
      `loadDirectRoute`/`rerouteDirectRoute` bei **jeder** Berechnung alle acht Wege-Graphen der
      Reihe nach durch (`offlineGraphCandidatePaths`, unsortiert nach Relevanz), bis einer passte -
      `WayGraphCache` verhindert zwar das wiederholte Neuladen *derselben* Region (s. o.), aber
      nicht das erstmalige Laden/Parsen *jeder zusätzlich heruntergeladenen* Region, wenn Start/Ziel
      erst spät in der Kandidatenliste vorkommen (z. B. Baden-Württemberg allein 11,3 Mio. Knoten,
      s. `largeRegionMaxVisitedNodes`). Je mehr Regionen heruntergeladen sind, desto größer wurde
      diese Kandidatenliste - passend zum "früher war es kürzer"-Eindruck des Nutzers.
      Neue `RegionBoundingBox` (grobe Rechteck-Näherung je Bundesland/Land, 0,15° Rand für
      Grenzungenauigkeit + `nearestNode`-Schnappradius) filtert die Kandidatenliste jetzt vorab auf
      Regionen, deren Box Start oder Ziel überhaupt enthalten könnte - offensichtlich nicht
      betroffene Regionen werden gar nicht erst geladen. Bewusst nur für `loadDirectRoute`/
      `rerouteDirectRoute` (neue `offlineGraphCandidatePaths(from:to:)`); das Straßennamen-Matching
      entlang kuratierter Routen (`loadCuratedRouteSteps` u. a.) nutzt weiterhin die ungefilterte
      Liste, da dort auch mittig durchquerte Regionen fernab von Start/Ziel relevant sein können.
      `RootTabView.preloadDownloadedWayGraphs()` lädt beim App-Start bewusst unverändert weiterhin
      alle heruntergeladenen Regionen vor (Hintergrund-Priorität, s. dort) - dieser Fix wirkt vor
      allem, falls eine Berechnung vor Abschluss des Vorladens angefordert wird, sowie bei jeder
      automatischen Neuberechnung während der Navigation (`rerouteDirectRoute`, alle 15 s möglich).
      → [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`RegionBoundingBox`, `DownloadableRegion.boundingBox`),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift)
      (`offlineGraphCandidatePaths(from:to:)`), Regressionstest
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift)
      (`regionBoundingBoxesContainKnownPointsAndExcludeFarAwayOnes`)
- [x] **Offline-Grenzübergang für Ketten aus drei oder mehr Regionen**: Direkter Anschluss an den
      Bounding-Box-Fund oben - beim Live-Test auf dem iPhone (Cuxhaven -> Hamburg, Niedersachsen +
      Schleswig-Holstein + Hamburg heruntergeladen) blieb die Direkt-Route trotz aller drei
      passenden Regionen weiterhin Online-Routing, obwohl der Geschwindigkeits-Fix selbst griff.
      Ursache: `CrossRegionRouteStitcher` (s. o. "Routing über Bundesland-/Landesgrenzen hinweg")
      verband bisher nur zwei Regionen über einen einzigen Übergangspunkt - Cuxhavens Strecke nach
      Hamburg führt laut der von MapKit gezeigten direkten Route aber über Schleswig-Holstein
      (Elmshorn/Pinneberg), eine Region, die weder Start noch Ziel selbst enthält und deshalb auch
      im bisherigen Zwei-Regionen-Versuch nie als Kandidat auftauchte.
      - Neue `findHandoverSequence` (reine, testbare Geometrie wie `findHandoverCoordinate`):
        ermittelt für jeden Abtastpunkt entlang der Luftlinie, welche von beliebig vielen
        Kandidatenregionen dort den nächsten Knoten hat, und fasst aufeinanderfolgende gleiche
        Regionen zu einer geordneten Kette zusammen. Bricht sauber ab, wenn eine Region trotz
        Entprellung (s. u.) mehrfach auftaucht oder die Kette länger als `maxChainLength` (6) wird.
      - Neue `chainedRoute`: löst pro Kettenübergang per (wiederverwendetem) `findHandoverCoordinate`
        den genauen Übergangspunkt auf, snappt ihn unabhängig in beiden angrenzenden Graphen (analog
        `combinedRoute`) und reiht die Teilrouten aneinander.
      - `ContentView.crossRegionOfflineDirectRoute` versucht `chainedRoute` als zusätzlichen Schritt,
        nachdem der einfachere Zwei-Regionen-Versuch fehlgeschlagen ist - dafür bekommt die Funktion
        jetzt bewusst die **ungefilterte** Kandidatenliste (nicht die Bounding-Box-gefilterte aus dem
        Fix oben), da eine mittig durchquerte Region vom Start-/Ziel-Filter sonst fälschlich
        ausgeschlossen würde.
      - **Live-Test-Fund (Cuxhaven -> Hamburg, direkt im Anschluss an die Erstversion)**: Die rohe
        Kette enthielt Schleswig-Holstein zweimal (`[Niedersachsen, Schleswig-Holstein, Hamburg,
        Schleswig-Holstein, Hamburg]`) - ein einzelner Abtastpunkt kippte an der stark verwinkelten
        Grenze Schleswig-Holstein/Hamburg (Wedel/Rissen) kurz zurück, wodurch die strikte
        "keine Region mehrfach"-Regel die eigentlich korrekte Kette komplett verwarf. Behoben durch
        neue `minRunLength` (2): Läufe kürzer als zwei Abtastpunkte gelten als Rauschen und werden in
        einen Nachbarlauf verschmolzen (mit Live-Debug-Ausgaben pro Abtastpunkt lokalisiert und mit
        synthetischen Distanz-Closures regressionsgetestet).
      - **Live-Test zeigte außerdem** (noch nicht als vollständiger Erfolg zu werten): Mit der
        entprellten Kette fand `chainedRoute` den richtigen Weg (Niedersachsen -> Schleswig-Holstein
        -> Hamburg), beide Übergänge snappten plausibel - die erste Teilstrecke selbst schlägt aber
        an einem unabhängigen Wege-Graph-Fehler in Niedersachsen fehl, s. u. "Wege-Graph
        Niedersachsen: Cuxhaven vom Rest der Region getrennt". Cuxhaven -> Hamburg bleibt deshalb bis
        auf Weiteres beim Online-Fallback - die Ketten-Logik selbst ist aber unabhängig davon korrekt
        (siehe Unit-Tests) und wird bei anderen, nicht von diesem Datenfehler betroffenen
        Drei-Regionen-Strecken bereits greifen.
      - Per Unit-Tests (`findHandoverSequence`/`chainedRoute`-Bausteine mit synthetischen
        Distanz-Closures: Dreier-Kette korrekt erkannt, Zwei-Regionen-Fall bewusst `nil`, wiederholt
        auftauchende Region bewusst `nil`) sowie mit temporären Live-Debug-Ausgaben auf dem iPhone
        verifiziert (danach wieder entfernt). `HowItWorksView` entsprechend aktualisiert.
      → [CrossRegionRouteStitcher.swift](FahrradApp/RadFaehrte/Services/CrossRegionRouteStitcher.swift)
      (`findHandoverSequence`, `chainedRoute`, `minRunLength`),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`crossRegionOfflineDirectRoute`),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      Regressionstests [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift)
      (`crossRegionRouteStitcherFindsThreeRegionChain` u. a.)
- [x] **Dänemark als fünftes Land ergänzt** (Nutzerwunsch, direkt im neuen v2-Format wie zuvor
      Schweden): Größenabschätzung per `curl -I` gegen den Geofabrik-Extrakt gecheckt - mit
      ~469 MB mit Abstand der kleinste bisherige Länder-Extrakt (Schweden 774 MB, Niederlande
      1,3 GB, Polen 1,9 GB).
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **920 Routen**
        (u. a. EuroVelo 3/7/10/12), **2,7 MB** als `Resources/denmark.sqlite` gebündelt, `"denmark"`
        in `RouteRepository.bundledResourceNames` ergänzt. Getestet per neuem Unit-Test
        `routeRepositoryFindsEuroVeloRouteNearCopenhagen` (analog Rotterdam/Krakau/Stockholm).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **286 MB**,
        6.340.222 Knoten, 13.098.164 Kanten, 54.258 eindeutige Straßennamen. Baudauer nur
        **3:12 Min** - mit Abstand der schnellste Länder-Build bisher, passend zur kleinsten
        Rohdatei und Fläche.
      - **Neuer Fall `EuropaLand.denmark`**: `boundingBox` aus dem PBF-Header ermittelt
        (`osmium.io.Reader(...).header().box()`) statt grob geschätzt - lieferte direkt eine
        plausible, eng am dänischen Staatsgebiet liegende Box (inkl. Bornholm).
      - Release-Asset `denmark_ways.sqlite` neu (kein `--clobber` nötig, anders als bei Polen)
        unter `way-graphs-eu-v1` hochgeladen, per `curl -I` gegengeprüft (200, korrekte
        Content-Length). `EuropaLand.denmark.approximateSizeMB` auf 286 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, neuer Unit-Test grün. `HowItWorksView`
        ("Offline-Karten") um Dänemark ergänzt. Live-Offline-Routing in Dänemark vom Nutzer noch
        nicht getestet (kein konkreter Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.denmark`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Bugfix: Löschen einer heruntergeladenen Region wirkte wie ein nicht erkannter Tastendruck**
      (Nutzer-Meldung 2026-08-02, direkt nach dem Live-Test des Polen-v2-Umstiegs): Löschen von
      Polen (~1,4 GB) dauerte spürbar (~5 s) ohne jede Rückmeldung. Ursache:
      `WayGraphDownloadManager.delete(_:)` lief komplett synchron auf dem Main-Thread -
      `WayGraphCache.invalidate` gibt dabei die letzte Referenz auf eine ggf. gemappte
      `WayGraphRepository` frei (bei v2 ein `mmap` über die komplette, oft mehrere hundert MB bis
      GB große Datei), zusammen mit dem eigentlichen `FileManager.removeItem` blockierte das
      spürbar die UI.
      - **Fix**: `delete(_:)` läuft jetzt in einem `Task.detached` (analog zum bereits
        bestehenden Muster bei `download(_:)`/`store`, beide `nonisolated`), neue Property
        `deletingRegions: Set<Region>` zeigt währenddessen einen Ladeindikator.
      - **UI**: `OfflineMapsView.regionRow` zeigt während des Löschens `ProgressView()` +
        "Wird gelöscht …" statt des Löschen-Buttons - gleiches Muster wie der bereits bestehende
        Spinner bei der Kombinationssuche (`combinedMatchesSection` in `ContentView`).
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, auf dem iPhone des Nutzers installiert -
        Nutzer bestätigt anschließend live, dass der Ladeindikator sofort erscheint.
      → [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift)
      (`delete`, `deletingRegions`), [OfflineMapsView.swift](FahrradApp/RadFaehrte/Views/OfflineMapsView.swift)
      (`regionRow`)
- [x] **Belgien als sechstes Land ergänzt** (Nutzerwunsch, direkt im neuen v2-Format wie zuvor
      Schweden/Dänemark): Größenabschätzung per `curl -I` gegen den Geofabrik-Extrakt gecheckt -
      ~659 MB (zwischen Dänemark 469 MB und Schweden 774 MB).
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **13.038
        Routen** (u. a. EuroVelo 3/4/12/19), mit Abstand am meisten bisher (Dänemark 920,
        Niederlande 17.521 blieb bisher Rekord) - Belgiens dichtes Knotenpunktnetz (v. a.
        Flandern) schlägt hier voll durch. **8,2 MB** als `Resources/belgium.sqlite` gebündelt,
        `"belgium"` in `RouteRepository.bundledResourceNames` ergänzt. Getestet per neuem
        Unit-Test `routeRepositoryFindsEuroVeloRouteNearBruges` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **299 MB**,
        6.694.265 Knoten, 13.568.168 Kanten, 110.390 eindeutige Straßennamen (mit Abstand die
        meisten Straßennamen bisher unter den Ländern, passend zur dichten Kartierung). Baudauer
        4:19 Min.
      - **Neuer Fall `EuropaLand.belgium`**: `boundingBox` wieder aus dem PBF-Header ermittelt
        (`osmium.io.Reader(...).header().box()`, s. Dänemark-Eintrag).
      - Release-Asset `belgium_ways.sqlite` neu unter `way-graphs-eu-v1` hochgeladen, per
        `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.belgium.approximateSizeMB` auf 299 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, neuer Unit-Test grün. `HowItWorksView`
        ("Offline-Karten") um Belgien ergänzt. Live-Offline-Routing in Belgien vom Nutzer noch
        nicht getestet (kein konkreter Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.belgium`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Luxemburg als siebtes Land ergänzt** (Nutzerwunsch, direkt im neuen v2-Format wie zuvor
      Schweden/Dänemark/Belgien): Größenabschätzung per `curl -I` gegen den Geofabrik-Extrakt
      gecheckt - mit ~45 MB mit Abstand der kleinste Extrakt bisher (nächstkleinstes Dänemark mit
      469 MB), entsprechend beide Build-Schritte in Sekunden statt Minuten fertig.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **378 Routen**
        (u. a. EuroVelo 5), **450 KB** als `Resources/luxembourg.sqlite` gebündelt, `"luxembourg"`
        in `RouteRepository.bundledResourceNames` ergänzt. Bauzeit nur 7 s. Getestet per neuem
        Unit-Test `routeRepositoryFindsEuroVeloRouteNearLuxembourgCity` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **35 MB**, 785.684
        Knoten, 1.596.524 Kanten, 6.400 eindeutige Straßennamen. Baudauer nur **16 s** - mit
        Abstand der schnellste Länder-Build bisher (bisheriger Rekord Dänemark mit 3:12 Min).
      - **Neuer Fall `EuropaLand.luxembourg`**: `boundingBox` wieder aus dem PBF-Header ermittelt
        (`osmium.io.Reader(...).header().box()`, s. Dänemark-Eintrag).
      - Release-Asset `luxembourg_ways.sqlite` neu unter `way-graphs-eu-v1` hochgeladen, per
        `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.luxembourg.approximateSizeMB` auf 35 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, neuer Unit-Test grün. `HowItWorksView`
        ("Offline-Karten") um Luxemburg ergänzt. Live-Offline-Routing in Luxemburg vom Nutzer noch
        nicht getestet (kein konkreter Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.luxembourg`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Geschätzte Fahrzeit vor Fahrtbeginn** (Nutzer-Idee 2026-08-02, umgesetzt): Sowohl in der
      Kartenvorschau einer Katalog-Route (`RouteDetailSheet` in `AllRoutesView`) als auch in der
      Liste "Eigene Routen" (`OwnRoutesView`) steht jetzt neben der Streckenlänge eine grobe
      Schätzung der Fahrzeit ("≈ 1 Std. 40 Min."), berechnet aus Distanz und der in den
      Einstellungen hinterlegten Wunschgeschwindigkeit (`averageSpeedKmh`) - derselben Grundlage,
      die auch `arrivalTimeSetSpeed`/`remainingTimeSetSpeed` in der Statistik-Leiste während der
      Navigation verwenden. Gemeinsame Formatierungsfunktion `estimatedDurationText(distanceKm:
      speedKmh:)` in `RouteSummary.swift`, da für Katalog- (`RouteSummary.distanceKm`) und eigene
      Routen (`ImportedRoute.totalDistanceKm`) gebraucht.
      → [RouteSummary.swift](FahrradApp/RadFaehrte/Models/RouteSummary.swift),
      [AllRoutesView.swift](FahrradApp/RadFaehrte/Views/AllRoutesView.swift),
      [OwnRoutesView.swift](FahrradApp/RadFaehrte/Views/OwnRoutesView.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **Straßennamen-Vorschau für Einzeltreffer: Teilanzeige bis zur echten Kartenlücke** (Nutzer-
      Beobachtung 2026-08-02, Bremen → Hannover, "EuroVelo 3 - Pilgrim's Route - part Germany"):
      Bisher zeigte die Straßennamen-Vorschau eines Einzeltreffers bei einer echten Lücke in der
      Routen-Geometrie (`routeSegmentPath` fand keinen durchgehenden Pfad) komplett nichts an -
      "Keine Straßendaten verfügbar" -, obwohl teils lange, zusammenhängende Streckenabschnitte auf
      beiden Seiten der Lücke durchaus vorhanden und über einen heruntergeladenen Wege-Graphen
      auflösbar gewesen wären. Kombinierte Ketten (`matchCuratedRouteSteps(forLegs:)`) zeigten
      dagegen schon länger Teilergebnisse (Etappen ohne Geometrie werden übersprungen) - dieselbe
      Großzügigkeit fehlte bisher beim Einzeltreffer.
      - **Wichtige Einschränkung, vorab mit dem Nutzer geklärt**: Es gibt zwei grundverschiedene
        Ausfallgründe hinter "Kartendaten hier lückenhaft". (1) Echte Lücke im Streckennetz - beide
        Anker liegen plausibel auf der Route (≤ 20 km, `maxPlausibleAnchorDistanceKm`), aber ohne
        durchgehenden Pfad dazwischen - genau der hier behobene Fall. (2) Ein Anschlusspunkt liegt
        schlicht zu weit von der Route entfernt (> 20 km) - keine Lücke *in* einer sonst passenden
        Route, sondern die Route kommt in die Gegend gar nicht. Für den konkreten Bremen→Hannover-
        Beispielfall aus der Nutzer-Beobachtung selbst (Fall 2, per Bounding-Box-Prüfung
        bestätigt: EuroVelo 3 verläuft in Deutschland Nordsee-Küste → Bremen → Osnabrück →
        Rheinland, kommt Hannover nie nahe) ändert dieser Fix nichts - dort bleibt "Keine
        Straßendaten verfügbar", weil es dort keine "Lücke", sondern schlicht keine Route gibt.
      - **`RouteMatcher.routeSegmentPathAllowingGap(along:from:to:)`** (neu, analog
        `routeSegmentPath`): findet bei fehlender Verbindung zwischen Start-/End-Anker (Fall 1
        oben) statt `nil` die beiden tatsächlich erreichbaren Teilstücke bis zum jeweils der
        Lücke nächstgelegenen Punkt (per `dijkstraDistances` + linearer Suche nach dem
        geografisch nächsten erreichbaren Knoten, dann normalem Dijkstra dorthin), plus deren
        Luftlinien-Abstand als grobes Maß für die Lückengröße (`RouteSegmentGapResult`,
        `RouteSegmentPathResult`).
      - **`ContentView`**: `CuratedRouteStepsAvailability` um `.partialSteps(fromStart:toEnd:
        gapDistanceKm:)` ergänzt; `loadCuratedRouteSteps` nutzt die neue Funktion und matcht beide
        Teilpfade unabhängig gegen den heruntergeladenen Wege-Graphen (wie bei Kombinations-
        Etappen) - fehlt einer Seite die Geometrie oder das Matching scheitert dort, wird nur die
        andere Seite gezeigt. `curatedRouteStepsDetailSheet` zeigt bei `.partialSteps` zwei
        Listen-Abschnitte mit einem Lücken-Hinweis ("Kartenlücke - keine Straßendaten (ca. X km)")
        dazwischen statt der bisherigen Alles-oder-nichts-Meldung.
      - Bewusst **nicht** auf die aktive Turn-by-Turn-Navigation (`loadCuratedRouteForNavigation`)
        übertragen - eine echte physische Lücke in den Quelldaten lässt sich für die laufende
        Navigation nicht sinnvoll überbrücken, ohne den Nutzer mitten in der Fahrt ohne Führung
        dastehen zu lassen. Betrifft ausschließlich die On-Demand-Vorschau.
      - **Verifiziert**: Neuer Unit-Test
        `routeSegmentPathAllowingGapReturnsBothPartialPathsAcrossARealGap` (synthetische,
        garantiert unverbundene Liniensegmente, da eine reale, hinreichend große und stabile
        Kartenlücke sich nicht zuverlässig referenzieren lässt) grün. Build fürs Gerät erfolgreich,
        auf "iPhone von Jörn" installiert. Volle Testsuite ansonsten unverändert (vorbestehende,
        unabhängige `RadFaehrteUITests`-Fehlschläge im Simulator, s. u. - nicht Teil dieser
        Änderung). **Live auf dem Gerät bestätigt** (2026-08-02) mit einem echten Kategorie-1-Fall:
        "Internationale Dollard Route" (Emden, Niedersachsen) zwischen Mohnblumenstraße und
        Thorner Straße, echte ~4,9-km-Lücke. Sheet zeigte "Weiter auf Mohnblumenstraße" gefolgt von
        "Kartenlücke - keine Straßendaten (ca. 4.9 km)" statt der alten Alles-oder-nichts-Meldung -
        die Ziel-Seite (Thorner Straße) lieferte dabei kein Matching-Ergebnis (nur eine Seite
        gezeigt, wie vorgesehen). Das Beispiel wurde per Scan aller deutschen Fernwege
        (RouteGraph-Komponentenanalyse auf `routes.sqlite`) gefunden, da kein Fall vorab bekannt
        war - der Scan-Code selbst war nur temporär und ist nicht Teil des Commits.
      → [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift)
      (`routeSegmentPathAllowingGap`, `RouteSegmentGapResult`, `RouteSegmentPathResult`,
      `nearestReachableNode`), [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift)
      (`CuratedRouteStepsAvailability`, `loadCuratedRouteSteps`, `curatedRouteStepsDetailSheet`),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [~] **Abbiege-Erkennung: Schwellenwert angehoben (Vorbereitung für geplante Sprachausgabe,
      2026-08-02)**: `stepDetails` erkannte bisher schon ab 20° Kursänderung eine Abbiegung -
      laut Code-Kommentar "nicht gegen echte Kreuzungen kalibriert", mit dem Risiko unnötiger
      Fehlalarme bei sanften Straßenschwenks. Bei der bestehenden Watch-Haptik unauffällig, aber
      als Vorstufe für eine geplante Sprachausgabe (s. u. "Ideen") ein größeres Problem, da eine
      falsche gesprochene Ansage viel auffälliger wäre als eine falsche Vibration. Als erster,
      risikoarmer Schritt auf 30° angehoben (grobe Schätzung, keine echte Kalibrierung gegen
      Kreuzungsdaten) - benannte Konstanten `turnAngleThresholdDegrees`/
      `sharpTurnAngleThresholdDegrees` statt der bisherigen Magic Numbers 20/120. Betrifft
      dieselbe Stelle, an der auch der Watch-Haptik-Trigger (`isTurnInstruction` in
      `ContentView.swift`) hängt - Nebeneffekt: sollte auch dort seltener fälschlich auslösen.
      Build fürs Gerät erfolgreich (`xcodebuild ... -destination 'generic/platform=iOS'`), **noch
      nicht live auf dem Gerät getestet** - ob 30° in der Praxis das richtige Maß ist (nicht zu
      viele sanfte Abbiegungen mehr verschluckt), muss auf einer echten Tour verifiziert werden.
      → [BikeRoutingEngine.swift](FahrradApp/RadFaehrte/Services/BikeRoutingEngine.swift)
      (`turnAngleThresholdDegrees`, `sharpTurnAngleThresholdDegrees`, `stepDetails`)
- [~] **Sprachausgabe für Abbiegehinweise** (Nutzer-Wunsch 2026-08-02, direkt im Anschluss an den
      angehobenen Abbiege-Schwellenwert oben umgesetzt): Kündigt Abbiegungen zusätzlich zur
      Watch-Vibration laut per `AVSpeechSynthesizer` (deutsche Stimme) an - nutzt denselben
      Auslösepunkt wie die bestehende Watch-Haptik (umbenannt von `checkWatchHapticTrigger` zu
      `checkTurnAnnouncementTrigger`, da die Funktion jetzt beides auslöst), damit beide für
      dieselbe Abbiegung gleichzeitig kommen - keine neue Erkennungslogik, derselbe fertige
      `instructions`-Text wie in der Navigations-Kopfzeile. Betrifft dieselbe Teilmenge wie die
      Watch-Haptik: ausgewählter Einzeltreffer, kombinierte Kette oder "Direkte Fahrrad-Route",
      jeweils mit vorhandenen Schritt-Daten - nicht bei reinen Radrouten-Treffern ohne
      Turn-by-Turn-Informationen oder GPX-Importen.
      - **Neuer Ein/Aus-Schalter** in den Einstellungen unter "Navigation" (`isVoiceGuidanceEnabled`,
        Standard: an), analog zum bestehenden Geschwindigkeits-Stepper.
      - **Neue Klasse** [VoiceAnnouncer.swift](FahrradApp/RadFaehrte/Services/VoiceAnnouncer.swift)
        kapselt `AVSpeechSynthesizer` + `AVAudioSession`-Konfiguration (`.duckOthers`, damit z. B.
        laufende Musik nur kurz leiser wird statt stummgeschaltet zu werden) an einer Stelle, wird
        beim Beenden der Navigation gestoppt (`stopNavigating`).
      - **Hintergrund-Wiedergabe**: `UIBackgroundModes` in
        [Supplemental-Info.plist](FahrradApp/RadFaehrte/Supplemental-Info.plist) um `audio` ergänzt
        (bisher nur `location`), damit die Ansage auch bei gesperrtem Display/App im Hintergrund
        hörbar bleibt - **noch nicht live verifiziert, ob das dafür ausreicht** (offener Punkt aus
        der ursprünglichen Diskussion).
      - Build für Simulator und echtes Gerät erfolgreich, auf "iPhone von Jörn" installiert -
        **Sprachausgabe selbst (Hörbarkeit, Timing, Verhalten bei gesperrtem Display/parallel
        laufender Musik) noch nicht live getestet**, das kann nur auf einer echten Fahrt geprüft
        werden.
      - **Zweistufig nachgezogen** (noch am selben Tag, nach erstem Live-Test-Eindruck): Statt
        einer einzelnen Ansage jetzt zwei - früh bei `watchHapticLeadDistanceMeters` ("In 100
        Metern rechts abbiegen auf ...") und spät ("Jetzt rechts abbiegen auf ..."), letztere
        ausgelöst am selben Punkt, an dem `advanceDirectRouteStepIfNeeded` ohnehin auf den
        nächsten Schritt umschaltet (Kopfzeile/Pfeil-Icon/Watch). Dieser Umschalt-Punkt war bisher
        fest auf 30 m verdrahtet - nach Nutzer-Feedback ("fühlt sich beim Fahren zu früh an") auf
        eine benannte Konstante `stepAdvanceLeadDistanceMeters = 10` gesenkt. Das betrifft bewusst
        nicht nur die neue Ansage, sondern auch den bisherigen Umschalt-Zeitpunkt von Kopfzeile/
        Pfeil-Icon/Watch-Anzeige - **explizit vom Nutzer so gewünscht**, nicht nur ein Nebeneffekt.
        Neuer eigener Merker `lastVoiceNowAnnouncementStepIndex` (analog
        `lastWatchHapticStepIndex`, aber unabhängig) verhindert Mehrfachauslösung der späten
        Ansage; neuer Hilfs-Helfer `lowercasingFirstLetter` bettet den großgeschrieben
        stehenden `instructions`-Text grammatisch korrekt in beide Ansage-Sätze ein. Watch-Haptik
        selbst bleibt bewusst einstufig (nur der bestehende frühe Trigger), um das dort schon gut
        funktionierende Verhalten nicht anzufassen. Build + Geräte-Installation erfolgreich -
        **ebenfalls noch nicht live getestet**.
      - **Ein/Aus-Schalter zusätzlich im Zahnrad-Schnelleinstellungen-Sheet** (2026-08-03,
        Nutzer-Wunsch): Der Schalter existierte bisher nur in den vollständigen Einstellungen
        unter "Navigation", nicht in `NavigationQuickSettingsView` (dem Sheet, das während einer
        laufenden Navigation übers Zahnrad-Symbol erreichbar ist und bewusst nur unterwegs
        relevante Werte zeigt) - dorthin gehört er aber, weil man ihn gerade während der Fahrt
        an-/abschalten will, ohne die Navigation dafür zu verlassen. Liest/schreibt denselben
        `isVoiceGuidanceEnabled`-Wert wie die vollständigen Einstellungen. Build fürs Gerät
        erfolgreich, noch nicht live getestet.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`checkTurnAnnouncementTrigger`,
      `advanceDirectRouteStepIfNeeded`, `stepAdvanceLeadDistanceMeters`,
      `lastVoiceNowAnnouncementStepIndex`, `lowercasingFirstLetter`, `voiceAnnouncer`,
      `isVoiceGuidanceEnabled`, `stopNavigating`),
      [VoiceAnnouncer.swift](FahrradApp/RadFaehrte/Services/VoiceAnnouncer.swift),
      [AppSettings.swift](FahrradApp/RadFaehrte/Models/AppSettings.swift),
      [NavigationSettingsView.swift](FahrradApp/RadFaehrte/Views/NavigationSettingsView.swift),
      [NavigationQuickSettingsView.swift](FahrradApp/RadFaehrte/Views/NavigationQuickSettingsView.swift),
      [Supplemental-Info.plist](FahrradApp/RadFaehrte/Supplemental-Info.plist),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift) ("Navigation")
- [x] **Schweiz als achtes Land ergänzt** (Nutzerwunsch, direkt im neuen v2-Format wie zuvor
      Schweden/Dänemark/Belgien/Luxemburg): Größenabschätzung per `curl -I` gegen den
      Geofabrik-Extrakt gecheckt - ~516 MB (zwischen Dänemark 469 MB und Belgien 659 MB).
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **1.008
        Routen** (u. a. EuroVelo 5/6/15), **4,3 MB** als `Resources/switzerland.sqlite` gebündelt,
        `"switzerland"` in `RouteRepository.bundledResourceNames` ergänzt. Getestet per neuem
        Unit-Test `routeRepositoryFindsEuroVeloRouteNearZurich` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **644,5 MB**,
        14.509.344 Knoten, 29.414.088 Kanten, 100.658 eindeutige Straßennamen. Baudauer 5:43 Min.
        ⚠️ **Überraschung**: Trotz kleinerer PBF-Datei (516 MB) deutlich mehr Knoten/Kanten als
        Belgien (6,7 Mio./13,6 Mio.) und dadurch auch eine über doppelt so große Ausgabedatei -
        dasselbe Muster wie zuvor bei Schweden (s. dortiger Eintrag): Die Schweiz hat ein sehr
        dichtes Berg-/Wanderwegenetz, das flächenmäßig viel ausgedehnter ist als es die reine
        PBF-Größe vermuten lässt.
      - **Neuer Fall `EuropaLand.switzerland`**: `boundingBox` wieder aus dem PBF-Header ermittelt
        (`osmium.io.Reader(...).header().box()`, s. Dänemark-Eintrag).
      - Release-Asset `switzerland_ways.sqlite` neu unter `way-graphs-eu-v1` hochgeladen, per
        `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.switzerland.approximateSizeMB` auf 645 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, neuer Unit-Test grün. `HowItWorksView`
        ("Offline-Karten") um Schweiz ergänzt. Live-Offline-Routing in der Schweiz vom Nutzer noch
        nicht getestet (kein konkreter Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.switzerland`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Frankreich als neuntes Land - kuratierte Routen fertig, Offline-Wege-Graph vorerst
      zurückgestellt** (Nutzerwunsch): Erste Größenabschätzung per `curl -I` gegen den
      Geofabrik-Extrakt zeigte bereits **~4,7 GB** - mit Abstand der größte Brocken bisher (2,6x
      Polen, dem bisherigen Rekordhalter mit 1,9 GB). Nutzer vorab gefragt und bestätigt, dass
      trotzdem versucht werden soll.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **8.148
        Routen** (u. a. EuroVelo 1/3/12/15, La Vélodyssée), **21,7 MB** als
        `Resources/france.sqlite` gebündelt, `"france"` in `RouteRepository.bundledResourceNames`
        ergänzt. Bauzeit 14:44 Min (mit Abstand am längsten für diesen Schritt, aber unkritisch).
        Getestet per neuem Unit-Test `routeRepositoryFindsEuroVeloRouteNearLaRochelle` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich) - **dieser Teil ist
        fertig und live nutzbar**, unabhängig vom Offline-Wege-Graph unten.
      - ⚠️ **Offline-Wege-Graph (`build_way_graph_v2.py`) zweimal am Speicherdruck des
        Baurechners gescheitert** (16 GB RAM): Erster Versuch lief über Nacht (Mac zwischendurch
        zugeklappt, Prozess pausierte dabei automatisch im Schlafmodus und lief beim Aufwachen
        unverändert weiter - kein Datenverlust dadurch) bis zu **72:41 Min reiner Rechenzeit** bei
        zuletzt nur noch ~23 % effektiver CPU-Auslastung (Rest ging fürs Swapping drauf, bis zu
        8,2 GB Swap-Nutzung, nur noch ~61 MB physisch frei) - auf Nutzerwunsch abgebrochen.
        Zweiter Versuch bei komplett freiem Speicher (9,5 GB frei nach dem Kill) zeigte
        anfangs bessere Effizienz (~85 %), verschlechterte sich aber nach einer Weile auf
        dasselbe Muster (~6-7 GB Swap bei 44 Min Rechenzeit) - ebenfalls abgebrochen.
        **Ursache**: `build_way_graph_v2.py` hält Knoten/Kanten während des gesamten Baus
        komplett in Python-Listen/-Dicts im Speicher (kein Streaming, kein externes Sortieren) -
        funktioniert bei den bisherigen Ländern (bis Schweiz: 645 MB, 14,5 Mio. Knoten) noch
        gut, skaliert aber nicht auf Frankreichs Straßennetz-Größenordnung auf einem 16-GB-Rechner.
      - **Entscheidung**: Vorerst zurückgestellt statt einer aufwendigeren Lösung (z. B.
        Aufteilung in Regionen wie bei Deutschland, oder ein speicherschonenderer,
        externer-Sortierung-basierter Bau-Ansatz) - die kuratierte Routen-Suche funktioniert für
        Frankreich bereits, die fehlende Offline-Routing-Engine ("ruhige Wege") betrifft nur die
        "Direkte Fahrrad-Route" außerhalb kartierter Fernwege. Kein `EuropaLand.france`-Fall
        angelegt, `HowItWorksView` ("Offline-Karten") bewusst **nicht** um Frankreich ergänzt -
        diese Liste nennt nur Länder mit herunterladbarem Wege-Graph, die kuratierten Routen
        sind dort ohnehin nicht aufgeführt (galt schon für Niederlande/Polen/Schweden vor deren
        jeweiligem Wege-Graph-Schritt).
      - `france-latest.osm.pbf` (4,7 GB) bleibt unversioniert in `Scripts/data/` liegen (wie bei
        den anderen Ländern), damit ein späterer Versuch nicht erneut heruntergeladen werden muss.
      - ⚠️ **Bugfix beim ersten Testlauf gefunden**: `"france"` war trotz gegenteiliger Notiz oben
        nie tatsächlich zu `RouteRepository.bundledResourceNames` hinzugefügt worden (nur
        `france.sqlite` selbst lag im Bundle - Xcodes synchronisierte Gruppe nimmt jede Datei in
        `Resources/` automatisch mit, unabhängig davon, ob `RouteRepository` sie überhaupt öffnet).
        Der neue Unit-Test schlug dadurch beim ersten Lauf fehl (`routes` leer für eine
        La-Rochelle-Bbox, obwohl die Rohdaten per direkter SQL-Abfrage nachweislich 27 Treffer
        lieferten) - Diagnose bestätigte identische, unbeschädigte Datenbank
        (`PRAGMA integrity_check` ok, 8148 Zeilen) und korrekte SQL-Logik, der fehlende
        Bundle-Eintrag war die einzige Erklärung. Nach Ergänzen des Eintrags Test grün.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, neuer Unit-Test grün (nach obigem
        Bugfix), komplette Test-Suite (37 Tests) auf dem iPhone des Nutzers grün, App installiert.
      → [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift)
- [x] **Frankreich-Wege-Graph doch noch gelöst - Aufteilung in 21 Regionen** (Nutzerwunsch, direkt
      im Anschluss an den zurückgestellten Versuch oben): Statt der einen zu großen
      Gesamt-Frankreich-Datei (4,7 GB, zweimal am Speicherdruck gescheitert) Frankreich wie
      Deutschland in Regionen aufgeteilt - Geofabrik bietet die alte, vor-2016-Gebietsreform-
      Einteilung mit **21 Regionen** direkt an (download.geofabrik.de/europe/france/<region>),
      von **32 MB (Corse)** bis **500 MB (Rhône-Alpes)** - dieselbe Größenordnung, die für
      Bundesländer/kleinere Länder bereits zuverlässig funktioniert (kein Speicherproblem mehr,
      da jede Region einzeln gebaut wird).
      - **Neuer Regionstyp `FranceRegion`** (`WayGraphStore.swift`, 21 Fälle, `DownloadableRegion`-
        konform wie `Bundesland`/`EuropaLand`) - eigener Typ statt eines Falls in `EuropaLand`,
        weil Frankreich als Ganzes zu groß fürs Bündeln in eine Datei ist. `boundingBox` je Region
        per HTTP-Range-Request ermittelt (`curl -r 0-500000` + `osmium.io.Reader(...).header().box()`
        auf nur die ersten 500 KB jeder PBF-Datei) - der Header-Block liegt am Dateianfang, ein
        Download der kompletten, teils hunderte MB großen Dateien war dafür nicht nötig.
      - **Neues Batch-Skript `Scripts/build_france_regions.sh`**: Für jede der 21 Regionen
        Download (mit derselben Größenprüfung wie bei den Bundesländern) → `build_way_graph_v2.py`
        → Upload zu neuem Release-Tag `way-graphs-fr-v1` → lokale Dateien löschen. Alle 21
        Regionen liefen beim ersten Durchlauf durch, **kein einziger Speicherdruck-Vorfall** -
        Baudauer pro Region 14 s (Corse) bis 222 s (Rhône-Alpes), zusammen **~35 Min reine
        Rechenzeit** für alle 21 (zum Vergleich: der gescheiterte Gesamt-Versuch brauchte schon
        allein beim zweiten Anlauf über 44 Min und war da noch nicht fertig).
      - **Größte Region (Rhône-Alpes)**: 532 MB, 12,0 Mio. Knoten, 24,2 Mio. Kanten, 121.693
        Straßennamen - selbst das lief in 3:42 Min glatt durch, ohne jedes Swapping.
      - **Dritte "Offline-Karten"-Kategorie in den Einstellungen** ("Offline-Karten Frankreich",
        analog Deutschland/Europa): neue `WayGraphStore<FranceRegion>`-Instanz in `RootTabView`/
        `SettingsView`/`ContentView` durchgereicht, `offlineGraphCandidatePaths()` (beide
        Varianten), `preloadDownloadedWayGraphs()` und `regionDisplayName(forPath:)` um
        `FranceRegion` ergänzt - dieselben generischen Mechanismen (Grenzübergänge, Bounding-Box-
        Vorfilter, Caching) wie bei Bundesländern/anderen Ländern gelten automatisch mit, ohne
        eigene Sonderlogik.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, komplette Test-Suite auf dem iPhone des
        Nutzers grün, App installiert. `HowItWorksView` ("Offline-Karten") um den Hinweis auf die
        Frankreich-Regionen-Aufteilung ergänzt.
      → [Scripts/build_france_regions.sh](FahrradApp/Scripts/build_france_regions.sh) (neu),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift) (`FranceRegion`),
      [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RootTabView.swift](FahrradApp/RadFaehrte/RootTabView.swift),
      [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`offlineGraphCandidatePaths`,
      `regionDisplayName`), [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-fr-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-fr-v1)
- [x] **"Offline-Karten Frankreich" in die Europa-Liste verschoben** (Nutzerwunsch, direkt im
      Anschluss an die Regionen-Aufteilung oben): Frankreich hatte zunächst einen eigenen dritten
      Einstellungs-Eintrag neben "Offline-Karten Deutschland"/"Offline-Karten Europa" bekommen -
      Nutzer wollte es stattdessen als Zeile innerhalb der Länderliste, die beim Antippen zur
      21-Regionen-Liste weiterleitet.
      - **`OfflineMapsView` um optionalen `trailingContent`-Parameter erweitert** (zweiter
        generischer Typ `TrailingContent: View`, `@ViewBuilder`-Closure mit Default `{ EmptyView() }`)
        - hängt eine zusätzliche Zeile ans Ende der `ForEach`-Regionsliste an, ohne die generische
        Wiederverwendung für Bundesländer/Länder/Frankreich-Regionen selbst anzufassen (alle drei
        nutzen weiterhin denselben Aufruf ohne den Parameter, der Default greift automatisch).
      - **`SettingsView`**: Der eigene "Offline-Karten Frankreich"-Eintrag ist raus, stattdessen
        bekommt der `OfflineMapsView(store: europaWayGraphStore, ...)`-Aufruf jetzt einen
        `trailingContent`-Closure mit einem `NavigationLink` "Frankreich", der zur (unverändert
        bestehenden) `OfflineMapsView<FranceRegion>` führt - rein optisch ein einfacher Zeilen-Link
        ohne Download-Button/Größenanzeige, da Frankreich selbst nicht direkt herunterladbar ist,
        nur seine 21 Unter-Regionen.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, auf dem iPhone des Nutzers installiert -
        Nutzer bestätigt live, dass "Frankreich" jetzt in der Europa-Liste erscheint und zur
        Regionen-Liste weiterleitet.
      → [OfflineMapsView.swift](FahrradApp/RadFaehrte/Views/OfflineMapsView.swift)
      (`trailingContent`), [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **Österreich als zehntes Land ergänzt** (Nutzerwunsch, direkt im neuen v2-Format wie zuvor
      Schweden/Dänemark/Belgien/Luxemburg/Schweiz): Größenabschätzung per `curl -I` gegen den
      Geofabrik-Extrakt gecheckt - ~768 MB (zwischen Belgien 659 MB und Polen/Niederlande).
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **2.162
        Routen** (u. a. EuroVelo 6/9/13/14), **6,3 MB** als `Resources/austria.sqlite` gebündelt,
        `"austria"` in `RouteRepository.bundledResourceNames` ergänzt. Getestet per neuem
        Unit-Test `routeRepositoryFindsEuroVeloRouteNearVienna` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **929,3 MB**,
        20.906.115 Knoten, 42.479.833 Kanten, 86.180 eindeutige Straßennamen. Baudauer 11:33 Min.
        ⚠️ **Wie erwartet (Muster von Schweden/Schweiz)**: Trotz PBF-Größe im Belgien-Bereich
        deutlich mehr Knoten/Kanten und eine über doppelt so große Ausgabedatei - Österreichs
        Alpen-Wegenetz ist dichter als die reine Dateigröße vermuten lässt. RSS des Bauprozesses
        stieg zwischenzeitlich auf ~6,9 GB mit leichtem Swap-Einsatz, blieb aber unkritisch (kein
        Abbruch nötig, anders als bei Frankreich als Gesamtdatei).
      - **Neuer Fall `EuropaLand.austria`**: `boundingBox` wieder aus dem PBF-Header ermittelt.
      - Release-Asset `austria_ways.sqlite` neu unter `way-graphs-eu-v1` hochgeladen, per
        `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.austria.approximateSizeMB` auf 929 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, neuer Unit-Test grün. `HowItWorksView`
        ("Offline-Karten") um Österreich ergänzt. Live-Offline-Routing in Österreich vom Nutzer
        noch nicht getestet (kein konkreter Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.austria`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Offline-Karten-Listen alphabetisch sortiert** (Nutzerwunsch, direkt im Anschluss an
      Österreich): Bisher erschienen Regionen in Enum-Deklarationsreihenfolge - bei `Bundesland`
      zufällig schon alphabetisch (deutsche Fallnamen), bei `EuropaLand`/`FranceRegion` nicht
      (englische/französische Fallnamen, aber deutsche `displayName`s - z. B. stand `.austria`
      vor `.belgium`, aber "Österreich" gehört alphabetisch ans Ende).
      - **`OfflineMapsView`** sortiert `Region.allCases` jetzt per `localizedStandardCompare` nach
        `displayName`, statt die rohe `CaseIterable`-Reihenfolge zu übernehmen - neue
        Generic-Randbedingung `where Region.ID == String` nötig, da `Region.id` sonst nicht
        garantiert `String` ist (Compile-Fehler beim ersten Versuch, mit der Randbedingung behoben).
      - **"Frankreich"-Sondereintrag korrekt einsortiert**: `trailingLabel`-Parameter (Vergleichswert
        für die Einsortierungs-Position) ergänzt, getrennt von `trailingContent` (der tatsächlichen
        Darstellung) - `OfflineMapsView` berechnet die Einfügeposition durch Vergleich von
        `trailingLabel` mit den sortierten `displayName`s, damit "Frankreich" zwischen "Dänemark"
        und "Luxemburg" landet statt immer ans Listenende gehängt zu werden.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, kompletter Testlauf (38 Tests) auf dem
        iPhone des Nutzers grün, App installiert.
      → [OfflineMapsView.swift](FahrradApp/RadFaehrte/Views/OfflineMapsView.swift) (`rows`,
      `trailingLabel`), [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift)
- [x] **Tschechien als elftes Land ergänzt** (Nutzerwunsch, direkt im neuen v2-Format wie zuvor
      Schweden/Dänemark/Belgien/Luxemburg/Schweiz/Österreich): Größenabschätzung per `curl -I`
      gegen den Geofabrik-Extrakt gecheckt - ~898 MB (zwischen Österreich 768 MB und Polen/
      Niederlande).
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **3.568
        Routen** (u. a. EuroVelo 4/7/13), **8,0 MB** als `Resources/czechia.sqlite` gebündelt,
        `"czechia"` in `RouteRepository.bundledResourceNames` ergänzt (Fallname `.czechia`
        bewusst als offizieller englischer Kurzname statt `.czechRepublic` gewählt, analog zu den
        anderen kurzen Länder-Fallnamen). Getestet per neuem Unit-Test
        `routeRepositoryFindsEuroVeloRouteNearPrague` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/Wien).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **495 MB**,
        11.076.383 Knoten, 22.684.322 Kanten, 34.228 eindeutige Straßennamen. Baudauer nur
        4:58 Min, kein Speicherdruck (anders als bei Österreich/Schweden/Schweiz - Tschechiens
        Wegenetz ist trotz ähnlicher PBF-Größe wie Österreich deutlich weniger dicht).
      - **Neuer Fall `EuropaLand.czechia`**: `boundingBox` wieder aus dem PBF-Header ermittelt.
      - Release-Asset `czechia_ways.sqlite` neu unter `way-graphs-eu-v1` hochgeladen, per
        `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.czechia.approximateSizeMB` auf 495 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, neuer Unit-Test grün. `HowItWorksView`
        ("Offline-Karten") um Tschechien ergänzt. Live-Offline-Routing in Tschechien vom Nutzer
        noch nicht getestet (kein konkreter Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.czechia`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Slowakei als zwölftes Land ergänzt** (Nutzerwunsch, bewusst ein kleineres Land vor dem
      als groß erwarteten Italien): Größenabschätzung per `curl -I` gegen den Geofabrik-Extrakt
      gecheckt - ~326 MB, mit Abstand die kleinste PBF-Datei unter den "richtigen" Ländern
      (nur Luxemburg war bisher kleiner).
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **1.749
        Routen** (u. a. EuroVelo 6/11/13), **2,9 MB** als `Resources/slovakia.sqlite` gebündelt,
        `"slovakia"` in `RouteRepository.bundledResourceNames` ergänzt. Bauzeit nur 55 s.
        Getestet per neuem Unit-Test `routeRepositoryFindsEuroVeloRouteNearBratislava` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/Wien/Prag).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **317,8 MB**,
        7.143.460 Knoten, 14.551.598 Kanten, 11.359 eindeutige Straßennamen. Baudauer nur
        2:19 Min, kein Speicherdruck.
      - **Neuer Fall `EuropaLand.slovakia`**: `boundingBox` wieder aus dem PBF-Header ermittelt.
      - Release-Asset `slovakia_ways.sqlite` neu unter `way-graphs-eu-v1` hochgeladen, per
        `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.slovakia.approximateSizeMB` auf 318 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, neuer Unit-Test grün. `HowItWorksView`
        ("Offline-Karten") um Slowakei ergänzt. Live-Offline-Routing in der Slowakei vom Nutzer
        noch nicht getestet (kein konkreter Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.slovakia`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Albanien als dreizehntes Land ergänzt** (Nutzerwunsch, bewusst ein weiteres kleines Land
      vor Italien): Größenabschätzung per `curl -I` gegen den Geofabrik-Extrakt gecheckt -
      ~51 MB, mit Abstand die kleinste PBF-Datei bisher (kleiner als Luxemburg).
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - nur **11
        Routen** (u. a. EuroVelo 8 - Mediterranean Route), **~50 KB** als
        `Resources/albania.sqlite` gebündelt, `"albania"` in
        `RouteRepository.bundledResourceNames` ergänzt. Bauzeit nur 11 s - deutlich weniger
        kartierte Radrouten als in den bisherigen Ländern, passend zu Albaniens noch jungem
        OSM-Kartierungsstand für Freizeitrouten. Getestet per neuem Unit-Test
        `routeRepositoryFindsEuroVeloRouteNearVlore` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/Wien/
        Prag/Bratislava).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **140 MB**,
        3.175.449 Knoten, 6.385.826 Kanten, 7.910 eindeutige Straßennamen. Baudauer nur 33 s -
        mit Abstand der schnellste Länder-Build bisher (kleinstes bisher gebautes Land).
      - **Neuer Fall `EuropaLand.albania`**: `boundingBox` wieder aus dem PBF-Header ermittelt.
      - Release-Asset `albania_ways.sqlite` neu unter `way-graphs-eu-v1` hochgeladen, per
        `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.albania.approximateSizeMB` auf 140 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, neuer Unit-Test grün. `HowItWorksView`
        ("Offline-Karten") um Albanien ergänzt. Live-Offline-Routing in Albanien vom Nutzer noch
        nicht getestet (kein konkreter Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.albania`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Zwei Bugs rund um die Ziel-Adresssuche behoben (Live-Fund 2026-08-03, Bückeburger
      Straße 9, Bremen)**: Nutzer stand an der Bückeburger Straße 9 (als Start korrekt per
      "Aktueller Standort" erkannt), gab dieselbe Adresse manuell als Ziel ein und wurde
      stattdessen zur benachbarten Nienburger Straße geleitet - laut Nutzer nicht das erste Mal.
      1. **Adresssuche löste auf falsche, benachbarte Straße auf**: `LocationSearchField.select`
         → `LocationSearchViewModel.resolve(_:)` nahm bei der `MKLocalSearch`-Auflösung einer
         angetippten Adresse bisher blind `response.mapItems.first` - dieser erste Treffer muss
         nicht zwingend der tatsächlich ausgewählten Adresse entsprechen (bekannte
         MapKit-Ungenauigkeit bei benachbarten Straßennamen). **Fix**: `resolve` sucht jetzt
         gezielt nach dem Treffer, dessen `name` zum Titel des angetippten Vorschlags passt
         (diakritik-/groß-kleinschreibungsunabhängig), `.first` bleibt nur Rückfallebene.
      2. **Absturz beim Ziel-Eintippen, beim Live-Test des Fixes oben entdeckt - unabhängiger
         Bug**: App stürzte laut Nutzer zuverlässig ab, sobald das Ziel eingegeben wurde. Vom
         iPhone abgeholtes Crash-Log (`xcrun devicectl device copy from ... --domain-type
         systemCrashLogs`) zeigte `EXC_BAD_ACCESS`/`SIGSEGV` mitten in `libsqlite3.dylib`,
         ausgelöst über `RouteRepository.route(withId:in:)` ← `RouteMatcher.findCombinedMatches`
         ← `ContentView.attemptCombinedThenClosestFallback`. **Ursache**: `ContentView` startet
         die Kombinationssuche über `Task.detached`
         (`attemptCombinedThenClosestFallback`/`attemptCombinedSearchAsAdditionalOption`), mehrere
         solcher Tasks können bei schnell aufeinanderfolgenden `runMatching()`-Aufrufen (z. B.
         beim Eintippen/Auswählen eines Ziels) gleichzeitig laufen - die `Task.isCancelled`-Prüfung
         sitzt erst **nach** dem synchronen SQLite-Teil, ein "veralteter" Task lief also noch mit,
         während schon der nächste startete. `RouteRepository` verwendet dieselben rohen
         `OpaquePointer`-SQLite-Verbindungen für alle Aufrufer, ohne eigene Synchronisierung - zwei
         Threads, die gleichzeitig dieselbe Verbindung benutzten, brachten die Speicherverwaltung
         von SQLite durcheinander. **Fix**: neues `NSLock` in `RouteRepository`, das jede
         öffentliche Methode serialisiert - unabhängig davon, wie viele Tasks gleichzeitig
         Anfragen stellen, läuft immer nur eine SQLite-Operation zur selben Zeit.
      - **Beide Fixes live auf dem iPhone getestet (Nutzer, 2026-08-03)**: kein Absturz mehr, Ziel
        wird korrekt aufgelöst.
      → [LocationSearchViewModel.swift](FahrradApp/RadFaehrte/ViewModels/LocationSearchViewModel.swift)
      (`resolve`, `matches`), [LocationSearchField.swift](FahrradApp/RadFaehrte/Views/LocationSearchField.swift)
      (`select`), [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift)
      (`lock`), [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift)
      (`attemptCombinedThenClosestFallback`, `attemptCombinedSearchAsAdditionalOption`)
- [x] **Italien als vierzehntes Land ergänzt - Aufteilung in 5 Makro-Regionen nötig, aber aus
      einem anderen Grund als bei Frankreich** (Nutzerwunsch): Größenabschätzung per `curl -I`
      gegen den Geofabrik-Extrakt gecheckt - ~2,06 GB, zweitgrößte PBF-Datei bisher (nach
      Frankreich 4,7 GB, vor Polen 1,9 GB). Nutzer vorab gefragt und bestätigt, dass trotzdem als
      Einzeldatei versucht werden soll (anders als bei Polen war hier aber ein zweiter
      Blocker nicht vorherzusehen, s. u.).
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **1.587
        Routen** (u. a. EuroVelo 5/7/8), **7,7 MB** als `Resources/italy.sqlite` gebündelt,
        `"italy"` in `RouteRepository.bundledResourceNames` ergänzt. Bauzeit 6:55 Min. Getestet
        per neuem Unit-Test `routeRepositoryFindsEuroVeloRouteNearRome` (analog
        Rotterdam/Krakau/.../Bratislava/Vlorë) - **dieser Teil funktionierte sofort und ist
        unabhängig vom Wege-Graph-Problem unten live nutzbar**.
      - ⚠️ **Gesamt-Italien-Wege-Graph gebaut, aber am GitHub-2-GiB-Asset-Limit gescheitert**:
        `build_way_graph_v2.py` lief als Einzeldatei durch (**60,8 Mio. Knoten, 121,6 Mio.
        Kanten, 365.821 Straßennamen, 2.675,5 MB Ausgabe**) - allerdings über **10:54 Std**
        Wanduhrzeit (der Mac wurde währenddessen zweimal zugeklappt/schlief, pausierte dabei
        automatisch ohne Datenverlust; zusätzlich musste der Prozess einmal manuell per
        `SIGSTOP`/`SIGCONT` pausiert werden, weil der Akku bei nur noch 33 % ohne verfügbares
        Ladekabel drohte leerzulaufen). Massiver Swap-Einsatz während des Baus (bis zu 8 GB),
        ähnlich dem Frankreich-Muster, aber diesmal lief der Bau tatsächlich durch. **Der
        eigentliche Blocker kam danach**: `gh release upload` scheiterte mit
        `size must be less than 2147483648` - GitHub erlaubt maximal 2 GiB pro Release-Asset,
        die 2,67-GB-Datei lag knapp drüber. Der fertige Wege-Graph war damit für nichts (gelöscht).
      - **Entscheidung**: Wie bei Frankreich in Regionen aufgeteilt, aber Geofabrik bietet für
        Italien nur **5 grobe Makro-Regionen** an (Nord-Ovest, Nord-Est, Centro, Sud, Isole -
        keine feinere Einteilung verfügbar, anders als Frankreichs 21 Regionen). Neuer Typ
        `ItalyRegion` (`DownloadableRegion`-konform wie `FranceRegion`), neues Batch-Skript
        `Scripts/build_italy_regions.sh`, neuer Release-Tag `way-graphs-it-v1`. Alle 5 Regionen
        liefen **beim ersten Durchlauf glatt durch, kein einziger Fehlschlag** - zusammen nur
        **~22:41 Min reine Bauzeit** (vs. 10:54 Std für den nutzlosen Gesamt-Versuch):
        Nord-Ovest 697 MB (15,9 Mio. Knoten, 8:26 Min), Nord-Est 616 MB (14,0 Mio. Knoten,
        5:40 Min), Centro 527 MB (12,1 Mio. Knoten, 3:09 Min), Sud 516 MB (11,7 Mio. Knoten,
        3:36 Min), Isole 343 MB (7,8 Mio. Knoten, 1:50 Min) - alle deutlich unter dem
        2-GiB-Limit.
      - **`OfflineMapsView` für zwei gleichzeitige Sonder-Einträge erweitert**: Der bisherige
        `trailingLabel`/`trailingContent`-Mechanismus (s. o. "Offline-Karten-Listen alphabetisch
        sortiert") konnte nur einen einzelnen Sonder-Eintrag ("Frankreich") korrekt einsortieren.
        Umgebaut auf `extraRows: [ExtraRow]` (`AnyView`-basiert statt eines zweiten generischen
        Typ-Parameters) - jede Zeile trägt ihr eigenes `label` für die Einsortierungs-Position,
        beliebig viele gleichzeitig möglich. "Frankreich" und "Italien" landen dadurch beide an
        ihrer korrekten alphabetischen Position in der Europa-Liste (zwischen Dänemark und
        Luxemburg bzw. zwischen Frankreich und Luxemburg).
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, komplette Test-Suite auf dem iPhone des
        Nutzers grün, App installiert.
      → [Scripts/build_italy_regions.sh](FahrradApp/Scripts/build_italy_regions.sh) (neu),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift) (`ItalyRegion`),
      [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [OfflineMapsView.swift](FahrradApp/RadFaehrte/Views/OfflineMapsView.swift) (`ExtraRow`),
      [RootTabView.swift](FahrradApp/RadFaehrte/RootTabView.swift),
      [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`offlineGraphCandidatePaths`,
      `regionDisplayName`), [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-it-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-it-v1)
- [x] **Spanien als fünfzehntes Land ergänzt - diesmal vorsorglich in 18 Regionen aufgeteilt**
      (Nutzerwunsch, direkt im Anschluss an Italien, mit Lehre aus dessen gescheitertem
      Gesamt-Versuch): Größenabschätzung per `curl -I` gegen den Geofabrik-Extrakt gecheckt -
      ~1,4 GB, kleiner als Polen (1,9 GB, erfolgreich als Einzeldatei gebaut). Trotzdem direkt
      aufgeteilt statt es als Einzeldatei zu versuchen: Italiens Muster (Ausgabe teils größer
      als PBF durch dichte Kartierung, 2,06 GB PBF → 2,67 GB Ausgabe) machte das Risiko real
      genug, um nicht wieder stundenlang umsonst zu bauen (s. o. "Italien als vierzehntes Land").
      - **Kuratierte Routen**: `extract_bicycle_routes.py` auf den Gesamt-Spanien-Extrakt
        angewendet (unabhängig von der Regionen-Aufteilung des Wege-Graphen) - **2.377 Routen**
        (u. a. EuroVelo 1/3/8), **5,3 MB** als `Resources/spain.sqlite` gebündelt, `"spain"` in
        `RouteRepository.bundledResourceNames` ergänzt. Bauzeit 5:29 Min. Getestet per neuem
        Unit-Test `routeRepositoryFindsEuroVeloRouteNearBarcelona` (analog
        Rotterdam/Krakau/.../La Rochelle/Wien/Prag/Bratislava/Vlorë/Rom).
      - **18 Regionen-Wege-Graphen direkt in Format v2** (`build_way_graph_v2.py`, analog
        `Scripts/build_italy_regions.sh` → neues `Scripts/build_spain_regions.sh`) - Geofabrik
        bietet Spanien in den 17 autonomen Gemeinschaften plus den beiden Exklaven Ceuta/Melilla
        an. **Alle 18 liefen beim ersten Durchlauf glatt durch, kein einziger Fehlschlag** -
        zusammen nur **~17:19 Min Gesamtbauzeit** (die vorsorgliche Aufteilung hat sich damit
        klar ausgezahlt: kein einziger Bau musste wiederholt werden, anders als bei Italien).
        Größte Region Cataluña: 608 MB (13,8 Mio. Knoten, 5:37 Min). Kleinste "echte" Region
        La Rioja: 28 MB (0:06 Min). Die beiden Exklaven Ceuta und Melilla waren erwartungsgemäß
        winzig (1,1 MB bzw. 0,8 MB, je unter einer Sekunde Bauzeit) - trotzdem sauber
        durchgelaufen, kein Sonderfall im Skript nötig.
      - **Neuer Typ `SpainRegion`** (`DownloadableRegion`-konform wie `FranceRegion`/
        `ItalyRegion`), neuer Release-Tag `way-graphs-es-v1`. `boundingBox` je Region wieder per
        HTTP-Range-Request ermittelt (s. Frankreich-Eintrag). Dritter `OfflineMapsView.ExtraRow`
        in der Europa-Liste ("Spanien"), landet automatisch an seiner korrekten alphabetischen
        Position (zwischen "Slowakei" und "Schweden"/"Schweiz" - deutsches "Spanien" sortiert
        dort ein).
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, komplette Test-Suite auf dem iPhone des
        Nutzers grün, App installiert.
      → [Scripts/build_spain_regions.sh](FahrradApp/Scripts/build_spain_regions.sh) (neu),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift) (`SpainRegion`),
      [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RootTabView.swift](FahrradApp/RadFaehrte/RootTabView.swift),
      [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`offlineGraphCandidatePaths`,
      `regionDisplayName`), [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-es-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-es-v1)
- [x] **Portugal als sechzehntes Land ergänzt** (Nutzerwunsch, direkt im neuen v2-Format wie zuvor
      Slowakei/Albanien/Tschechien): Größenabschätzung per `curl -I` gegen den Geofabrik-Extrakt
      gecheckt - ~400 MB, ähnliche Größenklasse wie Dänemark/Slowakei, deutlich kleiner als
      Polen/Spanien - deshalb direkt als Einzeldatei gebaut, kein Regionen-Split nötig.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **271
        Routen** (u. a. EuroVelo 1 - Atlantic Coast Route), **904 KB** als
        `Resources/portugal.sqlite` gebündelt, `"portugal"` in
        `RouteRepository.bundledResourceNames` ergänzt. Bauzeit 1:19 Min. Getestet per neuem
        Unit-Test `routeRepositoryFindsEuroVeloRouteNearLisbon` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/Wien/
        Prag/Bratislava/Vlorë/Rom/Barcelona).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **724,3 MB**,
        16.340.987 Knoten, 32.978.210 Kanten, 113.031 eindeutige Straßennamen. Baudauer 7:31 Min.
      - **Neuer Fall `EuropaLand.portugal`**: `boundingBox` aus dem PBF-Header ermittelt -
        auffallend breit (Longitude -33,62° bis -6,18°), da Geofabriks Portugal-Extrakt neben dem
        Festland auch Azoren und Madeira mit abdeckt.
      - Release-Asset `portugal_ways.sqlite` neu unter `way-graphs-eu-v1` hochgeladen, per
        `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.portugal.approximateSizeMB` auf 724 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, komplette Test-Suite (44 Tests, inkl.
        neuem Test) auf dem iPhone des Nutzers grün. `HowItWorksView` ("Offline-Karten") um
        Portugal ergänzt. Live-Offline-Routing in Portugal vom Nutzer noch nicht getestet (kein
        konkreter Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.portugal`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)

- [x] **Einstellungen neu strukturiert** (Nutzer-Wunsch 2026-08-04, im Zuge der
      Favoriten-Ergänzung s. o.: "irgendwie gefällt mir die Anordnung der Einstellungen nicht"):
      vorher 7 Sections, nur "Karte" mit Header, die übrigen kopflos und uneinheitlich (mal Picker
      inline, mal einzelner `NavigationLink` mit Footer) - dadurch wirkte besonders die Kette
      Offline-Karten/Alle Routen/Favoriten wie drei beliebig angehängte, optisch identische
      Ein-Zeilen-Sections statt einer durchdachten Gruppierung. Jetzt 5 Sections, alle mit Header:
      **Darstellung** (Erscheinungsbild + Kartenstil + Kartenausrichtung, vorher auf 2 kopflose
      Sections verteilt), **Navigation** (unverändert, jetzt mit Header), **Offline-Karten**
      (Deutschland + Europa, jetzt mit Header), **Meine Routen & Orte** (Alle Routen + Favoriten neu
      zusammengelegt, ein gemeinsamer Footer statt zwei), **Hilfe** (Wie funktioniert's? + Info,
      jetzt mit Header). Live auf dem iPhone bestätigt ("Passt gut").
      → [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift)
- [x] **Malta als siebzehntes Land ergänzt** (Nutzerwunsch, aus der "noch fehlende Länder"-Liste
      unten ausgewählt): Mit ~8,8 MB PBF mit Abstand das bisher kleinste "richtige" Land (kleiner
      als Luxemburg) - direkt als Einzeldatei gebaut.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - nur **5
        Routen** (EuroVelo 7 - Sun Route, dazu drei lokale SIBIT-Routen), **60 KB** als
        `Resources/malta.sqlite` gebündelt, `"malta"` in `RouteRepository.bundledResourceNames`
        ergänzt. Bauzeit 1,5 s. Getestet per neuem Unit-Test
        `routeRepositoryFindsEuroVeloRouteNearValletta` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/Wien/
        Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **7,3 MB**,
        165.518 Knoten, 324.637 Kanten, 6.249 eindeutige Straßennamen. Baudauer nur 3,4 s - mit
        Abstand der schnellste Länder-Build bisher.
      - **Neuer Fall `EuropaLand.malta`**: `boundingBox` aus dem PBF-Header ermittelt.
      - Release-Asset `malta_ways.sqlite` neu unter `way-graphs-eu-v1` hochgeladen, per `curl -I`
        gegengeprüft (200, korrekte Content-Length). `EuropaLand.malta.approximateSizeMB` auf 8
        gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, komplette Test-Suite (45 Tests, inkl.
        neuem Test) auf dem iPhone des Nutzers grün. `HowItWorksView` ("Offline-Karten") um Malta
        ergänzt. Live-Offline-Routing auf Malta vom Nutzer noch nicht getestet (kein konkreter
        Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.malta`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Andorra als achtzehntes Land ergänzt** (Nutzerwunsch, aus der "noch fehlende Länder"-Liste
      unten ausgewählt): ~3,4 MB PBF, kleiner Bergstaat - direkt als Einzeldatei gebaut.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **16
        Routen** (keine EuroVelo, stattdessen lokale "CIMA"-Bergradrouten, u. a. eine explizit
        "Andorra la Vella" im Namen), **45 KB** als `Resources/andorra.sqlite` gebündelt,
        `"andorra"` in `RouteRepository.bundledResourceNames` ergänzt. Bauzeit 0,8 s. Getestet
        per neuem Unit-Test `routeRepositoryFindsRouteNearAndorraLaVella` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/Wien/
        Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/Valletta).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **6,0 MB**,
        137.772 Knoten, 269.858 Kanten, 823 eindeutige Straßennamen. Baudauer 1,4 s.
      - **Neuer Fall `EuropaLand.andorra`**: `boundingBox` aus dem PBF-Header ermittelt.
      - Release-Asset `andorra_ways.sqlite` neu unter `way-graphs-eu-v1` hochgeladen, per
        `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.andorra.approximateSizeMB` auf 6 gesetzt.
      - **Falscher Alarm beim Verifizieren**: `combinedMatchBerlinToVredenHasPlausibleTotalDistance`
        (der mit Abstand schwerste Test, s. o. "Bugfix: Offline-Routing-Engine wurde... von iOS
        wegen Speicherüberlastung gekillt") crashte mehrfach mit "signal kill" (Jetsam). Per
        `git stash`-Kontrolltest (derselbe Test ohne die Andorra-Änderungen) zunächst fälschlich
        als Regression verdächtigt - stellte sich aber als reine Geräte-Aufheizung heraus: nach
        ca. 10 aufeinanderfolgenden Build-/Testläufen in kurzer Zeit stieg die Laufzeit desselben
        Tests selbst *ohne* Andorra-Code von 58 s auf 135 s. Nach 3 Minuten Gerätepause lief die
        komplette Suite (46 Tests) wieder normal durch (66 s für den Vreden-Test). Lehre: bei
        wiederholten Testläufen in kurzer Folge auf diesem iPhone 13 (4 GB RAM) können einzelne
        besonders speicherhungrige Tests durch Aufheizung/Speicherdruck spontan crashen, unabhängig
        vom tatsächlichen Code-Stand - vor dem Werten eines Fehlschlags hier immer erst eine
        Gerätepause und einen sauberen Wiederholungslauf einplanen.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, komplette Test-Suite (46 Tests, inkl.
        neuem Test) auf dem iPhone des Nutzers grün. `HowItWorksView` ("Offline-Karten") um
        Andorra ergänzt. Live-Offline-Routing in Andorra vom Nutzer noch nicht getestet (kein
        konkreter Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.andorra`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Höhenmeter: Barometer statt GPS-Höhe** - Nutzer-Meldung 2026-08-05 mit Screenshot: Auf einer
      komplett flachen Fahrt in Bremen zeigte die Statistik-Leiste 80 Höhenmeter bergauf an. Ursache
      war genau das bei der Einführung der Statistik-Leiste oben als unverifiziertes Risiko notierte
      Verhalten: `tourElevationGainMeters`/`-LossMeters` summierten roh `CLLocation.altitude`
      (GPS-Höhe) Punkt zu Punkt auf - ohne Barometer stark verrauscht (Fehler im zweistelligen
      Meterbereich), sodass sich das Rauschen bei einer naiven Summe in beide Richtungen zu deutlich
      falschen Werten aufaddiert, selbst wenn die Nettohöhe kaum schwankt.
      - **Fix**: `LocationManager` nutzt jetzt `CMAltimeter` (Luftdrucksensor, den praktisch jedes
        iPhone seit dem 6er hat) für die relative Höhenänderung - genau der Ansatz, den auch
        Komoot/Strava für Höhenmeter verwenden. Neue `elevationGainMeters`/`elevationLossMeters` +
        `resetElevationTracking()`, gestartet/gestoppt zusammen mit den Standort-Updates.
        `ContentView.accumulateTourDistance` spiegelt diese Werte, sobald `isBarometerAvailable`
        `true` ist; nur auf Geräten ganz ohne Barometer bleibt die alte GPS-Punkt-zu-Punkt-Summe als
        Rückfallebene bestehen.
      - Build (Device-Ziel) erfolgreich, auf dem iPhone des Nutzers installiert und gestartet -
        **Live-Verifikation auf einer erneuten flachen Fahrt (Höhenmeter sollte jetzt nahe 0
        bleiben) noch ausstehend**.
      - **Nachtrag 2026-08-05 - App startete danach gar nicht mehr**: Nutzer-Meldung, App stürzt
        beim Start ab. Ursache: Seit iOS 17.5/watchOS 10.5 verlangt `CMAltimeter
        .startRelativeAltitudeUpdates` zwingend den Schlüssel `NSMotionUsageDescription` im
        Info.plist - ohne ihn stürzt die App sofort ab, sobald der Sensor gestartet wird. Das
        passierte hier gleich beim Öffnen: `ContentView`s `.onAppear` ruft
        `locationManager.startUpdating()` auf, wenn die Standortberechtigung schon erteilt ist, und
        das startet direkt `startBarometerUpdates()`. Der Schlüssel fehlte komplett in
        `Supplemental-Info.plist`. **Fix**: `NSMotionUsageDescription` ergänzt. Build (Device-Ziel)
        erneut erfolgreich, per `devicectl` auf dem iPhone installiert und gestartet - **kein
        Absturz mehr beim Start (Nutzer, 2026-08-05)**. Die eigentliche Höhenmeter-Plausibilität
        auf einer flachen Fahrt testet der Nutzer noch separat nach.
      → [LocationManager.swift](FahrradApp/RadFaehrte/Services/LocationManager.swift)
      (`isBarometerAvailable`, `elevationGainMeters`, `elevationLossMeters`,
      `resetElevationTracking`, `startBarometerUpdates`),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`accumulateTourDistance`),
      [Supplemental-Info.plist](FahrradApp/RadFaehrte/Supplemental-Info.plist)
      (`NSMotionUsageDescription`)
- [x] **Sprachausgabe "Jetzt abbiegen" kommt zu spät (Nutzer-Meldung 2026-08-05)**: Zwei
      Ursachen identifiziert, beide behoben:
      - **Warteschlangen-Rückstau**: `VoiceAnnouncer.speak()` rief bisher nur
        `synthesizer.speak(utterance)` auf - `AVSpeechSynthesizer` reiht neue Ansagen dabei nur
        in eine Warteschlange ein statt eine noch laufende zu unterbrechen. Bei dicht
        aufeinanderfolgenden Abbiegungen (oder wenn die frühe "In 100 Metern..."-Ansage noch
        läuft) staute sich das, sodass die dringlichere "Jetzt..."-Ansage - und mit ihr auch die
        nächste "In 100 Metern..."-Ansage der folgenden Abbiegung - erst deutlich verspätet zu
        hören war. **Fix**: `speak()` bricht jetzt eine noch laufende Ansage per
        `stopSpeaking(at: .immediate)` sofort ab, bevor die neue gestartet wird.
      - **Fixer 20-m-Vorlauf ignorierte Tempo**: Die "Jetzt"-Ansage löste bisher bei einem festen
        `voiceNowAnnouncementLeadDistanceMeters = 20` aus. Der gesprochene Satz braucht selbst
        aber ca. 3,5 Sekunden - bei höherem Tempo (z. B. E-Bike) ist der Nutzer am Satzende schon
        über den Abbiegepunkt hinaus. **Fix**: Vorlauf wird jetzt aus dem aktuellen Tempo
        (`location.speed`) berechnet (`voiceNowAnnouncementLeadDistance(for:)` = Tempo ×
        angenommene Sprechdauer, mit Unter-/Obergrenze 15-45 m) statt eines festen Meter-Werts.
      - Build fürs Gerät erfolgreich, per `devicectl` auf "iPhone von Jörn" installiert -
        **live auf einer echten Fahrt noch nicht verifiziert**.
      - **Nachtrag (noch am selben Tag, 2026-08-05)**: Nutzer meldete einen weiteren Fall - bei
        einer Tour am selben Morgen war die Sprachausgabe aktiviert, blieb bei der ersten
        Abbiegung aber stumm; nach Aus- und Wiedereinschalten des Schalters ging es. Ursache:
        `VoiceAnnouncer` aktivierte die `AVAudioSession` bisher nur faul beim allerersten
        `speak()`-Aufruf - wird eine Audio-Session zum ersten Mal aktiviert und im selben Moment
        schon gesprochen, kann iOS die allererste Äußerung verschlucken, weil die Audio-Route
        noch nicht steht (kein Fehler, einfach lautlos). Das Umschalten selbst hat vermutlich
        nichts repariert (der Schalter aktiviert keine Audio-Session), sondern zufällig zeitlich
        mit der nächsten - dann funktionierenden - Ansage zusammengefallen. **Fix**: neue Methode
        `VoiceAnnouncer.prepare()` aktiviert die Audio-Session bereits proaktiv in
        `ContentView.startNavigating()`, statt erst bei der ersten echten Ansage - dem System
        bleibt so Zeit, die Route aufzubauen, bevor tatsächlich gesprochen wird. Zusätzlich
        geprüft: `isVoiceGuidanceEnabled` hat als Default `true` und wird über `@AppStorage`
        sofort bei jeder Änderung persistiert (nicht erst beim Beenden) - entspricht bereits dem
        Nutzer-Wunsch ("bei Erstinstallation an, Änderungen bleiben über Neustarts erhalten"),
        keine Änderung nötig. Build fürs Gerät erfolgreich, per `devicectl` auf "iPhone von Jörn"
        installiert - **live auf einer echten Fahrt noch nicht verifiziert**.
      - **Nachtrag (Live-Test 2026-08-05)**: Nutzer bestätigte, die Sprachausgabe funktioniere
        jetzt besser (kein stummes Erstversagen mehr), die "Jetzt"-Ansage dürfe aber noch ca. 5 m
        früher kommen. Neue `voiceNowAnnouncementSafetyMarginMeters = 5` als pauschaler Aufschlag
        auf den tempoabhängigen Vorlauf - bewusst nicht über eine höhere Sprechdauer-Schätzung
        gelöst, da sich das bei niedrigem Tempo mit der Untergrenze verwässert hätte.
        Unter-/Obergrenze dafür ebenfalls von 15/45 auf 20/50 m angehoben, damit der Vorlauf über
        den ganzen Tempobereich einheitlich 5 m früher liegt. Build fürs Gerät erfolgreich, per
        `devicectl` auf "iPhone von Jörn" installiert - **live noch nicht erneut verifiziert**.
      - **Nachtrag (Nutzer-Feedback 2026-08-06)**: Die tempoabhängige Berechnung funktionierte in
        der Praxis weiterhin nicht gut. Auf Wunsch des Nutzers zurück auf einen festen,
        tempounabhängigen Vorlauf von 40 m (`voiceNowAnnouncementLeadDistanceMeters`) - die ganze
        Tempo-/Sprechdauer-Logik (`voiceNowAnnouncementLeadDistance(for:)`,
        `voiceNowAnnouncementSpeechDurationEstimate`, `voiceNowAnnouncementSafetyMarginMeters`,
        Unter-/Obergrenzen) entfernt. Build fürs Gerät erfolgreich, per `devicectl` auf "iPhone von
        Jörn" installiert - **live noch nicht verifiziert**.
      - **Nachtrag (Live-Test 2026-08-07, mit Screenshots belegt)**: Nutzer meldete falsche
        Straßennamen in den Ansagen die ganze Fahrt über - z. B. kurz vor der Abbiegung auf
        "Humboldtstraße" (Kopfzeile zeigte korrekt "Links abbiegen auf Humboldtstraße, In 20 m")
        sagte die Sprachausgabe stattdessen "Jetzt abbiegen auf St.-Jürgen-Straße" (die bereits
        gefahrene, vorherige Straße). **Ursache gefunden**: echter Off-by-one-Bug in
        `advanceDirectRouteStepIfNeeded` - die "Jetzt"-Ansage nutzte `steps[currentIndex]`, das
        laut `previewedStep`-Konvention aber die Anweisung beschreibt, mit der man den *aktuellen*
        Schritt betreten hat (also die schon erledigte Abbiegung), nicht die bevorstehende am
        Ende des aktuellen Schritts. Kopfzeile und die frühe "In X Metern"-Ansage
        (`checkTurnAnnouncementTrigger`) nutzten dafür schon korrekt `steps[currentIndex + 1]`
        (`previewedStep`) - nur die "Jetzt"-Ansage hatte den Fehler, und zwar bei praktisch jeder
        Abbiegung. **Fix**: `advanceDirectRouteStepIfNeeded` verwendet jetzt ebenfalls
        `steps[currentIndex + 1]` für Text und `isTurnInstruction`-Prüfung. Der vom Nutzer separat
        gemeldete Fall (Screenshot 1: "In 100 Metern ..."-Ansage kam erst nach dem Abbiegen zu
        hören, inhaltlich aber wohl korrekt) ist vermutlich ein Nebeneffekt desselben Bugs (die
        fehlerhafte "Jetzt"-Ansage konnte im Sprach-Puffer die korrekte verdrängen/verzögern) -
        nicht separat behoben, da kein eigener Fehler dafür gefunden wurde. Build fürs Gerät
        erfolgreich, per `devicectl` auf "iPhone von Jörn" installiert.
      - **Nachtrag (Live-Test-Bestätigung 2026-08-07)**: Nutzer bestätigte, der Off-by-one-Fix
        funktioniert - die "Jetzt"-Ansage nennt jetzt die richtige (bevorstehende) Straße. Zugleich
        Wunsch geäußert, die frühe "In 100 Metern ..."-Sprachansage (`checkTurnAnnouncementTrigger`)
        ganz wegzulassen - die "Jetzt"-Ansage kurz vor der Abbiegung reicht. **Fix**: den
        `voiceAnnouncer.speak(...)`-Aufruf dort entfernt, das Watch-Haptik-Signal
        (`watchHapticTriggerCounter`) an derselben Stelle bleibt unverändert erhalten. Damit ist
        dieser Roadmap-Punkt abgeschlossen. Build fürs Gerät erfolgreich, per `devicectl` auf
        "iPhone von Jörn" installiert - **live noch nicht verifiziert**.
      → [VoiceAnnouncer.swift](FahrradApp/RadFaehrte/Services/VoiceAnnouncer.swift) (`speak`,
      `prepare`), [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift)
      (`voiceNowAnnouncementLeadDistanceMeters`, `advanceDirectRouteStepIfNeeded`,
      `previewedStep`, `checkTurnAnnouncementTrigger`, `startNavigating`)
- [x] **Liechtenstein als neunzehntes Land ergänzt** (Nutzerwunsch, aus der "noch fehlende
      Länder"-Liste unten ausgewählt): ~3,4 MB PBF, kleiner Alpenstaat - direkt als Einzeldatei
      gebaut.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **18
        Routen** (u. a. EuroVelo 15 - Rheinradweg), **32 KB** als `Resources/liechtenstein.sqlite`
        gebündelt, `"liechtenstein"` in `RouteRepository.bundledResourceNames` ergänzt. Bauzeit
        0,8 s. Getestet per neuem Unit-Test `routeRepositoryFindsEuroVeloRouteNearVaduz` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/Wien/
        Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/Valletta/Andorra la Vella).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **3,9 MB**,
        87.311 Knoten, 177.308 Kanten, 1.003 eindeutige Straßennamen. Baudauer 1,3 s.
      - **Neuer Fall `EuropaLand.liechtenstein`**: `boundingBox` aus dem PBF-Header ermittelt.
      - Release-Asset `liechtenstein_ways.sqlite` neu unter `way-graphs-eu-v1` hochgeladen, per
        `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.liechtenstein.approximateSizeMB` auf 4 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, komplette Test-Suite (47 Tests, inkl.
        neuem Test, u. a. den beim vorigen Mal gecrashten `combinedMatchBerlinToVredenHasPlausibleTotalDistance`
        jetzt wieder normal bei 77 s) auf dem iPhone des Nutzers grün - diesmal ohne
        Aufheiz-Zwischenfall. `HowItWorksView` ("Offline-Karten") um Liechtenstein ergänzt.
        Live-Offline-Routing in Liechtenstein vom Nutzer noch nicht getestet (kein konkreter
        Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.liechtenstein`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Monaco als zwanzigstes Land ergänzt** (Nutzerwunsch, aus der "noch fehlende Länder"-Liste
      unten ausgewählt): ~0,7 MB PBF, mit Abstand die kleinste PBF-Datei bisher (kleiner als
      Andorra/Liechtenstein) - direkt als Einzeldatei gebaut.
      - **Keine kuratierten Routen**: `extract_bicycle_routes.py` findet **0**
        `route=bicycle`-Relationen - erwartbar bei diesem winzigen Stadtstaat. Deshalb kein
        `Resources/monaco.sqlite`, kein Eintrag in `RouteRepository.bundledResourceNames` und
        kein neuer Unit-Test (nichts zu finden). Monaco bekommt damit nur den Offline-Wege-Graph
        für "Direkte Fahrrad-Route", keine kuratierte Routensuche.
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **0,3 MB**,
        7.853 Knoten, 13.012 Kanten, 236 eindeutige Straßennamen. Baudauer 0,2 s - kleinster und
        schnellster Länder-Build bisher.
      - **Neuer Fall `EuropaLand.monaco`**: `boundingBox` aus dem PBF-Header ermittelt - reicht
        mit ca. 20 km Breite deutlich über das eigentliche Stadtgebiet (< 4 km) hinaus, da
        Geofabriks Extrakt einen kleinen Rand ins angrenzende Frankreich mitnimmt.
      - Release-Asset `monaco_ways.sqlite` neu unter `way-graphs-eu-v1` hochgeladen, per
        `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.monaco.approximateSizeMB` auf 1 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, komplette Test-Suite (47 Tests) auf dem
        iPhone des Nutzers grün - `combinedMatchBerlinToVredenHasPlausibleTotalDistance` crashte
        im ersten Durchlauf direkt nach der Liechtenstein-Sitzung erneut mit Jetsam-Kill (Gerät
        noch aufgeheizt), lief nach 3 Minuten Pause aber wieder durch (114 s, spürbar langsamer
        als der Normalwert ~65 s, aber stabil). `HowItWorksView` ("Offline-Karten") um Monaco
        ergänzt. Live-Offline-Routing in Monaco vom Nutzer noch nicht getestet (kein konkreter
        Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.monaco`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Nordmazedonien als einundzwanzigstes Land ergänzt** (Nutzerwunsch, aus der "noch fehlende
      Länder"-Liste unten ausgewählt): ~29,5 MB PBF - direkt als Einzeldatei gebaut.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **12
        Routen** (u. a. EuroVelo 11 - East Europe Route, EuroVelo 13 - Iron Curtain Trail),
        **60 KB** als `Resources/macedonia.sqlite` gebündelt (Fallname `.macedonia` als
        offizieller Geofabrik-Slug gewählt, analog zu den anderen kurzen Länder-Fallnamen -
        `displayName` zeigt trotzdem "Nordmazedonien"), `"macedonia"` in
        `RouteRepository.bundledResourceNames` ergänzt. Bauzeit 5,5 s. Getestet per neuem
        Unit-Test `routeRepositoryFindsEuroVeloRouteNearSkopje` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/Wien/
        Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/Valletta/Andorra la Vella/Vaduz).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **62,8 MB**,
        1.420.513 Knoten, 2.863.787 Kanten, 3.616 eindeutige Straßennamen. Baudauer 13,5 s.
      - **Neuer Fall `EuropaLand.macedonia`**: `boundingBox` aus dem PBF-Header ermittelt.
      - Release-Asset `macedonia_ways.sqlite` (größer als bisherige Uploads, Hintergrundprozess
        nötig) neu unter `way-graphs-eu-v1` hochgeladen, per `curl -I` gegengeprüft (200,
        korrekte Content-Length). `EuropaLand.macedonia.approximateSizeMB` auf 63 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, komplette Test-Suite (48 Tests, inkl.
        neuem Test) auf dem iPhone des Nutzers grün, diesmal ohne Aufheiz-Zwischenfall (Vreden-Test
        bei normalen 74 s). `HowItWorksView` ("Offline-Karten") um Nordmazedonien ergänzt.
        Live-Offline-Routing in Nordmazedonien vom Nutzer noch nicht getestet (kein konkreter
        Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.macedonia`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Kosovo als zweiundzwanzigstes Land ergänzt** (Nutzerwunsch, aus der "noch fehlende
      Länder"-Liste unten ausgewählt): ~30,6 MB PBF - direkt als Einzeldatei gebaut.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **6
        Routen** (keine EuroVelo, stattdessen lokale Radwanderwege im Rugova-Gebirge bei Peja/Peć
        im Westen des Landes), **32 KB** als `Resources/kosovo.sqlite` gebündelt, `"kosovo"` in
        `RouteRepository.bundledResourceNames` ergänzt. Bauzeit 5,8 s. Getestet per neuem
        Unit-Test `routeRepositoryFindsRouteNearPeja` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/Wien/
        Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/Valletta/Andorra la Vella/Vaduz/Skopje).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **57,6 MB**,
        1.300.570 Knoten, 2.620.104 Kanten, 17.153 eindeutige Straßennamen. Baudauer 14,9 s -
        auffallend viele eindeutige Straßennamen für die PBF-Größe (mehr als Nordmazedonien bei
        ähnlicher Kantenzahl).
      - **Neuer Fall `EuropaLand.kosovo`**: `boundingBox` aus dem PBF-Header ermittelt.
      - Release-Asset `kosovo_ways.sqlite` (Hintergrundprozess, wie schon bei Nordmazedonien)
        neu unter `way-graphs-eu-v1` hochgeladen, per `curl -I` gegengeprüft (200, korrekte
        Content-Length). `EuropaLand.kosovo.approximateSizeMB` auf 58 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, komplette Test-Suite (49 Tests, inkl.
        neuem Test) auf dem iPhone des Nutzers grün, ohne Aufheiz-Zwischenfall (Vreden-Test bei
        normalen 76 s). `HowItWorksView` ("Offline-Karten") um Kosovo ergänzt. Live-Offline-Routing
        in Kosovo vom Nutzer noch nicht getestet (kein konkreter Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.kosovo`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Montenegro als dreiundzwanzigstes Land ergänzt** (Nutzerwunsch, aus der "noch fehlende
      Länder"-Liste unten ausgewählt): ~34,0 MB PBF - direkt als Einzeldatei gebaut.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **75
        Routen** (u. a. EuroVelo 8 - Mediterranean Route entlang der Küste), **512 KB** als
        `Resources/montenegro.sqlite` gebündelt, `"montenegro"` in
        `RouteRepository.bundledResourceNames` ergänzt. Bauzeit 6,6 s. Getestet per neuem
        Unit-Test `routeRepositoryFindsEuroVeloRouteNearBudva` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/Wien/
        Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/Valletta/Andorra la Vella/Vaduz/Skopje/Peja).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **70,3 MB**,
        1.595.133 Knoten, 3.206.198 Kanten, 3.150 eindeutige Straßennamen. Baudauer 15,9 s.
      - **Neuer Fall `EuropaLand.montenegro`**: `boundingBox` aus dem PBF-Header ermittelt.
      - Release-Asset `montenegro_ways.sqlite` (Hintergrundprozess, wie schon bei
        Nordmazedonien/Kosovo) neu unter `way-graphs-eu-v1` hochgeladen, per `curl -I`
        gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.montenegro.approximateSizeMB` auf 70 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, komplette Test-Suite (50 Tests, inkl.
        neuem Test) auf dem iPhone des Nutzers grün, ohne Aufheiz-Zwischenfall (Vreden-Test bei
        normalen 79 s). `HowItWorksView` ("Offline-Karten") um Montenegro ergänzt.
        Live-Offline-Routing in Montenegro vom Nutzer noch nicht getestet (kein konkreter
        Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.montenegro`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Bosnien und Herzegowina als vierundzwanzigstes Land ergänzt** (Nutzerwunsch, aus der
      "noch fehlende Länder"-Liste unten ausgewählt): ~159,9 MB PBF - direkt als Einzeldatei
      gebaut.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **80
        Routen** (keine durchgehende EuroVelo-Route, nur kurze EV6-/EV8-Anschlussstücke an den
        Grenzen; sonst v. a. lokale Radrouten wie "Biciklistička staza Ćiro" und eine Route bei
        Baščaršija, Sarajevos Altstadt), **299 KB** als `Resources/bosnia-herzegovina.sqlite`
        gebündelt, `"bosnia-herzegovina"` in `RouteRepository.bundledResourceNames` ergänzt.
        Bauzeit 32,5 s. Getestet per neuem Unit-Test `routeRepositoryFindsRouteNearSarajevo`
        (analog Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/
        Wien/Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/Valletta/Andorra la Vella/Vaduz/Skopje/
        Peja/Budva).
      - **Neuer Fall `EuropaLand.bosniaHerzegovina`**: Fallname mit explizitem
        `rawValue = "bosnia-herzegovina"` gewählt (Swift-Identifier kann keine Bindestriche
        enthalten), analog `SpainRegion.castillaLaMancha = "castilla-la-mancha"`. `boundingBox`
        aus dem PBF-Header ermittelt.
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **222,6 MB**,
        5.042.878 Knoten, 10.163.661 Kanten, 8.092 eindeutige Straßennamen. Baudauer 78,5 s -
        größtes bisher gebautes Land seit der Balkan-Serie (Nordmazedonien/Kosovo/Montenegro
        lagen alle deutlich darunter).
      - Release-Asset `bosnia-herzegovina_ways.sqlite` (Hintergrundprozess, größter Upload seit
        Nordmazedonien) neu unter `way-graphs-eu-v1` hochgeladen, per `curl -I` gegengeprüft
        (200, korrekte Content-Length). `EuropaLand.bosniaHerzegovina.approximateSizeMB` auf 223
        gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, komplette Test-Suite (51 Tests, inkl.
        neuem Test) auf dem iPhone des Nutzers grün - `combinedMatchBerlinToVredenHasPlausibleTotalDistance`
        crashte im ersten Durchlauf direkt nach den rechenintensiven Bosnien-Läufen erneut mit
        Jetsam-Kill (bekanntes Aufheiz-Muster, s. o. "Andorra als achtzehntes Land ergänzt"),
        lief nach 3 Minuten Pause aber wieder normal durch (70 s). `HowItWorksView`
        ("Offline-Karten") um Bosnien und Herzegowina ergänzt. Live-Offline-Routing in Bosnien
        und Herzegowina vom Nutzer noch nicht getestet (kein konkreter Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.bosniaHerzegovina`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Serbien als fünfundzwanzigstes Land ergänzt** (Nutzerwunsch, aus der "noch fehlende
      Länder"-Liste unten ausgewählt): ~238,3 MB PBF - direkt als Einzeldatei gebaut.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **87
        Routen** (u. a. EuroVelo 6 - Atlantic-Black Sea entlang der Donau durch Belgrad,
        EuroVelo 13 - Iron Curtain Trail), **762 KB** als `Resources/serbia.sqlite` gebündelt,
        `"serbia"` in `RouteRepository.bundledResourceNames` ergänzt. Bauzeit 43,8 s. Getestet
        per neuem Unit-Test `routeRepositoryFindsEuroVeloRouteNearBelgrade` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/Wien/
        Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/Valletta/Andorra la Vella/Vaduz/Skopje/
        Peja/Budva/Sarajevo).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **355,4 MB**,
        8.012.494 Knoten, 16.212.738 Kanten, 31.643 eindeutige Straßennamen. Baudauer 2:02 Min -
        größtes bisher gebautes Land seit der Balkan-Serie, deutlich über Bosnien und Herzegowina.
      - **Neuer Fall `EuropaLand.serbia`**: `boundingBox` aus dem PBF-Header ermittelt.
      - Release-Asset `serbia_ways.sqlite` (Hintergrundprozess, größter Upload bisher) neu unter
        `way-graphs-eu-v1` hochgeladen, per `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.serbia.approximateSizeMB` auf 355 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, komplette Test-Suite (52 Tests, inkl.
        neuem Test) auf dem iPhone des Nutzers grün, diesmal ohne Aufheiz-Zwischenfall (Vreden-Test
        bei normalen 66 s). `HowItWorksView` ("Offline-Karten") um Serbien ergänzt.
        Live-Offline-Routing in Serbien vom Nutzer noch nicht getestet (kein konkreter
        Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.serbia`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Kroatien als sechsundzwanzigstes Land ergänzt** (Nutzerwunsch, aus der "noch fehlende
      Länder"-Liste unten ausgewählt): ~198,1 MB PBF - direkt als Einzeldatei gebaut.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **597
        Routen** (mit Abstand die meisten bisher - u. a. EuroVelo 6, 8, 9 und 13), **1,9 MB** als
        `Resources/croatia.sqlite` gebündelt, `"croatia"` in
        `RouteRepository.bundledResourceNames` ergänzt. Bauzeit 38,1 s. Getestet per neuem
        Unit-Test `routeRepositoryFindsEuroVeloRouteNearSplit` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/Wien/
        Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/Valletta/Andorra la Vella/Vaduz/Skopje/
        Peja/Budva/Sarajevo/Belgrad).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **243,8 MB**,
        5.508.411 Knoten, 11.124.774 Kanten, 23.705 eindeutige Straßennamen. Baudauer 1:29 Min.
      - **Neuer Fall `EuropaLand.croatia`**: `boundingBox` aus dem PBF-Header ermittelt.
      - Release-Asset `croatia_ways.sqlite` (Hintergrundprozess) neu unter `way-graphs-eu-v1`
        hochgeladen, per `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.croatia.approximateSizeMB` auf 244 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, komplette Test-Suite (53 Tests, inkl.
        neuem Test) auf dem iPhone des Nutzers grün, ohne Aufheiz-Zwischenfall (Vreden-Test bei
        normalen 67 s). `HowItWorksView` ("Offline-Karten") um Kroatien ergänzt.
        Live-Offline-Routing in Kroatien vom Nutzer noch nicht getestet (kein konkreter
        Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.croatia`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Slowenien als siebenundzwanzigstes Land ergänzt** (Nutzerwunsch, aus der "noch fehlende
      Länder"-Liste unten ausgewählt): ~310,7 MB PBF - direkt als Einzeldatei gebaut.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **392
        Routen** (u. a. EuroVelo 8, 9 und 13), **1,2 MB** als `Resources/slovenia.sqlite`
        gebündelt, `"slovenia"` in `RouteRepository.bundledResourceNames` ergänzt. Bauzeit
        59,1 s. Getestet per neuem Unit-Test `routeRepositoryFindsEuroVeloRouteNearLjubljana`
        (analog Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/
        Wien/Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/Valletta/Andorra la Vella/Vaduz/Skopje/
        Peja/Budva/Sarajevo/Belgrad/Split).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **255,4 MB**,
        5.775.729 Knoten, 11.667.277 Kanten, 11.300 eindeutige Straßennamen. Baudauer 1:55 Min.
      - **Neuer Fall `EuropaLand.slovenia`**: `boundingBox` aus dem PBF-Header ermittelt.
      - Release-Asset `slovenia_ways.sqlite` (Hintergrundprozess) neu unter `way-graphs-eu-v1`
        hochgeladen, per `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.slovenia.approximateSizeMB` auf 255 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, komplette Test-Suite (54 Tests, inkl.
        neuem Test) auf dem iPhone des Nutzers grün, ohne Aufheiz-Zwischenfall (Vreden-Test bei
        normalen 63 s). `HowItWorksView` ("Offline-Karten") um Slowenien ergänzt.
        Live-Offline-Routing in Slowenien vom Nutzer noch nicht getestet (kein konkreter
        Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.slovenia`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Bulgarien als achtundzwanzigstes Land ergänzt** (Nutzerwunsch, aus der "noch fehlende
      Länder"-Liste unten ausgewählt): ~171,2 MB PBF - direkt als Einzeldatei gebaut.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **64
        Routen** (u. a. EuroVelo 6 entlang der Donau, EuroVelo 13 - Iron Curtain Trail), **504 KB**
        als `Resources/bulgaria.sqlite` gebündelt, `"bulgaria"` in
        `RouteRepository.bundledResourceNames` ergänzt. Bauzeit 32,1 s. Getestet per neuem
        Unit-Test `routeRepositoryFindsEuroVeloRouteNearSofia` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/Wien/
        Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/Valletta/Andorra la Vella/Vaduz/Skopje/
        Peja/Budva/Sarajevo/Belgrad/Split/Ljubljana).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **268,0 MB**,
        5.964.106 Knoten, 12.299.650 Kanten, 14.054 eindeutige Straßennamen. Baudauer 1:22 Min.
      - **Neuer Fall `EuropaLand.bulgaria`**: `boundingBox` aus dem PBF-Header ermittelt.
      - Release-Asset `bulgaria_ways.sqlite` (Hintergrundprozess) neu unter `way-graphs-eu-v1`
        hochgeladen, per `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.bulgaria.approximateSizeMB` auf 268 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, komplette Test-Suite (55 Tests, inkl.
        neuem Test) auf dem iPhone des Nutzers grün, ohne Aufheiz-Zwischenfall (Vreden-Test bei
        normalen 76 s). `HowItWorksView` ("Offline-Karten") um Bulgarien ergänzt.
        Live-Offline-Routing in Bulgarien vom Nutzer noch nicht getestet (kein konkreter
        Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.bulgaria`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Ungarn als neunundzwanzigstes Land ergänzt** (Nutzerwunsch, aus der "noch fehlende
      Länder"-Liste unten ausgewählt): ~321,6 MB PBF - direkt als Einzeldatei gebaut.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **564
        Routen** (u. a. EuroVelo 6 entlang der Donau durch Budapest, EuroVelo 11, EuroVelo 13),
        **1,7 MB** als `Resources/hungary.sqlite` gebündelt, `"hungary"` in
        `RouteRepository.bundledResourceNames` ergänzt. Bauzeit 58,9 s. Getestet per neuem
        Unit-Test `routeRepositoryFindsEuroVeloRouteNearBudapest` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/Wien/
        Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/Valletta/Andorra la Vella/Vaduz/Skopje/
        Peja/Budva/Sarajevo/Belgrad/Split/Ljubljana/Sofia).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **308,8 MB**,
        6.850.905 Knoten, 14.175.804 Kanten, 32.966 eindeutige Straßennamen. Baudauer 2:30 Min -
        größtes bisher gebautes Land.
      - **Neuer Fall `EuropaLand.hungary`**: `boundingBox` aus dem PBF-Header ermittelt.
      - Release-Asset `hungary_ways.sqlite` (Hintergrundprozess) neu unter `way-graphs-eu-v1`
        hochgeladen, per `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.hungary.approximateSizeMB` auf 309 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, komplette Test-Suite (56 Tests, inkl.
        neuem Test) auf dem iPhone des Nutzers grün, ohne Aufheiz-Zwischenfall (Vreden-Test bei
        normalen 65 s). `HowItWorksView` ("Offline-Karten") um Ungarn ergänzt.
        Live-Offline-Routing in Ungarn vom Nutzer noch nicht getestet (kein konkreter
        Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.hungary`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [~] **Kleiner Schlenker in der Offline-Routing-Engine an Kreuzungen mit uneinheitlich
      getaggtem Radweg** (Nutzer-Meldung 2026-08-06, mit Foto: an einer Kreuzung Bei den drei
      Pfählen/Am Hulsberg schlug die Route einen kleinen Rechts-Schlenker zur Ampel-Aufstellfläche
      vor, obwohl es geradeaus weitergeht):
      - **Erster Versuch (verworfen als Hauptursache, aber beibehalten)**: Vermutet als
        Pfadwahl-Problem - `BikeRoutingEngine.search` bewertete Kanten bisher rein nach
        `edge.weight` (Distanz × Straßentyp-Faktor inkl. Radweg-Bonus), ohne Berücksichtigung des
        gefahrenen Winkels. Neuer `turnPenaltyMetersPerDegree`-Malus (1,0 m/Grad) ergänzt, auf
        `gScore` addiert (nicht auf `realDistance`). **Live-Test durch den Nutzer** (Routenvorschau
        für dieselbe Kreuzung zu Hause angeschaut, ohne echte Fahrt - Screenshot) zeigte: Schlenker
        weiterhin sichtbar, Malus wirkungslos für diesen Fall. Bleibt trotzdem im Code (schadet
        nicht, könnte anderswo echte Zickzack-Pfadwahl noch verhindern).
      - **Tatsächliche Ursache gefunden** per Overpass-Abfrage der OSM-Daten an der Kreuzung: "Bei
        den Drei Pfählen" ist dort in mehrere kurze Way-Segmente zerschnitten, uneinheitlich
        getaggt - vor der Kreuzung `cycleway:right=track` (eindeutige Seite, Linie wird 3,5 m
        versetzt gezeichnet, s. `cycleOffsetMeters`), genau an der Kreuzung ein ~30 m langes Stück
        mit `cycleway:both=track` (keine eindeutige Seite laut `offset_side` in
        `build_way_graph.py` - bewusst kein Versatz bei mehrdeutigen Tags, s. Kommentar dort),
        danach wieder eindeutig getaggt. Reines Darstellungs-Artefakt in
        `BikeRoutingEngine.displayCoordinates` (Linie springt kurz zurück zur Fahrbahnmitte und
        wieder heraus), keine tatsächlich andere Pfadwahl - Grund, warum der Abbiege-Malus nichts
        bewirkte. **Fix**: neue `smoothedOffsetSides`-Funktion überbrückt kurze Lücken ohne
        eindeutige Seite (`maxSmoothedGapMeters = 50`), wenn die Abschnitte davor und danach
        dieselbe eindeutige Seite haben - rein clientseitige Nachbearbeitung, kein Neubau/Upload
        der Wege-Graphen nötig. Bei widersprüchlichen Seiten oder längeren Lücken bleibt es wie
        bisher bei "keine Seite behaupten". **Vom Nutzer bestätigt** (Routenvorschau erneut
        angeschaut, 2026-08-07): Schlenker an dieser Kreuzung weg, "klappt schon viel besser".
      - **Zweiter, unabhängiger Fall (Nutzer-Meldung 2026-08-07, live auf einer echten Fahrt
        beobachtet: "mini Schlenker mit Abbiegehinweis" auf Am Hulsberg Richtung Bei den Drei
        Pfählen)**: Diesmal per echter GPS-Aufzeichnung aus dem "Verlauf" diagnostiziert statt
        geschätzter Adress-Koordinaten (`xcrun devicectl device copy from` mit
        `--domain-type appDataContainer --domain-identifier com.frankenfeld.RadFaehrte --source
        /Documents/DrivenTours`, dann dieselbe A*-Suche standalone gegen die heruntergeladene
        `bremen_ways.sqlite` laufen lassen, s. u. "Live-Debugging" für die Technik). Ursache:
        Die Route nutzt zwischen "Am Schwarzen Meer" und "Am Hulsberg" einen ~800 m langen
        unbenannten Verbindungsweg; `buildSteps` gruppiert Schritte nach Straßenname, meldet also
        an beiden Enden dieses unbenannten Abschnitts eine eigene Abbiegung. Der Winkel dafür kam
        bisher aus **nur einer einzelnen angrenzenden Kante** (`bearing(ofEdgeEndingAt:)`) - an
        einer der beiden Namensgrenzen war diese Kante nur 2,4 m kurz (OSM-Digitalisierungsdetail,
        keine echte Kreuzung), ihre Einzel-Peilung wich stark vom tatsächlichen, sanften
        Streckenverlauf ab und löste ein falsches "Rechts abbiegen" ganz ohne Straßennamen aus.
        **Fix**: neue `windowedBearing`-Funktion (ersetzt `bearing(ofEdgeEndingAt:)`) läuft ab der
        Namensgrenze mindestens `turnBearingWindowMeters = 15` m weit über mehrere Kanten
        rückwärts/vorwärts, bevor sie die Peilung misst - dämpft kurze Störkanten, ohne echte
        Abbiegungen zu verschlucken. Vorab gegen die echte GPS-Teststrecke verifiziert (Standalone-
        Tool, s. u.): falsches "Rechts abbiegen" für den unbenannten Weg verschwindet, wird
        korrekt zu "Route folgen". Build fürs Gerät erfolgreich, per `devicectl` auf "iPhone von
        Jörn" installiert - **auf einer echten Fahrt über dieselbe Stelle noch nicht erneut
        verifiziert**.
      → [BikeRoutingEngine.swift](FahrradApp/RadFaehrte/Services/BikeRoutingEngine.swift)
      (`turnPenaltyMetersPerDegree`, `search`, `maxSmoothedGapMeters`, `smoothedOffsetSides`,
      `displayCoordinates`, `turnBearingWindowMeters`, `windowedBearing`, `buildSteps`)
- [x] **"Los"-Button blass/deaktiviert, solange Routendaten für die Navigation noch nachgeladen
      werden (Nutzerwunsch 2026-08-06)**: Der Button erschien bisher sofort tippbar, sobald eine
      Route ausgewählt war (`selectedMatch`/`combinedMatch`/`isDirectRouteMode`), auch während im
      Hintergrund noch Daten für die eigentliche Turn-by-Turn-Navigation geladen wurden - bei der
      "Direkten Fahrrad-Route" die Alternativrouten (`isLoadingDirectRoute`), bei kuratierten
      Einzel-/Kombi-Treffern die angereicherten Abbiege-Hinweise (`curatedRoute`, bisher ganz ohne
      eigenes Lade-Flag). Neues `isPreparingCuratedRouteForNavigation`-Flag (gesetzt/zurückgesetzt
      in `loadCuratedRouteForNavigation`/`loadCuratedRouteForNavigation(forCombined:)`) plus neue
      berechnete `isPreparingSelectedRouteForStart`, per `.disabled(...)` auf den "Los"-Button
      angewendet - SwiftUIs Standard-Deaktivierungsstil blasst den Button dabei automatisch aus.
      **Auf dem Gerät vom Nutzer verifiziert** (Hannover-Suche): Button zunächst blass
      korrekt, kurzzeitig wirkte es wie ein Fehler, weil er blau wurde, während die "Direkte
      Fahrrad-Route"-Zeile noch einen Ladespinner zeigte - Ursache war aber kein Fehler in dieser
      Änderung, sondern bestehendes Verhalten: `runMatching()` wählt bei jeder neuen Suche
      zunächst automatisch "Direkte Fahrrad-Route" vor, eine parallel gefundene Kombination
      überschreibt diese Vorauswahl aber automatisch (`combinedMatch = combined.first`, s.
      `attemptCombinedThenClosestFallback`) - der Button folgte danach korrekt der neuen Auswahl
      (Kombination), während die inzwischen abgewählte Direktroute im Hintergrund weiterlud. Vom
      Nutzer nach Rückfrage ausdrücklich bestätigt, dieses automatische Umschalten unverändert zu
      lassen.
      - **Nachtrag (Live-Fund 2026-08-07, Bremen → Frankfurt am Main)**: Obiger Fix deckte nur das
        Nachladen für die *bereits gewählte* Route ab, nicht die noch laufende Suche nach einer
        *alternativen* Routen-Kombination (`isSearchingCombinedMatch`, Anzeige "Suche nach
        Routen-Kombination …"). Button stand schon blau/aktiv für die vorausgewählte "Direkte
        Fahrrad-Route" da, während im Hintergrund noch geprüft wurde, ob eine passendere Kombination
        aus Fernwegen existiert. `isPreparingSelectedRouteForStart` prüft jetzt zusätzlich
        `isSearchingCombinedMatch` (unabhängig vom Routen-Modus) und hält den Button so lange blass,
        bis auch diese Suche abgeschlossen ist. **Auf dem Gerät vom Nutzer verifiziert**
        (Bremen → Frankfurt am Main): funktioniert wie erwartet.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift)
      (`isPreparingSelectedRouteForStart`, `isPreparingCuratedRouteForNavigation`,
      `isSearchingCombinedMatch`, `loadCuratedRouteForNavigation`,
      `loadCuratedRouteForNavigation(forCombined:)`, `runMatching`,
      `attemptCombinedThenClosestFallback`)

- [x] **Isolierte Graph-Inseln (Stuttgart/Baden-Württemberg, Cuxhaven/Niedersachsen) - allgemeiner
      `nearestNodes`-Ausweichkandidaten-Fix statt Neubau, deckt aber nicht jeden Einzelfall ab**:
      Nutzer-Meldung (2026-08-06): "Direkte Fahrrad-Route" fällt trotz heruntergeladener
      Bundesländer (Bremen, Niedersachsen, Hamburg, Schleswig-Holstein) für die Strecke Bremen (als
      "Aktueller Standort") → Neumünster weiterhin still auf Online-Routing zurück - direkter
      Anschluss an die beiden unten dokumentierten, noch offenen Funde ("Wege-Graph
      Baden-Württemberg: Stuttgart-Bereich...", "Wege-Graph Niedersachsen: Cuxhaven..."), die als
      Ursache eine fehlerhafte Wege-Graph-Erstellung (`build_way_graph_v2.py`, zwei nicht
      zusammengeführte Teilgraphen) vermutet hatten.
      - **Ursachen-Korrektur Teil 1**: Niedersachsen frisch aus einem heute heruntergeladenen
        OSM-Extrakt neu gebaut und per neuem `Scripts/debug_reachability.py` (BFS-Erreichbarkeit ab
        einer Koordinate, lädt/parst das v2-Flachdateiformat direkt) geprüft - Cuxhaven, Hannover
        und der aus dem Ketten-Fund bekannte Stade-Übergangspunkt liegen alle in derselben
        97,81-%-Hauptkomponente. Dieselbe BFS gegen die tatsächlich ausgelieferte
        `niedersachsen_ways.sqlite` (Release `way-graphs-v4`, trotz Dateiendung im v2-Flachformat,
        per Magic-Bytes `RFG2` bestätigt) zeigt praktisch dasselbe Ergebnis - kein
        Merge-Fehler beim Bauen. Die verbleibenden ~2,2 % nicht erreichbarer Knoten sind über den
        ganzen Graphen verteilte, echte kleine Inseln (Sackgassen, private Zufahrten, unangebundene
        Wege) - eine normale Eigenschaft realer OSM-Straßennetze.
      - **Allgemeiner Fix (Teil 1)**: `WayGraphRepository.nearestNode` ruft jetzt neues
        `nearestNodes(to:maxDistanceMeters:limit:)` auf (bis zu `limit` statt nur des einen
        nächstgelegenen Knotens). `BikeRoutingEngine.search` gibt jetzt ein `SearchOutcome`
        (`.found`/`.queueExhausted(visitedCount:)`/`.nodeLimitExceeded`) statt eines einfachen
        Optionals zurück. Neues `BikeRoutingEngine.wellConnectedCandidates`: filtert Kandidaten per
        begrenzter Breitensuche (Obergrenze `localConnectivityProbeCap` = 600 Knoten,
        `nearestNodesPoolSize` = 40 abgefragte Rohkandidaten) auf ausreichende lokale Anbindung,
        **bevor** die teure A*-Suche überhaupt startet - deutlich billiger als der volle A*-Versuch,
        der bei einer Insel auf der GROSSEN Seite fast den kompletten zusammenhängenden Graphen
        durchsucht, bevor er am `maxVisitedNodes`-Limit aufgibt (`.nodeLimitExceeded`), statt schnell
        mit wenigen besuchten Knoten zu scheitern (`.queueExhausted`, s. `isolatedIslandVisitedNodeThreshold`
        als zusätzliches Sicherheitsnetz für genau diesen zweiten, seltenen Fall). Da
        `route(from:to:)` und alle `CrossRegionRouteStitcher`-Teilstrecken über dieselbe
        `routes`-Funktion laufen, greift der Fix überall.
      - **Live-Nachtest zeigte einen zweiten, tieferliegenden Fund**: Für die Strecke Bremen →
        Neumünster bleibt selbst mit Teil 1 ein `nodeLimitExceeded` (jetzt bei 3 statt 1,5 Mio.
        Knoten, s. `CrossRegionRouteStitcher.legMaxVisitedNodes` unten) bestehen. Per Live-Debug-Ausgaben
        (danach entfernt) und `Scripts/debug_reachability.py`/`debug_nearby_reachability.py` (neu,
        listet die N nächsten Knoten zu einer Koordinate mit Hauptkomponenten-Zugehörigkeit)
        lokalisiert: Der von `findHandoverCoordinate` gefundene Niedersachsen/Schleswig-Holstein-
        Übergangspunkt bei ca. 53,681° N/9,528° O (Elbe-Bereich nahe Wischhafen/Kehdingen,
        südlich von Wedel) snappt auf eine **321 Knoten große, real getrennte Insel** (0,00 %
        Erreichbarkeit von Bremen aus) - nicht auf 2 Knoten wie beim ursprünglichen Cuxhaven-Fund,
        sondern eine deutlich größere lokale Insel. Selbst die 200 nächstgelegenen Knoten zu diesem
        Punkt liegen **alle** auf dieser Insel, ein nächster Hauptkomponenten-Knoten wurde erst
        durch gezieltes Verschieben der Prüfkoordinate um ~4,6 km westlich gefunden.
      - **Fix (Teil 2, hilft, löst den Bremen→Neumünster-Fall aber weiterhin nicht)**: Neue
        `startMaxDistanceMeters`/`endMaxDistanceMeters`-Parameter an `BikeRoutingEngine.route`/
        `routes` (Standard `defaultEndpointMaxDistanceMeters` = 2000 m, wie zuvor) -
        `CrossRegionRouteStitcher.combinedRoute`/`chainedRoute` übergeben für die berechneten
        Übergangspunkte jetzt den größeren `handoverSnapMeters` (5000 m) statt des engen Standards,
        echte Start-/Zielpunkte (Nutzer-Standort/-Adresse) bleiben beim engen Radius.
        `legMaxVisitedNodes` vorsorglich von 1,5 auf 3 Mio. Knoten angehoben (Baden-Württemberg/
        Niedersachsen haben je 6,3-11,3 Mio. Knoten Hauptkomponente).
      - **Bewusst nicht weiter verfolgt in dieser Sitzung**: Die 321-Knoten-Insel bei Wischhafen ist
        vermutlich keine Baupipeline-Lücke, sondern spiegelt eine echte Eigenheit der Gegend wider
        (Elbe-Mündungsbereich, ggf. nur per Fähre querbar) - `findHandoverCoordinate` findet aber nur
        den **einen** geometrisch nächsten Kreuzungspunkt der Luftlinie mit der Bundesland-Grenze,
        ohne Alternativen (z. B. einen Umweg über Hamburgs Elbbrücken) zu berücksichtigen. Ein
        echter Fix bräuchte entweder mehrere Übergangs-Kandidaten entlang der Grenze oder eine
        explizite Hamburg-Zwischenetappe - größerer Umbau, zurückgestellt bis erneuter
        Nutzer-Bedarf. Bremen → Neumünster fällt bis dahin weiterhin (korrekt, nicht stillschweigend
        falsch) auf Online-Routing zurück.
      - Kein Wege-Graph musste neu gebaut/hochgeladen werden - reiner App-seitiger Fix.
      - Per `RadFaehrteTests` (57 Tests, alle bestanden, u. a. die Regionsketten-/
        CrossRegionRouteStitcher-Regressionstests) sowie mehreren Live-Builds auf dem angeschlossenen
        iPhone (per `xcrun devicectl ... --console`) verifiziert.
      → [WayGraphRepository.swift](FahrradApp/RadFaehrte/Services/WayGraphRepository.swift)
      (`nearestNode`, `nearestNodes`),
      [BikeRoutingEngine.swift](FahrradApp/RadFaehrte/Services/BikeRoutingEngine.swift) (`search`,
      `SearchOutcome`, `routes`, `wellConnectedCandidates`, `endpointCandidateCount`,
      `nearestNodesPoolSize`, `localConnectivityProbeCap`, `isolatedIslandVisitedNodeThreshold`,
      `defaultEndpointMaxDistanceMeters`),
      [CrossRegionRouteStitcher.swift](FahrradApp/RadFaehrte/Services/CrossRegionRouteStitcher.swift)
      (`legMaxVisitedNodes`, `combinedRoute`, `chainedRoute`),
      neue [Scripts/debug_reachability.py](FahrradApp/Scripts/debug_reachability.py),
      [Scripts/debug_nearby_reachability.py](FahrradApp/Scripts/debug_nearby_reachability.py)
      (Ad-hoc-BFS-Diagnosewerkzeuge für künftige ähnliche Funde)
- [ ] **Bremen → Neumünster (und vermutlich andere Strecken über die Elbe-Mündung) findet weiterhin
      keine Offline-Route**: Direkter Folgefund aus obigem Eintrag - der geometrisch nächste
      Bundesland-Übergangspunkt bei Wischhafen/Kehdingen liegt auf einer 321 Knoten großen, vom Rest
      Niedersachsens getrennten Insel, der nächste gut angebundene Knoten ist zu weit entfernt
      (>4 km), um ihn mit den aktuellen Suchradien noch zu finden. Fällt korrekt (nicht
      stillschweigend falsch) auf Online-Routing zurück. **Möglicher nächster Schritt**: mehrere
      Übergangs-Kandidaten entlang der Bundesland-Grenze statt nur des einen geometrisch nächsten
      probieren, oder für Fälle mit Hamburg als Nachbarregion explizit einen Umweg über dessen
      Elbbrücken erzwingen. Zurückgestellt, bis erneuter Nutzer-Bedarf gemeldet wird.
      → [CrossRegionRouteStitcher.swift](FahrradApp/RadFaehrte/Services/CrossRegionRouteStitcher.swift)
      (`findHandoverCoordinate`, `combinedRoute`)
- [x] **Rumänien als dreißigstes Land ergänzt** (Nutzerwunsch, aus der "noch fehlende
      Länder"-Liste unten ausgewählt): ~325,6 MB PBF - direkt als Einzeldatei gebaut.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **137
        Routen** (u. a. EuroVelo 6 entlang der Donau, EuroVelo 13), **750 KB** als
        `Resources/romania.sqlite` gebündelt, `"romania"` in
        `RouteRepository.bundledResourceNames` ergänzt. Bauzeit 57,8 s. Getestet per neuem
        Unit-Test `routeRepositoryFindsEuroVeloRouteNearBucharest` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/Wien/
        Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/Valletta/Andorra la Vella/Vaduz/Skopje/
        Peja/Budva/Sarajevo/Belgrad/Split/Ljubljana/Sofia/Budapest).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **507,0 MB**,
        11.407.329 Knoten, 23.170.631 Kanten, 40.371 eindeutige Straßennamen. Baudauer 3:11 Min -
        mit Abstand das größte bisher gebaute Land, aber deutlich unter GitHubs 2-GiB-Asset-Limit.
      - **Neuer Fall `EuropaLand.romania`**: `boundingBox` aus dem PBF-Header ermittelt.
      - Release-Asset `romania_ways.sqlite` (Hintergrundprozess, größter Upload bisher) neu unter
        `way-graphs-eu-v1` hochgeladen, per `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.romania.approximateSizeMB` auf 507 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich, komplette Test-Suite (58 Tests, inkl.
        neuem Test) auf dem iPhone des Nutzers grün, ohne Aufheiz-Zwischenfall (Vreden-Test bei
        normalen 65 s). `HowItWorksView` ("Offline-Karten") um Rumänien ergänzt.
        Live-Offline-Routing in Rumänien vom Nutzer noch nicht getestet (kein konkreter
        Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.romania`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Griechenland als einunddreißigstes Land ergänzt** (Nutzerwunsch, aus der "noch fehlende
      Länder"-Liste unten ausgewählt): ~338,9 MB PBF - ähnliche Größenordnung wie Rumänien/Ungarn,
      trotzdem der bisher mit Abstand größte Wege-Graph (dichtes Wegenetz durch die vielen Inseln
      und Gebirgsregionen) - direkt als Einzeldatei gebaut.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **56
        Routen** (u. a. EuroVelo 8 - Mediterranean Route, EuroVelo 11 - East Europe Route bei
        Athen), **324 KB** als `Resources/greece.sqlite` gebündelt, `"greece"` in
        `RouteRepository.bundledResourceNames` ergänzt. Bauzeit 1:02 Min. Getestet per neuem
        Unit-Test `routeRepositoryFindsEuroVeloRouteNearAthens` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/Wien/
        Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/Valletta/Andorra la Vella/Vaduz/Skopje/
        Peja/Budva/Sarajevo/Belgrad/Split/Ljubljana/Sofia/Budapest/Bukarest).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **970,8 MB**,
        21.901.071 Knoten, 44.362.423 Kanten, 33.671 eindeutige Straßennamen. Baudauer 16:07 Min -
        mit Abstand der langsamste und größte Länder-Build bisher (fast doppelt so groß wie
        Rumänien trotz ähnlicher PBF-Größe), spürbarer Speicherdruck auf dem Baurechner während des
        Baus (nur noch ~60 MB freier RAM, starke Speicherkompression). Trotzdem klar unter GitHubs
        2-GiB-Asset-Limit.
      - **Neuer Fall `EuropaLand.greece`**: `boundingBox` aus dem PBF-Header ermittelt.
      - Release-Asset `greece_ways.sqlite` (Hintergrundprozess, größter Upload bisher, ~1 GB) neu
        unter `way-graphs-eu-v1` hochgeladen, per `curl -I` gegengeprüft (200, korrekte
        Content-Length). `EuropaLand.greece.approximateSizeMB` auf 971 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich. Erster Testlauf brach nach knapp einer
        Stunde mit "Failed to install or launch the test runner" ab (Geräte-Verbindungsaussetzer,
        nicht auf Griechenlands Größe zurückzuführen - App-Bundle selbst wuchs durch Griechenland
        nur um die kleine kuratierte Routen-DB, der große Wege-Graph wird separat vom Nutzer
        heruntergeladen, nicht mit der App gebaut). Zweiter Versuch lief sauber durch: komplette
        Test-Suite (59 Tests, inkl. neuem Test) auf dem iPhone des Nutzers grün, Vreden-Test bei
        normalen 60 s. `HowItWorksView` ("Offline-Karten") um Griechenland ergänzt.
        Live-Offline-Routing in Griechenland vom Nutzer noch nicht getestet (kein konkreter
        Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.greece`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **Finnland als achtunddreißigstes Land ergänzt** (Nutzerwunsch 2026-08-07, direkt im
      Anschluss an Irland): ~737,8 MB PBF - direkt als Einzeldatei gebaut, trotz Größe klar
      unter der 1,4-2-GB-Schwelle.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **327
        Routen** (u. a. EuroVelo 7 - Sun Route, EuroVelo 10 - Baltic Sea Cycle Route, EuroVelo 11
        - East Europe Route, EuroVelo 13 - Iron Curtain Trail), **1,38 MB** als
        `Resources/finland.sqlite` gebündelt, `"finland"` in
        `RouteRepository.bundledResourceNames` ergänzt. Bauzeit 2:17 min (1 Relation ohne
        auflösbare Geometrie übersprungen). Getestet per neuem Unit-Test
        `routeRepositoryFindsEuroVeloRouteNearHelsinki` (EuroVelo 10 verläuft durch Helsinki)
        (analog Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/
        Wien/Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/Valletta/Andorra la Vella/Vaduz/Skopje/
        Peja/Budva/Sarajevo/Belgrad/Split/Ljubljana/Sofia/Budapest/Bukarest/Athen/Nikosia/
        Tallinn/Riga/Vilnius/Reykjavík/Dublin).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **908,3 MB**
        (deutlich unter GitHubs 2-GiB-Limit, aber mit Abstand der bisher größte
        Einzeldatei-Wege-Graph), 20.244.592 Knoten, 41.630.571 Kanten, 115.685 eindeutige
        Straßennamen. Baudauer 11:17 min - mit Abstand die längste bisherige Bauzeit,
        deutlich über der aus Irlands PBF-Größe hochgerechneten Schätzung (Systemzeit-Anteil
        durch die schiere Datenmenge überproportional gestiegen).
      - **Neuer Fall `EuropaLand.finland`**: `boundingBox` aus dem PBF-Header ermittelt.
      - Release-Asset `finland_ways.sqlite` neu unter `way-graphs-eu-v1` hochgeladen, per
        `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.finland.approximateSizeMB` auf 908 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich. Komplette Test-Suite (66 Tests, inkl.
        neuem Test) auf dem iPhone des Nutzers im ersten Durchlauf grün, Vreden-Test bei normalen
        67,7 s, kein Jetsam-Kill. `HowItWorksView` ("Offline-Karten") um Finnland ergänzt.
        Live-Offline-Routing in Finnland vom Nutzer noch nicht getestet (kein konkreter
        Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.finland`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)

- [x] **Irland als siebenunddreißigstes Land ergänzt** (Nutzerwunsch 2026-08-07, direkt im
      Anschluss an Island): gemeinsamer Geofabrik-Extrakt `ireland-and-northern-ireland`
      (~409,1 MB PBF, deckt Irland + Nordirland ab) - direkt als Einzeldatei gebaut, trotz
      deutlich über der bisherigen Größenordnung liegend (nächstgrößere Einzeldatei bisher war
      Schweden mit ~1,06 GB Wege-Graph, hier aber bewusst risikoarm da PBF selbst mit 409 MB
      noch klar unter der 1,4-2-GB-Schwelle liegt, ab der bisher vorsorglich aufgeteilt wurde).
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **3.440
        Routen** (mit Abstand die meisten aller bisherigen Länder - dichtes lokales
        Radwegenetz), **3,44 MB** als `Resources/ireland.sqlite` gebündelt, `"ireland"` in
        `RouteRepository.bundledResourceNames` ergänzt. Bauzeit 79,1 s (1 Relation ohne
        auflösbare Geometrie übersprungen). Getestet per neuem Unit-Test
        `routeRepositoryFindsEuroVeloRouteNearDublin` (EuroVelo 2 - Capitals Route verläuft
        durch Dublin) (analog Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/
        Zürich/La Rochelle/Wien/Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/Valletta/Andorra la
        Vella/Vaduz/Skopje/Peja/Budva/Sarajevo/Belgrad/Split/Ljubljana/Sofia/Budapest/Bukarest/
        Athen/Nikosia/Tallinn/Riga/Vilnius/Reykjavík).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **413,3 MB**
        (knapp über dem PBF, aber deutlich unter GitHubs 2-GiB-Asset-Limit), 9.373.999 Knoten,
        18.822.993 Kanten, 54.074 eindeutige Straßennamen. Baudauer 3:19 min - mit Abstand die
        längste bisherige Bauzeit für eine Einzeldatei.
      - **Neuer Fall `EuropaLand.ireland`**: `boundingBox` aus dem PBF-Header ermittelt -
        auffällig groß (minLat 47,96 statt der erwarteten ~51,4, vermutlich Geofabrik-Puffer für
        Meeresgebiete/Inseln im Atlantik, analog zu Portugals durch Azoren/Madeira erweiterter
        Box) - wie bei allen anderen Ländern unverändert aus dem Header übernommen.
      - Release-Asset `ireland_ways.sqlite` neu unter `way-graphs-eu-v1` hochgeladen, per
        `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.ireland.approximateSizeMB` auf 413 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich. Komplette Test-Suite (65 Tests, inkl.
        neuem Test) auf dem iPhone des Nutzers im ersten Durchlauf grün, Vreden-Test bei normalen
        69,2 s, kein Jetsam-Kill. `HowItWorksView` ("Offline-Karten") um Irland ergänzt.
        Live-Offline-Routing in Irland vom Nutzer noch nicht getestet (kein konkreter
        Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.ireland`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)

- [x] **Island als sechsunddreißigstes Land ergänzt** (Nutzerwunsch 2026-08-07, direkt im
      Anschluss an Litauen): ~64,6 MB PBF - direkt als Einzeldatei gebaut.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **35
        Routen**, **100 KB** als `Resources/iceland.sqlite` gebündelt, `"iceland"` in
        `RouteRepository.bundledResourceNames` ergänzt. Bauzeit 14,2 s. Keine EuroVelo-Route im
        Datensatz (Island liegt außerhalb des EuroVelo-Netzes) - stattdessen das signierte
        Reykjavíker Radwegenetz gefunden (farbig benannte Hauptrouten: Blá/Rauð/Gul/Græn/Fjólublá
        leið, analog Kopenhagens Supercykelstier). Getestet per neuem Unit-Test
        `routeRepositoryFindsRouteNearReykjavik` (Fjólublá leið in Reykjavík) (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/Wien/
        Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/Valletta/Andorra la Vella/Vaduz/Skopje/
        Peja/Budva/Sarajevo/Belgrad/Split/Ljubljana/Sofia/Budapest/Bukarest/Athen/Nikosia/
        Tallinn/Riga/Vilnius).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **54,3 MB**,
        1.226.369 Knoten, 2.472.863 Kanten, 10.465 eindeutige Straßennamen. Baudauer 23,8 s.
      - **Neuer Fall `EuropaLand.iceland`**: `boundingBox` aus dem PBF-Header ermittelt.
      - Release-Asset `iceland_ways.sqlite` neu unter `way-graphs-eu-v1` hochgeladen, per
        `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.iceland.approximateSizeMB` auf 54 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich. Komplette Test-Suite (64 Tests, inkl.
        neuem Test) auf dem iPhone des Nutzers im ersten Durchlauf grün, Vreden-Test bei normalen
        70,4 s, kein Jetsam-Kill. `HowItWorksView` ("Offline-Karten") um Island ergänzt.
        Live-Offline-Routing in Island vom Nutzer noch nicht getestet (kein konkreter
        Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.iceland`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)

- [x] **Litauen als fünfunddreißigstes Land ergänzt** (Nutzerwunsch 2026-08-07, direkt im
      Anschluss an Lettland - damit alle drei baltischen Staaten komplett): ~221,9 MB PBF -
      direkt als Einzeldatei gebaut.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **77
        Routen** (u. a. EuroVelo 10 - Baltic Sea Cycle Route, EuroVelo 11 - East Europe Route,
        EuroVelo 13), **336 KB** als `Resources/lithuania.sqlite` gebündelt, `"lithuania"` in
        `RouteRepository.bundledResourceNames` ergänzt. Bauzeit 42,5 s. Getestet per neuem
        Unit-Test `routeRepositoryFindsEuroVeloRouteNearVilnius` (EuroVelo 11 verläuft direkt
        durch Vilnius) (analog Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/
        Zürich/La Rochelle/Wien/Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/Valletta/Andorra la
        Vella/Vaduz/Skopje/Peja/Budva/Sarajevo/Belgrad/Split/Ljubljana/Sofia/Budapest/Bukarest/
        Athen/Nikosia/Tallinn/Riga).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **168,3 MB**,
        3.756.593 Knoten, 7.715.837 Kanten, 15.767 eindeutige Straßennamen. Baudauer 89,1 s.
      - **Neuer Fall `EuropaLand.lithuania`**: `boundingBox` aus dem PBF-Header ermittelt.
      - Release-Asset `lithuania_ways.sqlite` neu unter `way-graphs-eu-v1` hochgeladen, per
        `curl -I` gegengeprüft (200, korrekte Content-Length).
        `EuropaLand.lithuania.approximateSizeMB` auf 168 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich. Versuch, die vier schwersten
        Kombinationssuche-Tests (Vreden & Co.) per `-only-testing:`/`-skip-testing:` von der
        restlichen Suite zu trennen (sollte Jetsam-Kills durch Geräte-Aufheizung isolieren, s.
        "Bekannte Probleme"), scheiterte an drei verschiedenen Selektor-Formaten (jeweils
        "Executed 0 tests" bzw. Filter griff still nicht) - Ansatz verworfen, s.
        `feedback_split_heavy_tests`-Memory. Stattdessen kompletter Testlauf ohne Filter:
        komplette Test-Suite (63 Tests, inkl. neuem Test) auf dem iPhone des Nutzers grün im
        ersten sauberen Durchlauf, Vreden-Test bei normalen 64,1 s, kein Jetsam-Kill. `HowItWorksView`
        ("Offline-Karten") um Litauen ergänzt. Live-Offline-Routing in Litauen vom Nutzer noch
        nicht getestet (kein konkreter Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.lithuania`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)

- [x] **Lettland als vierunddreißigstes Land ergänzt** (Nutzerwunsch 2026-08-07, direkt im
      Anschluss an Estland): ~139,3 MB PBF - direkt als Einzeldatei gebaut.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **253
        Routen** (u. a. EuroVelo 10 - Baltic Sea Cycle Route, EuroVelo 11 - East Europe Route,
        EuroVelo 13 - Iron Curtain Trail), **1,04 MB** als `Resources/latvia.sqlite` gebündelt,
        `"latvia"` in `RouteRepository.bundledResourceNames` ergänzt. Bauzeit 23,5 s. Getestet per
        neuem Unit-Test `routeRepositoryFindsEuroVeloRouteNearRiga` (EuroVelo 10 verläuft bei
        Jūrmala nahe Riga) (analog Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/
        Zürich/La Rochelle/Wien/Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/Valletta/Andorra la
        Vella/Vaduz/Skopje/Peja/Budva/Sarajevo/Belgrad/Split/Ljubljana/Sofia/Budapest/Bukarest/
        Athen/Nikosia/Tallinn).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **133,1 MB**,
        2.964.755 Knoten, 6.106.691 Kanten, 12.006 eindeutige Straßennamen. Baudauer 52,5 s.
      - **Neuer Fall `EuropaLand.latvia`**: `boundingBox` aus dem PBF-Header ermittelt.
      - Release-Asset `latvia_ways.sqlite` neu unter `way-graphs-eu-v1` hochgeladen, per `curl -I`
        gegengeprüft (200, korrekte Content-Length). `EuropaLand.latvia.approximateSizeMB` auf 133
        gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich. Erster Testlauf scheiterte am bekannten
        Jetsam-Kill beim schwersten Kombinationssuche-Test (Geräte-Aufheizung, kein echter
        Lettland-Bug - alle Lettland-Tests liefen bereits im ersten Lauf grün durch), zweiter
        Versuch scheiterte an einem falschen Arbeitsverzeichnis (kein echter Testfehler). Dritter
        Versuch lief sauber durch: komplette Test-Suite (62 Tests, inkl. neuem Test) auf dem
        iPhone des Nutzers grün, Vreden-Test bei 67,7 s. `HowItWorksView` ("Offline-Karten") um
        Lettland ergänzt. Live-Offline-Routing in Lettland vom Nutzer noch nicht getestet (kein
        konkreter Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.latvia`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)

- [x] **Estland als dreiunddreißigstes Land ergänzt** (Nutzerwunsch 2026-08-07, direkt im
      Anschluss an Zypern, wie in "noch fehlende Länder" vorgemerkt): ~121,8 MB PBF - direkt als
      Einzeldatei gebaut.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **120
        Routen** (u. a. EuroVelo 10 - Baltic Sea Cycle Route, EuroVelo 11 - East Europe Route,
        EuroVelo 13 - Iron Curtain Trail), **946 KB** als `Resources/estonia.sqlite` gebündelt,
        `"estonia"` in `RouteRepository.bundledResourceNames` ergänzt. Bauzeit 19,5 s. Getestet
        per neuem Unit-Test `routeRepositoryFindsEuroVeloRouteNearTallinn` (EuroVelo 10 verläuft
        direkt durch Tallinn) (analog Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/
        Luxemburg-Stadt/Zürich/La Rochelle/Wien/Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/
        Valletta/Andorra la Vella/Vaduz/Skopje/Peja/Budva/Sarajevo/Belgrad/Split/Ljubljana/Sofia/
        Budapest/Bukarest/Athen/Nikosia).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **99,7 MB**,
        2.223.009 Knoten, 4.566.056 Kanten, 12.861 eindeutige Straßennamen. Baudauer 46,7 s.
      - **Neuer Fall `EuropaLand.estonia`**: `boundingBox` aus dem PBF-Header ermittelt.
      - Release-Asset `estonia_ways.sqlite` neu unter `way-graphs-eu-v1` hochgeladen, per `curl -I`
        gegengeprüft (200, korrekte Content-Length). `EuropaLand.estonia.approximateSizeMB` auf
        100 gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich. Komplette Test-Suite (61 Tests, inkl.
        neuem Test) auf dem iPhone des Nutzers grün, Vreden-Test bei normalen 85,7 s.
        `HowItWorksView` ("Offline-Karten") um Estland ergänzt. Live-Offline-Routing in Estland
        vom Nutzer noch nicht getestet (kein konkreter Reiseanlass bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.estonia`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)

- [x] **Zypern als zweiunddreißigstes Land ergänzt** (Nutzerwunsch, aus der "noch fehlende
      Länder"-Liste unten ausgewählt): ~37,0 MB PBF - direkt als Einzeldatei gebaut.
      - **Kuratierte Routen**: `extract_bicycle_routes.py` unverändert angewendet - **10
        Routen** (u. a. EuroVelo 8 - Mediterranean Route rund um die Insel), **196 KB** als
        `Resources/cyprus.sqlite` gebündelt, `"cyprus"` in `RouteRepository.bundledResourceNames`
        ergänzt. Bauzeit 7,1 s. Getestet per neuem Unit-Test
        `routeRepositoryFindsEuroVeloRouteNearNicosia` (analog
        Rotterdam/Krakau/Stockholm/Kopenhagen/Brügge/Luxemburg-Stadt/Zürich/La Rochelle/Wien/
        Prag/Bratislava/Vlorë/Rom/Barcelona/Lissabon/Valletta/Andorra la Vella/Vaduz/Skopje/
        Peja/Budva/Sarajevo/Belgrad/Split/Ljubljana/Sofia/Budapest/Bukarest/Athen).
      - **Offline-Wege-Graph direkt in Format v2** (`build_way_graph_v2.py`) - **75,3 MB**,
        1.686.403 Knoten, 3.439.370 Kanten, 13.128 eindeutige Straßennamen. Baudauer 18,6 s.
      - **Neuer Fall `EuropaLand.cyprus`**: `boundingBox` aus dem PBF-Header ermittelt.
      - Release-Asset `cyprus_ways.sqlite` neu unter `way-graphs-eu-v1` hochgeladen, per `curl -I`
        gegengeprüft (200, korrekte Content-Length). `EuropaLand.cyprus.approximateSizeMB` auf 75
        gesetzt.
      - **Verifiziert**: Build (Device-Ziel) erfolgreich. Erste beiden Testläufe scheiterten
        zunächst - einer am nicht mehr vertrauten Entwickler-Zertifikat auf dem iPhone (Nutzer hat
        es unter Einstellungen → Allgemein → VPN & Geräteverwaltung neu bestätigt), der andere am
        bekannten Jetsam-Kill bei den schwersten Kombinationssuche-Tests durch Geräte-Aufheizung
        nach den intensiven Griechenland-Läufen (s. o. "Andorra als achtzehntes Land ergänzt" für
        die Vorgeschichte) - beides kein echter Zypern-Bug. Dritter Versuch lief sauber durch:
        komplette Test-Suite (59 Tests, inkl. neuem Test) auf dem iPhone des Nutzers grün,
        Vreden-Test bei normalen 63 s. `HowItWorksView` ("Offline-Karten") um Zypern ergänzt.
        Live-Offline-Routing in Zypern vom Nutzer noch nicht getestet (kein konkreter Reiseanlass
        bisher).
      → [Scripts/build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py) (unverändert),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`EuropaLand.cyprus`), [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift),
      [RouteRepository.swift](FahrradApp/RadFaehrte/Services/RouteRepository.swift),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift),
      [github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1](https://github.com/Joern2368/RadFaehrte/releases/tag/way-graphs-eu-v1)
- [x] **"Wie funktioniert's"-Texte gekürzt** (2026-08-07): Nutzer-Feedback, dass die Erklärtexte
      (v. a. "Route suchen" und "Offline-Karten", die über die Zeit durch viele Feature-Ergänzungen
      auf mehrere hundert Wörter je Abschnitt angewachsen waren) zu lang seien. Alle Topic-Texte auf
      die Kernaussage gekürzt, Detail-Sonderfälle (z. B. Lücken-Anzeige bei EuroVelo/D-Routen ohne
      durchgehende Kartierung, vollständige Länderliste bei Offline-Karten) entfernt statt weiter
      mitgepflegt. Build gegen `generic/platform=iOS` geprüft (`CODE_SIGNING_ALLOWED=NO`), danach auf
      "iPhone von Jorn" (iPhone 13) installiert und gestartet; Nutzer hat die gekürzten Texte im
      Gerät gegengeprüft und für gut befunden.
      → [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **Statistik-Leiste um drei weitere Werte ergänzt** (2026-08-07, Nutzer-Brainstorm "was
      könnte man noch hinzufügen" - drei der vorgeschlagenen Ideen ausgewählt, die ohne neue
      Datenquelle allein aus vorhandenen GPS-/Barometer-Daten ableitbar sind):
      - **Pausenzeit** (`pausedTime`): einfach `Fahrtzeit − Bewegungszeit`
        (`tourStartTime`/`tourMovingSeconds` waren schon vorhanden).
      - **Höchste erreichte Höhe** (`maxAltitude`): Maximum über `CLLocation.altitude` bei gültiger
        `verticalAccuracy`, analog zu `tourMaxSpeedKmh` in `accumulateTourDistance` mitgeführt.
      - **Aktuelle Steigung/Gefälle** (`currentGrade`, in %): eine reine Punkt-zu-Punkt-Ableitung
        wäre bei GPS-/Barometer-Rauschen unbrauchbar sprunghaft (dieselbe Erkenntnis wie beim
        Barometer-Fix für Höhenmeter, s. o.) - stattdessen ein gleitendes 30-m-Fenster
        (`gradeSamples`, in `updateGradeSamples` gepflegt) aus Höhe (Barometer wenn verfügbar,
        sonst GPS-Höhe) über gefahrene Distanz, auf ±30 % gekappt, erst ab mind. 15 m Strecke im
        Fenster angezeigt (sonst "–"). Dafür `LocationManager.relativeAltitudeMeters` (vorher
        `lastRelativeAltitudeMeters`, privat) nach außen exponiert - ist der Rohwert, aus dem bisher
        nur die kumulierte Gewinn/Verlust-Summe berechnet wurde.
      - Alle drei einfach als weitere `NavigationStatKind`-Fälle ergänzt, keine Änderung an
        Persistenz/Einstellungs-UI nötig (`NavigationStatSettingsView` iteriert bereits über
        `allCases`). Build (Device-Ziel) erfolgreich, auf "iPhone von Jörn" installiert und
        gestartet - **Live-Verifikation der neuen Werte (v. a. Steigungs-Plausibilität an einer
        echten Steigung/Rampe) noch ausstehend**.
      → [NavigationStat.swift](FahrradApp/RadFaehrte/Models/NavigationStat.swift),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`statDisplay`,
      `accumulateTourDistance`, `updateGradeSamples`, `currentGradePercent`, `pausedTimeDisplay`,
      `tourMaxAltitudeMeters`, `gradeSamples`),
      [LocationManager.swift](FahrradApp/RadFaehrte/Services/LocationManager.swift)
      (`relativeAltitudeMeters`)
- [x] **Verlauf: Touren umbenennen + direkt starten** (2026-08-08, Nutzerwunsch): `DrivenTour`
      bekommt ein neues optionales Feld `name` (Codable, `nil` bei bereits gespeicherten Touren
      ohne dieses Feld weiterhin klaglos decodierbar). In `HistoryView` nach links wischen oder
      Stift-Symbol in der Detailansicht öffnet einen Alert mit Textfeld zum Umbenennen;
      `store.save(...)` überschreibt dabei einfach die bestehende JSON-Datei (Dateiname = `id`).
      Ist kein Name gesetzt, zeigen Liste/Detail weiterhin das Datum als Titel (`displayName`
      liefert einen datumsbasierten Fallback-Titel für Kontexte, die zwingend einen Namen
      brauchen). Für "direkt starten" bekommt `HistoryView` einen `onStart`-Callback, analog
      `OwnRoutesView`: `RootTabView` wandelt die `DrivenTour` dafür in eine `ImportedRoute` um
      (`importedRoute(from:)`) und nutzt denselben bereits vorhandenen `routeToStart`-Mechanismus
      wie beim Starten einer importierten GPX-Tour (`ContentView.startImportedRoute`) - beide sind
      für die Navigation gleichwertig: eine feste Punktreihenfolge ohne DB-Match. Starten-Button in
      der Zeile (nur bei ≥2 Koordinaten) sowie Play-Symbol in der Detail-Toolbar. Build (Device-
      Ziel) erfolgreich - **Live-Verifikation auf dem iPhone noch ausstehend**.
      → [DrivenTour.swift](FahrradApp/RadFaehrte/Models/DrivenTour.swift) (`name`, `displayName`),
      [HistoryView.swift](FahrradApp/RadFaehrte/Views/HistoryView.swift) (`startRename`,
      `commitRename`, `tourRow`, `tourDetail`), [RootTabView.swift](FahrradApp/RadFaehrte/RootTabView.swift)
      (`importedRoute(from:)`), [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **Anfahrt-Linie zum Streckenanfang: grau gepunktet statt orange gestrichelt** (2026-08-08,
      Nutzer-Feedback nach Live-Test - die orange gestrichelte Linie wirkte v. a. bei Anfahrten
      durch dichtes Straßennetz zu dominant/alarmierend). Recherche zu Konventionen anderer
      Apps: Apple Maps selbst zeigt den Fußweg-Anteil in Transit-Wegbeschreibungen als graue
      gepunktete Linie, klar abgesetzt von den durchgezogenen, farbigen Transit-Linien - dieses
      Muster übernommen, da es iPhone-Nutzern bereits vertraut ist und weniger wie eine
      konkurrierende zweite Route wirkt. Live auf dem Gerät getestet und für besser befunden.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`routeOverlayContent`,
      `connectorRouteToStart`/`connectorRouteToEnd`-Darstellung)
- [x] **"Direkte Fahrrad-Route" (offline): Anfahrt/Zielweg-Connector ergänzt, damit die blaue Linie
      wirklich am Zielpunkt endet** (2026-08-08, Nutzer-Beobachtung: Ziel "Bückeburger Straße 9" lag
      sichtbar nicht am Ende der blauen Linie). Ursache: `BikeRoutingEngine.routes` snappt Start/Ziel
      auf den nächstgelegenen Knoten im Wege-Graphen (`nearestNodes`, bis zu 2 km Suchradius) und
      `displayCoordinates` baut die Linie ausschließlich aus Graph-Knoten-Koordinaten - die
      tatsächlich gesuchte Koordinate wurde nie angehängt. Für benannte/kuratierte Routen gab es
      dafür bereits einen Connector-Mechanismus (`loadConnectorRoute`, graue gepunktete Linie), der
      im Direktrouten-Modus (`isDirectRouteMode`) aber fehlte. Neue `loadDirectRouteConnectors`
      (analog zu `loadConnectorRoute`, ab 50 m Lücke) lädt bei Bedarf eine Online-Wegbeschreibung
      vom letzten Graph-Knoten zur echten Zielkoordinate (und vom Start zum ersten Graph-Knoten) und
      zeigt sie als dieselbe graue gepunktete Linie wie bei kuratierten Routen. Aufgerufen aus
      `loadDirectRoute` (alle drei Zweige: Offline-Einzelregion, Cross-Region, Online-Fallback) und
      `rerouteDirectRoute` (dort mit der Live-Position statt `startPlace`). Build (Device-Ziel)
      erfolgreich - **Live-Verifikation auf dem iPhone noch ausstehend**.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`loadDirectRouteConnectors`,
      `loadDirectRoute`, `rerouteDirectRoute`, `routeOverlayContent`)
- [x] **Ø-Tempo bezieht sich jetzt auf reine Fahrzeit statt Gesamtzeit seit Start** (2026-08-09,
      Nutzer-Beobachtung: Anhalten/Pause drücken lässt den Durchschnittswert künstlich sinken).
      `currentAverageSpeedKmh` (Live-Anzeige während der Navigation) sowie die beim Beenden der
      Tour berechnete `averageSpeedKmh` (Verlauf-Eintrag `DrivenTour` + HealthKit-Workout) teilten
      die Strecke bisher durch `Date().timeIntervalSince(tourStartTime)` bzw. `duration` - beides
      Gesamtzeit inklusive Stillstand. Beide nutzen jetzt stattdessen `tourMovingSeconds` (die
      bereits vorhandene reine Bewegungszeit ohne Stopps, s. `movingTime`-Statistik). Betrifft
      auch die davon abgeleiteten Werte `arrivalTimeAverageSpeed`/`remainingTimeAverageSpeed`.
      Build (Device-Ziel) erfolgreich, auf dem iPhone installiert - **Live-Verifikation beim
      Fahren mit Pause noch ausstehend**.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`currentAverageSpeedKmh`,
      `stopNavigating`), [NavigationStat.swift](FahrradApp/RadFaehrte/Models/NavigationStat.swift)
- [x] **Anfahrt-Linie zum Streckenanfang folgt jetzt der Live-Position statt am Planungs-Startpunkt
      einzufrieren** (2026-08-09, Nutzer-Beobachtung mit Screenshot: Weser Radweg bei Hemelingen -
      wich der Nutzer während der Navigation vom ursprünglich geplanten Weg zur Route ab, blieb die
      graue gepunktete Linie unverändert am alten Startpunkt stehen statt zur aktuellen Position zu
      zeigen). Ursache: `loadConnectorRoute`/`loadCombinedConnectorRoute` berechnen
      `connectorRouteToStart` nur einmal beim Auswählen der Route (`onChange(of: selectedMatch)`
      bzw. `combinedMatch`), ausgehend vom damaligen `startPlace` - anders als beim Connector der
      "Direkten Fahrrad-Route" (`loadDirectRouteConnectors`, dort schon an die Live-Position
      gekoppelt über `rerouteDirectRoute`) gab es für kuratierte Routen/Touren keine
      Neuberechnung während der Fahrt. Neue `checkCuratedConnectorDeviation` (analog
      `checkDirectRouteDeviation`, aber bewusst **ohne** die eigentliche Route neu zu berechnen -
      s. Kommentar an `directRouteDeviationThresholdKm`, bei kuratierten Routen soll ein Abweichen
      zur Strecke zurückführen, nicht die Strecke ändern) läuft bei jedem Standort-Update während
      der Navigation mit, aktualisiert `connectorRouteToStart` alle 15 s vom aktuellen Standort aus
      neu (solange die Route noch >50 m entfernt ist) und blendet die Linie aus, sobald die Route
      erreicht ist. Build (Simulator-Ziel) erfolgreich - **Live-Verifikation auf dem iPhone noch
      ausstehend**.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`checkCuratedConnectorDeviation`,
      `curatedConnectorRelevantThresholdKm`, `curatedConnectorRerouteCooldown`, `handleLocationUpdate`)
- [x] **Kartenvorschau bei der Routenplanung ein-/ausklappbar** (2026-08-09, Nutzer-Wunsch: die
      kleine Kartenvorschau unterhalb der Routenvorschläge ganz sehen können, ohne dafür erst "Los"
      zu drücken). Neuer Zustand `isRouteFormCollapsed`: eingeklappt blendet Suchfelder,
      Routenvorschläge und "Los"-Button aus, die Karte füllt danach den ganzen Bildschirm (analog
      `mapFillsFullScreen`, bisher nur für den ausgeblendeten Navigations-Banner). Erster Versuch
      nutzte dafür eine Wisch-Geste direkt auf der Karte - nach Live-Test verworfen (Nutzer-Feedback:
      löste beim normalen Verschieben/Antippen der Karte zu leicht versehentlich mit aus). Stattdessen
      jetzt ein schmaler Ziehgriff über der Karte (`routeFormCollapseGrabber`, Tippen oder Wischen
      nach oben klappt ein), der nicht mit der Kartenbedienung kollidiert; ein kleiner Griff über der
      dann vollflächigen Karte (`routeFormHandle`, Tippen oder Wischen nach unten) blendet wieder ein
      - beide Griffe eine direkte Kopie des bereits vorhandenen Musters für den Navigations-Banner
      (`isNavigationBannerVisible`/`navigationBannerHandle`). Wird beim Start einer Navigation
      zurückgesetzt, damit nach deren Ende wieder die volle Ansicht erscheint. Live auf dem iPhone
      getestet und für gut befunden.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`isRouteFormCollapsed`,
      `mapFillsFullScreen`, `routeFormCollapseGrabber`, `routeFormHandle`, `startNavigating`)
- [x] **Fix: Start-/Ziel-Suchfelder erschienen nach dem Ein-/Ausklappen der Kartenvorschau leer**
      (2026-08-09, Nutzer-Beobachtung mit drei Screenshots direkt nach Einführung des Ziehgriffs
      oben: Karte hochziehen und wieder runter zeigte "Start"/"Ziel" als Platzhalter statt "Aktueller
      Standort"/"Achim", obwohl Route und Karte weiterhin die vorherige Auswahl zeigten). Ursache:
      der Ziehgriff entfernt den Suchfelder-Bereich per `if` komplett aus dem View-Baum und erzeugt
      ihn beim Wiedereinblenden neu - dabei geht `LocationSearchField`s eigener `@State private var
      viewModel` (und damit der angezeigte `queryFragment`-Text) verloren, obwohl die eigentliche
      Auswahl (`selectedPlace`-Binding) unverändert blieb. Der vorhandene `onChange(of:
      selectedPlace)`-Sync griff nur bei einer echten Änderung, nicht beim ersten Erscheinen einer
      frischen View-Instanz. Neuer Abgleich in `onAppear` zieht `queryFragment` bei Bedarf aus
      `selectedPlace` nach. Live auf dem iPhone getestet und für gut befunden.
      → [LocationSearchField.swift](FahrradApp/RadFaehrte/Views/LocationSearchField.swift)
- [x] **"Direkte Fahrrad-Route": Online-Route als wischbare Alternative zur Offline-Route**
      (2026-08-11, Nutzer-Wunsch nach einer Diskussion über Bremen/Niedersachsen-Offline-Routing).
      Bisher berechnete `loadDirectRoute` die Online-Route (`MKDirections`) nur als kompletten
      Fallback, wenn keine Offline-Route gefunden wurde - war eine Offline-Route ("ruhige Wege
      bevorzugt") erfolgreich, gab es keine Möglichkeit mehr, stattdessen die direktere Online-
      Route zu sehen. Jetzt zeigt die Direktrouten-Karte einen Wisch-Pager (`directRoutePager`,
      analog zu `matchesPager`/`combinedMatchesPager`): eine Seite je Offline-Alternative, plus
      eine letzte Seite für die Online-Route. Diese wird bewusst **nicht** bei jeder Suche
      automatisch mitberechnet (Nutzer-Entscheidung: unnötige Online-Anfrage, wenn ohnehin meist
      bei der ruhigen Route geblieben wird), sondern erst per `onAppear` nachgeladen
      (`loadOnlineDirectRouteAlternative`), sobald tatsächlich zu ihrer Seite gewischt wird.
      Ersetzt außerdem die bisherige Auswahl unter mehreren `directRoutes` per Antippen der Route
      auf der Karte (`handleMapTap`, eigenes Punkt-zu-Linie-Hit-Testing) - Nutzer-Entscheidung:
      Wischen soll die einzige Auswahlmethode sein, einheitlich mit den kuratierten Routen. Live
      auf dem iPhone getestet und für gut befunden.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`directRoutePager`,
      `loadOnlineDirectRouteAlternative`, `loadDirectRoute`, `handleMapTap`), [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **Fix: Kartenvorschau schrumpfte mit jeder zusätzlichen Wisch-Karte in der Ergebnisliste**
      (2026-08-11, direkte Folge des Online-Route-Wisch-Pagers oben - Nutzer-Beobachtung per
      Screenshot: Direktroute + zwei kuratierte Treffer als je 102pt hohe Pager-Karten drückten die
      Kartenvorschau darunter sichtbar klein, da sie im äußeren `VStack` nur den nach der
      Ergebnisliste verbleibenden Platz bekommt). Zwei verworfene Zwischenschritte, bevor die
      eigentliche Ursache klar war:
      1. Direktrouten-Pager-Höhe auf 72pt reduziert + Hinweistext "N Routen – wischen zum Wechseln"
         aus dem Untertitel entfernt - Höhen-Reduktion rückgängig gemacht (Live-Fund: 72pt reichte
         nicht, die von `.indexViewStyle` überlagerten Punkte schnitten sich sichtbar mit der
         zweiten Textzeile), Wegfall des Hinweistexts beibehalten.
      2. Eigentlicher Fix: Die Ergebnisliste (`resultsSection`) steckt jetzt in einer `ScrollView`
         mit `resultsSectionMaxHeight` (320pt) als Obergrenze, statt frei zu wachsen - bei mehr
         Treffern wird die Liste selbst scrollbar, die Kartenvorschau behält unabhängig von der
         Trefferzahl eine verlässliche Mindesthöhe. Live auf dem iPhone getestet und für gut
         befunden.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`resultsSectionMaxHeight`,
      `directRoutePager`, `directRouteSubtitle`)
- [x] **Fix: Blaue Routen-/Anfahrt-Linie startete beim Loslaufen sichtbar neben statt auf dem
      blauen Standort-Punkt** (2026-08-14, Nutzer-Beobachtung mit Screenshot direkt nach Tippen auf
      "Los" mit "Aktuelle Position" als Start). Ursache: `startPlace` bei "Aktuelle Position" ist
      eine einmalige GPS-Momentaufnahme (`resolveCurrentLocationAsStart`), die Route/Anfahrt-Linie
      dazu wird ebenfalls nur einmal beim Berechnen bzw. Auswählen der Route berechnet
      (`loadDirectRoute`/`loadConnectorRoute`) - `startNavigating` selbst gleicht beides beim
      Tippen auf "Los" nicht mit der zu dem Zeitpunkt ggf. schon abweichenden Live-Position ab. Die
      vorhandene Selbstkorrektur (`checkDirectRouteDeviation`/`checkCuratedConnectorDeviation`)
      lief bisher nur reaktiv bei künftigen Standort-Updates während der Navigation, nicht beim
      Start selbst - dadurch die sichtbare Lücke direkt nach "Los". Fix: `startNavigating` ruft
      beide Prüfungen jetzt einmal sofort mit der aktuellen Position auf, statt auf den ersten
      GPS-Tick danach zu warten. Build (Device-Ziel) erfolgreich - **Live-Verifikation auf dem
      iPhone noch ausstehend**.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`startNavigating`,
      `checkDirectRouteDeviation`, `checkCuratedConnectorDeviation`)
- [x] **Fix: Blaue Route/Anfahrt-Linie endete manchmal komplett vor dem Ziel- bzw. Startpunkt,
      ohne jede Anfahrts-/Zielweg-Linie** (2026-08-14, Nutzer-Beobachtung mit Screenshot: Ziel
      "Bückeburger Straße 9" - derselbe Fall, der am 2026-08-08 oben scheinbar schon behoben wurde,
      aber laut dortigem Vermerk nie live auf dem iPhone verifiziert war; genau dieser erste Live-
      Test schlug fehl). Ursache: Alle vier Stellen, die eine Anfahrts-/Zielweg-Linie per Online-
      Wegbeschreibung berechnen (`loadConnectorRoute`, `loadCombinedConnectorRoute`,
      `loadDirectRouteConnectors`, `checkCuratedConnectorDeviation`) nutzen dafür `Self.directions`
      (`MKDirections`, mit `try?`) - schlägt die Anfrage fehl (kein Netz, oder MKDirections liefert
      für sehr kurze Strecken mitunter schlicht kein Ergebnis), wurde das bisher überall still
      verschluckt: `connectorRouteToStart`/`connectorRouteToEnd` blieben `nil`, keine Linie, kein
      Hinweis - die blaue Hauptroute wirkte dann, als würde sie einfach vor dem eigentlichen Ziel
      aufhören. Fix: neue `@State`-Fallbacks `connectorRouteToStartFallback`/
      `connectorRouteToEndFallback` (`[CLLocationCoordinate2D]?`) - schlägt die Online-
      Wegbeschreibung fehl, wird stattdessen eine einfache Luftlinie zwischen den beiden Punkten
      gezeigt (gleicher grau gepunkteter Stil), statt gar nichts. `MKRoute` selbst lässt sich nicht
      synthetisch erzeugen (kein öffentlicher Initializer), daher ein separates Fallback-Feld statt
      eines Ersatz-`MKRoute`-Werts. Build (Device-Ziel) erfolgreich, auf "iPhone von Jörn"
      installiert. **Live-Test auf dem iPhone zeigte: Fix allein reichte nicht** - der Fallback
      griff nicht, weil in diesem Fall (s. Eintrag direkt darunter) gar keine
      Fehlerbehandlung nötig war, sondern die Auslöse-Schwelle selbst zu hoch stand.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`connectorRouteToStartFallback`,
      `connectorRouteToEndFallback`, `loadConnectorRoute`, `loadCombinedConnectorRoute`,
      `loadDirectRouteConnectors`, `checkCuratedConnectorDeviation`, `routeOverlayContent`)
- [x] **Fix: Anfahrts-/Zielweg-Connector der "Direkten Fahrrad-Route" löste erst ab 50 m Lücke aus -
      eine deutlich sichtbare 48-m-Lücke blieb dadurch ohne jede Linie** (2026-08-14, unmittelbare
      Fortsetzung des Eintrags direkt darüber: Live-Test auf dem iPhone mit "Bückeburger Straße 9"
      zeigte die blaue Linie weiterhin sichtbar vor dem Zielpunkt endend, auch nach dem
      Fallback-Fix, sogar nach vollständigem Neustart der App). Statt weiter zu raten, temporäres
      Debug-Logging in `loadDirectRouteConnectors` ergänzt und live über
      `xcrun devicectl device process launch --console` auf dem angeschlossenen iPhone mitgelesen,
      während der Nutzer die Suche wiederholte. Ergebnis: Der erste Ladevorgang (3 Offline-
      Routenalternativen) hatte tatsächlich eine 56,7-m-Lücke zum Ziel und lud den Connector
      erfolgreich (`route=OK`). Ein zweiter, kurz darauf folgender Aufruf - ausgelöst durchs Laden
      der Online-Routenalternative (`loadOnlineDirectRouteAlternative`, dabei mit einer leicht
      abweichenden, präziseren `ziel`-Koordinate aus dem zweiten Geocoding-Ergebnis) - hatte nur
      noch 48,5 m Lücke. Das lag *unter* der bisherigen Schwelle `directRouteConnectorMinDistanceMeters`
      (50 m), löste also gar keinen Connector-Versuch aus (weder echte Route noch Luftlinien-
      Fallback) - keine Netzwerk-/Fehlerfrage, sondern die Schwelle selbst zu hoch für eine auf dem
      Kartenausschnitt klar erkennbare Lücke. Auf 15 m gesenkt (deutlich unter jede beobachtete
      Lücke, aber weiterhin groß genug für reines Snapping-Rauschen der Offline-Engine). Debug-
      Logging nach der Diagnose wieder entfernt. Build (Device-Ziel) erfolgreich, auf "iPhone von
      Jörn" installiert - **live mit demselben Ziel ("Bückeburger Straße 9") verifiziert**: Linie
      erreicht jetzt den Zielpunkt (zunächst als grauer gepunkteter Connector, wie bei jeder
      Anfahrts-/Zielweg-Linie bisher üblich - Nutzer wollte stattdessen durchgängig Blau, s.
      Eintrag direkt darunter).
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift)
      (`directRouteConnectorMinDistanceMeters`, `loadDirectRouteConnectors`)
- [x] **"Direkte Fahrrad-Route": Anfahrts-/Zielweg-Connector jetzt durchgängig blau statt grau
      gepunktet** (2026-08-14, Nutzerwunsch direkt nach obigem Fix: "durchgängig blau bis zum
      Ziel"). Bewusst nur für den Direktrouten-Modus (`isDirectRouteMode`) geändert, nicht für
      kuratierte Routen/Touren (`loadConnectorRoute`/`loadCombinedConnectorRoute`/
      `checkCuratedConnectorDeviation` weiterhin grau gepunktet) - der Unterschied ist inhaltlich
      begründet: Bei der Direktroute ist die Anfahrt/der Zielweg schlicht die letzte, vom
      Offline-Engine-Snapping abgeschnittene Teilstrecke derselben Route (soll nicht wie ein
      separater Abschnitt wirken), während die graue Linie bei kuratierten Routen bewusst eine vom
      Nutzer erkennbar andere, selbst geplante Strecke zur eigentlichen (festen) Tour markiert -
      diese Unterscheidung war der Grund für die grau-gepunktete Konvention vom 2026-08-08 und
      bleibt dort weiter gültig. `connectorRouteToStart`/`connectorRouteToEnd` sowie deren
      Luftlinien-Fallbacks nutzen im Direktrouten-Zweig von `routeOverlayContent` jetzt denselben
      Stil wie die Hauptroute (`.stroke(.blue, lineWidth: 5)`) statt grau gepunktet. Build
      (Device-Ziel) erfolgreich, auf "iPhone von Jörn" installiert - **live getestet und für gut
      befunden**.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`routeOverlayContent`)
- [x] **Fix: Blauer Haken in der Direktrouten-Alternativen-Liste ("Ruhige Route (offline)"/"Direkte
      Fahrrad-Route") erschien bei jeder Seite, nicht nur bei der ausgewählten** (2026-08-14,
      Nutzer-Fund per Screenshot). Ursache: `directRouteRow` zeigte das
      `checkmark.circle.fill`-Icon komplett unbedingt an - anders als die strukturell fast
      identischen `matchRow`/`combinedRouteRow`, die den Haken korrekt hinter
      `if match.id == selectedMatch?.id`/`combinedMatch?.id` verstecken. Fix: `directRouteRow`
      bekommt jetzt einen `isSelected`-Parameter (`index == selectedDirectRouteIndex`), Haken nur
      noch bei `if isSelected`. Build (Device-Ziel) erfolgreich, auf "iPhone von Jörn" installiert.
      **Live-Test zeigte weiteres, tieferliegendes Verhalten**: Da `directRoutePager` wie
      `matchesPager`/`combinedMatchesPager` das Wischen selbst schon als Auswahl behandelt
      (`TabView(selection: $selectedDirectRouteIndex)` setzt die Auswahl direkt beim Wischen, ganz
      ohne Antippen - bewusstes, dokumentiertes Verhalten aller drei Pager, s. Kommentare an
      `matchesPager`), zeigt jede Seite beim bloßen Durchwischen weiterhin ihren eigenen Haken -
      das ist kein Rendering-Fehler mehr, sondern folgt konsequent aus diesem App-weiten
      Wisch-wählt-aus-Muster. Nutzer-Entscheidung 2026-08-14 nach Rückfrage: **so lassen**, kein
      Umbau zu "Wischen nur Vorschau, erst Antippen wählt aus".
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`directRouteRow`,
      `directRoutePager`)
- [x] **Fix: Großer Leerraum zwischen Ergebnisliste und "Los"-Button bei wenigen Treffern**
      (2026-08-14, Nutzer-Fund per Screenshot: nur ein Treffer "Radrouten in der Nähe" nach
      Eingabe des Starts, darunter viel leere Fläche vor dem "Los"-Button). Ursache: Die
      `ScrollView` der Ergebnisliste (s. Fix oben, "Kartenvorschau schrumpfte...") bekommt per
      `.frame(maxHeight: resultsSectionMaxHeight)` nur eine Obergrenze - `ScrollView` füllt einen so
      angebotenen Platz aber immer komplett aus, unabhängig davon, ob der Inhalt tatsächlich so hoch
      ist. Bei nur einer Wisch-Karte reservierte das die vollen 320pt, obwohl der Inhalt viel
      kleiner war. **Zwei Fix-Versuche mit Laufzeit-Messung live auf dem iPhone gescheitert und
      wieder verworfen** - beide machten die komplette Ergebnisliste unsichtbar (nicht nur falsch
      hoch, sondern komplett weg, auch nach Laden der Treffer):
      1. `GeometryReader` direkt im Hintergrund von `resultsSection`, dessen gemessene Höhe per
         `PreferenceKey` in einen `@State` zurückgespeist und als `min(gemessen, resultsSectionMaxHeight)`
         auf dasselbe `ScrollView` angewandt wurde, das den `GeometryReader` enthielt - vermuteter
         Rückkopplungskreis (`ScrollView`-Höhe hängt von einer Messung ab, die im selben, dadurch
         begrenzten `ScrollView` stattfindet).
      2. Entkoppelter Versuch: unsichtbare, per `.fixedSize(vertical: true)` von jeder
         Höhenvorgabe unabhängige Mess-Kopie von `resultsSection` (`.frame(height: 0).hidden()`)
         parallel zum sichtbaren, unveränderten `ScrollView` in einem `ZStack` - sollte den
         Rückkopplungskreis aus Versuch 1 eigentlich vermeiden, zeigte auf dem iPhone aber exakt
         dasselbe Symptom (keine Route sichtbar).
      **Tatsächlicher Fix (3. Versuch): keine Laufzeit-Messung mehr, sondern eine deterministische
      Höhen-Schätzung** (`resultsSectionEstimatedHeight`) anhand derselben Zustandsgrößen, die
      `resultsSection` selbst zum Aufbau nutzt (`nearbyMatches`/`matches`/`combinedMatches`/
      `isDirectRouteMode`/`directRoutes`/`isFallbackMatches`/`isSearchingCombinedMatch`/`zielPlace`) -
      alle Wisch-Pager sind ohnehin fest `.frame(height: 102)` hoch, die Schätzung addiert dazu
      Label-/Divider-/Platzhalter-Konstanten je nach sichtbaren Abschnitten. Muss nicht pixelgenau
      sein (zu großzügig lässt nur etwas Leerraum, zu knapp macht die Liste an der Stelle
      scrollbar), vermeidet aber die SwiftUI-Unzuverlässigkeit der ersten beiden Versuche komplett,
      da sie zur Layout-Zeit nichts misst. `.frame(maxHeight: min(resultsSectionEstimatedHeight,
      resultsSectionMaxHeight))` auf dem `ScrollView`. Live auf dem iPhone getestet (München als
      Start, ein Treffer) und vom Nutzer für gut befunden.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`resultsSectionEstimatedHeight`,
      `resultsSectionMaxHeight`)
- [x] **"Radrouten in der Nähe"-Vorschau (Start ohne Ziel) nach Streckenlänge statt Entfernung
      sortiert** (2026-08-14, Nutzer-Wunsch: längste Route zuerst). `RouteMatcher.findNearby`
      selektiert die Kandidaten weiterhin nach Nähe (Suchradius + `limit`, unverändert) - nur die
      Anzeige-Reihenfolge in `loadNearbyMatches` wurde geändert, sortiert jetzt absteigend nach
      Streckenlänge. **Erster Versuch nutzte nur `route.distanceKm`** (OSM-`distance`-Tag) und
      scheiterte prompt am Live-Test: Nutzer-Fund - der Ammerseeradweg ist eine lange, bekannte
      Route, landete aber ganz hinten, weil er (wie viele auch bekannte Routen) in den OSM-Daten
      keinen `distance`-Tag trägt (`?? 0` schob ihn ans Ende). **Fix:** Neue
      `BikeRoute.geometryLengthKm` summiert die Streckenlänge direkt aus der Linien-Geometrie
      (`CLLocation.distance(from:)` zwischen aufeinanderfolgenden Punkten je Liniensegment,
      Segmente addiert) als Fallback, wenn `distanceKm` fehlt - kann bei an einer Regionsgrenze
      abgeschnittenen Kartendaten leicht zu kurz ausfallen, ist aber deutlich näher an der Wahrheit
      als `0`. `nearbySubtitle` zeigt jetzt ebenfalls immer diesen Fallback-Wert (vorher nur bei
      vorhandenem Tag), damit die angezeigte Länge zur Sortierung passt. Live auf dem iPhone
      getestet (Ammerseeradweg erscheint jetzt weiter vorn) und vom Nutzer für gut befunden.
      **Dritte Runde (Freiburg, per Screenshot gefunden):** Jetzt erschien "RadNETZ
      Baden-Württemberg" ganz vorn - Recherche direkt in `routes.sqlite` (Python-Nachbau von
      `findNearby` gegen die echte Datenbank, siehe Vorgehen unten) zeigte: das ist keine normale
      Route, sondern eine OSM-Superroute, die das GESAMTE landesweite Radnetz Baden-Württembergs
      als eine `route=bicycle`-Relation bündelt - über 15.800 unzusammenhängende
      Liniensegmente, die `geometryLengthKm` (s. o.) auf über 3100 km aufsummierte. Als Route zum
      Auswählen ergibt so ein Eintrag ohnehin keinen Sinn ("das ganze Bundesland" losfahren).
      **Fix:** Neue `RouteMatcher.isImplausiblyFragmentedSuperroute` (Schwellenwert 5000
      Liniensegmente - der bisher längste echte Fernweg im Datensatz, "Badischer Weinradweg" mit
      468 km, hat 2270 Segmente, reichlich Abstand nach unten) schließt solche Sammel-Einträge an
      allen vier Kandidatensuchstellen aus (`findMatches`, `findClosestMatches`, `findNearby`,
      `combinableRoutes`), nicht nur aus der Sortierung. Vor dem Fix per eigenem Python-Skript
      gegen die reale `routes.sqlite` verifiziert (Geometrie-BLOB entpackt, `findNearby`-Filterung/
      Dedup/Sortierung nachgebaut), dass "Badischer Weinradweg" danach korrekt vorn steht - dann
      erst gebaut und live getestet. Nutzer testete anschließend zusätzlich München, Berlin,
      Dresden, Bielefeld und Passau - überall unauffällig.
      → [BikeRoute.swift](FahrradApp/RadFaehrte/Models/BikeRoute.swift) (`geometryLengthKm`),
      [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift)
      (`isImplausiblyFragmentedSuperroute`), [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift)
      (`loadNearbyMatches`, `nearbySubtitle`)
- [x] **Ziel-/Start-Suche als größeres Sheet statt winzigem Dropdown** (2026-08-18, Nutzer-Beobachtung:
      das Inline-Dropdown unter dem Ziel-Feld war per `.frame(maxHeight: 220)` gedeckelt - geteilt
      zwischen "Auf Karte wählen", "Aktuelle Position", Favoriten-Leiste, "Zuletzt gesucht" und
      Live-Suchergebnissen, dadurch besonders das Scrollen durch die letzten Ziele fummelig). Ein
      erster Entwurf sah vor, das Textfeld an seiner Position zu belassen und nur das Dropdown durch
      ein Sheet darunter zu ersetzen - verworfen, da SwiftUI bei `.medium`/`.large`-Sheets
      standardmäßig die Interaktion mit dem Hintergrund blockiert und das Präsentieren eines Sheets
      die Tastatur eines fokussierten Feldes darunter einreißen kann (Risiko: Sheet schließt sich
      sofort wieder selbst). Stattdessen wandert das Sucheingabefeld jetzt komplett mit ins Sheet
      (Standardmuster wie bei Apple/Google Maps): das äußere Feld bleibt ein echtes `TextField` (für
      Kompatibilität mit `app.textFields["Start"/"Ziel"]` in den UI-Tests) und wird beim Fokussieren
      durch einen passiven `Text` ersetzt, während gleichzeitig ein `.sheet` mit eigenem, automatisch
      fokussiertem `TextField` (`isSheetFieldFocused`) plus `.presentationDetents([.medium, .large])`
      erscheint - nie zwei gleichnamige Textfelder gleichzeitig im Baum, daher keine Mehrdeutigkeit
      für XCUITest. Favoriten sind jetzt vertikale Listenzeilen statt horizontaler Scroll-Leiste
      (mehr Platz im Sheet), "Zuletzt gesucht"-Einträge lassen sich per Swipe-to-delete löschen statt
      über den kleinen "x"-Button direkt neben der Auswahlfläche. Gilt für Start- und Ziel-Feld
      gleichermaßen (gemeinsame Komponente), `ContentView.swift` musste dafür nicht geändert werden.
      Live auf dem iPhone getestet und vom Nutzer für gut befunden.
      → [LocationSearchField.swift](FahrradApp/RadFaehrte/Views/LocationSearchField.swift)
- [x] **Zuletzt gesuchte Ziele auch im Start-Feld anzeigen** (2026-08-18). Die Auswahl im Start-Feld
      wurde schon vorher im `RecentPlaceStore` gespeichert (`onPlaceChosen: recordRecent` war dort
      bereits verdrahtet) - nur die "Zuletzt gesucht"-Sektion selbst fehlte, weil `recents`/
      `onDeleteRecent` nur beim Ziel-Feld übergeben wurden. Start und Ziel teilen sich weiterhin
      denselben `RecentPlaceStore` (eine gemeinsame Liste, kein getrennter Verlauf je Feld).
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift)
- [x] **"Suchverlauf löschen" in den Einstellungen** (2026-08-18, Nutzer-Wunsch). Neuer Button unter
      "Meine Routen & Orte" (kein Favoriten-Pendant - Favoriten lassen sich in der Favoriten-Ansicht
      schon einzeln per Swipe löschen, ein Bulk-Löschen dort wäre redundant). Bestätigung per
      `.confirmationDialog` nach dem bestehenden Muster von "Navigation beenden" in `ContentView.swift`
      (roter "Löschen"-Button + "Abbrechen"). Neue `RecentPlaceStore.clear()` entfernt die
      `RecentPlaces.json` komplett. Der Button steht bewusst ohne `role: .destructive` (wäre sonst rot
      wie alle anderen Zeilen der Sektion) - die eigentliche destruktive Bestätigung passiert erst im
      Dialog selbst. Der ursprünglich mitgeplante Erklärtext im Footer der Sektion wurde auf
      Nutzer-Wunsch wieder entfernt (auch der schon vorher vorhandene zu "Alle Routen"/"Favoriten") -
      die Sektion hat jetzt keinen Footer mehr.
      → [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift),
      [RecentPlaceStore.swift](FahrradApp/RadFaehrte/Services/RecentPlaceStore.swift)
- [x] **Wegearten-Aufschlüsselung jetzt auch für die "Direkte Fahrrad-Route (online)"** (2026-08-18,
      Nutzer-Frage: bei den Offline-Alternativen ("ruhige Wege bevorzugt") wird die Wegearten-Liste
      angezeigt, bei der Online-Route (`MKDirections`) bisher nie - Ursache: `MKRoute` liefert selbst
      keine OSM-Tag-Daten, `DirectRoute.init(route:)` setzte `metersByCategory` bisher hart auf `[:]`.
      Fix: Sobald eine Online-Route geladen wird (`loadOnlineDirectRouteAlternative` - Wisch-Seite
      neben Offline-Alternativen - sowie der reine Online-Fallback-Zweig in `loadDirectRoute`, wenn gar
      keine Offline-Route gefunden wurde), wird ihre Polyline zusätzlich per Map-Matching gegen die
      lokal heruntergeladenen Wege-Graphen abgeglichen - dieselbe Technik, die
      `CuratedRouteStepMatcher`/`matchCuratedRouteSteps` bereits für kuratierte GPX-Routen nutzt, hier
      nur auf `MKRoute.polyline.coordinates` statt auf eine kuratierte Routen-Linie angewendet. Neuer
      `DirectRoute.init(route:metersByCategory:)`-Parameter (Default `[:]`) nimmt das Ergebnis auf.
      Bewusst **nicht** in `rerouteDirectRoute` ergänzt (Neuberechnung während aktiver Navigation bei
      Streckenabweichung) - dort soll die neue Route ohne zusätzliche Matching-Verzögerung möglichst
      schnell wieder auf der Karte erscheinen, Wegetypen sind während der laufenden Navigation
      zweitrangig. Funktioniert nur, wenn eine passende Region heruntergeladen ist (gleiche Grenze wie
      bei kuratierten Routen) und das Matching genug der Route abdeckt (`minMatchedFraction`) - sonst
      bleibt die Wegearten-Sektion wie bisher leer. Build (Device-Ziel) erfolgreich, auf "iPhone von
      Jörn" installiert - **live getestet und für gut befunden**.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`DirectRoute.init(route:)`,
      `loadOnlineDirectRouteAlternative`, `loadDirectRoute`, `matchCuratedRouteSteps`)
- [x] **Rastplätze auf der Karte (alle 16 Bundesländer)** (2026-08-19): Neue, eigenständige
      Funktion zeigt Trinkwasserstellen, Cafés, Aussichtspunkte und Fahrrad-Reparaturstationen aus
      OpenStreetMap als Pins auf der Karte. Erst als Test nur für Bremen + Niedersachsen gebaut,
      nach positivem Live-Test-Feedback ("gefällt mir gut") auf alle 16 Bundesländer ausgeweitet
      (`restStopSupportedRegions = Bundesland.allCases`). Technisch **vollständig parallel** zur
      bestehenden Wege-Graph-Infrastruktur aufgebaut, nicht in sie integriert - eigenes
      Datenformat/eigene Download-Verwaltung, damit sich das Feature bei Nichtgefallen
      rückstandsfrei entfernen lässt (reine Neu-Dateien + wenige additive Zeilen in
      `ContentView`/`SettingsView`/`AppSettings`/`RootTabView`).
      - **Datenpipeline**: `Scripts/build_rest_stops.py` liest nur einzelne OSM-Knoten
        (`osmium.FileProcessor` **ohne** `.with_locations()`, da anders als beim Wege-Graph keine
        Way-Geometrie aufgelöst werden muss) und schreibt sie in eine indizierte SQLite-Tabelle
        (Schema wie `routes.sqlite`: Zeilen + Bbox-Index, **kein** Blob-Format wie bei den
        Wege-Graphen, da Rastplätze Punktdaten sind, die live per Bbox abgefragt werden statt
        komplett in den Speicher geladen zu werden). Release-Tag `rest-stops-v1`, Asset-Name
        `<bundesland>_reststops.sqlite`.
      - **App-Seite**: `RestStopStore`/`RestStopRepository`/`RestStopCache`/
        `RestStopDownloadManager` (eigenständig, nicht generisch über `DownloadableRegion` -
        für einen 2-Länder-Test wäre das verfrüht; nutzt aber den bestehenden `Bundesland`-Enum
        direkt weiter). Download-UI: eigener `RestStopsOfflineView`-Screen (kein
        `OfflineMapsView<Region>`-Aufruf, um die generische Wege-Graph-UI unangetastet zu lassen),
        verlinkt aus einer neuen "Rastplätze"-Sektion in `SettingsView` mit einem einzelnen
        Ein/Aus-Schalter (`showRestStops`, Opt-in). Kartenanzeige: eigene `Annotation`+`Button`-Pins
        (kein `Map(selection:)`, konsistent mit der bestehenden Vermeidung von MapKits eingebauten
        interaktiven Annotation-APIs), Tippen öffnet ein minimales Detail-Sheet (Kategorie, Name,
        Koordinate).
      - **Live-Fund (Performance + UX)**: Ein erster Test *mit* Bänken (`amenity=bench`) zeigte zwei
        Probleme. Erstens technisch: Schon ein einzelner Stadtteil (Bremen/Findorff-Bürgerpark)
        lieferte durch die hohe Bankdichte hunderte Treffer gleichzeitig - die Menge eigener
        SwiftUI-`Annotation`-Views blockierte spürbar die Kartengesten (Pinch-to-Zoom reagierte
        nicht mehr). Dagegen wurden `restStopMaxLatitudeDelta` (0.02° - nur Straßenzug-Ebene) und
        ein harter Gesamt-Deckel `restStopMaxResults` (80, nach Nähe zum Kartenzentrum sortiert
        gekappt) ergänzt. Zweitens, unabhängig von der Performance-Korrektur, **Nutzer-Feedback
        nach Live-Test**: "zu unruhig auf der Karte, zu viele Pins" - Bänke allein waren in Bremen
        93 % aller Treffer (4033 von 4388) und für die Routenplanung kaum relevant. Bänke wurden
        daraufhin komplett aus der Extraktion entfernt (nur noch 4 statt 5 Kategorien) - Bremen
        schrumpfte dadurch von 4388 auf 357, Niedersachsen von 76.607 auf 5880 Treffer. Zweiter
        Live-Test **für gut befunden**. **Später (im Rollout auf alle 16 Bundesländer, s. u.)
        wieder als 5. Kategorie ergänzt** - nicht mehr komplett ausgeschlossen, sondern per
        40×40-m-Raster ausgedünnt (`BENCH_GRID_METERS` in `build_rest_stops.py`, max. eine Bank pro
        Zelle), um zwischen "gar keine Bänke" und "93 % aller Treffer" einen Mittelweg zu finden.
      - **Öffnungszeiten**: Zusätzliche `opening_hours`-Spalte (OSM-Rohtext, z. B. "Mo-Fr
        08:00-18:00; Sa 09:00-14:00") im Skript ergänzt, im Detail-Sheet unter dem Namen
        angezeigt (Uhr-Symbol) - bewusst **nicht** als "gerade geöffnet?"-Auswertung interpretiert,
        das wäre eine eigene kleine DSL-Interpretation (Feiertage, Sonderfälle) und deutlich mehr
        Aufwand als der reine Text. `RestStop.openingHoursGerman` übersetzt nur die englischen
        Wochentags-/Sonderkürzel (`Tu/We/Th/Su/PH/off` → `Di/Mi/Do/So/Feiertag/geschlossen`) per
        Wortgrenzen-Regex, damit die App trotz englischem OSM-Rohformat komplett deutsch bleibt (s.
        CLAUDE.md) - Zeiten/Kommas/Semikolons bleiben unverändert. Schema-Änderung, daher
        `restStopsFormatVersion` auf 2 hochgezählt (verwirft alte heruntergeladene Dateien
        automatisch). In Bremen haben 199 von 267 Cafés das Tag gesetzt, live getestet und für gut
        befunden.
      - **Rollout auf alle 16 Bundesländer**: `Scripts/build_rest_stops_bundeslaender.sh` (neu,
        analog `process_all_bundeslaender.sh` für die Wege-Graphen) lädt nacheinander jedes
        `.osm.pbf`, baut die Rastplätze-Datenbank und lädt sie als `rest-stops-v1`-Asset hoch;
        überspringt den Download, falls die `.pbf`-Datei schon lokal vorliegt (z. B. nach einem
        zwischenzeitlich abgebrochenen Lauf). Auf Nutzer-Wunsch einmal bewusst nach Bayern
        gestoppt (Akku laden), später mit den restlichen 12 fortgesetzt. Alle 16 Dateien liegen
        deutlich unter 1 MB (Bremen 48 KB, Bayern als größte 912 KB, `nordrhein-westfalen` trotz
        18 Mio. Einwohnern nur 816 KB) - Größe korreliert mit POI-Dichte, nicht mit
        Fläche/Bevölkerung, deshalb reale Werte statt einer Formel in
        `RestStopDownloadManager.restStopApproximateSizeKB`. Anzeige in `RestStopsOfflineView`
        entsprechend auf KB statt MB umgestellt (ein pauschales "~1 MB" für alle 16 wäre keine
        hilfreiche Unterscheidung gewesen).
      → [Scripts/build_rest_stops.py](FahrradApp/Scripts/build_rest_stops.py),
      [Scripts/build_rest_stops_bundeslaender.sh](FahrradApp/Scripts/build_rest_stops_bundeslaender.sh),
      [RestStop.swift](FahrradApp/RadFaehrte/Models/RestStop.swift),
      [RestStopStore.swift](FahrradApp/RadFaehrte/Services/RestStopStore.swift),
      [RestStopRepository.swift](FahrradApp/RadFaehrte/Services/RestStopRepository.swift),
      [RestStopCache.swift](FahrradApp/RadFaehrte/Services/RestStopCache.swift),
      [RestStopDownloadManager.swift](FahrradApp/RadFaehrte/Services/RestStopDownloadManager.swift),
      [RestStopsOfflineView.swift](FahrradApp/RadFaehrte/Views/RestStopsOfflineView.swift),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`restStopOverlayContent`,
      `reloadNearbyRestStops`, `restStopCandidatePaths`)
- [x] **Rastplätze auch aus dem Schnelleinstellungen-Sheet während der Navigation** (2026-08-21):
      Nutzer-Wunsch - der "Rastplätze anzeigen"-Schalter und der Download-Link waren bisher nur über
      den Einstellungen-Tab erreichbar, der während der Navigation ausgeblendet ist (Tab-Leiste weg).
      `NavigationQuickSettingsView` (erreichbar über das Zahnrad-Symbol in
      `ContentView.navigationControlsOverlay`) bekommt dafür eine eigene "Rastplätze"-Sektion,
      identisch zu der in `SettingsView` (Toggle + `NavigationLink` zu `RestStopsOfflineView`).
      Bewusst **anders** als die dortige Doc-Kommentar-Regel "Offline-Karten-Downloads o. Ä. wären
      hier fehl am Platz" (die bezieht sich auf die Wege-Graphen mit bis zu einigen hundert MB) -
      der Rastplätze-Download pro Bundesland ist mit unter 1 MB winzig, und der Bedarf entsteht
      typischerweise genau unterwegs ("hier wäre eine Pause gut"). Dafür bekommt
      `NavigationQuickSettingsView` einen neuen `restStopStore`-Parameter (von `ContentView`
      durchgereicht, dieselbe Instanz wie die Kartenanzeige, damit ein Download sofort auf der Karte
      sichtbar wird). Build (Device-Ziel) erfolgreich.
      → [NavigationQuickSettingsView.swift](FahrradApp/RadFaehrte/Views/NavigationQuickSettingsView.swift),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`showQuickSettings`-Sheet)
- [x] **Rastplatz-Kategorien einzeln ein-/ausschaltbar** (2026-08-21): Nutzer-Wunsch - bisher gab es
      nur den einen globalen Schalter `showRestStops` für alle 5 Kategorien zusammen. Neuer
      `@AppStorage`-Key `showRestStopKinds` (kommagetrennte `RestStop.Kind`-`rawValue`-Liste,
      Default = alle 5, analog dem bestehenden Muster bei `navigationStatSlots`/`NavigationStatKind`
      - Encode/Decode-Helfer dafür leben direkt auf `RestStop.Kind` statt separat, da eng an die
      Enum-Fälle gekoppelt). Eigene Unterseite `RestStopKindSettingsView` (analog
      `NavigationStatSettingsView` - eigener Screen statt 5 zusätzlicher Inline-Toggle-Zeilen in der
      "Rastplätze"-Sektion), verlinkt sowohl aus `SettingsView` als auch aus
      `NavigationQuickSettingsView` (dieselbe Dopplung wie beim bestehenden Rastplätze-Toggle, s.
      Eintrag oben). Filterung passiert in `ContentView.reloadNearbyRestStops` **vor** dem
      Ergebnis-Cap (`restStopMaxResults`), nicht erst beim Rendern - sonst könnte eine deaktivierte
      Kategorie (z. B. Bänke) weiterhin den Cap füllen und aktivierte Kategorien (z. B. Cafés) von
      der Karte verdrängen. `HowItWorksView` entsprechend ergänzt (nannte bis dahin ohnehin nur 4
      statt 5 Kategorien - Bänke fehlten dort seit deren Wiedereinführung, s. Eintrag oben). Build
      (Device-Ziel) erfolgreich, auf "iPhone von Jörn" installiert - **live getestet und für gut
      befunden**.
      → [RestStop.swift](FahrradApp/RadFaehrte/Models/RestStop.swift) (`Kind.decode`/`Kind.encode`),
      [AppSettings.swift](FahrradApp/RadFaehrte/Models/AppSettings.swift),
      [RestStopKindSettingsView.swift](FahrradApp/RadFaehrte/Views/RestStopKindSettingsView.swift),
      [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift),
      [NavigationQuickSettingsView.swift](FahrradApp/RadFaehrte/Views/NavigationQuickSettingsView.swift),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`reloadNearbyRestStops`),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **Biergärten als 6. Rastplatz-Kategorie + Nachzieh-Rollout für alle 16 Bundesländer**
      (2026-08-21): Nutzer-Wunsch. `amenity=biergarten` in `build_rest_stops.py` als `KIND_BEER_GARDEN`
      ergänzt (Label "Biergarten", Icon `mug.fill`), `RestStop.Kind.beerGarden` +
      `RestStopRepository.init?(rawKindValue:)`-Fall 5 entsprechend. Erst nur Bremen lokal neu gebaut
      und **direkt per `xcrun devicectl device copy to`** in den App-Container auf "iPhone von Jörn"
      geschoben (`Documents/RestStops/bremen.sqlite`) statt über das GitHub-Release - so ließ sich
      live testen, ohne die anderen 15 Regionen oder Downloads anderer (künftiger) Nutzer anzufassen.
      **Live-Test für gut befunden**, danach voller Rollout.
      - **Nebenfund beim Rollout**: Nur Bremen, Bayern (ursprünglich), Baden-Württemberg und
        Niedersachsen hatten tatsächlich Bank-Daten (`kind=4`) - die Bänke-Wiedereinführung (s.
        Eintrag "Rastplätze auf der Karte" oben) war nie bei den restlichen 12 Bundesländern
        angekommen, vermutlich ein unvollständiger Lauf von `build_rest_stops_bundeslaender.sh` beim
        letzten Mal. Der Biergarten-Rollout hat das automatisch mitgezogen, da jede Region ohnehin
        komplett aus der `.osm.pbf` neu gebaut wird - entsprechend sind die Dateien für diese 12
        Regionen jetzt deutlich größer (nicht nur wegen Biergärten, sondern weil sie erstmals
        überhaupt Bank-Daten enthalten).
      - **Rollout-Ablauf**: Jedes der 16 Bundesländer einzeln (Nutzer-Wunsch, nach jedem Bundesland
        gestoppt und auf Freigabe gewartet, s. Roadmap-Konvention weiter oben) - `.osm.pbf` von
        Geofabrik geladen, `build_rest_stops.py` neu gebaut, direkt per `gh release upload
        rest-stops-v1 <datei> --clobber` hochgeladen, `.pbf` danach wieder gelöscht (Speicherplatz).
        `Scripts/build_rest_stops_bundeslaender.sh` selbst nicht verwendet (dessen `STATES`-Liste war
        ohnehin veraltet, s. o.) - stattdessen jeder Schritt einzeln über die Kommandozeile, passend
        zum Wunsch nach Pausen zwischen den Bundesländern. Reihenfolge: Bayern, Nordrhein-Westfalen,
        Baden-Württemberg, Niedersachsen, Rheinland-Pfalz, Thüringen, Sachsen, Brandenburg, Hessen,
        Schleswig-Holstein, Sachsen-Anhalt, Mecklenburg-Vorpommern, Saarland, Berlin, Hamburg (Bremen
        vom Test bereits vorher hochgeladen). Alle 16 Assets im Release `rest-stops-v1` aktuell.
      - **Größen/Zahlen** (Biergärten pro Region, zur Einordnung): Bayern 995, Nordrhein-Westfalen
        415, Baden-Württemberg 446, Niedersachsen 142, Rheinland-Pfalz 169, Thüringen 136, Sachsen
        203, Brandenburg 121, Hessen 256, Schleswig-Holstein 31, Sachsen-Anhalt 75,
        Mecklenburg-Vorpommern 40, Saarland 37, Berlin 48, Hamburg 4, Bremen 10 - Dateigrößen jetzt
        zwischen 200 KB (Bremen) und 8 MB (Bayern), `RestStopDownloadManager.restStopApproximateSizeKB`
        entsprechend aktualisiert. Anzeige in `RestStopsOfflineView` wechselt jetzt automatisch zu MB
        ab 1000 KB (`RestStopDownloadManager.approximateSizeDisplay`, mit explizitem
        `Locale(identifier: "de_DE")` fürs Dezimalkomma, s. CLAUDE.md) - eine reine KB-Zahl wäre bei
        8000+ nicht mehr gut lesbar gewesen.
      - **`restStopsFormatVersion` auf 3 hochgezählt**, obwohl sich am SQLite-Schema selbst nichts
        geändert hat (reiner Inhalts-Refresh) - damit bereits heruntergeladene Regionen beim nächsten
        Start automatisch verworfen werden und sich die neuen Kategorien nachladen, statt dass
        jemand manuell löschen und neu herunterladen muss.
      → [Scripts/build_rest_stops.py](FahrradApp/Scripts/build_rest_stops.py),
      [RestStop.swift](FahrradApp/RadFaehrte/Models/RestStop.swift),
      [RestStopRepository.swift](FahrradApp/RadFaehrte/Services/RestStopRepository.swift),
      [RestStopStore.swift](FahrradApp/RadFaehrte/Services/RestStopStore.swift)
      (`restStopsFormatVersion`),
      [RestStopDownloadManager.swift](FahrradApp/RadFaehrte/Services/RestStopDownloadManager.swift),
      [RestStopsOfflineView.swift](FahrradApp/RadFaehrte/Views/RestStopsOfflineView.swift),
      [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift),
      [NavigationQuickSettingsView.swift](FahrradApp/RadFaehrte/Views/NavigationQuickSettingsView.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **Toiletten als 7. Rastplatz-Kategorie** (2026-08-22): Nutzer-Wunsch, nach Nachfrage "was wäre
      noch cool" (Alternativen Picknickplätze und Rastplätze-entlang-der-Route abgewogen, Nutzer
      wollte nur Toiletten). `amenity=toilets` in `build_rest_stops.py` als `KIND_TOILETS = 6`
      ergänzt (Label "Toilette", Icon `toilet.fill`), `RestStop.Kind.toilets` +
      `RestStopRepository.init?(rawKindValue:)`-Fall 6 entsprechend - identisches Muster wie beim
      Biergarten-Eintrag oben. Genauso erst nur Bremen lokal neu gebaut und live getestet (**für gut
      befunden**), danach voller Rollout über alle 16 Bundesländer einzeln mit Pause nach jedem
      (Bayern, Nordrhein-Westfalen, Baden-Württemberg, Niedersachsen, Rheinland-Pfalz, Thüringen,
      Sachsen, Brandenburg, Hessen, Schleswig-Holstein, Sachsen-Anhalt, Mecklenburg-Vorpommern,
      Saarland, Berlin, Hamburg - Bremen vorher schon hochgeladen).
      - **Toiletten pro Region**: Bayern 5295, Nordrhein-Westfalen 3426, Baden-Württemberg 3643,
        Niedersachsen 2469, Rheinland-Pfalz 1242, Thüringen 672, Sachsen 1315, Brandenburg 1523,
        Hessen 1829, Schleswig-Holstein 1482, Sachsen-Anhalt 593, Mecklenburg-Vorpommern 1022,
        Saarland 257, Berlin 626, Hamburg 348, Bremen 143 - deutlich seltener kartiert als Bänke,
        daher ohne eigenes Ausdünnen übernommen (anders als bei `KIND_BENCH`).
      - `restStopsFormatVersion` erneut hochgezählt (auf 4, gleiche Begründung wie beim
        Biergarten-Eintrag: reiner Inhalts-Refresh, aber automatische Aktualisierung bereits
        heruntergeladener Regionen gewünscht). Größentabelle in `RestStopDownloadManager.swift`
        entsprechend aktualisiert (z. B. Bayern jetzt 8,3 MB).
      → [Scripts/build_rest_stops.py](FahrradApp/Scripts/build_rest_stops.py),
      [RestStop.swift](FahrradApp/RadFaehrte/Models/RestStop.swift),
      [RestStopRepository.swift](FahrradApp/RadFaehrte/Services/RestStopRepository.swift),
      [RestStopStore.swift](FahrradApp/RadFaehrte/Services/RestStopStore.swift)
      (`restStopsFormatVersion`),
      [RestStopDownloadManager.swift](FahrradApp/RadFaehrte/Services/RestStopDownloadManager.swift),
      [RestStopsOfflineView.swift](FahrradApp/RadFaehrte/Views/RestStopsOfflineView.swift),
      [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift),
      [NavigationQuickSettingsView.swift](FahrradApp/RadFaehrte/Views/NavigationQuickSettingsView.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **Feature umbenannt zu "POI" + E-Bike-Ladestation/Bäckerei als neue Kategorien** (2026-08-24):
      Nutzer fand den Namen "Rastplätze" inzwischen unpassend (Kategorien wie Bäckerei/E-Bike-
      Ladestation sind keine "Rastplätze" im engeren Sinn) - nach kurzem Zwischenstand
      "Unterwegs-Punkte" (Nutzer-Auswahl aus 4 Vorschlägen) landete die endgültige Wahl auf **POI**.
      Alle UI-Strings in `SettingsView`, `NavigationQuickSettingsView`, `RestStopsOfflineView`,
      `RestStopKindSettingsView` und `HowItWorksView` entsprechend umbenannt ("POIs anzeigen",
      "POI-Kategorien", "POIs herunterladen") - interne Swift-Typnamen (`RestStop`, `RestStopStore`
      usw.) und Dateinamen bewusst **nicht** mit umbenannt (rein interne Bezeichner, kein
      Nutzernutzen, hätte nur unnötig viele Dateien angefasst).
      - **Neue Kategorien**: `amenity=charging_station` + `bicycle=yes`/`designated` als
        E-Bike-Ladestation (Icon `bolt.fill`) und `shop=bakery` als Bäckerei (Icon
        `takeoutbag.and.cup.and.straw.fill`). Auf Nutzer-Nachfrage "was gibt es noch für nette
        Sachen" auch Fahrrad-Luftpumpe (`amenity=bicycle_pump`) probiert, aber nach 0 Treffern in
        sowohl Bremen als auch Bayern (Live-Test) auf Nutzer-Entscheid wieder entfernt - offenbar in
        Deutschland kaum als eigener OSM-Knoten kartiert. `KIND_BICYCLE_PUMP = 8` bewusst nicht neu
        vergeben (Nummerierungslücke), da weder Bremen noch Bayern je eine Zeile mit diesem Wert
        hatten.
      - **Live-Fund (Cache-Bug)**: Beim Testen fiel auf, dass ein erneuter Download einer bereits im
        laufenden Prozess gecachten Region (`RestStopCache`) die alte, im Speicher gehaltene
        Repository weiterverwendete statt die neu heruntergeladene Datei zu lesen - bis zum
        nächsten App-Neustart. Betraf konkret den Testablauf: Testdaten per `devicectl copy`
        aufs Gerät geschoben, dann versehentlich nochmal reguär über die Einstellungen
        heruntergeladen (zog die zu dem Zeitpunkt noch alte Release-Version) - Bäckereien blieben
        unsichtbar, obwohl der Nutzer täglich an mehreren vorbeifährt. Gefixt in
        `RestStopDownloadManager.download`: `RestStopCache.shared.invalidate(path:)` direkt nach
        `store.save(...)`, bevor die Repository erneut warmgeladen wird.
      - **Rollout**: Wie gehabt alle 16 Bundesländer einzeln mit Pause, beginnend mit Bayern.
        E-Bike-Ladestationen pro Region: Bayern 1019, Baden-Württemberg 788, Nordrhein-Westfalen
        1018, Niedersachsen 431, Hessen 318, Rheinland-Pfalz 274, Schleswig-Holstein 189, Sachsen
        175, Sachsen-Anhalt 160, Brandenburg 147, Thüringen 113, Saarland 85, Mecklenburg-
        Vorpommern 74, Hamburg 47, Berlin 15, Bremen 3 - auffällig wenige in den Stadtstaaten
        Berlin/Hamburg trotz hoher POI-Dichte sonst, evtl. andere Tagging-Konvention dort oder
        tatsächlich seltener. `restStopsFormatVersion` auf 5 erhöht (reiner Inhalts-Refresh, wie
        bei den vorherigen beiden Rollouts).
      → [Scripts/build_rest_stops.py](FahrradApp/Scripts/build_rest_stops.py),
      [RestStop.swift](FahrradApp/RadFaehrte/Models/RestStop.swift),
      [RestStopRepository.swift](FahrradApp/RadFaehrte/Services/RestStopRepository.swift),
      [RestStopStore.swift](FahrradApp/RadFaehrte/Services/RestStopStore.swift)
      (`restStopsFormatVersion`),
      [RestStopCache.swift](FahrradApp/RadFaehrte/Services/RestStopCache.swift),
      [RestStopDownloadManager.swift](FahrradApp/RadFaehrte/Services/RestStopDownloadManager.swift)
      (`download` - Cache-Invalidierung),
      [RestStopKindSettingsView.swift](FahrradApp/RadFaehrte/Views/RestStopKindSettingsView.swift),
      [RestStopsOfflineView.swift](FahrradApp/RadFaehrte/Views/RestStopsOfflineView.swift),
      [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift),
      [NavigationQuickSettingsView.swift](FahrradApp/RadFaehrte/Views/NavigationQuickSettingsView.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **Sichtweite-Regler: Obergrenze von 200 m auf 300 m erhöht** (2026-08-24, Nutzerwunsch):
      Reine Bereichsänderung in `AppSettingsDefaults.navigationLookaheadRange` (50...200 →
      50...300) - Stepper in `NavigationSettingsView`/`NavigationQuickSettingsView` sowie die
      Kamera-Distanz-Umrechnung (`ContentView.navigationCameraDistance`) übernehmen den neuen
      Bereich automatisch, da beide den zentralen Range-Wert referenzieren statt eigener
      Grenzen. Auf dem iPhone des Nutzers gebaut und installiert.
      → [AppSettings.swift](FahrradApp/RadFaehrte/Models/AppSettings.swift)
      (`navigationLookaheadRange`)
- [x] **Statistik-Leiste um sechs weitere Werte ergänzt** (2026-08-24, Nutzer-Brainstorm "was
      könnte man noch hinzufügen" - sechs der vorgeschlagenen Ideen ausgewählt; anders als beim
      Drei-Werte-Batch vom 2026-08-07 brauchte einer davon (Sonnenuntergang) eine neue, komplett
      lokale Berechnung statt nur vorhandener Rohdaten):
      - **Netto-Höhenmeter** (`netElevation`): `tourElevationGainMeters − tourElevationLossMeters`,
        mit Vorzeichen dargestellt.
      - **Fahrtrichtung/Himmelsrichtung** (`heading`): `LocationManager.currentHeading` (bereits für
        die Kamera-Ausrichtung vorhanden) auf 8 Himmelsrichtungen (N/NO/O/SO/S/SW/W/NW) gerundet.
      - **Fortschritt in %** (`progressPercent`): zurückgelegte Strecke im Verhältnis zur Summe aus
        zurückgelegter Strecke und Luftlinie zum Ziel (`distanceToDestinationKm`) - dieselbe
        Luftlinien-Näherung wie beim bereits bestehenden Feld "Entfernung zum Ziel", da die
        tatsächliche Routenlänge je nach Navigationsmodus (kuratierte Route, Ketten-Match,
        Direktroute, importierte GPX) aus komplett unterschiedlichen Quellen käme.
      - **Akkustand des Telefons** (`batteryLevel`): `UIDevice.current.batteryLevel`, dafür
        `UIDevice.current.isBatteryMonitoringEnabled = true` einmalig in `ContentView.onAppear`
        gesetzt (ohne das liefert `batteryLevel` dauerhaft -1).
      - **Aktuelle Uhrzeit** (`currentTime`): einfache `DateFormatter`-Ausgabe.
      - **Sonnenuntergangszeit / Restzeit bis Sonnenuntergang** (`sunsetTime`/`timeUntilSunset`):
        neue Datei `SunCalculator.swift` mit einer Low-Precision-Variante des NOAA-Sonnenstand-
        Algorithmus (Meeus) - läuft komplett lokal aus Standort + Gerätedatum, keine Wetter-/
        Astronomie-API nötig. Genauigkeit im Bereich weniger Minuten, für eine
        Orientierungshilfe auf dem Rad ausreichend.
      - Für die durch die Ergänzungen auf 24 Einträge gewachsene Auswahl-Liste zusätzlich
        `NavigationStatKind`s Deklarationsreihenfolge (= Reihenfolge in der Einstellungen-Liste)
        von chronologisch/unsortiert auf thematisch gruppiert umgestellt (Geschwindigkeit → Strecke/
        Fortschritt → Zeit → Höhe → Sonstiges) - persistierte Auswahl (`rawValue`-Strings) davon
        unberührt. `arrivalTimeText` nutzt jetzt denselben neuen statischen `shortTimeFormatter` wie
        `currentTime`/`sunsetTime` statt eine eigene `DateFormatter`-Instanz pro Aufruf anzulegen.
        Build (Device-Ziel) erfolgreich, auf "iPhone von Jörn" installiert und gestartet - Nutzer
        hat die neuen Felder live gegengeprüft. Danach noch die Beschriftung unter dem Wert (z. B.
        "Aktuell", "Strecke", "Ziel") auf Nutzerwunsch von `.caption2` (11 pt) schrittweise auf
        `.system(size: 14)` vergrößert - benannte Textstile springen in zu großen Stufen (`.caption`
        = 12 pt, `.footnote` = 13 pt, kein Stil bei genau 14 pt), für pixelgenaue Anpassungswünsche
        ist eine feste `.system(size:)`-Punktgröße statt eines benannten Stils die passendere Wahl.
      → [NavigationStat.swift](FahrradApp/RadFaehrte/Models/NavigationStat.swift),
      [SunCalculator.swift](FahrradApp/RadFaehrte/Services/SunCalculator.swift) (neu),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`statDisplay`,
      `progressPercentDisplay`, `sunsetDate`, `compassDirectionText`, `shortTimeFormatter`,
      `navigationStat`), [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
- [x] **POIs für Länder außerhalb Deutschlands (Luxemburg, Liechtenstein, Andorra als Testländer)**
      (2026-08-24, Nutzerfrage "geht das auch für die europäischen Länder"): Bisher waren POIs fest
      auf `Bundesland` zugeschnitten (s. `RestStopStore`-Doc-Kommentar, "für einen 2-Länder-Test wäre
      die generische Abstraktion verfrüht") - mit einem zweiten Land war genau dieser Punkt erreicht.
      - **Genericisierung**: `RestStopStore`/`RestStopDownloadManager`/`RestStopsOfflineView` von fest
        `Bundesland` auf `<Region: DownloadableRegion>` bzw. dem neuen, engeren
        `RestStopDownloadableRegion`-Protokoll (`restStopDownloadURL`/`restStopApproximateSizeKB` -
        eigene Requirements statt `DownloadableRegion.downloadURL`/`.approximateSizeMB`, die bereits
        für die Wege-Graphen reserviert sind) umgestellt - direkt analog zu `WayGraphStore<Region>`,
        das für die Wege-Graphen bereits denselben Weg (Bundesland → +EuropaLand → +Frankreich/
        Italien/Spanien) gegangen ist. Koppelt die POI-Funktion nicht an die Wege-Graph-Klassen
        selbst, bleibt also weiterhin unabhängig entfernbar.
      - **Neue Konstante** `restStopSupportedEuropaLands: [EuropaLand]` (analog
        `restStopSupportedRegions`), bewusst nicht `EuropaLand.allCases` (von 34 Fällen haben bisher
        nur zwei eine gebaute POI-Datei). Zweite `RestStopStore<EuropaLand>`-Instanz app-weit in
        `RootTabView`, durchgereicht an `ContentView`/`SettingsView`/`NavigationQuickSettingsView` -
        gemeinsamer physischer Ordner `Documents/RestStops/` mit den Bundesland-Dateien (keine
        `rawValue`-Kollision).
      - **Neuer Release-Tag** `rest-stops-eu-v1` (statt `rest-stops-v1`, das implizit
        Bundesland-only ist) - analog `way-graphs-eu-v1` bei den Wege-Graphen.
      - **`ContentView.restStopCandidatePaths`** aggregiert jetzt Pfade aus beiden Regionstypen
        (Bundesland-Liste + Europa-Liste, je mit eigenem `boundingBox`-Vorfilter), analog dem
        bestehenden Mehrfach-Typ-Muster in `offlineGraphCandidatePaths`.
      - **UI**: In "Einstellungen" und im Navigations-Schnelleinstellungen-Sheet aus einem
        "POIs herunterladen"-Link zwei geworden ("POIs Deutschland" / "POIs Europa"), analog dem
        bestehenden "Offline-Karten Deutschland"/"Offline-Karten Europa"-Muster.
      - **Testländer**: Luxemburg (8669 POIs, Release-Asset 544 KB), Liechtenstein (608 POIs,
        56 KB) und Andorra (300 POIs, 36 KB) - alle drei pbf-Dateien lagen bereits lokal vor (aus
        der früheren Wege-Graph-Onboarding), `build_rest_stops.py` selbst brauchte keine Änderung
        (war schon länderunabhängig). Auf Nutzerwunsch schrittweise, ein Land nach dem anderen mit
        Zwischen-Check auf dem Gerät (analog dem Bundesländer-Rollout). Weitere kleine Länder
        (Malta, Monaco, ... - pbf liegt ebenfalls schon lokal vor) sowie die größeren macht der
        Nutzer selbst zu einem späteren Zeitpunkt mit schnellerem Internet. Alle drei auf dem
        iPhone des Nutzers live getestet ("läuft gut").
      → [RestStopStore.swift](FahrradApp/RadFaehrte/Services/RestStopStore.swift),
      [RestStopDownloadManager.swift](FahrradApp/RadFaehrte/Services/RestStopDownloadManager.swift)
      (`RestStopDownloadableRegion`, `Bundesland`/`EuropaLand`-Konformitäten),
      [RestStopsOfflineView.swift](FahrradApp/RadFaehrte/Views/RestStopsOfflineView.swift),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`restStopCandidatePaths`,
      `europaRestStopStore`), [RootTabView.swift](FahrradApp/RadFaehrte/RootTabView.swift),
      [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift),
      [NavigationQuickSettingsView.swift](FahrradApp/RadFaehrte/Views/NavigationQuickSettingsView.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)

## Bekannte Probleme

- [ ] **Bremen-Daten stecken offenbar auch im Niedersachsen-Wege-Graphen** (Live-Fund 2026-08-11,
      Nutzer-Beobachtung: Bremen-Offline-Karte gelöscht, App neu gestartet, Route komplett
      innerhalb Bremens - z. B. Große Weidestraße ↔ Bürgerpark, mehrere km von der Landesgrenze
      entfernt - fand trotzdem weiterhin eine "Ruhige Route (offline)"). Löschen selbst
      funktioniert korrekt (`WayGraphStore.delete` entfernt die `.sqlite`-Datei tatsächlich,
      `WayGraphCache` wird vorher invalidiert) - kein Cache-Bug. Ursache vermutlich im
      Rohmaterial: Der `offlineGraphCandidatePaths`-Vorfilter (grobe Bounding-Box je Bundesland,
      s. `WayGraphStore.RegionBoundingBox`) lässt Niedersachsen als Kandidaten für jede
      Bremen-Koordinate zu, da Bremen als Enklave innerhalb Niedersachsens liegt und dessen
      Bounding-Box zwangsläufig mit einschließt - das ist so beabsichtigt (billiger Vorfilter).
      Dass mit dem 2000-m-Snap-Radius aber selbst mitten in der Stadt Bremen tatsächlich
      Straßenknoten im heruntergeladenen Niedersachsen-Graphen gefunden werden, spricht dafür,
      dass der zugrunde liegende Geofabrik-Extrakt (`niedersachsen-latest.osm.pbf`, ungeklippt) die
      Bremer Straßendaten redundant enthält. Praktisch bedeutet das: Bremen einzeln löschen befreit
      nicht wirklich von den Bremen-Daten, solange Niedersachsen weiterhin heruntergeladen ist -
      nicht weiter untersucht/behoben, da **Nutzer-Entscheidung 2026-08-11: nicht nötig**
      (unkritisch, kostet nur etwas doppelten Speicherplatz).
      → [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift) (`RegionBoundingBox`, `delete`),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`offlineGraphCandidatePaths`),
      [Scripts/build_way_graph.py](FahrradApp/Scripts/build_way_graph.py)

- [x] **Wege-Graph Baden-Württemberg: Stuttgart-Bereich vom Rest der Region getrennt (Live-Fund
      2026-08-01)**: Nutzer meldete, dass "Direkte Fahrrad-Route" für Freiburg → Stuttgart
      (214 km, beide Enden innerhalb des heruntergeladenen Bundeslands Baden-Württemberg) nie
      offline berechnet wird, obwohl beide Städte erfolgreich auf einen Knoten im Wege-Graphen
      snappen. Diagnose in zwei Schritten:
      1. **Erste Vermutung (teilweise richtig, aber nicht die Hauptursache)**: `BikeRoutingEngine`s
         Standard-Obergrenze (300.000 besuchte Knoten, kalibriert für lokale Stadt-Strecken) reicht
         für ein so großes Bundesland (11,3 Mio. Knoten) nicht - dieselbe Klasse Problem, die für
         `CrossRegionRouteStitcher`-Teilstrecken schon mit `legMaxVisitedNodes = 1.500.000` gelöst
         wurde. Fix übernommen für die einfache Einzelregion-Suche
         (`ContentView.largeRegionMaxVisitedNodes`), grundsätzlich sinnvoll für andere große,
         zusammenhängende Strecken - **behebt den Freiburg-Stuttgart-Fall selbst aber nicht**.
      2. **Eigentliche Ursache**: Eine BFS-Erreichbarkeitsprüfung (unabhängig von Gewichtung/
         Zeitlimit, direkt gegen die vom Gerät kopierte `baden-wuerttemberg.sqlite`) ergab: von
         Freiburgs Knoten aus sind 11.219.695 der 11.346.909 Knoten erreichbar (praktisch der
         komplette Graph) - Stuttgarts Knoten gehört **nicht** dazu. Stuttgarts Bereich liegt in
         einer eigenen, vollständig getrennten Graph-Insel. Kein Umfangsproblem, sondern ein
         echter Fehler in der Wege-Graph-Erstellung (`Scripts/build_way_graph_v2.py`) - vermutlich
         wurden beim Bau zwei Teilgraphen nicht richtig zusammengeführt.
      - **Behoben (2026-08-06, s. o. "Isolierte Graph-Inseln... beheben")**: keine
        Baupipeline-Ursache - Stuttgarts damaliger Knoten lag zufällig auf einer der vielen kleinen,
        aber normalen OSM-Netzlücken. Allgemeiner App-seitiger Fix
        (`WayGraphRepository.nearestNodes`, `BikeRoutingEngine.routes`) probiert seitdem bei einem
        isolierten Startknoten automatisch nahegelegene Ausweichkandidaten, ohne Baden-Württemberg
        neu zu bauen.
      - Zusätzlicher Nebenbefund aus derselben Sitzung: Zwischen Freiburg und Stuttgart existiert
        auch **keine sinnvolle Kombination benannter Fernwege** (`findCombinedMatches` liefert 0
        Treffer trotz bis zu 2000 durchprobierter Routen) - anders als das Wege-Graph-Problem ist
        das kein Bug, sondern eine reale Eigenheit der OSM-Kartierung in dieser Region ("RadNETZ
        Baden-Württemberg" ist eine einzige große Netz-Relation, kein verkettbarer linearer
        Fernweg, s. auch "Straßennamen-Fehlermeldung" oben zu ähnlichen Netz- vs.
        Linear-Routen-Fällen).
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`largeRegionMaxVisitedNodes`,
      `offlineDirectRoutes`)

- [x] **Wege-Graph Niedersachsen: Cuxhaven vom Rest der Region getrennt (Live-Fund 2026-08-02,
      vermutlich derselbe Bug-Typ wie oben bei Baden-Württemberg)**: Entdeckt beim Live-Test der
      neuen Regionsketten-Funktion (s. o. "Offline-Grenzübergang für Ketten aus drei oder mehr
      Regionen") an der Strecke Cuxhaven → Hamburg: Die Ketten-Erkennung fand die korrekte Kette
      Niedersachsen → Schleswig-Holstein → Hamburg, beide Übergänge snappten plausibel (Lücken
      knapp über bzw. unter dem Limit), aber die erste Teilstrecke (Cuxhaven → Übergang bei
      Stade/Wedel, ~60 km) schlug bei der eigentlichen `BikeRoutingEngine`-Suche fehl. Temporäre
      Live-Debug-Ausgabe in `BikeRoutingEngine.search` zeigte: Die Suche brach nicht am
      `maxVisitedNodes`-Limit ab, sondern weil die Warteschlange nach nur **2 besuchten Knoten**
      leer lief - Cuxhavens genutzter Knoten hat im Niedersachsen-Graphen praktisch keine
      Verbindung zum übrigen Netz. Noch nicht wie beim Baden-Württemberg-Fall per BFS gegen die
      volle Datei verifiziert, aber dasselbe Symptom (isolierte Graph-Insel statt Knotenlimit) legt
      denselben Ursachen-Typ nahe (`Scripts/build_way_graph_v2.py`).
      - Auswirkung eingegrenzt: Betrifft nur diese eine Verbindung (bzw. andere Strecken, die
        ebenfalls über Cuxhavens isolierten Bereich müssten) - die Regionsketten-Funktion selbst
        wurde unabhängig davon anhand synthetischer Distanz-Closures unit-getestet und funktioniert
        nachweislich korrekt (s. o.).
      - **Behoben (2026-08-06, s. o. "Isolierte Graph-Inseln... beheben")**: BFS-Erreichbarkeitsprüfung
        gegen ein frisch heruntergeladenes Niedersachsen sowie gegen die tatsächlich ausgelieferte
        `niedersachsen_ways.sqlite` zeigt beide Male 97,81 % zusammenhängend, Cuxhaven eingeschlossen
        - keine Baupipeline-Ursache, sondern eine der vielen normalen kleinen OSM-Netzlücken, auf die
        der damalige Startknoten zufällig gefallen war. Allgemeiner App-seitiger Fix
        (`WayGraphRepository.nearestNodes`, `BikeRoutingEngine.routes`) probiert seitdem bei einem
        isolierten Startknoten automatisch nahegelegene Ausweichkandidaten, ohne Niedersachsen neu zu
        bauen.
      → [BikeRoutingEngine.swift](FahrradApp/RadFaehrte/Services/BikeRoutingEngine.swift) (`search`,
      Debug-Ausgaben nach Diagnose wieder entfernt)

**Nutzer-Entscheidung 2026-07-26**: Die App funktioniert insgesamt schon gut, keiner der vier
folgenden Punkte gilt aktuell als dringend – zurückgestellt, bis von Nutzer-Seite wieder Bedarf
gemeldet wird. Einträge bewusst nicht gelöscht (enthalten Diagnose-Stand/nächste Schritte, falls
später doch wieder aufgegriffen).

- [ ] **Bekannte EuroVelo-/D-Routen sind an manchen Stellen nicht durchgehend nutzbar - echte
      Grenze der OSM-Daten, bewusst nicht weiter verfolgt (Nutzer-Entscheidung 2026-07-30)**:
      Mehrere Live-Tests (Berlin↔Vreden, Münster↔Aachen, Münster↔Leverkusen) zeigten, dass
      "berühmte" internationale Fernwege (EuroVelo 2, EuroVelo 3) in der gefundenen Kombination
      nicht auftauchen, obwohl sie laut offizieller EuroVelo-Karte (vom Nutzer gegengeprüft,
      [eurovelo.com/ev3#map](https://de.eurovelo.com/ev3#map)) dort tatsächlich durchgehend
      verlaufen. Ursache **nicht** ein Bug in Suche/Algorithmus (A*, Ref-Tag-Bonus - beide bereits
      umgesetzt, s. o.), sondern echte Lücken in der OSM-Kartierung der jeweiligen Routen-Relation
      selbst: "EuroVelo 2 - Hauptstadt-Route - Teil Deutschland" zerfällt in 13 nicht miteinander
      verbundene Fragmente, "EuroVelo 3 - Pilgrim's Route - part Germany #6 100 Schlösser Route"
      in 5 Fragmente, deren nördlichstes schon **~8 km vor Münster endet** (bestätigt: nördlichster
      Punkt bei Lat 51,8878, Münster liegt bei 51,9607) - der Abschnitt durch die Stadt selbst
      (den die offizielle Karte zeigt) ist schlicht nicht Teil dieser OSM-Relation, obwohl die
      physische Radinfrastruktur dort vermutlich existiert. Damit die App das nicht wie ein eigenes
      Versäumnis wirken lässt, prüft sie jetzt zumindest transparent, ob so eine Route in der Nähe
      liegt - seit 2026-07-31 nicht mehr nur als Hinweistext, sondern als echter, wählbarer Treffer
      mit "Kartendaten hier lückenhaft" statt Streckenlänge (s. o. "Routen mit Kartenlücke bleiben
      sicht- und wählbar...", `nearbyWellKnownRouteMatches`) - Nutzer-Wunsch: selbst entscheiden
      können, ob man die Route trotz der Lücke nutzt.
      - **Geprüfte, aber verworfene Lösung**: Lücken in kuratierten Fernwegen automatisch über die
        vorhandene Straßen-Routing-Engine (`BikeRoutingEngine`, sonst nur für "Direkte
        Fahrrad-Route"/"Ruhige Route" genutzt) überbrücken. Verworfen wegen mehrerer Nachteile:
        (1) funktioniert nur, wenn das betroffene Bundesland heruntergeladen ist - dieselbe Suche
        verhielte sich je nach Nutzer/Gerät unterschiedlich; (2) vermischt zwei unterschiedliche
        Versprechen der App - eine automatisch überbrückte Lücke ist die eigene Einschätzung der
        App, keine tatsächlich beschilderte Strecke, der Nutzer bekäme "EuroVelo 3" angezeigt, führe
        aber ggf. einen unbeschilderten Weg; (3) keine klare Schwelle, ab welcher Lückengröße noch
        sinnvoll automatisch überbrückt werden sollte (8 km bei Münster vs. 450 km beim
        ID-Kollisions-Fund Berlin→Vreden); (4) spürbarer zusätzlicher Wartungsaufwand und
        Performance-Kosten (große Wege-Graphen zusätzlich laden). Einzig verlässlicher Fix bliebe
        eine Korrektur direkt in OpenStreetMap (die fehlende Verbindung als Relations-Mitglied
        nachtragen) - extern, nicht von der App aus lösbar, aber bei diesem konkreten Fund (nur
        ~8 km) potenziell ein kleiner, machbarer Beitrag, falls sich jemand (Nutzer oder
        OSM-Community) darum kümmern möchte.
      → [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift) (`nearbyWellKnownRouteMatches`)

- [x] **Navigations-Heading zeigt wiederholt in eine falsche, aber wechselnde Richtung - Ursache
      per echter Fahrt-Log-Auswertung gefunden, Korrektur eingebaut (2026-08-03)**: Nutzer-
      Beobachtungen 2026-07-25 (zwei Fahrten, Nordost/Nordwest an verschiedenen Stellen) und erneut
      2026-08-03 per Screenshots während einer Fahrt in der Bremer Altstadt (BGM-Smidt-Straße/Am
      Brill) - Karte zeigte diagonal statt geradeaus, obwohl laut Nutzer geradeaus gefahren wurde;
      Handy am Lenker/Vorbau montiert, zeigte zum Vorderrad.
      - **Diagnose**: `heading_debug.log` der Fahrt vom 2026-08-03 (12:23-12:29 UTC) per
        `xcrun devicectl device copy from --device 87BE914F-930C-51BC-A9F2-DB962D831B54
        --domain-type appDataContainer --domain-identifier com.frankenfeld.RadFaehrte
        --source /Documents/heading_debug.log --destination <lokaler Pfad>` kabellos vom iPhone
        geholt und ausgewertet (Python-Skript im Scratchpad, nicht Teil des Repos). Ergebnis
        eindeutig: `CLLocation.course` stimmte bei 15-19 km/h über mehr als eine Minute
        durchgehend auf ±5-10° mit der aus den rohen GPS-Positionen berechneten tatsächlichen
        Bewegungsrichtung überein (`course` selbst also verlässlich - **kein GPS-Problem**),
        während `currentHeading` (`CMDeviceMotion.heading`) einen stabilen Versatz von ca.
        35-45° zeigte - ein **Magnetometer-Bias**, plausibel durch die Halterung/Nähe zum
        Vorderrad (Nutzer-Beschreibung: Handy zeigt zum Vorderrad, also am Lenker/Vorbau, nicht
        am Rahmen montiert). Damit auch der zweite, in der App unabhängig gemeldete Effekt (rote
        "gefahrene Strecke"-Linie liegt neben der blauen Routen-Linie) erklärt: `hAcc` lag in
        diesem Abschnitt meist bei 8-10 m, was den engen 7-m-Einraste-Radius
        (`routeSnapThresholdKm`) der roten Linie öfter überschreitet als den 10-/20-m-Hysterese-
        Radius des blauen Punkts - eher normales GPS-Rauschen in der dicht bebauten Altstadt als
        ein eigener Bug; bewusst nicht angefasst, da der 7-m-Radius absichtlich eng gewählt wurde
        (ein vorheriger, größerer 15-m-Radius verursachte Zickzack in Kurven, s. o.
        "Navigations-Politur nach Live-Tests").
      - **Offline-Validierung vor der Korrektur**: Da der erste Korrektur-Versuch (s. o.,
        2026-07-25) im Live-Test scheiterte (Kartendrehung blieb bei falscher, ungefähr
        konstanter Ausrichtung stehen) und ohne Messdaten wieder zurückgebaut wurde, wurde diesmal
        zuerst ein Korrektur-Algorithmus offline gegen genau diese Aufzeichnung simuliert, bevor
        Swift-Code geändert wurde: geglätteter Bias-Schätzer (`heading - course`, exponentiell
        geglättet, nur aktualisiert bei ≥ 8 km/h und `courseAccuracy` ≤ 100) senkte den mittleren
        Heading-Fehler gegen die tatsächliche Bewegungsrichtung von 34° auf 8° (Anteil grob
        falscher Werte, > 20° Fehler, von 74 % auf 23 %).
      - **Implementierung**: `LocationManager.updateMagnetometerBiasEstimate` schätzt bei jedem
        GPS-Update (nur bei ≥ 8 km/h, gültigem `course`, `courseAccuracy` ≤ 100) den Versatz
        zwischen rohem `CMDeviceMotion.heading` (`rawDeviceHeading`) und `course`, geglättet
        (`biasSmoothingAlpha = 0.15`) statt bei einem einzelnen Ausreißer sofort zu springen -
        dieselbe Absicherung, an der der erste Versuch vermutlich gescheitert war (eine an einer
        Kreuzung/Rampe vermutlich selbst ungenaue Kurs-Messung). `currentHeading` (weiterhin von
        allen bisherigen Verwendungsstellen - Kamera, `compassBadge`, Richtungspfeil - unverändert
        genutzt) ist jetzt dieser korrigierte Wert, angewendet auf den weiterhin schnellen
        20-Hz-`CMDeviceMotion`-Strom (Rotation bleibt dadurch flüssig, nicht auf GPS-Update-Takt
        limitiert). `heading_debug.log` protokolliert jetzt zusätzlich `rawHeading` und `bias`
        neben dem korrigierten `heading`, damit ein künftiger Vergleich ohne weiteren Umbau
        möglich ist. Build für das iPhone des Nutzers erfolgreich (`xcodebuild`,
        `devicectl device install app`) - **Live-Verifikation auf einer echten Fahrt noch
        ausstehend** (Offline-Simulation ist eine Annäherung, keine Garantie fürs Live-Verhalten,
        s. gescheiterter erster Versuch). Debug-Logging bewusst weiter aktiv gelassen, um das bei
        Bedarf direkt nachvollziehen zu können.
      → [LocationManager.swift](FahrradApp/RadFaehrte/Services/LocationManager.swift)
      (`updateMagnetometerBiasEstimate`, `magnetometerBiasEstimate`, `rawDeviceHeading`,
      `correctedHeading`, `angularDifference`, `appendDebugLog`)

- [x] **Radweg-Seitenversatz bei mehrdeutigem `cycleway`-Tag: kein Raten mehr, nur noch bei
      eindeutigem `cycleway:right`/`cycleway:left` versetzt dargestellt – Live-Verifikation durch
      den Nutzer bestätigt (2026-08-02): funktioniert wie erwartet.**
      Nutzer-Meldung 2026-07-25 beim Fahren (Außer der Schleifmühle, Bremen): "Direkte
      Fahrrad-Route" zeigte den Radweg links der Fahrbahn an, gefahren wurde aber rechts.
      - Per Overpass-Abfrage geprüft: OSM hat dort eindeutig `cycleway:right=track`,
        `cycleway:left=no` – **keine falschen OSM-Daten**, die App zeigte es nur falsch an.
      - **Zwei Rate-Regeln nacheinander probiert und beide live widerlegt** (Kern-Erkenntnis der
        ganzen Untersuchung): [offset_side()](FahrradApp/Scripts/build_way_graph.py:75) enthielt
        ursprünglich eine "immer links raten"-Regel für Straßen mit mehrdeutigem, unqualifiziertem
        `cycleway=track`-Tag (kein `:left`/`:right`) - eingeführt nach einem früheren Live-Test an
        Findorffstraße/Crüsemannallee/Richtweg. Diese Regel vertauschte dabei versehentlich auch
        die eindeutigen `cycleway:right`/`cycleway:left`-Zweige mit, wodurch "Außer der
        Schleifmühle" (echtes `cycleway:right`-Tag) falsch wurde. Fix Nr. 1 (2026-07-26): die
        eindeutigen Zweige tag-treu zurückgestellt, die mehrdeutige Rate-Regel auf "rechts raten"
        umgestellt (gängige deutsche OSM-Konvention). Rebuild + Upload + Re-Deploy aufs iPhone
        durchgeführt - **Nutzer-Test danach zeigte Richtweg und Findorffstraße erneut falsch
        herum** (jetzt rechts statt links, während der reale Weg dort links liegt). Per Overpass
        zusätzlich geprüft: keine separat kartierte Radweg-Geometrie in der Nähe, die man
        stattdessen nutzen könnte - das Tag gibt die Seite bei diesen Straßen schlicht nicht her,
        unabhängig von der gewählten Rate-Richtung.
      - **Fix Nr. 2 / aktueller Stand (2026-07-26)**: Rate-Regel komplett entfernt. `offset_side()`
        gibt jetzt nur noch bei eindeutigem `cycleway:right`/`cycleway:left` einen Versatz zurück
        (tag-treu: `right` → `OFFSET_RIGHT`, `left` → `OFFSET_LEFT`); bei `cycleway:both` oder
        unqualifiziertem `cycleway` (keine Seitenangabe möglich) jetzt bewusst **kein Versatz**
        (`OFFSET_NONE`, Linie bleibt auf der Straßen-Mittellinie) statt eine Seite zu raten -
        Nutzer-Entscheidung nach Abwägung "ungenau aber nie aktiv falsch" vs. "hübscher aber
        regelmäßig auf der falschen Seite". `offsetPoint()` in
        [BikeRoutingEngine.swift](FahrradApp/RadFaehrte/Services/BikeRoutingEngine.swift:271)
        unverändert - war in allen Durchgängen bereits korrekt, das Problem lag ausschließlich in
        der Tag-Interpretation.
      - **Rebuild + Upload (Runde 2) abgeschlossen (2026-07-26, `rebuild_and_upload_v4.sh`)**: Alle
        16 Bundesländer neu von Geofabrik geladen, neu gebaut, als Assets in den GitHub-Release
        `way-graphs-v4` hochgeladen (`--clobber`). Beide Rebuild-Runden liefen fehlerfrei durch.
      - **App auf dem iPhone erneut gebaut und installiert (2026-07-26)**, per `xcodebuild` +
        `xcrun devicectl` auf das physische Gerät ("iPhone von Jörn").
      - **Live-Verifikation abgeschlossen (2026-08-02)**: Nutzer bestätigt - Richtweg,
        Findorffstraße und Crüsemannallee zeigen den Radweg jetzt korrekt ohne Versatz (Linie auf
        der Straße), "Außer der Schleifmühle" weiterhin korrekt rechts versetzt.
      → [Scripts/build_way_graph.py](FahrradApp/Scripts/build_way_graph.py) (`offset_side`),
      [BikeRoutingEngine.swift](FahrradApp/RadFaehrte/Services/BikeRoutingEngine.swift)
      (`offsetPoint`), [Scripts/rebuild_and_upload_v4.sh](FahrradApp/Scripts/rebuild_and_upload_v4.sh)
- [x] **`testUseCurrentLocationAsStart` gelöscht (Nutzer-Entscheidung 2026-08-07)**: Test flakte
      zuverlässig im Simulator (Start-Feld wurde nicht mit "Aktueller Standort" befüllt,
      `XCTWaiter` lief in Timeout) – Verdacht: Simulator hat keine simulierte Standort-Position
      gesetzt, wodurch `LocationManager`s einmalige Standortabfrage ins Leere läuft. Die reale
      Funktion ("Aktuelle Position" als Start) läuft auf dem echten iPhone nachweislich (s. o.
      diverse Live-Fixes, die den Marker/Standort-Fluss nutzen) – der flakende Test war reiner
      Simulator-Artefakt ohne echten Nutzen, daher entfernt statt repariert.
      → [RadFaehrteUITests.swift](FahrradApp/RadFaehrteUITests/RadFaehrteUITests.swift)
- [ ] **Kein Reroute auf parallelem Weg trotz Offline-Routing (Beispiel Weserlustweg)** – Nutzer-
      Meldung 2026-07-25: Bei aktiver "Direkter Fahrrad-Route" (Bremen-Offline-Wegegraph
      heruntergeladen) führte die berechnete Route über die Hastedter Brückenstraße, tatsächlich
      gefahren wurde aber auf dem direkt parallel liegenden Weserlustweg (Hastedt/Hemelingen,
      Bremen) – keine automatische Neuberechnung während der ganzen Fahrt.
      - Per Overpass-Abfrage geprüft: OSM kennt den Weserlustweg gut (`highway=path`,
        `bicycle=designated`, `foot=designated`, `segregated=yes`, beleuchtet, Beschilderung
        `DE:241`/`DE:1022-11`) – **keine OSM-Datenlücke**.
      - `build_way_graph.py` gewichtet `highway=path` + `bicycle=designated` sogar günstig
        (wie `cycleway`, Faktor 0.6, s. o. Findorffstraße-Fix) – der Weg müsste vom Router
        eigentlich bevorzugt werden, wenn er im Graphen sauber angebunden ist.
      - Zwei offene Hypothesen, noch nicht verifiziert:
        1. Anbindung des Weserlustweg an das übrige Wegenetz fehlt/ist an dieser Stelle
           unterbrochen (Damm-/Deichweg mit ggf. nur wenigen Einmündungen) – Router hätte ihn
           dann nie als Alternative gesehen.
        2. Der seitliche Abstand zur angezeigten Route blieb während der Fahrt unter der
           `directRouteDeviationThresholdKm`-Schwelle (25 m) – dann hätte die App das korrekt
           nicht als Abweichen gewertet, obwohl es sich für den Nutzer nach einem anderen Weg
           anfühlte.
      - **Nächster Schritt**: falls die Fahrt im Verlauf-Tab aufgezeichnet wurde, die
        aufgezeichnete GPS-Linie gegen die damals berechnete Route legen, um zwischen den beiden
        Hypothesen zu unterscheiden. Nutzer möchte das Thema später angehen.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`checkDirectRouteDeviation`,
      `directRouteDeviationThresholdKm`), [Scripts/build_way_graph.py](FahrradApp/Scripts/build_way_graph.py)
      (`HIGHWAY_WEIGHTS`, `weight_multiplier`)
- [x] **Ausgewählte Route bleibt manchmal unsichtbar auf der Karte, obwohl das Häkchen in der Liste
      schon korrekt gesetzt ist - behoben, Live-Verifikation durch Nutzer am 2026-08-01
      bestätigt ("klappt danke").** Nutzer-Meldung 2026-08-01 (Screenshot: "Große Weidestraße",
      "Stadtrundweg Bremen - große Route" mit Häkchen ausgewählt, aber keine blaue Linie auf der
      Karte): Tritt "sehr häufig" beim Antippen einer Route in der Ergebnisliste auf. Tippt man
      danach eine andere Route an, wird die sofort korrekt angezeigt; wechselt man dann zurück zur
      zuerst gewählten, wird auch die jetzt angezeigt.
      - **Ursache (Verdacht, nicht live bestätigt)**: `routeOverlayContent` zeichnete die Routen-
        `MapPolyline`s bisher über `ForEach(Array(selectedRouteLines.enumerated()), id: \.offset)`
        - die `ForEach`-Identität hing also nur vom Index innerhalb des Arrays ab, nicht vom Inhalt
        der Route selbst. Da `mergedLines` die meisten Routen (auch unterschiedliche) auf genau ein
        zusammenhängendes Segment reduziert, hatten zwei nacheinander gewählte, aber inhaltlich
        verschiedene Routen im Normalfall dieselbe Identität (Index 0). SwiftUI aktualisiert in
        diesem Fall nur die Koordinaten der bestehenden `MapPolyline`-Instanz, statt sie zu
        entfernen und neu hinzuzufügen - MapKits SwiftUI-`Map` zeichnet eine so "in place"
        geänderte Polyline dabei offenbar nicht zuverlässig neu. Erst eine Route mit einer
        *anderen* Segment-Anzahl (ändert die Zahl der `ForEach`-Elemente) erzwingt ein echtes
        Neuzeichnen alle sichtbaren Segmente - passt zum beobachteten Verhalten.
      - **Fix**: Neuer Zähler `routeSelectionToken`, der bei jeder Neuzuweisung von
        `selectedRouteLines` (in beiden `onChange`-Handlern für `selectedMatch` und
        `combinedMatch`) hochgezählt wird. Die `ForEach`-Identität der Routen-Segmente
        (`routeLineSlots`, neuer `RouteLineSlot`-Typ) kombiniert diesen Token mit dem Segment-
        Index, sodass jede neue Auswahl garantiert eine neue Identität bekommt, unabhängig von der
        zufälligen Segment-Anzahl. Analoger Fix für die hervorgehobene Alternative bei "Direkte
        Fahrrad-Route" (`selectedDirectRouteIndex`) - dieselbe Codestruktur (feste Position im
        `@MapContentBuilder`, kein `ForEach`) war potenziell genauso betroffen, dort aber noch
        nicht gemeldet.
      - Build für `RadFaehrte.xcodeproj` erfolgreich (`xcodebuild ... -destination 'id=...'`),
        auf "iPhone von Jörn" installiert (`xcrun devicectl device install app`). Noch offen:
        Nutzer bestätigt im echten Gebrauch, dass frisch gewählte Routen jetzt immer sofort
        erscheinen.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`routeOverlayContent`,
      `routeLineSlots`, `routeSelectionToken`, `RouteLineSlot`)
- [x] **Grüner Start-Marker/blauer Standort-Punkt blieben nach einer neuen Auswahl mitunter an der
      alten, falschen Position stehen, obwohl die zugrunde liegenden Koordinaten längst korrekt
      waren - zweiter Fall derselben MapKit-Redraw-Ursache wie beim ersten Eintrag oben
      (unsichtbare Route). Behoben, Live-Verifikation durch Nutzer am 2026-08-01 bestätigt
      (Zoom auf den Marker zeigte danach eindeutig Bremer Marktplatz/Rathaus/Ratskeller statt der
      vorherigen Küsten-Position).** Nutzer-Meldung 2026-08-01: Start "Aktueller Standort" (Nutzer tatsächlich in
      Bremen), Ziel Münster - Treffer "[D9] Weser-Romantische Straße Teil 1" mit "~147,2 km
      Entfernung zur Route". Grüner Start-Marker + blauer Standort-Punkt lagen auf der Karte jedoch
      weit nördlich an der Nordseeküste, nicht in Bremen. Auch nach explizitem Neustart der App und
      manueller Ortseingabe ("Bremen" statt "Aktueller Standort") blieb der Marker an derselben
      falschen Position - das widersprach der ersten Vermutung (veralteter GPS-Cache, s. u.).
      - **Erste Vermutung (widerlegt)**: `resolveCurrentLocationAsStart` übernahm ungeprüft die
        allererste, ggf. gecachte/veraltete `locationManager.currentLocation`-Position. Dagegen
        eingebaute Frische-Prüfung (`resolveCurrentLocationAsStartIfReady`, `timestamp` ≤ 15 s alt
        oder 8 s-Timeout) blieb wirkungslos - der Marker zeigte danach live immer noch dieselbe
        falsche Position, auch beim manuellen "Bremen"-Suchbegriff (der `currentLocation` gar nicht
        verwendet). Bleibt trotzdem sinnvoll (verhindert weiterhin einen echten Stale-Cache-Fall)
        und wurde nicht zurückgebaut.
      - **Tatsächliche Ursache, per temporärem Debug-Log (`route_debug.log`,
        `ContentView.appendRouteDebugLog`) zweifelsfrei bestätigt**: `startPlace.coordinate` war
        die ganze Zeit korrekt (Log vom 2026-08-01 10:41 UTC: `start=53.0758078,8.8073913`, echtes
        Bremen; `nearestToStart` nur 0,24 km entfernt - alles wie erwartet). Das Problem lag rein
        in der Kartendarstellung: `Marker(startPlace.title, ..., coordinate: startPlace.coordinate)`
        und die blaue `Annotation("Standort", coordinate: userLocationDisplayCoordinate)` standen
        als einzelne, strukturell immer gleich bleibende Elemente im `@MapContentBuilder` (kein
        `ForEach`, keine wechselnde Identität) - exakt dieselbe MapKit-Eigenheit wie beim ersten
        Eintrag oben: Ändert sich nur die `coordinate` einer bestehenden Marker-/Annotation-Instanz
        "in place", zeichnet MapKit sie bei größeren Sprüngen nicht zuverlässig neu.
      - **Fix**: `Marker(startPlace...)`/`Marker(zielPlace...)` jetzt über `ForEach([startPlace])`/
        `ForEach([zielPlace])` eingebunden - nutzt `SelectedPlace.id` (frische `UUID` pro Auswahl)
        als Identität, erzwingt also bei jeder neuen Auswahl ein echtes Entfernen+Hinzufügen. Für
        den blauen Punkt (der sich während der Navigation laufend in kleinen Schritten bewegt, wo
        ein Erzwingen bei *jedem* Update die Animation stören würde) neuer Zähler
        `userLocationMarkerToken`, der nur bei einem GPS-Sprung > `userLocationMarkerJumpThresholdMeters`
        (300 m, s. `updateUserLocationMarkerTokenIfNeeded`) erhöht wird - normale kleine
        Fahrt-Updates bleiben sanft, ein großer Sprung (wie hier beobachtet) erzwingt Neuzeichnen.
      - Build erfolgreich, auf "iPhone von Jörn" installiert. Temporäres Debug-Log
        (`route_debug.log`, `appendRouteDebugLog`) nach erfolgreicher Diagnose wieder entfernt
        (Fix erneut gebaut/installiert, Datei-Schreibcode existiert nicht mehr).
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`userLocationMarkerToken`,
      `updateUserLocationMarkerTokenIfNeeded`, `resolveCurrentLocationAsStart`,
      `resolveCurrentLocationAsStartIfReady`), [SelectedPlace.swift](FahrradApp/RadFaehrte/Models/SelectedPlace.swift)
- [x] **"Weser-Romantische Straße Teil 1" (Bremen -> Nordsee) blieb trotz mehrerer Sortier-Versuche
      als erste/aktive Seite im Einzeltreffer-Pager für Bremen -> Münster stehen, obwohl sie
      praktisch nutzlos für diese Fahrt ist - tatsächliche Ursache gefunden (eine zweite,
      bestehende Sortierung überschrieb die neue). Behoben, Live-Verifikation durch Nutzer am
      2026-08-01 bestätigt.** Nutzer-Beobachtung 2026-08-01: Der Treffer zeigte zwar korrekt transparent die
      riesige Restdistanz ("~147 km Entfernung zur Route", s. Eintrag oben), stand aber trotzdem an
      erster Stelle. Nutzer-Wunsch: nicht ausblenden (Rückschritt ggü. Nutzer-Entscheidung
      2026-07-31), auch nicht die Abschnitts-Reihenfolge (Einzeltreffer vor Kombination) ändern -
      nur *innerhalb* des Einzeltreffer-Pagers soll ein eindeutig besserer Treffer wie "EuroVelo 3 -
      Pilgrim's Route - part Germany" vorgezogen werden.
      - **Fix Nr. 1 (Teilschritt, allein unzureichend)**: `appendNearbyWellKnownMatches` sortiert
        `matches` seither nach dem Anhängen aufsteigend nach `combinedDistanceKm`. Blieb im Live-Test
        wirkungslos - Ursache war eine zweite, unabhängige, bereits bestehende Sortierung (s. u.),
        die kurz danach asynchron nachlief und die neue Reihenfolge wieder verwarf. Bleibt trotzdem
        sinnvoll als sofortige Zwischen-Sortierung, bevor diese zweite Sortierung greift.
      - **Fix Nr. 2 (Abschnitts-Reihenfolge, per Nutzer-Feedback zurückgenommen)**: Testweise
        `combinedMatchesSection` vor `singleMatchesSection` gezeigt, wenn der beste Einzeltreffer
        weiterhin unpraktikabel war. Nutzer wollte stattdessen die Abschnitts-Reihenfolge
        unverändert lassen - zurückgebaut, `resultsSection` zeigt wieder immer erst Einzeltreffer,
        dann Kombination.
      - **Tatsächliche Ursache gefunden**: [`practicalDistanceKm(for:)`](FahrradApp/RadFaehrte/ContentView.swift:2674)
        (genutzt von `filterAndReorderMatchesByPracticalDistance`, läuft automatisch, sobald die
        Streckenlängen-Berechnung für alle Treffer fertig ist - s. `loadRouteSegmentDistances`) gab
        bei einer echten Kartenlücke (`segment == nil`, "Kartendaten hier lückenhaft") bisher
        `.greatestFiniteMagnitude` zurück - sortierte solche Treffer dadurch *immer* ans Ende,
        selbst wenn beide Anschlusspunkte sehr nah an Start/Ziel liegen. Per Nutzer-Screenshot
        bestätigt: "EuroVelo 3 - Pilgrim's Route - part Germany" hatte nur ~0,5 km
        `combinedDistanceKm` (extrem nah an beiden Enden, nur mit Lücke dazwischen) - landete aber
        wegen der `.greatestFiniteMagnitude`-Regel hinter "D9 Teil 1" (~147 km, aber *berechenbar*
        da kein Kartenloch). Fix Nr. 1s Sortierung wurde dadurch zuverlässig von dieser zweiten,
        asynchron nachlaufenden Sortierung überschrieben.
      - **Fix Nr. 3**: `practicalDistanceKm(for:)` fällt bei einer Kartenlücke jetzt auf
        `match.combinedDistanceKm` zurück statt auf `.greatestFiniteMagnitude` - ein extrem naher,
        aber lückenhafter Treffer sortiert sich jetzt vor einen durchgehend berechenbaren, aber
        praktisch nutzlosen Treffer ein.
      - Build erfolgreich, auf "iPhone von Jörn" installiert, Live-Test nach komplettem App-Neustart
        bestätigt: "EuroVelo 3" erscheint jetzt vor "D9 Teil 1" im Einzeltreffer-Pager.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`practicalDistanceKm`,
      `filterAndReorderMatchesByPracticalDistance`, `appendNearbyWellKnownMatches`)
- [x] **Kombinationssuche schlug für Stuttgart -> Konstanz eine unsinnige 272-km-Kette vor**
      (Nutzer-Beobachtung 2026-08-06, per Screenshot): Als Kombination erschien eine über den
      Remstal-Radweg (Richtung Waiblingen, also zunächst vom Ziel weg) verkettete Route mit ~272 km
      Gesamtlänge (~16 h) bei nur ~130 km Luftlinie - ein klarer Umweg statt einer sinnvollen
      Verbindung. Zusätzlich erschienen "D-Route 8"/"EuroVelo 15" als Einzeltreffer mit ~67-70 km
      "Entfernung zur Route" und "Kartendaten hier lückenhaft" (erwartetes Verhalten von
      `nearbyWellKnownRouteMatches`, s. Eintrag 2026-07-31 - die Route liegt nur nahe Stuttgart, weit
      von Konstanz).
      - **Ursache**: `findCombinedMatches`s Sicherheitsgrenze `maxDistanceMultiplier` (bisher 3)
        ließ Ketten bis zum 3-fachen der Luftlinie zu - bei ~130 km Luftlinie also bis ~390 km. Die
        272-km-Kette lag darunter und wurde trotz erkennbarem Umweg nicht verworfen.
      - **Fix**: `maxDistanceMultiplier` von 3 auf 1.7 gesenkt - lässt weiterhin natürlich
        verwinkelte Ketten zu (Flusstal-/Gebirgsführung), verwirft aber deutlich ineffizientere
        Ketten. Betrifft beide Aufrufer (`runMatching`s Fallback und die zusätzliche
        Kombinationssuche neben Einzeltreffern), da beide den Default-Wert nutzen.
      - Build erfolgreich, auf "iPhone von Jörn" installiert, Live-Test Stuttgart -> Konstanz vom
        Nutzer bestätigt ("viel besser").
      → [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift) (`findCombinedMatches`,
      `maxDistanceMultiplier`)
- [x] **Kombinationssuche wählte für Bremen -> Hannover den falschen Treffer als aktive Auswahl**
      (Nutzer-Beobachtung 2026-08-06, per Screenshot, direkt im Anschluss an den
      `maxDistanceMultiplier`-Fix oben): Häkchen und Kartenlinie zeigten "D7 Pilgerroute"/"EuroVelo 3"
      (~96 km entfernt, Richtung Osnabrück/Rheinland - kommt Hannover nie nahe, s. Eintrag
      2026-08-02), während die eigentlich brauchbare, per Kombinationssuche gefundene Kette
      "StadtLandFluss → Weser-Romantische Straße → Energieroute Radweg → Aller-Radweg" (~156 km,
      plausible Größenordnung für die echte Strecke, vgl. die vom Nutzer tatsächlich gefahrene
      "Weser-Radweg → Aller-Radweg → Leine-Heide-Radweg"-Route) unmarkiert blieb.
      - **Ursache**: `attemptCombinedThenClosestFallback` setzte bisher `combinedMatch =
        combined.first` sofort nach Fund einer Kombination - überschrieb damit erstens die per
        `runMatching()` schon gesetzte "Direkte Fahrrad-Route"-Vorauswahl (Nutzer-Entscheidung
        2026-08-01). Schlimmer: Das direkt danach laufende `appendNearbyWellKnownMatches` befüllt
        `matches` - dessen eigener Wisch-Pager-Reset (`resultsSection.onChange(of: matches)` →
        `pagedMatchIndex = 0` → `matchesPager.onChange(of: pagedMatchIndex)` → `selectedMatch =
        items[0]`) kaskadierte über die zentrale Gegenseitige-Ausschließlichkeit
        (`onChange(of: selectedMatch)`) direkt danach nochmal drüber und nilte die gerade gesetzte
        `combinedMatch` wieder - Endergebnis war der erstbeste, oft kilometerweit entfernte
        `nearbyWellKnownRouteMatches`-Treffer aktiv statt der Kombination.
      - **Fix**: `combinedMatch = combined.first` entfernt - `combinedMatches` bleibt befüllt und im
        Wisch-Pager sicht-/wählbar, wird aber nicht mehr automatisch aktiv gesetzt. Bringt
        `attemptCombinedThenClosestFallback` in Einklang mit der Geschwister-Funktion
        `attemptCombinedSearchAsAdditionalOption`, die genau das aus demselben Grund schon seit
        2026-07-30 bewusst unterlässt (s. deren Doku-Kommentar).
      - Build erfolgreich, auf "iPhone von Jörn" installiert. Bestehende Test-Suite (`RadFaehrteTests`)
        lief auf dem echten Gerät mehrfach durch - dabei wiederholt (aber jeweils unterschiedliche)
        einzelne lang laufende Kombinations-Tests mit "Test crashed with signal kill" abgebrochen,
        nie derselbe zweimal, jeweils in Isolation grün - deutet auf Geräte-Timeout/-Watchdog bei
        Testläufen über `xcodebuild test` hin, nicht auf eine echte Regression durch diese Änderung.
      - **Fix Nr. 1 allein unzureichend** - Nutzer-Nachtest (2026-08-06, per Screenshot) zeigte
        weiterhin "EuroVelo 3"/"D7 Pilgerroute" mit Häkchen, obwohl `combinedMatch = combined.first`
        bereits entfernt war. **Tatsächliche, tiefere Ursache**: `pagedMatchIndex` (der Wisch-Pager-
        Index der Einzeltreffer-Seite) ist ein app-weiter `@State`, der über verschiedene Suchen
        *derselben* App-Sitzung hinweg erhalten bleibt. Stand er von einer früheren Suche noch auf
        einer anderen Seite als 0 (z. B. weil in einer vorigen Suche durch den Pager gewischt
        wurde), sah `resultsSection.onChange(of: matches) { pagedMatchIndex = 0 }`s Reset für
        SwiftUI wie ein *echter* Seitenwechsel aus - `matchesPager.onChange(of: pagedMatchIndex)`
        feuerte daraufhin genauso, als hätte der Nutzer aktiv zur ersten Seite gewischt, und setzte
        `selectedMatch = items[0]`, unabhängig davon, ob dieser erste Treffer je angetippt oder
        bewusst angesehen wurde. Derselbe Mechanismus betraf `combinedMatchesPager`/
        `pagedCombinedMatchIndex` identisch.
      - **Fix Nr. 2**: Beide Pager (`matchesPager`, `combinedMatchesPager`) nutzen jetzt ein eigenes
        `Binding`, dessen `set` (nur bei echter TabView-Nutzerinteraktion aufgerufen) zusätzlich zur
        Seite auch die Auswahl (`selectedMatch`/`combinedMatch`) setzt. Der programmatische Reset in
        `resultsSection.onChange(of: matches/combinedMatches)` schreibt weiterhin nur auf den rohen
        `pagedMatchIndex`/`pagedCombinedMatchIndex`-Zustand, läuft also nie durch dieses `Binding`
        und berührt die Auswahl nicht mehr - ein echter Wisch wählt weiterhin sofort aus, ein
        stiller Index-Reset nicht mehr.
      - Nutzer-Nachtest (2026-08-06) bestätigte: Fix Nr. 2 wirkt - kein automatisches Häkchen auf
        "EuroVelo 3"/"D7 Pilgerroute" mehr, antippen setzt weiterhin bewusst ein Häkchen wie
        erwartet. Der eigentliche, verbleibende Störfaktor war aber ein anderer: Die beiden Treffer
        **erscheinen überhaupt noch in der Liste**, obwohl sie Hannover nie nahekommen ("das sind
        Routen, mit denen ich nichts anfangen kann, wenn ich von Bremen nach Hannover möchte").
      - **Fix Nr. 3 - Wurzel des eigentlichen Problems**: `nearbyWellKnownRouteMatches` zeigte bisher
        jeden bekannten Fernweg, der nur an *einem* Ende nahe lag, unabhängig davon, wie weit das
        andere Ende entfernt ist (bewusste Nutzer-Entscheidung 2026-07-31, am Fall Münster -> Köln:
        EuroVelo 3 liegt dort an *beiden* Enden plausibel nahe, nur mit echter Kartenlücke
        dazwischen - "ein noch so großer Wert ist besser als gar keiner"). Bremen -> Hannover ist
        aber ein anderer Fall: EuroVelo 3/D7 Pilgerroute laufen von Bremen Richtung Osnabrück/
        Rheinland, kommen Hannover nie näher als ~94 km - keine Kartenlücke, sondern schlicht keine
        Route in der Gegend (dieselbe Unterscheidung wie bei `routeSegmentPathAllowingGap`, s.
        Eintrag 2026-08-02). `nearbyWellKnownRouteMatches` prüft jetzt zusätzlich, dass *auch* das
        entferntere Ende innerhalb der bestehenden `maxPlausibleAnchorDistanceKm`-Schwelle (20 km)
        liegt - vorher unbegrenzt. Neuer Regressionstest
        `nearbyWellKnownMatchesExcludesRoutesFarFromTheOtherEnd` (Bremen -> Hannover, erwartet weder
        "EV3" noch "D7"); bestehender Test zum Münster -> Köln-Fall lief unverändert grün durch (dort
        liegt Köln innerhalb der neuen Schwelle). Komplette Suite (57 Tests) auf dem echten iPhone
        grün.
      - Build erfolgreich, auf "iPhone von Jörn" installiert. Noch nicht auf dem iPhone
        nachgetestet - Nutzer muss Bremen -> Hannover ein viertes Mal prüfen.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`attemptCombinedThenClosestFallback`,
      `matchesPager`, `combinedMatchesPager`), [RouteMatcher.swift](FahrradApp/RadFaehrte/Services/RouteMatcher.swift)
      (`nearbyWellKnownRouteMatches`, `maxPlausibleAnchorDistanceKm`),
      [RadFaehrteTests.swift](FahrradApp/RadFaehrteTests/RadFaehrteTests.swift)
      (`nearbyWellKnownMatchesExcludesRoutesFarFromTheOtherEnd`)
## Geplante Features (Nutzer-Ideen + Ergänzungen, priorisiert)

### Offline-Karten Europa: noch fehlende Länder (Stand 2026-08-04)
Alle bisherigen 16 Länder (Deutschland + die 15 in "Aktueller Stand" oben) sind über
`download.geofabrik.de/europe/` bezogen. Liste unten per `curl -I` gegen die dortigen
`<land>-latest.osm.pbf`-Extrakte ermittelt (Größen können sich mit der Zeit leicht ändern -
vor dem tatsächlichen Bau jeweils neu prüfen, wie bisher immer gehandhabt). Sortiert nach
PBF-Größe, kleinste zuerst - bisheriges Muster war, kleine Länder unkompliziert direkt als
Einzeldatei zu bauen und nur bei Ländern über ca. 1,4-2 GB vorsorglich in Regionen aufzuteilen
(Lehre aus Italien, s. o.).

**Auf Nutzerwunsch gestrichen (2026-08-07)**: Moldau, Georgien, Belarus, die Ukraine und die
Türkei werden nicht ergänzt - keine weitere Begründung genannt, daher hier nicht weiter
kommentiert.

**Direkt als Einzeldatei machbar (analog Portugal/Tschechien/Slowakei/Albanien etc.):**
- [x] **Monaco** (~0,7 MB, Geofabrik-Slug `monaco`) - erledigt, s. "Aktueller Stand" oben
      ("Monaco als zwanzigstes Land ergänzt"). Tatsächlich sogar 0 kuratierte Routen statt nur
      "kaum" - nur der Wege-Graph wurde gebaut.
- [x] **Andorra** (~3 MB, `andorra`) - erledigt, s. "Aktueller Stand" oben ("Andorra als
      achtzehntes Land ergänzt")
- [x] **Liechtenstein** (~3 MB, `liechtenstein`) - erledigt, s. "Aktueller Stand" oben
      ("Liechtenstein als neunzehntes Land ergänzt")
- [x] **Malta** (~9 MB, `malta`) - erledigt, s. "Aktueller Stand" oben ("Malta als
      siebzehntes Land ergänzt")
- [x] **Nordmazedonien** (~29 MB, `macedonia`) - erledigt, s. "Aktueller Stand" oben
      ("Nordmazedonien als einundzwanzigstes Land ergänzt")
- [x] **Kosovo** (~31 MB, `kosovo`) - erledigt, s. "Aktueller Stand" oben ("Kosovo als
      zweiundzwanzigstes Land ergänzt")
- [x] **Montenegro** (~34 MB, `montenegro`) - erledigt, s. "Aktueller Stand" oben ("Montenegro
      als dreiundzwanzigstes Land ergänzt")
- [x] **Zypern** (~37 MB, `cyprus`) - erledigt, s. "Aktueller Stand" oben ("Zypern als
      zweiunddreißigstes Land ergänzt")
- [x] **Island** (~65 MB, `iceland`) - erledigt, s. "Aktueller Stand" oben ("Island als
      sechsunddreißigstes Land ergänzt")
- [x] **Estland** (~122 MB, `estonia`) - erledigt, s. "Aktueller Stand" oben ("Estland als
      dreiunddreißigstes Land ergänzt")
- [x] **Lettland** (~139 MB, `latvia`) - erledigt, s. "Aktueller Stand" oben ("Lettland als
      vierunddreißigstes Land ergänzt")
- [x] **Bosnien und Herzegowina** (~160 MB, `bosnia-herzegovina`) - erledigt, s. "Aktueller
      Stand" oben ("Bosnien und Herzegowina als vierundzwanzigstes Land ergänzt")
- [x] **Bulgarien** (~171 MB, `bulgaria`) - erledigt, s. "Aktueller Stand" oben ("Bulgarien als
      achtundzwanzigstes Land ergänzt")
- [x] **Kroatien** (~198 MB, `croatia`) - erledigt, s. "Aktueller Stand" oben ("Kroatien als
      sechsundzwanzigstes Land ergänzt")
- [x] **Litauen** (~222 MB, `lithuania`) - erledigt, s. "Aktueller Stand" oben ("Litauen als
      fünfunddreißigstes Land ergänzt")
- [x] **Serbien** (~238 MB, `serbia`) - erledigt, s. "Aktueller Stand" oben ("Serbien als
      fünfundzwanzigstes Land ergänzt")
- [x] **Slowenien** (~311 MB, `slovenia`) - erledigt, s. "Aktueller Stand" oben ("Slowenien als
      siebenundzwanzigstes Land ergänzt")
- [x] **Ungarn** (~321 MB, `hungary`) - erledigt, s. "Aktueller Stand" oben ("Ungarn als
      neunundzwanzigstes Land ergänzt")
- [x] **Rumänien** (~325 MB, `romania`) - erledigt, s. "Aktueller Stand" oben ("Rumänien als
      dreißigstes Land ergänzt")
- [x] **Griechenland** (~339 MB, `greece`) - erledigt, s. "Aktueller Stand" oben ("Griechenland
      als einunddreißigstes Land ergänzt")
- [x] **Irland (+ Nordirland)** (~409 MB, `ireland-and-northern-ireland`) - erledigt, s.
      "Aktueller Stand" oben ("Irland als siebenunddreißigstes Land ergänzt")
- [x] **Finnland** (~737 MB, `finland`) - erledigt, s. "Aktueller Stand" oben ("Finnland als
      achtunddreißigstes Land ergänzt")

**Vermutlich Regionen-Split nötig (>1 GB, vorsorglich wie Frankreich/Italien/Spanien prüfen):**
- [ ] **Norwegen** (~1,37 GB, `norway`) - läge in der Größenordnung von Polen/Schweden (beide
      erfolgreich als Einzeldatei), Italiens Lehre (dichte Kartierung → Ausgabe größer als PBF)
      macht vorsichtiges Vorgehen trotzdem sinnvoll
- [ ] **Großbritannien** (~2,16 GB, `great-britain`) - **zurückgestellt (Nutzerentscheidung
      2026-08-07)**. Über Italiens gescheiterter Einzeldatei-Größe (und schon jetzt über GitHubs
      2-GiB-Asset-Limit). Frühere Notiz hier war falsch: Geofabrik bietet England/Schottland/Wales
      **nicht** als eigene Extrakte an (geprüft per `curl` gegen
      `europe/great-britain/england-latest.osm.pbf` etc. - alle liefern 302 auf die Startseite,
      es existiert nur `great-britain-latest.osm.pbf` als Gesamtdatei). Ein Split wäre daher nur
      per selbst gebautem Zuschnitt entlang von OSM-Verwaltungsgrenzen (`osmium extract --polygon`
      mit England/Schottland/Wales-Grenzpolygonen) möglich, nicht per fertigen
      Geofabrik-Regionen wie bei Frankreich/Italien/Spanien - deutlich mehr Aufwand. Vor Angehen
      mit Nutzer klären, ob dieser Aufwand gewünscht ist.

**Nicht separat verfügbar**: San Marino und Vatikanstadt haben bei Geofabrik keinen eigenen
Extrakt (in `italy.osm.pbf` enthalten) - für sie wäre eine eigene Route-Extraktion aus dem
Italien-Gesamtextrakt nötig, falls gewünscht.

### Phase 1 – schnelle, unabhängige Verbesserungen
Keine Änderung an der Datenbank nötig, jeweils in sich abgeschlossen.

- [x] **Start/Ziel-Tausch-Button** – vertauscht die beiden `SelectedPlace`-Werte
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`swapStartAndZiel`)
- [x] **Standort als Start verwenden** – Button/Icon im Start-Feld, nutzt `LocationManager`
      statt Adresssuche (einmalige Standortabfrage, Titel „Aktueller Standort“, kein Reverse
      Geocoding)
      → [LocationSearchField.swift](FahrradApp/RadFaehrte/Views/LocationSearchField.swift), [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`useCurrentLocationAsStart`)
- [x] **Adress-Suche mit Hausnummer** – vom Nutzer getestet, `MKLocalSearch` liefert zuverlässig
      hausnummer-genaue Treffer in Deutschland. Kein Code nötig, Punkt damit erledigt.
- [~] **Filter nach Netzwerktyp** (rcn/ncn/icn/lcn) in der Ergebnisliste – Daten sind bereits
      in der DB vorhanden (`network`-Spalte), reine UI-Aufgabe. Aktuell zurückgestellt
      (Nutzer: "brauche ich erstmal nicht") – Idee bleibt hier dokumentiert, falls später
      relevant.

### Phase 2 – neue, in sich geschlossene Features

- [ ] **Rundtour-Modus** – Start = Ziel, Vorschlag einer Rundfahrt (Konzept noch zu klären:
      z. B. Umkreissuche nach Routen, die beim Startpunkt vorbeikommen und eine
      Mindestlänge/Form haben)
- [x] **Zuletzt gefahrene Strecken** – umgesetzt als "Verlauf"-Tab, s. o. unter "Vierter Tab
      'Eigene Routen' + echter Fahr-Verlauf" (Persistenz über JSON-Dateien statt UserDefaults/
      SwiftData).
- [ ] **Favoriten (Routen)** – weiterhin offen: manuell markierte Lieblingsstrecken (unabhängig vom
      automatischen Fahr-Verlauf). Nicht zu verwechseln mit "Favoriten (Orte)" direkt darunter -
      andere Idee, anderer Nutzen.
- [x] ~~**Favoriten (Orte), 1. Versuch: "Zuhause"/"Arbeit" + eigene Schnellziele**~~ – **umgesetzt,
      live getestet ("funktioniert super"), dann noch am selben Tag wieder verworfen** ("gefällt mir
      leider nicht", kein genannter Grund). Code per `git revert` entfernt (Commit `b12bcee`,
      revertiert `97b5996`). Bei Nachfrage (2026-08-04) konkretisiert: die Favoriten-Zeilen blieben
      strukturell fest in der Vorschlagsliste verankert, unabhängig davon ob schon getippt wurde -
      wirkte dadurch mit den echten Adress-Suchergebnissen vermischt statt wie bei Google Maps klar
      vom Tipp-Vorgang getrennt. Siehe 2. Versuch direkt darunter, der genau das behebt.
- [x] **Favoriten (Orte), 2. Versuch: "Zuhause"/"Arbeit" + eigene Schnellziele, Google-Maps-Stil**
      (Nutzer-Wunsch 2026-08-04, nach Verwerfen des 1. Versuchs s. o.): Gespeicherte Orte (nicht
      Routen) fürs schnelle Auswählen als Start/Ziel.
      - **Anzeige nur bei leerem Suchfeld**: Anders als beim 1. Versuch erscheinen Favoriten (und
        die neue "Zuletzt gesucht"-Liste, s. u.) nur, solange noch nichts eingetippt ist
        (`LocationSearchField.showsFavoritesAndRecents`) - sobald eine Eingabe beginnt, weichen sie
        vollständig den echten Adressvorschlägen, statt wie beim 1. Versuch dauerhaft in der Liste
        stehen zu bleiben. "Auf Karte wählen"/"Aktuelle Position" bleiben wie bisher unabhängig vom
        Suchtext sichtbar.
      - **Nur im Ziel-Feld, nicht im Start-Feld** (Live-Test 2026-08-04: Nutzer sah "Zuhause"/
        "Arbeit" beim Antippen des leeren Start-Felds und fand das unnötig - Start ist praktisch
        immer "Aktuelle Position", Favoriten sind eher Fahrtziele). `ContentView` übergibt
        `favorites`/`recents`/`onDeleteRecent` deshalb nur noch an das Ziel-`LocationSearchField`
        (Parameter dort defaulten auf `[]`, ohne Übergabe zeigt das Start-Feld also nichts).
        Speichern per Stern-Symbol bleibt in beiden Feldern möglich (ein im Start-Feld gewählter Ort
        landet über denselben `FavoritePlaceStore` trotzdem in der Ziel-Feld-Liste), ebenso
        schreibt eine Start-Feld-Auswahl weiterhin in "Zuletzt gesucht" mit (`onPlaceChosen:
        recordRecent` bleibt an beiden Feldern dran) - nur die Anzeige der beiden Listen ist auf
        das Ziel-Feld beschränkt.
      - **Favoriten als horizontale Kacheln, nicht als Liste** (Live-Test 2026-08-04: Nutzer schickte
        zum Vergleich einen echten Google-Maps-Screenshot - dort stehen Zuhause/Arbeit/weitere als
        nebeneinander scrollbare Kacheln mit Icon + Name + Adresse, getrennt durch vertikale
        Trennlinien, nicht als vertikale Listenzeilen wie im 1. Versuch). Umgesetzt als
        `ScrollView(.horizontal)` mit `HStack` über `favorites`, jede Kachel ein `Button` mit
        Icon + zweizeiligem Text (Name/Adresse), `Divider()` zwischen den Kacheln statt darunter -
        dadurch klar von der weiterhin vertikalen "Zuletzt gesucht"-Liste darunter unterscheidbar.
      - **Neu dazu: "Zuletzt gesucht"** (Nutzerwunsch beim selben Gespräch, Google Maps als
        Vorbild) - eine automatisch mitgeschriebene Liste der zuletzt gewählten Adress-Treffer
        (max. 6, neueste zuerst, gleicher Titel rutscht statt Duplikat nur nach oben), unterhalb der
        Favoriten mit eigener "Zuletzt gesucht"-Überschrift, einzeln löschbar über ein kleines Kreuz
        pro Zeile. Getrennter Store von `FavoritePlaceStore`, da hier nichts bewusst gespeichert
        wird → [RecentPlace.swift](FahrradApp/RadFaehrte/Models/RecentPlace.swift),
        [RecentPlaceStore.swift](FahrradApp/RadFaehrte/Services/RecentPlaceStore.swift) (JSON,
        eine Datei mit der ganzen Liste statt einer Datei je Eintrag wie bei `FavoritePlaceStore`).
      - **Speichern (Favorit)**: wie beim 1. Versuch unverändert - Stern-Symbol neben dem
        Lösch-Symbol im Suchfeld, sobald ein Ort ausgewählt ist, öffnet einen Dialog ("Als Zuhause
        speichern" / "Als Arbeit speichern" / "Eigener Favorit ..." mit Namens-Eingabe). Zuhause/
        Arbeit sind feste, je einmalige Sonderplätze (neuer Ort ersetzt den alten,
        `FavoritePlaceStore.save`) - eigene Favoriten beliebig viele.
      - **Verwalten/Löschen (Favoriten)**: Unterseite Einstellungen → Favoriten
        ([FavoritePlacesView.swift](FahrradApp/RadFaehrte/Views/FavoritePlacesView.swift)) - für
        "Zuletzt gesucht" keine eigene Verwaltungsseite, nur das Kreuz pro Zeile direkt in der
        Vorschlagsliste (Liste begrenzt sich über die Kappung auf 6 Einträge ohnehin selbst).
      - **Speicherung**: JSON-Dateien/-Datei in `Documents/FavoritePlaces/` bzw.
        `Documents/RecentPlaces.json`, analog `ImportedRouteStore`/`DrivenTourStore` - kein
        SwiftData/Core Data nötig.
      - **Type-Checker-Stolperstein** (unverändert vom 1. Versuch übernommen): Die zwei
        Favoriten-Dialoge (Auswahl + Namens-Alert) als weitere inline
        `.confirmationDialog`/`.alert`-Modifier direkt an `ContentView.body` angehängt ließen den
        Compiler mit "unable to type-check this expression in reasonable time" scheitern - behoben
        durch Auslagerung in `FavoriteSaveDialogsModifier: ViewModifier`.
      - Per `devicectl` über WLAN aufs iPhone übertragen und live getestet (2026-08-04, mehrere
        Runden mit Nutzer-Feedback zwischendurch): Speichern Zuhause/Arbeit/eigener Favorit,
        Anzeigen/Antippen der Favoriten-Kacheln und "Zuletzt gesucht"-Liste im Ziel-Feld bei leerem
        Suchfeld, Verschwinden beim Tippen, Kachel-Layout - alles bestätigt ("Passt gut"). Löschen
        einzelner Favoriten geht bisher nur über Einstellungen → Favoriten (Swipe-to-Delete), nicht
        direkt an der Kachel - für den Nutzer i.O., siehe Rückfrage im selben Gespräch.
      - **Löschen einzelner Favoriten direkt an der Kachel** (z. B. Long-Press-Menü) wurde dem
        Nutzer als Ergänzung angeboten, aber nicht angefordert - offene Idee für später, falls der
        Umweg über Einstellungen → Favoriten sich als lästig erweist.
      - **Bug behoben: Favorit von "Aktueller Position" gespeichert übernahm Platzhaltertitel**
        (Live-Fund 2026-08-04: Nutzer speicherte "Arbeit", während "Aktuelle Position" als Start
        gewählt war - die Zeile zeigte danach dauerhaft "Aktueller Standort" statt einer echten
        Adresse). Ursache: `resolveCurrentLocationAsStart` setzt für `startPlace` bewusst nur den
        UI-Platzhaltertitel `"Aktueller Standort"` (praktisch fürs Live-Anzeigen während der Fahrt,
        keine Adresse nötig) - `saveFavorite` übernahm diesen Platzhalter bis dahin ungeprüft 1:1.
        Fix: `saveFavorite` erkennt den Platzhalter (neue Konstante
        `ContentView.currentLocationTitle`, ersetzt die bisher doppelt vorkommende Literalzeichenkette)
        und löst die Koordinate vorher per `CLGeocoder` zu einer echten Adresse auf - derselbe Weg,
        den `pickZielOnMap`/`reverseGeocodeZielPlace` für "Auf Karte wählen" schon nutzten (Logik in
        `addressComponents(from:fallbackTitle:)` extrahiert, jetzt von beiden Stellen gemeinsam
        genutzt). Bereits installierte, falsch benannte Favoriten (z. B. der Nutzer-Testfall
        "Arbeit") sind davon nicht automatisch repariert - Nutzer wurde gebeten, sie einmal manuell
        zu löschen und neu zu speichern.
        → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`currentLocationTitle`,
        `addressComponents(from:fallbackTitle:)`, `saveFavorite`, `reverseGeocodeZielPlace`)
      → [FavoritePlace.swift](FahrradApp/RadFaehrte/Models/FavoritePlace.swift),
      [FavoritePlaceStore.swift](FahrradApp/RadFaehrte/Services/FavoritePlaceStore.swift),
      [FavoritePlacesView.swift](FahrradApp/RadFaehrte/Views/FavoritePlacesView.swift),
      [RecentPlace.swift](FahrradApp/RadFaehrte/Models/RecentPlace.swift),
      [RecentPlaceStore.swift](FahrradApp/RadFaehrte/Services/RecentPlaceStore.swift),
      [LocationSearchField.swift](FahrradApp/RadFaehrte/Views/LocationSearchField.swift)
      (`favorites`, `recents`, `onSaveFavorite`, `onDeleteRecent`, `onPlaceChosen`,
      `showsFavoritesAndRecents`, `select(_ favorite:)`, `select(_ recent:)`),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`favoritePlaces`,
      `recentPlaces`, `favoritePlaceStore`, `recentPlaceStore`, `saveFavorite`, `recordRecent`,
      `deleteRecent`, `FavoriteSaveDialogsModifier`),
      [SettingsView.swift](FahrradApp/RadFaehrte/Views/SettingsView.swift),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift) ("Route suchen")

### Phase 3 – erfordert Neuextraktion der OSM-Daten

Diese Punkte brauchen zusätzliche Informationen, die die aktuelle `routes.sqlite` nicht enthält
(nur Routen-Relationen mit Gesamtgeometrie, keine Einzelsegment-Attribute).

- [x] **Straßennamen pro Wegabschnitt für kuratierte Radrouten** (Map-Matching-Versuch,
      2026-08-01) – **für Einzeltreffer umgesetzt**, ohne `routes.sqlite` neu zu extrahieren:
      [CuratedRouteStepMatcher.swift](FahrradApp/RadFaehrte/Services/CuratedRouteStepMatcher.swift)
      snappt die (Douglas-Peucker-vereinfachte) Polyline eines Treffers auf den ohnehin für die
      Offline-Engine vorhandenen Wege-Graphen (`WayGraphRepository`) - direkte Kante wo möglich,
      sonst eine eng begrenzte, rein distanzbasierte Überbrückung für Lücken.
      - **Historie/Sackgasse**: Die erste Version routete zwischen alle 300 m abgetasteten
        Stützpunkten per `BikeRoutingEngine.route` (derselben "ruhigsten Route"-Suche wie die
        Offline-Engine) - Live-Diagnose gegen eine bekannte Referenzstrecke zeigte einen
        4-fachen Umweg auf einem einzelnen Hop (298 m Luftlinie → 1208 m tatsächliche Länge):
        "ruhigste Route zwischen zwei Punkten" ist das falsche Werkzeug fürs Nachzeichnen einer
        schon feststehenden Strecke. Die jetzige Version (Knoten-Snapping statt Neu-Routen) liegt
        beim selben Test innerhalb von 1 % der Referenzdistanz.
      - Per Unit-Test gegen echte Bremen-Wege-Graph-Daten validiert (synthetischer Rundlauf-Test
        + echte Weser-Radweg-Geometrie), zusätzlich live auf dem iPhone bestätigt (plausible
        echte Straßennamen: Bredenstraße, Schlachte, Wilhelm-Kaisen-Brücke, Werderstraße - kein
        Absturz, keine Lücken).
      - **UI-Anbindung**: Vorschau-Sheet über neues Listen-Symbol neben einem Einzeltreffer
        (`curatedRouteStepsDetail`/`curatedRouteStepsDetailSheet`), **und** echte Live-Turn-by-
        Turn-Navigation - die Navigations-Kopfzeile (`previewedStep`/`navigationInstructionText`/
        Watch-Haptik) wurde dafür über eine neue `activeStepRoute`-Abstraktion generalisiert
        (entweder `directRoutes[selectedDirectRouteIndex]` oder das neu geladene `curatedRoute`),
        bewusst **ohne** `isDirectRouteMode` selbst anzufassen (das hätte Reroute-/GPX-Export-/
        Alternativrouten-Logik mit betroffen, unnötiges Risiko für die gut funktionierenden
        Teile). Live auf dem iPhone bestätigt: echte Abbiege-Ankündigung mit Straßenname +
        Live-Entfernung + Pfeil-Icon, identisch zur "Direkten Fahrrad-Route".
      - **Kombinierte Ketten nachgezogen** (2026-08-01, Nutzer-Wunsch): `combinedMatch` (mehrere
        verkettete Fernwege) nutzt dieselbe Matching-Logik pro Etappe (`CombinedRouteLeg.
        pathCoordinates` liegt bereits vor, kein erneutes `routeSegmentPath` nötig), Etappen
        werden unabhängig gematcht (können in unterschiedlichen heruntergeladenen Regionen
        liegen) und mit Verschmelzung an den Etappengrenzen aneinandergereiht. Das Etappen-Sheet
        zeigt zusätzlich eine "Straßennamen"-Sektion über alle Etappen hinweg, und die Live-
        Turn-by-Turn-Navigation funktioniert jetzt auch für ausgewählte Ketten (teilt sich mit
        Einzeltreffern denselben `curatedRoute`-Zustand, da sich beide Modi gegenseitig
        ausschließen). Live auf dem iPhone bestätigt (Bremen → Achim, "StadtLandFluss →
        Geestweg").
      - **Regionsübergreifende Einzeltreffer nachgezogen** (2026-08-09, Nutzer-Beobachtung): Ein
        Einzeltreffer, dessen Geometrie selbst eine Bundesland-/Länder-Grenze überquert (z. B.
        "Weser Radweg Alternative Route" zwischen Bremen und Niedersachsen), fiel bisher komplett
        auf den generischen Hinweis "Route folgen" zurück, weil `matchCuratedRouteSteps` nur
        prüfte, ob **ein einzelner** heruntergeladener Wege-Graph ≥50 % der Strecke abdeckt
        (`CuratedRouteStepMatcher.minMatchedFraction`) - bei einer Grenzüberquerung deckte aber
        keiner der beiden Graphen allein genug ab. Neue zweite Stufe
        `CuratedRouteStepMatcher.steps(along:candidateRepositories:)`, analog
        `CrossRegionRouteStitcher` für die direkte Fahrrad-Route, aber ohne
        Übergangspunkt-Suche entlang einer Luftlinie nötig (die kuratierte Route liefert die
        echten Zwischenpunkte bereits): ordnet jeden Punkt der Region mit dem nächstgelegenen
        Graph-Knoten zu, fasst aufeinanderfolgende Punkte derselben Region zu einem Abschnitt
        zusammen, matcht jeden Abschnitt einzeln und reiht die Ergebnisse mit einem "Weiter in
        <Region>"-Übergangsschritt aneinander. Live auf dem iPhone bestätigt (Bremen → Achim,
        Weser Radweg Alternative Route).
      - **Graue "Anfahrt"-Linie zeigt jetzt ebenfalls Straßennamen** (2026-08-09, Nutzer-
        Beobachtung im Anschluss an den Grenzüberquerungs-Fix oben, live an derselben Stelle:
        Weser-Querung Bremen → Hemelingen): Direkt nach "Los" zeigte die Kopfzeile weiterhin
        "Route folgen", weil `activeStepRoute` nur `directRoutes`/`curatedRoute` kannte, nicht
        aber `connectorRouteToStart` - die graue Anfahrt-Linie vom Nutzer-Standort zum
        Einstiegspunkt der kuratierten Route. Dabei liegt dafür (via `loadConnectorRoute`/
        `loadCombinedConnectorRoute`/`checkCuratedConnectorDeviation`) längst eine echte
        `MKRoute` mit von Apple formulierten `instructions`-Texten inkl. Straßennamen vor -
        bisher nur fürs graue Kartenoverlay genutzt, nie für die Navigations-Anzeige. Neuer
        dritter Zweig in `activeStepRoute` (zwischen `directRoutes` und `curatedRoute`, mit
        eigenem `currentConnectorStepIndex`, analog zu den beiden bestehenden Indizes): Solange
        `connectorRouteToStart` gesetzt ist, wickelt er es in `DirectRoute(route:)` (bestehender
        MKRoute-Initializer, unverändert) und liefert dessen Schritte an Kopfzeile, Sprachausgabe
        und Watch-Haptik - alle drei nutzen bereits einheitlich `activeStepRoute`/`previewedStep`,
        keine Änderung an ihnen nötig. Sobald `checkCuratedConnectorDeviation` die Anfahrt-Linie
        nullt (Route erreicht), übernimmt automatisch `curatedRoute` wie zuvor.
      → [CuratedRouteStepMatcher.swift](FahrradApp/RadFaehrte/Services/CuratedRouteStepMatcher.swift),
      [BikeRoutingEngine.swift](FahrradApp/RadFaehrte/Services/BikeRoutingEngine.swift)
      (`buildSteps` nicht mehr `private`, von `CuratedRouteStepMatcher` mitgenutzt),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`activeStepRoute`,
      `curatedRoute`, `currentConnectorStepIndex`, `loadCuratedRouteForNavigation`,
      `curatedRouteStepsDetailSheet`, `loadCuratedRouteSteps`, `matchCuratedRouteSteps`,
      `loadConnectorRoute`, `loadCombinedConnectorRoute`, `checkCuratedConnectorDeviation`),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift) ("Route suchen",
      "Navigation")
- [x] **Abbiege-Hinweise oben im Bildschirm für kuratierte Radrouten** – s. o., als Teil desselben
      Map-Matching-Versuchs für Einzeltreffer mitumgesetzt. Ursprünglich bewusst ohne Sprachausgabe
      (siehe ursprüngliche Spezifikation, MVP-Ausschluss) - inzwischen nachgerüstet, s. u.
      "Sprachausgabe für Abbiegehinweise" unter "Aktueller Stand".
- [ ] **Wegearten-Aufschlüsselung anzeigen** (Nutzer-Idee 2026-08-15: "40 km Landstraße, 12 km
      Radweg" usw. pro Route) – umfasst auch den älteren Punkt "Oberflächentyp anzeigen"
      (asphaltiert/Schotter/etc., relevant für Rennrad- vs. Trekkingrad-Nutzer), da unbefestigte
      Wege eine der Kategorien sind.
      - **Schema-Änderung umgesetzt** (2026-08-15): Neues `UInt8 wayCategory`-Feld pro Kante im
        Format-v2-Wege-Graphen (`WAY_CATEGORY_*`/`way_category()` in `build_way_graph.py`, von
        `build_way_graph_v2.py` mitgeschrieben) - 5 grobe, laientaugliche Kategorien statt der
        vollen OSM-`highway`-Palette: Radweg, Ruhige Straße, Landstraße, Unbefestigter Weg,
        Sonstiger Weg. `surface` schlägt `highway` (ein unbefestigter Radweg zählt als
        "Unbefestigter Weg", nicht "Radweg" - praktisch relevanter für die Rad-Wahl). Kanten-
        Record dadurch 17 → 18 Byte, Magic `"RFG2"` → `"RFG3"` (verhindert Fehlinterpretation
        alter Dateien mit dem neuen Parser), `wayGraphFormatVersion` 6 → 7 in
        `WayGraphStore.swift` (verwirft alte lokal heruntergeladene Graphen automatisch beim
        nächsten Start). Gegen echte Bremen-`.osm.pbf`-Daten verifiziert (Build-Script neu
        gelaufen, Byte-Layout per Python nachgelesen: 391.152 Kanten, Kategorie-Verteilung
        plausibel für eine Stadt - 53,5 % ruhige Straße, 17,8 % sonstige, je ~9-11 % Radweg/
        Landstraße/unbefestigt). Bestehende Unit-Tests (`RadFaehrteTests.swift`) nutzen weiter das
        alte, unveränderte SQLite-Format v1 (`bremen_ways.sqlite`) und sind daher nicht
        betroffen.
      - **Live-Fund + Fix: `cycleway:right/left`-Straßen fälschlich als "Landstraße" kategorisiert**
        (2026-08-15, Demo-Lauf gegen echte Bremen-Daten Hauptbahnhof -> Bürgerpark, außerhalb der
        App per eigenständig kompiliertem Kommandozeilen-Programm, das `WayGraphRepository`/
        `BikeRoutingEngine` direkt nutzt - kein Simulator/Gerät nötig für diese reine
        Daten-Verifikation): Straßen mit separat kartiertem, aber nur als `cycleway:right/left=
        track`-Attribut (nicht als eigener `highway=cycleway`-Way) getaggtem Radweg - z. B.
        Theodor-Heuss-Allee, Admiralstraße - landeten komplett in "Landstraße" statt "Radweg",
        obwohl der Nutzer dort tatsächlich auf dem separaten Radweg fährt (dieselben Tags, die
        `offset_side()`/`CYCLE_INFRA_BONUS` bereits für Linien-Versatz bzw. Routing-Gewichtung
        auswerten). `way_category()` prüft jetzt zusätzlich `CYCLE_INFRA_TAGS`/`CYCLE_INFRA_VALUES`
        (bereits vorhandene Konstanten). Auswirkung am Testfall: von 1,78 km fälschlich
        "Landstraße" zu korrekt "Radweg" (1,87 km Gesamtroute bestand danach zu 1,78 km aus
        "Radweg", 0,08 km "Ruhige Straße", 0,01 km "Sonstiger Weg" - kein einziger Meter
        "Landstraße" mehr, plausibel für eine "ruhigste Route"-Suche). Bremen lokal neu gebaut und
        Demo erneut verifiziert.
      - **Aggregation + UI umgesetzt** (2026-08-15): `BikeRoutingEngine.Result` hat jetzt
        `metersByCategory: [WayGraphRepository.WayCategory: Double]` - während der A*-Suche pro
        Knoten mitgeführt (analog `offsetSide`/`nameIndex`), aus den kumulierten Distanzen beim
        Pfad-Rekonstruieren aggregiert (kein nachträgliches Kanten-Raten nötig).
        `CrossRegionRouteStitcher` summiert die Kategorien seiner Teilstrecken (`combinedRoute`,
        `chainedRoute`); die beiden kuratierten-Routen-Stellen in `ContentView.swift` liefern
        bewusst ein leeres Dictionary (kein OSM-Tag-Zugriff dort, s. o.). UI: neuer Balken-Icon-
        Button neben "Ruhige Route (offline)" in der Ergebnisliste (nur sichtbar, wenn
        `metersByCategory` nicht leer ist), öffnet ein Sheet mit der nach Kilometern absteigend
        sortierten Liste - bewusst ein eigenes Sheet statt inline in der Zeile, analog
        `curatedRouteStepsDetailSheet`, aber ohne dessen Async-Lade-/Fehlerzustände (Daten liegen
        hier schon synchron vor). Live auf dem iPhone getestet (Bremen Hauptbahnhof -> Bürgerpark,
        manuell aufs Gerät kopierter Testgraph statt regulärem Download, s. u.) - Nutzer bestätigt
        "sieht sehr gut aus".
      - **Entscheidung: keine Kartenfärbung** (2026-08-15, Nutzer-Rückmeldung nach Live-Test):
        Routenlinie bleibt einheitlich blau, auch in der Vorschau vor "Los" - der eingangs als
        Option 3 durchdachte Ansatz (Linie nach Wegeart einfärben) wird nicht umgesetzt. Grund:
        zusätzliche visuelle Komplexität ausgerechnet im Moment des schnellen Routen-Vergleichs,
        ohne klaren Mehrwert gegenüber dem Sheet.
      - **Alle 16 Bundesländer neu gebaut + hochgeladen** (2026-08-17, Nutzer-Wunsch "alle 19
        Regionen neu bauen", dabei rauskam: es sind inzwischen tatsächlich 93 Regionen über alle
        Release-Tags hinweg - DE (16) + Europa (33 Länder inkl. NL/SE/PL) + Frankreich (21) +
        Italien (5) + Spanien (18), nicht mehr die "19" von der ursprünglichen v2-Migration. Nach
        Absprache bewusst auf die 16 Bundesländer für diese Sitzung begrenzt, Rest siehe unten).
        Neuer Release-Tag `way-graphs-v5` (16 `<bundesland>_ways.sqlite`-Assets, trotz Namen im
        neuen Flachdatei-Format v2+wayCategory, s. o.) - Bremen aus dem bereits lokal gebauten
        Testdatensatz übernommen, die übrigen 15 einzeln heruntergeladen (Geofabrik), mit
        `build_way_graph_v2.py` neu gebaut und hochgeladen (`gh release upload`), größere Downloads
        (Hessen, Niedersachsen, NRW, Baden-Württemberg, Bayern) liefen dafür im Hintergrund.
        Zwischen jedem Bundesland Rückfrage an den Nutzer, ob es weitergehen soll (spät abends,
        Nutzer wollte irgendwann schlafen gehen). `WayGraphDownloadManager.swift`s `downloadURL`
        für `Bundesland` zeigt jetzt auf `way-graphs-v5` statt `way-graphs-v4`,
        `approximateSizeMB` mit den echten neuen Asset-Größen aktualisiert (ca. 4-6 % größer als
        v4, 1 zusätzliches Byte pro Kante). Build erfolgreich verifiziert.
      - **Zurückgestellt** (2026-08-17, Nutzer-Entscheidung): die übrigen 77 Regionen (33 Länder
        `way-graphs-eu-v1`, 21 Frankreich `way-graphs-fr-v1`, 5 Italien `way-graphs-it-v1`, 18
        Spanien `way-graphs-es-v1`) werden **bewusst noch nicht** neu gebaut - `WayGraphDownloadManager.swift`
        zeigt dort weiterhin auf die alten Tags, ein regulärer Download liefert also weiterhin das
        alte, vom neuen Parser nicht mehr lesbare Format (s. `WayGraphRepository`s
        Format-v2-Dokumentation). Größerer Batch als die Bundesländer heute (teils mehrere GB
        Rohdaten pro Land, z. B. Polen/Schweden/Finnland/Griechenland >900 MB), eigene Sitzung(en)
        nötig, wenn es soweit ist.
      - **Auch für kuratierte Radrouten umgesetzt** (2026-08-17, Nutzer-Wunsch: "auch bei den
        kartierten Radwegen wie Weserradweg, Friedensradweg, Oder-Neiße-Radweg" die Wegearten
        sehen) - die obige Aussage "kuratierte Routen bleiben davon unberührt" gilt also nicht
        mehr. `CuratedRouteStepMatcher` matcht kuratierte Routen (`routes.sqlite`, keine eigenen
        OSM-Tags) ja bereits für Straßennamen/Abbiege-Hinweise gegen denselben Wege-Graphen -
        neue `MatchResult`-Struct (`steps` + `metersByCategory`) bündelt beides, da beides beim
        selben Kanten-Walk über den gematchten Knotenpfad anfällt (neue private Funktion
        `metersByCategory(alongNodePath:repository:)`). Gilt für Einzeltreffer
        (`steps(along:using:)`) **und** regionsübergreifende Einzeltreffer
        (`steps(along:candidateRepositories:)`, summiert über Abschnitte) **und** kombinierte
        Ketten (`ContentView.matchCuratedRouteSteps(forLegs:)`, summiert über Etappen) - dieselbe
        Grundvoraussetzung wie bei den Straßennamen: nur innerhalb heruntergeladener Regionen, nur
        so vollständig wie das Matching selbst gelingt (bei einer kombinierten Kette werden nicht
        abgedeckte Etappen einfach übersprungen, der Rest bleibt vollständig). UI: neue "Wegearten"-
        Sektion oberhalb der bestehenden "Straßennamen"-Sektion in `curatedRouteStepsDetailSheet`
        (Einzeltreffer) und `combinedRouteDetailSheet` (Ketten), nur wenn die Aufschlüsselung
        nicht leer ist. Bei `partialSteps` (Kartenlücke zwischen Start/Ziel) bewusst weggelassen,
        um den Fehlerfall nicht zusätzlich zu verzweigen. Live auf dem iPhone getestet (Weser-
        Radweg Bremen, Nutzer bestätigt "sieht gut aus"; Oder-Neiße-Radweg-Kette zeigte zunächst
        nichts an, weil Brandenburg nicht heruntergeladen war - kein Bug, dieselbe Voraussetzung
        wie bei Straßennamen, nach Brandenburg-Download erwartungsgemäß funktionsfähig).
      - **Farbpunkte in allen drei Wegearten-Listen** (2026-08-17, Nutzer-Wunsch nach Live-Test:
        "ein wenig farblich unterscheiden") - zentrale Farbzuordnung in `ContentView.
        wayCategoryColor(_:)` (Grün Radweg, Blau Ruhige Straße, Orange Landstraße, Braun
        Unbefestigter Weg, Grau Sonstiger Weg), gemeinsamer Zeilen-Helper `wayCategoryRow(_:
        meters:)` in allen drei Sheets (Offline-Route, kuratierter Einzeltreffer, kombinierte
        Kette) statt dreifach dupliziertem `HStack` - verhindert, dass die Zuordnung bei
        künftigen Änderungen auseinanderdriftet. Bewusst als reine `Color`-Extension in
        `ContentView.swift`, nicht in `WayGraphRepository.swift` (Services-Layer bleibt
        SwiftUI-frei, kein anderes Service-File importiert dort `SwiftUI`). Ausdrücklich **kein**
        Widerspruch zur "keine Kartenfärbung"-Entscheidung oben - die galt nur für die
        Routenlinie auf der Karte, nicht für diese Listen-Sheets.
      - **Konsistenz-Fixes nach Live-Test** (2026-08-17, Nutzer-Beobachtung): Das "Ruhige Route
        (offline)"-Sheet zeigte bisher nur Wegearten, keine Straßennamen - dabei liegen die längst
        in `DirectRoute.steps` vor, nur nie angezeigt. `wayCategoryDetailSheet` zeigt jetzt wie die
        beiden kuratierten Sheets zuerst "Wegearten", dann "Straßennamen" darunter (Titel "Ruhige
        Route" statt nur "Wegearten"). Zusätzlich das Listen-Symbol (`list.bullet`) an allen drei
        Stellen (Offline-Route, kuratierter Einzeltreffer, kombinierte Kette) von `.secondary` auf
        `.blue` vereinheitlicht - Nutzer-Wunsch, nachdem die Offline-Route zunächst noch das
        andere Symbol (`chart.bar.doc.horizontal`) hatte.
      - **Neue Kategorie "Radweg an Landstraße"** (2026-08-17, Nutzer-Wunsch nach Live-Test: einen
        Radweg direkt neben einer Landstraße vom freistehenden Radweg unterscheiden - Nebenstraße,
        freies Feld, Wald usw.) - `WayCategory.cyclewayNearMainRoad` (Rohwert 5), mint statt grün
        in der Liste. Neuer räumlicher Index `MainRoadIndex` in `build_way_graph.py`: ein
        vorgezogener, zusätzlicher Osmium-Durchlauf ("Pass 0") sammelt alle Landstraßen-
        Kantensegmente in einem Gitter-Index (Zellgröße ~150 m, grobe Vorauswahl vor exakter
        Punkt-zu-Strecke-Distanzberechnung), danach prüft `way_category()` für jede Radweg-Kante
        (Mittelpunkt, nicht Endpunkt - robuster gegen Kreuzungen), ob sie innerhalb von
        `NEARBY_MAIN_ROAD_METERS` (15 m, bewusst enger als die anfangs erwogenen 25-30 m, um keine
        unbeteiligten parallelen Straßen zu erwischen) einer Landstraßen-Kante liegt. Ein
        `cycleway:right/left`-Tag an der Straße selbst matcht dabei praktisch automatisch (die
        Straße liegt ja bereits im Index, falls sie selbst ein `MAIN_ROAD_HIGHWAYS`-Typ ist) -
        die räumliche Prüfung entscheidet nur bei echten, separat kartierten Radweg-Ways (der
        Uphuser-Heerstraße-Fall). Reine Content-Änderung, kein Format-Bruch (weiterhin `UInt8`) -
        kein `wayGraphFormatVersion`-Bump nötig, nur ein Neu-Bau der Regionsdateien (`gh release
        upload --clobber` auf denselben `way-graphs-v5`-Tag). Gegen echte Bremen-Daten verifiziert
        (7,8 % "Radweg an Landstraße" neben 7,0 % freistehendem "Radweg", plausible Verteilung,
        keine Ausreißer). **Alle 16 Bundesländer neu gebaut und hochgeladen** (2026-08-17,
        zweistufig: erst Bremen + Niedersachsen zur Kontrolle, nach Nutzer-Bestätigung "sieht gut
        aus" der Rest in einem Rutsch ohne Rückfrage nach jedem einzelnen - anders als beim ersten
        Bundesländer-Rollout, da das Verfahren inzwischen zweimal sauber lief). Da eine inhaltliche
        Content-Änderung ohne Versionsbump vom lokalen Download-Cache der App nicht automatisch
        erkannt wird, Bremen + Niedersachsen zusätzlich manuell aufs Test-iPhone kopiert (`xcrun
        devicectl device copy to`), App neu installiert, App-Ordner blieb dabei erhalten. Zwei
        Uploads (Hessen, Baden-Württemberg) scheiterten unterwegs an einem kurzzeitigen
        GitHub-Server-Fehler (HTTP 503) - der jeweilige Bau selbst war erfolgreich, nur der Upload
        schlug fehl; erneuter Upload-Versuch (ohne Neu-Bau, da die fertige Datei noch lokal lag)
        lief beide Male sauber durch. Per Asset-Zeitstempel im Release verifiziert, dass alle 16
        tatsächlich neu hochgeladen wurden (nicht nur der lokale Build-Log). **Noch offen**: die
        bereits zurückgestellten 77 EU/FR/IT/ES-Regionen haben die neue Kategorie weiterhin nicht -
        dort bleibt es vorerst bei nur "Radweg" ohne die Unterscheidung.
      → [build_way_graph.py](FahrradApp/Scripts/build_way_graph.py) (`way_category`,
      `WAY_CATEGORY_*`, `UNPAVED_SURFACES`, `MAIN_ROAD_HIGHWAYS`, `QUIET_ROAD_HIGHWAYS`,
      `MainRoadIndex`, `NEARBY_MAIN_ROAD_METERS`, `point_to_segment_distance_meters`),
      [build_way_graph_v2.py](FahrradApp/Scripts/build_way_graph_v2.py),
      [WayGraphRepository.swift](FahrradApp/RadFaehrte/Services/WayGraphRepository.swift)
      (`Edge.wayCategoryRaw`/`.wayCategory`, `WayCategory`),
      [WayGraphStore.swift](FahrradApp/RadFaehrte/Services/WayGraphStore.swift)
      (`wayGraphFormatVersion`),
      [BikeRoutingEngine.swift](FahrradApp/RadFaehrte/Services/BikeRoutingEngine.swift)
      (`Result.metersByCategory`, `cameFromCategory`),
      [CrossRegionRouteStitcher.swift](FahrradApp/RadFaehrte/Services/CrossRegionRouteStitcher.swift),
      [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`DirectRoute.metersByCategory`,
      `wayCategoryDetailRoute`, `wayCategoryDetailSheet`, `directRouteRow`, `wayCategoryColor`,
      `wayCategoryRow`, `curatedRouteStepsDetailSheet`, `combinedRouteDetailSheet`,
      `matchCuratedRouteSteps`, `curatedRouteResult`, `CuratedRouteStepsAvailability`),
      [WayGraphDownloadManager.swift](FahrradApp/RadFaehrte/Services/WayGraphDownloadManager.swift)
      (`Bundesland.downloadURL`/`.approximateSizeMB`),
      [CuratedRouteStepMatcher.swift](FahrradApp/RadFaehrte/Services/CuratedRouteStepMatcher.swift)
      (`MatchResult`, `metersByCategory(alongNodePath:repository:)`)

### Phase 4 – größere Architektur-Entscheidungen

Diese Punkte brauchen vor der Umsetzung eine bewusste Grundsatzentscheidung.

- [x] **Schnellste Route als Alternative** – Entscheidung gefallen (nach einem Zwischenexperiment,
      s. u.): Apple `MKDirections` (Fahrrad-Profil, Fallback Fußweg). Als "Direkte Fahrrad-Route"
      immer verfügbare Option ganz oben in der Ergebnisliste, unabhängig von gefundenen
      Radrouten-Matches – für Ziele außerhalb des importierten Radroutennetzes.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`selectDirectRoute`)

      **Zwischenexperiment (zunächst verworfen, dann wiederaufgegriffen und umgesetzt - s. o. unter
      "Ruhige-Wege-Offline-Routing pro Bundesland"):** Eine eigene, offline arbeitende
      A*-Routing-Engine über einen aus OSM extrahierten Wege-/Kreuzungsgraphen wurde gebaut und
      funktionierte technisch gut (bevorzugte gezielt Radwege/ruhige Straßen, meidet
      Hauptstraßen; erst Testregion Bremen, dann live erfolgreich auf ganz Deutschland skaliert,
      13,2 Mio. Ways). Ursprünglicher Grund für die Rücknahme: der deutschlandweite Wegegraph
      (`ways_germany.sqlite`) war mit ~3,7 GB viel zu groß fürs App-Bundle – eine Lösung dafür
      (Download pro Bundesland) hätte einen Datei-Host gebraucht, den es damals nicht gab. Das ist
      inzwischen gelöst (GitHub-Repo + Releases, s. o.).
- [ ] **Höhenprofil / Steigungen** – benötigt zusätzliche Höhendaten (z. B. SRTM), die
      aktuell nicht vorliegen; relevant für "schöne vs. schnelle Route"-Abwägung
- [ ] **Offline-Kartenkacheln** – ⚠️ **Grundsätzliche Einschränkung:** MapKit erlaubt keinen
      Offline-Download von Kartenkacheln für Drittanbieter-Apps (anders als z. B. Komoot/
      Outdooractive mit eigenen Tile-Servern). Unsere Routendaten sind offlinefähig, die
      Kartenanzeige selbst nicht. Falls das ein Muss wird, wäre ein Wechsel des Karten-
      Frameworks nötig – bewusste Entscheidung, keine Kleinigkeit.
- [x] **Wege-Graph per `mmap` statt über SQLite lesen** (Nutzerwunsch 2026-07-27, explizit als
      wichtig markiert) - **Format v2 + `WayGraphRepository`-Umbau umgesetzt, als Pilotversuch für
      Niederlande + Bremen + Bayern** (s. o. "Wege-Graph-Format v2 (mmap, kein SQLite mehr) -
      Pilotversuch Niederlande" für die vollen Details). Punkt 1 (Kanten schon beim Bauen sortiert
      wegschreiben) und Punkt 2 (`mmap` + on-demand-Dekodierung statt eigene Arrays) sind fertig,
      `Scripts/build_way_graph_v2.py` bewusst als **neues, separates** Skript statt
      `build_way_graph.py` zu ändern (importiert dessen Gewichtungslogik, dupliziert sie nicht) -
      so bleibt das alte Skript für die noch nicht umgestellten Regionen unverändert nutzbar.
      - [x] **Punkt 3 erledigt**: Polen als letzte verbleibende Region auf Format v2 umgestellt
        (s. u. "🎉 Polen auf Format v2 umgestellt - Rollout aller 19 Regionen abgeschlossen") -
        damit sind alle 19 Regionen (16 Bundesländer + Niederlande, Schweden, Polen) auf Format v2
        (mmap statt SQLite), der Rollout ist vollständig abgeschlossen.
      - **Anders als ursprünglich hier notiert gelöst**: Kein Format-Versions-Bump nötig und kein
        Kompatibilitäts-Übergangszeit-Problem, da `WayGraphRepository` beide Formate gleichzeitig
        per Magic-Bytes-Erkennung unterstützt (v1 SQLite und v2 Flachdatei koexistieren dauerhaft
        in derselben Repository-Klasse, nicht nur übergangsweise) - ein harter Cutover war dadurch
        gar nicht nötig, jede Region kann unabhängig und zu einem beliebigen Zeitpunkt umgestellt
        werden, ohne die anderen zu berühren.

## Ideen (unsortiert, noch nicht priorisiert)

Lose Sammlung für Einfälle, die noch nicht in eine der Phasen oben eingeordnet sind.

- [x] **Ziel per Fingertipp auf der Karte setzen** (Nutzer-Idee 2026-08-01, umgesetzt): Alternative
      zur Adresssuche fürs Ziel-Feld - z. B. wenn die genaue Adresse nicht bekannt ist, die Stelle
      auf der Karte aber sichtbar. Bewusst als **expliziter Modus** statt automatischem Tap
      (Nutzerentscheidung im Gespräch): normales Verschieben/Zoomen der Karte soll nicht
      versehentlich das Ziel ändern.
      - **Aktivierung**: Neue Zeile "Auf Karte wählen" in der Vorschlagsliste des Ziel-Feldes
        (analog zur bestehenden "Aktuelle Position"-Zeile beim Start-Feld) setzt
        `isPickingZielOnMap = true`. Während aktiv zeigt ein Banner oben auf der Karte einen
        Hinweistext + "Abbrechen"-Button.
      - **Tap-Verarbeitung**: `handleMapTap` prüft `isPickingZielOnMap` **vor** der bestehenden
        Logik zur Alternativrouten-Auswahl (`isDirectRouteMode`) und gibt danach früh zurück - kein
        Konflikt mit dem bestehenden Tap-Handling für die "Direkte Fahrrad-Route".
      - **Reverse Geocoding**: `pickZielOnMap` setzt `zielPlace` zunächst mit Platzhaltertitel
        "Ziel auf der Karte" (sofortige Marker-/Listenreaktion), `reverseGeocodeZielPlace` löst die
        Koordinate anschließend asynchron per `CLGeocoder` in Straße + PLZ/Ort auf und ersetzt den
        Titel - über einen Vergleich der `SelectedPlace.id` verworfen, falls der Nutzer
        zwischenzeitlich schon ein anderes Ziel gewählt hat.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`isPickingZielOnMap`,
      `pickZielOnMap`, `reverseGeocodeZielPlace`, `handleMapTap`, `pickZielOnMapBanner`),
      [LocationSearchField.swift](FahrradApp/RadFaehrte/Views/LocationSearchField.swift)
      (`onPickOnMap`), [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift)
      ("Route suchen")
      - Live auf dem iPhone getestet (Nutzer, 2026-08-01): Banner, Kartentipp und Reverse-Geocoding
        funktionieren wie erwartet.
      - ⚠️ **Zwei Folgefehler per Live-Test gefunden und behoben (2026-08-01)**:
        1. **Absturz, wenn zuerst Start (z. B. "Aktuelle Position") und danach erst per
           "Auf Karte wählen" das Ziel gesetzt wurde** - trat zuverlässig nur in dieser
           Reihenfolge auf, nie umgekehrt (erst Ziel per Kartentipp, dann Start). Ursache: Ist
           beim Kartentipp bereits ein Start gesetzt, läuft über `onChange(of: zielPlace))` die
           volle `runMatching()`-Suche inkl. neuer Karten-Overlays (`selectedRouteLines`/
           `routeSelectionToken`) **synchron mit**, während MapKit noch mitten in der
           Verarbeitung genau dieser `SpatialTapGesture` steckt (bei umgekehrter Reihenfolge
           bricht `runMatching()` mangels Start früh ab, viel weniger Arbeit synchron im
           Gesten-Callback). Behoben, indem `pickZielOnMap` aus `handleMapTap` heraus jetzt über
           `DispatchQueue.main.async` auf den nächsten Runloop-Durchlauf verschoben wird, statt
           direkt im Gesten-Callback zu laufen.
        2. **Nach Ziel-per-Kartentipp + Start "Aktuelle Position" waren zwei Treffer gleichzeitig
           mit Haken markiert** ("Ruhige Route (offline)" und eine kombinierte Fernweg-Kette) -
           sollte sich gegenseitig ausschließen. Ursache: `reverseGeocodeZielPlace` ersetzt
           `zielPlace` nachträglich durch eine neue Instanz mit aufgelöster Adresse (gleiche
           Koordinate, neue `SelectedPlace.id`) - das löst über `onChange(of: zielPlace)` eine
           **zweite**, redundante `runMatching()`-Suche für dieselben Koordinaten aus. Traf diese
           zweite Suche zeitlich ungünstig auf eine noch laufende asynchrone Kombinationssuche der
           ersten Suche, konnten am Ende `isDirectRouteMode` (von der zweiten Suche gesetzt) und
           `combinedMatch` (von der ersten, verspätet eintreffenden Suche gesetzt) gleichzeitig
           aktiv bleiben, statt dass sich `combinedMatch`s `onChange`-Handler wie vorgesehen
           gegenseitig ausschließend verhält. Behoben durch `lastMatchingCoordinates` in
           `runMatching()`: Sind Start- und Zielkoordinate identisch zur zuletzt tatsächlich
           gesuchten Kombination, bricht die Funktion sofort ab, ohne die aktuelle Auswahl
           anzurühren - nur ein Adress-Update ohne Koordinatenänderung soll keine neue Suche
           auslösen.
        Beide Fixes live auf dem iPhone nachgetestet (Nutzer, 2026-08-01): kein Absturz mehr in
        Reihenfolge 1, nur noch ein Treffer markiert in Reihenfolge 2.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`handleMapTap`,
      `runMatching`, `lastMatchingCoordinates`)
      - ⚠️ **Derselbe "zwei Treffer gleichzeitig markiert"-Fehler auch über einen ganz anderen Weg
        reproduziert (Nutzer-Screenshot 2026-08-01, reine Textsuche Hannover → Braunschweig, kein
        Kartentipp beteiligt)**: Der `lastMatchingCoordinates`-Fix oben deckte nur den einen
        Auslöser (redundante zweite `runMatching()`-Suche durchs Reverse-Geocoding) ab, nicht das
        eigentliche strukturelle Problem - `isDirectRouteMode`, `selectedMatch` und `combinedMatch`
        wurden an mehreren Stellen unabhängig voneinander gesetzt, ohne dass jede Stelle die jeweils
        anderen beiden zurücksetzt. Konkret setzten `selectDirectRoute()` (u. a. automatisch am Ende
        jeder `runMatching()`) und `filterAndReorderMatchesByPracticalDistance()` `isDirectRouteMode
        = true`, ohne ein zwischenzeitlich (asynchron durch die Kombinationssuche) gesetztes
        `combinedMatch` zu löschen. Behoben durch einen neuen zentralen
        `onChange(of: isDirectRouteMode)`-Handler (analog zu den bereits bestehenden für
        `selectedMatch`/`combinedMatch`), der bei `isDirectRouteMode = true` immer `selectedMatch`
        und `combinedMatch` auf `nil` setzt - damit ist die gegenseitige Ausschließlichkeit der drei
        Auswahl-Zustände unabhängig vom jeweiligen Auslöser an einer Stelle garantiert.
        Live auf dem iPhone nachgetestet (Nutzer, 2026-08-01, Route Hannover → Braunschweig): nur
        noch ein Treffer markiert.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`onChange(of:
      isDirectRouteMode)`, `selectDirectRoute`, `filterAndReorderMatchesByPracticalDistance`)

- **Radwege in der Nähe anzeigen** – ~~alle in `routes.sqlite` vorhandenen Radrouten rund um den
  aktuellen Standort (oder einen gewählten Kartenausschnitt) direkt auf der Karte darstellen~~ –
  **teilweise umgesetzt** als Vorschau-Zeile mit den 10 nächstgelegenen Treffern, sobald nur ein
  Start (kein Ziel) gesetzt ist (s. o. unter "Ergebnisliste: Zwei kompakte Zeilen..."). Weiterhin
  offen: eine echte Kartendarstellung (z. B. alle nahen Routen gleichzeitig als Linien auf der
  Karte, unabhängig von einer Start-Auswahl), falls das noch gewünscht ist.

- **POIs entlang der Route** (Trinkwasser, Radläden/Werkstätten, Rastplätze, Sehenswürdigkeiten) –
  Marktvergleich (2026-08-01: Komoot "Highlights", Bikemap POI-Layer) zeigt das als häufig genutztes
  Feature. Für RadFährte am ehesten über Overpass-API-Abfrage (POI-Tags wie `amenity=drinking_water`,
  `shop=bicycle`, `tourism=*`) für den sichtbaren Kartenausschnitt oder entlang der gewählten Route,
  keine eigene Datenpipeline nötig (anders als `routes.sqlite`). Noch nicht priorisiert.

- **Heatmap beliebter Strecken** – Marktvergleich (2026-08-01: Strava-, RideWithGPS- und
  Komoot-Kernfeature) zur Orientierung, welche Wege andere Radfahrer häufig nutzen. Für RadFährte
  ohne eigene Nutzerbasis nicht direkt umsetzbar (keine aggregierten Fahrtdaten vorhanden) – am
  ehesten als Kartenlayer über die vorhandene `routes.sqlite` (Häufigkeit/Netzwerk-Typ als Proxy)
  oder durch Einbindung einer externen Heatmap-Kachel-Quelle. Noch nicht priorisiert, unklar ob
  ohne echte Nutzerdaten sinnvoll.

- **Live-Standort teilen / Live-Tracking** – Marktvergleich (2026-08-01: Komoot-Premium-Feature)
  für Fälle, in denen jemand während der Fahrt erreichbar/verfolgbar sein möchte. Technisch am
  ehesten über einen einfachen Cloud-Endpunkt (Standort-Updates während `navigationMode` senden)
  + Teilen-Link, keine bestehende Infrastruktur dafür vorhanden. Datenschutz-Aspekt beachten
  (kein automatisches Teilen, explizites Aktivieren pro Fahrt). Noch nicht priorisiert.

- **Wetterwarnungen entlang der Route** – Marktvergleich (2026-08-01: z. B. linexo). Apple
  `WeatherKit` ist first-party und würde sich ohne zusätzlichen Account/API-Key einfügen lassen
  (Abfrage für Start/Ziel bzw. Streckenpunkte, Warnung bei Regen/Sturm während der geplanten
  Fahrzeit). Noch nicht priorisiert.

- [x] **Gefahrene Touren nach Apple Health übertragen** (umgesetzt 2026-08-02, im Zuge der
      Apple-Watch-Integration statt als eigener Anlauf): Jede zu Ende gefahrene Navigation wird
      automatisch (kein manueller Button, keine Verlauf-Entscheidung nötig) über
      [WorkoutRecorder.swift](FahrradApp/RadFaehrte/Services/WorkoutRecorder.swift) als
      Radfahr-Training in Health gespeichert - inzwischen inklusive vollständiger GPS-Route als
      `HKWorkoutRoute` (nicht nur Distanz/Dauer-Zusammenfassung wie ursprünglich hier skizziert).
      Details, offene Punkte und Live-Test-Stand siehe oben unter "Aktueller Stand" →
      "Apple Watch"/"Hintergrund-Pausieren behoben durch `HKWorkoutSession`"
      (ab [ROADMAP.md:1857](ROADMAP.md) "Ergänzend: Fahrten landen jetzt auch ganz ohne Apple
      Watch in Health").

- [x] **GPX-Export für Fahrradcomputer/zum Teilen** (Nutzer-Idee 2026-07-30, umgesetzt 2026-08-01):
      Die aktuell gewählte Route (Einzeltreffer, kombinierte Kette oder "Direkte Fahrrad-Route")
      lässt sich über ein Teilen-Symbol neben dem "Los"-Button als `.gpx`-Datei exportieren - über
      das native iOS-Teilen-Sheet z. B. per AirDrop an einen Freund, "In Dateien sichern" (für
      Radcomputer-Sync) oder Mail. Ebenso im Verlauf-Tab: in der Detailansicht einer aufgezeichneten
      Fahrt exportiert ein Teilen-Symbol im Toolbar die Strecke.
      - **GPXWriter**: Neues [GPXWriter.swift](FahrradApp/RadFaehrte/Services/GPXWriter.swift),
        Gegenstück zu [GPXParser.swift](FahrradApp/RadFaehrte/Services/GPXParser.swift) - schreibt
        `[[CLLocationCoordinate2D]]` als `<trk>` mit einem `<trkseg>` pro Liniensegment, bewusst
        ohne Höhe/Zeitstempel (hat die App für keine dieser Routen-Arten). Zahlen per reiner
        `Double`-String-Interpolation statt `String(format: "%.6f", …)` - Letzteres würde auf einem
        deutsch eingestellten Gerät ein Komma statt Punkt liefern und ungültiges GPX erzeugen.
        `writeTemporaryFile` schreibt ins `FileManager.temporaryDirectory`, `GPXExportFile` kapselt
        die URL `Identifiable` fürs `.sheet(item:)`.
      - **Teilen-Sheet**: [ActivityView.swift](FahrradApp/RadFaehrte/Views/ActivityView.swift), ein
        dünner `UIActivityViewController`-Wrapper - bewusst kein `ShareLink`/`Transferable`, da die
        Datei ohnehin synchron vor dem Öffnen des Sheets erzeugt wird und der direkte Wrapper dafür
        einfacher ist.
      - **Einzeltreffer nur als gesuchtes Segment**: Anders als `selectedRouteLines` (komplette
        Geometrie der ganzen Fernroute) exportiert `ContentView.exportableRoute` bei einem
        Einzeltreffer nur das Stück zwischen Start und Ziel, per `RouteMatcher.routeSegmentPath`
        (derselbe Baustein, den auch die Kombinationssuche pro Etappe nutzt) - sonst enthielte die
        Datei z. B. den kompletten "Brückenradweg" statt nur der gesuchten Strecke Bremen ->
        Osnabrück.
      - **Live auf dem iPhone getestet** (Nutzer, 2026-08-01): Export/Teilen-Sheet funktioniert.
        Dass RadFährte selbst nicht als Teilen-Ziel im eigenen Sheet auftaucht, ist erwartetes
        iOS-Verhalten (die präsentierende App listet sich nie selbst als Ziel) - kein Bug, für den
        Rundlauf-Test stattdessen "In Dateien sichern" + manueller Import über "Eigene Routen" oder
        Files-App-"Öffnen mit".
      - Noch nicht umgesetzt: Export auch für kuratierte Routen direkt aus
        [AllRoutesView.swift](FahrradApp/RadFaehrte/Views/AllRoutesView.swift) (unabhängig von einer
        Start/Ziel-Suche) - bisher nicht gebraucht, da der Button in `ContentView` alle drei
        Such-Ergebnis-Arten abdeckt.
      → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`exportableRoute`,
      `exportRoute`, `exportFile`), [GPXWriter.swift](FahrradApp/RadFaehrte/Services/GPXWriter.swift),
      [ActivityView.swift](FahrradApp/RadFaehrte/Views/ActivityView.swift),
      [HistoryView.swift](FahrradApp/RadFaehrte/Views/HistoryView.swift) (`exportTour`, `exportFile`),
      [HowItWorksView.swift](FahrradApp/RadFaehrte/Views/HowItWorksView.swift) ("Route exportieren",
      "Verlauf")

- **Kontaktzugriff zum Teilen von Routen/Touren** – Marktvergleich (2026-08-02: Naviki bietet
  Kontaktzugriff, vermutlich um Routen/Ziele direkt an Kontakte zu senden statt nur per
  allgemeinem Teilen-Sheet wie beim GPX-Export oben). Technisch über `ContactsUI`
  (`CNContactPickerViewController`) statt vollem `Contacts`-Framework-Zugriff, damit kein
  `NSContactsUsageDescription` samt vollem Adressbuch-Zugriff nötig ist - der Picker liefert nur
  den vom Nutzer explizit gewählten Kontakt. Naheliegendste Anwendung: gewählten Kontakt als
  Empfänger für den bestehenden GPX-Export/Teilen-Flow vorschlagen (z. B. direkt per Mail/iMessage
  an die hinterlegte Adresse, falls vorhanden), nicht als eigenständige Kontaktverwaltung. Noch
  nicht priorisiert, unklar ob Mehrwert gegenüber dem bereits vorhandenen nativen Teilen-Sheet groß
  genug ist.

- **Kartenstil mit hervorgehobenen Radrouten (à la Bikemap/OpenCycleMap)** – Nutzer-Beobachtung
  2026-08-02 anhand eines Bikemap-Screenshots: cremefarbene Karte mit hervorgehobenen,
  ausgeschilderten Radrouten (gelb/grün gestrichelte Linie). Bikemap/OpenCycleMap basieren dafür
  auf OpenStreetMap. Kein simpler vierter `case` neben `standard`/`satellite`/`hybrid` in
  [MapStyleOption.swift](FahrradApp/RadFaehrte/Models/MapStyleOption.swift) - diese drei sind
  native MapKit-Stile ohne fremde Kachel-Quelle. Zwei Umsetzungs-Optionen:
  1. Externe Kachel-Quelle (z. B. OpenCycleMap/Thunderforest) per `MKTileOverlay` einbinden -
     bedeutet externen Anbieter/API-Key, Attribution-Pflicht, Netzwerkabhängigkeit; passt nicht so
     recht zum bisherigen Offline-Ansatz mit `routes.sqlite`.
  2. Eigene Hervorhebung auf der bestehenden Standardkarte: die aus `routes.sqlite` bereits
     bekannten Radrouten unabhängig von einer Start/Ziel-Suche als farbige Overlay-Linien
     einblenden (Berührungspunkt mit der Idee "Radwege in der Nähe anzeigen" oben) - eher ein
     Layer/Toggle als ein neuer Kartenstil, passt aber besser zur vorhandenen Architektur und
     bräuchte keinen externen Anbieter.

  **Nachteile geprüft (2026-08-02):**
  - Option 2: `routes.sqlite` enthält aktuell **50.364 Routen** (64 MB) - alle davon beim
    Herauszoomen (z. B. ganz Deutschland) zu rendern wäre visuell überladen und eine potenzielle
    MapKit-Performance-Bremse, bräuchte zwingend Filterung nach sichtbarem Kartenausschnitt +
    zoomstufenabhängiges Ausdünnen (gleiche noch offene Herausforderung wie bei "echte
    Kartendarstellung" unter "Radwege in der Nähe anzeigen"). Zusätzlich Redundanz, da Apples
    Standardkarte in vielen Regionen ohnehin schon eigene Radweg-Symbolik zeigt - Mehrwert kleiner
    als bei Bikemap, dessen OSM-Basiskarte das nicht tut. Ohne Auswertung des Routentyps auch keine
    Unterscheidung Fernroute vs. lokaler Weg, würde eher wie undifferenziertes Linienwirrwarr wirken
    statt gezielt hervorgehobener Fernrouten. Dauerhafte Rendering-/Akkulast, falls der Layer
    während der Navigation aktiv bliebe.
  - Option 1 (zusätzlich zu den o. g. Punkten): Internetabhängigkeit widerspricht dem bisher eher
    offline-orientierten Ansatz, plus Kosten/Rate-Limits je nach Anbieter.
  Noch nicht priorisiert, Option 2 naheliegender, aber Performance-/Filter-Aufwand nicht zu
  unterschätzen.

- **Höhenmeter einer Route schon vor Fahrtbeginn anzeigen** – Nutzer-Frage 2026-08-02: In der
  Statistik-Leiste gibt es "Höhenmeter" (`elevationGain`/`elevationLoss` in
  [NavigationStat.swift](FahrradApp/RadFaehrte/Models/NavigationStat.swift)) bereits, aber nur als
  Live-Aufsummierung aus GPS-/Höhenmesserdaten "seit Start" während der Fahrt - kein
  vorab berechnetes Höhenprofil der Route selbst. Grund: [BikeRoute.swift](FahrradApp/RadFaehrte/Models/BikeRoute.swift)
  (`lines: [[CLLocationCoordinate2D]]`) enthält nur 2D-Koordinaten ohne Höhe, und
  [GPXParser.swift](FahrradApp/RadFaehrte/Services/GPXParser.swift) liest das `<ele>`-Tag beim
  Import eigener Routen aktuell gar nicht aus. Zwei denkbare Umsetzungswege:
  1. Höhenmodell/DEM für die OSM-Katalogrouten anbinden (aufwändig, zusätzliche Datenquelle,
     würde auch die Offline-Datenbank vergrößern).
  2. `<ele>`-Werte beim GPX-Import auslesen und daraus Höhenmeter bergauf/bergab berechnen -
     funktioniert nur für eigene GPX-Importe (`OwnRoutesView`), nicht für die OSM-Katalogrouten
     aus `routes.sqlite`, da deren Rohdaten keine Höheninformation enthalten.
  Noch nicht priorisiert, keine Umsetzung begonnen. (Die geschätzte Fahrzeit aus derselben
  Diskussion wurde bereits umgesetzt, s. "Aktueller Stand" oben.)

- **Live Activity / Dynamic Island während der Navigation** (Idee 2026-08-02, Aufwand/Nachteile
  überschlagen, **nicht umgesetzt**): Distanz, ETA und nächste Abbiegung auch auf dem
  Sperrbildschirm bzw. in der Dynamic Island anzeigen, während man in einer anderen App ist oder
  das Display gesperrt hat – analog Uber/Essenslieferungen. Technisch rein additiv über
  `ActivityKit`, keine neue Datenquelle nötig (dieselben Werte wie in der bestehenden
  Navigations-Kopfzeile, `previewedStep`/`navigationInstructionText` in
  [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift)), müsste die Kernnavigation selbst
  nicht anfassen (ähnlich isoliert wie die bestehende Watch-Anbindung über `checkWatchHapticTrigger`).
  **Abgewogene Nachteile, bevor entschieden wird:**
  1. Live Activities laufen (soweit bekannt) nur einige Stunden (grob 8 h), dann beendet iOS sie
     automatisch – bei den hier relevanten mehrstündigen Fernradweg-Touren würde die Anzeige
     mitten in der Fahrt verschwinden, während die Navigation in der App selbst normal
     weiterläuft. Könnte wie ein Bug wirken statt wie eine System-Grenze.
  2. Die Dynamic-Island-Pille selbst gibt es nur ab iPhone 14 Pro; auf älteren Geräten nur der
     Sperrbildschirm-Teil – relevant, falls das eigene Test-iPhone kein Pro-Modell ist (Vorgabe:
     immer auf dem echten Gerät verifizieren, nicht im Simulator).
  3. Update-Frequenz ist vom System gedrosselt, keine echte Sekunde-für-Sekunde-Live-Anzeige –
     bei einem Navigations-Feature könnte ein spürbar hinterherhinkender Wert auffallen.
  4. Zweiter, unabhängiger Außenanzeige-Kanal neben der bestehenden Watch-Integration (eigene
     Extension, eigene API, eigener Lebenszyklus) – zusätzliche Wartungsfläche.
  Vor einer Umsetzung wäre insbesondere Punkt 1 (aktuelles Zeitlimit) gegen die aktuelle
  Apple-Doku zu prüfen. Noch nicht priorisiert, keine Umsetzung begonnen.

- **Refactoring: Auswahl-Zustand (`selectedMatch`/`combinedMatch`/`isDirectRouteMode`) als ein
  Enum statt vier separater States** (Claude-Analyse 2026-08-14, unabhängig von einer konkreten
  Nutzer-Meldung, **bewusst zurückgestellt**): [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift)
  ist mit 4148 Zeilen, 92 `@State`-Variablen und 79 Methoden ein einzelnes großes View-Struct ohne
  separates ViewModel. Auffällig viele der oben dokumentierten Live-Fixes sind derselbe Bug-Typ:
  `selectedMatch`, `combinedMatch` und `isDirectRouteMode`/`selectedDirectRouteIndex` sind vier
  unabhängige States, die sich gegenseitig ausschließen *sollen*, aber nur durch drei von Hand
  gepflegte `onChange`-Handler ([ContentView.swift:578-633](FahrradApp/RadFaehrte/ContentView.swift))
  synchron gehalten werden - jeder der Fälle "zwei Treffer gleichzeitig markiert" (Hannover ->
  Braunschweig, Bremen -> Hannover, s. o.) entstand, weil eine Stelle im Code einen dieser States
  setzte, ohne die anderen zurückzusetzen. Jeder Fix fügte ein weiteres Werkzeug hinzu
  (`routeSelectionToken`, `lastMatchingCoordinates`, den zentralen
  `onChange(of: isDirectRouteMode)`-Handler), statt die Ursache zu beseitigen.
  - **Vorschlag**: Ein `enum RouteSelection { case none, single(RouteMatch),
    combined(CombinedRouteMatch), direct(index: Int) }` ersetzt die vier States - gegenseitige
    Ausschließlichkeit ist dann strukturell garantiert statt manuell durchgesetzt, die drei
    `onChange`-Handler und `routeSelectionToken` könnten entfallen. Ausgelagert in eine eigene,
    SwiftUI-unabhängige `@Observable`-Klasse (`RouteSelectionStore`) wäre das erstmals auch per
    schnellem Unit-Test prüfbar, statt nur per Live-Test auf dem iPhone - genau die Fälle, die
    bisher mehrere Runden mit dem Nutzer gebraucht haben.
  - **Migrations-Idee**: nicht die ganze Datei umbauen, sondern nur den Auswahl-Cluster, mit
    Kompatibilitäts-Properties (`var selectedMatch: RouteMatch? { ... }`) für einen schrittweisen
    Umbau ohne große Zwischenzeit mit nicht-kompilierbarem Code. Geschätzter Umfang ca. 400-600
    Zeilen, keine beabsichtigte Verhaltensänderung.
  - **Zurückgestellt (Nutzer-Entscheidung 2026-08-14)**: reiner Aufräum-Umbau ohne neuen Nutzen,
    genau im bug-anfälligsten Bereich der App - Risiko aktuell nicht gerechtfertigt. Erst wieder
    angehen, wenn ein neuer, ähnlicher Auswahl-Bug live auffällt (dann als konkreter
    Live-Testfall für die Migration nutzbar, analog zum bisherigen Vorgehen bei
    Wege-Graph-Bugs oben).
  → [ContentView.swift](FahrradApp/RadFaehrte/ContentView.swift) (`selectedMatch`, `combinedMatch`,
  `isDirectRouteMode`, `selectedDirectRouteIndex`, `routeSelectionToken`, `onChange(of:
  isDirectRouteMode)`, `onChange(of: selectedMatch)`, `onChange(of: combinedMatch)`)

## Offene Entscheidungen (vor Umsetzung zu klären)

1. ~~MKDirections vs. eigene Routing-Engine für "schnellste Route" (Phase 4)~~ – entschieden:
   beides parallel (online MKDirections als Standard, eigene Offline-Engine für heruntergeladene
   Bundesländer, siehe oben).
2. Höhendaten-Quelle, falls Höhenprofil gewünscht (Phase 4)
3. Umgang mit der Offline-Karten-Einschränkung (Phase 4) – akzeptieren oder Framework-Wechsel?
4. Konzept für den Rundtour-Modus (Phase 2) – wie wird eine "gute" Rundtour algorithmisch bestimmt?
5. ~~Ob/wann die Pro-Bundesland-Download-Idee für die ruhige-Wege-Engine umgesetzt wird~~ –
   erledigt, siehe oben. Offen bleibt: Routing über Bundesland-Grenzen hinweg (aktuell wird nur
   das erste heruntergeladene Bundesland probiert, s. o. "Bekannte Lücke"), und ob eine
   serverseitige On-Demand-Variante (ohne Download) ergänzt werden soll.

## Technische Referenz

**Projektstruktur (Auszug):**
```
FahrradApp/FahrradApp/
├── Scripts/          build_way_graph.py, venv/ (gitignored), data/ (gitignored)
└── RadFaehrte/
    ├── Models/       BikeRoute.swift, SelectedPlace.swift, DrivenTour.swift, ImportedRoute.swift
    ├── ViewModels/   LocationSearchViewModel.swift
    ├── Views/        LocationSearchField.swift, HistoryView.swift, OwnRoutesView.swift, SettingsView.swift
    ├── Services/     RouteRepository.swift, RouteMatcher.swift, LocationManager.swift,
    │                 WayGraphRepository.swift, BikeRoutingEngine.swift, WayGraphStore.swift,
    │                 WayGraphDownloadManager.swift, DrivenTourStore.swift, ImportedRouteStore.swift
    ├── Resources/    routes.sqlite (64 MB, im App-Bundle)
    ├── RootTabView.swift
    └── ContentView.swift
```

**`routes.sqlite`-Schema:**
```sql
CREATE TABLE routes (
    id INTEGER PRIMARY KEY,
    name TEXT, network TEXT, ref TEXT, distance_km REAL, operator TEXT,
    min_lon REAL, min_lat REAL, max_lon REAL, max_lat REAL,
    geometry BLOB   -- little-endian: UInt32 numLines, je Line UInt32 numPoints,
                     -- dann numPoints * (Float32 lon, Float32 lat)
);
CREATE INDEX idx_routes_bbox ON routes(min_lon, max_lon, min_lat, max_lat);
```

**Datenpipeline (falls Neu-Extraktion nötig, z. B. für Phase 3):**
1. `germany-latest.osm.pbf` von `download.geofabrik.de/europe/` laden (~4,8 GB)
2. Python-venv mit `pyosmium` + `shapely` (kein Homebrew nötig, reine pip-Installation)
3. Zwei-Pass-Extraktion: Relationen mit `route=bicycle` sammeln (inkl. Sub-Relationen für
   Superrouten), dann Way-Geometrien auflösen (`FileProcessor(...).with_locations()`)
4. Douglas-Peucker-Vereinfachung via `shapely.simplify()`, Toleranz ~0.0001° (≈11 m)
5. Binär packen in SQLite (siehe Schema oben)
6. Für Phase 3 (Straßennamen/Oberfläche): zusätzlich pro Way `tags.get("name")` und
   `tags.get("surface")` mitschreiben, z. B. als weitere Spalten oder separate Tabelle
   mit Way-ID-Referenz statt nur der zusammengefassten Route-Geometrie
7. ⚠️ Die Python-Skripte dieser Pipeline (`extract_routes.py`, `build_sqlite.py`,
   `simplify_routes.py`) lagen nur im Scratchpad und sind nicht mehr vorhanden - müssten
   bei Bedarf neu geschrieben werden.

**Getestetes Beispiel (Referenz für Regressionstests):** Bremen → Achim findet den
Weser-Radweg (`rcn`) sowie Varianten davon.

**Git/GitHub:** Repo liegt in `FahrradApp/FahrradApp/.git` (nicht auf oberster Ebene - Roadmap/
Spezifikation liegen eine Ebene höher und sind bewusst unversioniert). Remote:
[github.com/Joern2368/RadFaehrte](https://github.com/Joern2368/RadFaehrte), **öffentlich**
(Voraussetzung dafür, dass Release-Assets ohne Auth-Token herunterladbar sind). `gh`-CLI ist auf
diesem Mac ohne Homebrew installiert (`~/.local/bin/gh`, Binary-Release von GitHub) und war
bereits über den System-Schlüsselbund für den Account `Joern2368` authentifiziert. Release-Tags
`way-graphs-v1`/`-v2` (alte Wege-Graph-Formate) liegen weiterhin auf GitHub - bewusst nicht
gelöscht, da es davon keine Kopie in der Git-Historie gibt (nur die `.sqlite`-Ergebnisse sind
per `.gitignore` von Git ausgeschlossen, nicht die Scripts) und Löschen daher endgültig wäre,
ohne echten Vorteil. `way-graphs-v3` wurde dagegen gelöscht (kurzlebiger Fehlversuch, s. u.).

**Wege-Graph-Pipeline (`Scripts/build_way_graph.py`) für die Offline-Routing-Engine:**
1. `<bundesland>-latest.osm.pbf` von `download.geofabrik.de/europe/germany/` laden
2. Python-venv (`Scripts/venv`) mit `osmium` (PyPI-Paketname, nicht `pyosmium`!) + `shapely`
3. `osmium.FileProcessor(pbf_path).with_locations()` **ohne** Entity-Filter durchlaufen (mit
   Filter z. B. nur `osmium.osm.WAY` funktioniert `.with_locations()` nicht - Fehlermeldung
   "Nodes not read from file"), selbst per `way.is_way()` filtern
4. Pro Way: `is_bikeable(tags)` prüft `highway`/`bicycle`/`access`, `weight_multiplier(tags)`
   gewichtet nach `HIGHWAY_WEIGHTS` (Radweg/ruhige Straße < 1.0, Hauptstraße > 1.0),
   `direction(tags)` beachtet `oneway`/`oneway:bicycle=no`
5. Dichte 0-basierte Knoten-Indizes vergeben (nicht die OSM-IDs direkt verwenden), Ergebnis in
   **einer** SQLite-Datei mit **einer** Tabelle `graph (node_count, edge_count, nodes BLOB,
   edges BLOB)` statt einer Zeile pro Knoten/Kante mit Indizes (letzteres kostete bei
   Baden-Württemberg allein ~700 MB zusätzlich für zwei nie genutzte Indizes - die App lädt beim
   Start ohnehin den kompletten Graphen in den Speicher, fragt nie einzeln per SQL nach)
6. Blob-Format (Stand v4, aktuell): `nodes` = pro Knoten (Index-Reihenfolge) `Float32 lat,
   Float32 lon` (8 Byte); `edges` = pro Kante `UInt32 fromIndex, UInt32 toIndex,
   Float32 distanceMeters, Float32 weight, UInt8 offsetSide, UInt32 nameIndex` (21 Byte,
   `offsetSide` seit v2, `nameIndex` seit v4 - Index in eine deduplizierte `names`-Tabelle,
   `0xFFFFFFFF` = unbenannt); `names` = pro eindeutigem Straßennamen `UInt16 byteLength` +
   UTF-8-Bytes, zusätzliche Tabellenspalten `name_count`/`names`. Ursprüngliche v1-Kante war nur
   16 Byte (`UInt32 fromIndex, UInt32 toIndex, Float32 distanceMeters, Float32 weight`, keine
   Namen/Versatz) - falls hier künftig nochmal was geändert wird: `WayGraphStore.formatVersion`
   hochzählen (sonst interpretiert die App alte heruntergeladene Dateien mit falscher
   Byte-Schrittweite).
7. Vor dem Schreiben alte Datei löschen + am Ende `VACUUM` - sonst blähen Altlasten einer
   wiederverwendeten Datei die Größe unnötig auf
8. Release-Asset-Name: `<bundesland>_ways.sqlite`, aktuell hochgeladen unter Tag `way-graphs-v4`
   (v1 = Ursprungsformat, v2 = + Radweg-Versatz, v3 = zurückgezogener Fehlversuch mit
   UInt16-Namensindex, s. u. "Frühere Fehlversuche", v4 = UInt32-Namensindex)

**App-seitige Nutzung:** `WayGraphRepository` liest die zwei Blobs komplett in
`[CLLocationCoordinate2D]`/`[[Edge]]`-Arrays (indiziert per Knoten-Index, keine Dictionaries -
schneller bei Millionen Knoten). `BikeRoutingEngine` sucht per A* (Heuristik mit konservativem
`minWeightMultiplier`, damit sie nie die echten Restkosten überschätzt); `gScore`/`cameFrom` etc.
bleiben Dictionaries statt Arrays über die volle Graphgröße, weil eine einzelne Suche in einem
großen Bundesland meist nur einen kleinen lokalen Ausschnitt berührt.

**Frühere Fehlversuche (für's nächste Mal notiert):**
- Erste Größen-Stichprobe per `curl -sL -o /dev/null` lädt die komplette Datei trotzdem
  herunter (nur die Ausgabe wird verworfen) - für reine Größenchecks lieber `curl -I` (HEAD)
  verwenden, auch wenn Geofabrik dafür ggf. `-L` zum Redirects-Folgen braucht.
- **Bei kompakten Zähl-/Index-Feldern lieber großzügig dimensionieren, nicht an einer kleinen
  Testregion (z. B. Bremen) hochrechnen**: Der Namensindex fürs Wege-Graph-Format (s. o.) wurde
  zunächst als `UInt16` (max. 65.534 eindeutige Werte) angelegt, weil das für die winzige
  Testregion Bremen (5.430 Namen) extrem großzügig wirkte. Beim echten Bau aller 16
  Bundesländer traf Baden-Württemberg exakt auf diese Grenze (tatsächlich 86.500 eindeutige
  Namen) - ein stiller Datenverlust (überzählige Namen wurden als "unbenannt" behandelt), keine
  Fehlermeldung. Auf `UInt32` umgestellt (neuer Format-Tag `way-graphs-v4`, `v3` mit dem
  UInt16-Fehler wurde gar nicht erst richtig ausgeliefert). Lehre: Bei Werten, die mit der
  Kartenabdeckung skalieren (Wege, Kreuzungen, Straßennamen, ...), immer am größten realistischen
  Bundesland (Bayern/NRW) gegenprüfen, nicht nur an der kleinen Testregion - deren Zahlen sind
  oft um Größenordnungen kleiner.
- `pip install pyosmium` schlägt fehl ("no versions found") - das PyPI-Paket heißt `osmium`.

**Offline-Routing-Bugs mit echten Nutzerdaten statt geratenen Adress-Koordinaten reproduzieren**
(genutzt für den "Am Hulsberg"-Abbiege-Fehlalarm, s. o. "Kleiner Schlenker..."): Ein per
Adresssuche (z. B. Nominatim) geschätzter Start-/Zielpunkt trifft selten exakt denselben Knoten
wie Apples eigene Geokodierung in der App - für eine A*-Suche über einen großen Graphen kann das
zu einer komplett anderen Route führen als der tatsächlich in der App berechneten, wodurch sich
ein gemeldeter Bug lokal nicht reproduzieren lässt. Zuverlässiger: die **tatsächlich aufgezeichnete
Fahrt** aus dem "Verlauf"-Tab vom Gerät ziehen (`DrivenTourStore` speichert jede abgeschlossene
Tour als `Documents/DrivenTours/<uuid>.json` mit echten GPS-Koordinaten) - `xcrun devicectl device
copy from --device <udid> --domain-type appDataContainer --domain-identifier
com.frankenfeld.RadFaehrte --source /Documents/DrivenTours --destination <lokaler-ordner>`, dann
zwei Punkte aus der aufgezeichneten Strecke rund um die gemeldete Stelle als Start/Ziel nehmen.
Für die eigentliche Reproduktion `BikeRoutingEngine.swift` + `WayGraphRepository.swift` unverändert
in ein eigenes Verzeichnis kopieren, per `swiftc -O WayGraphRepository.swift BikeRoutingEngine.swift
main.swift -o routedebug -lsqlite3` zu einem Kommandozeilen-Tool bauen (beide Dateien haben keine
Projekt-spezifischen Abhängigkeiten außer `CoreLocation`/`SQLite3`, laufen unverändert auch als
macOS-Kommandozeilentool) und gegen die per `gh release download way-graphs-v4 -R
Joern2368/RadFaehrte -p "<bundesland>_ways.sqlite"` heruntergeladene echte Graph-Datei laufen
lassen - liefert exakt dieselben `coordinates`/`steps` wie die App, ohne Xcode/Simulator/Gerät für
jede Iteration neu bauen zu müssen. Ergebnis war hier eindeutig: eine 2,4 m kurze Kante genau an
einer Namensgruppen-Grenze verursachte eine falsche Abbiege-Ansage (s. u. "Kleiner Schlenker...").

**Live-Debugging auf einem echten iPhone ohne Xcode-GUI** (genutzt für den Navigationskamera-Bug,
s. o.): `xcrun devicectl device process launch --console --device <udid> <bundle-id>` hängt
stdout/stderr des Geräts an - Ausgabe unbedingt in eine Datei umleiten
(`... > log.txt 2>&1 & disown`), da `print()` beim Piping (nicht-TTY) geblockt puffert und sonst
minutenlang nichts ankommt. Für den Nutzer reicht kurzes Kabel-Verbinden zum Start der Sitzung -
danach kann er ohne Rechner in der Hand im selben WLAN weitertesten (die Verbindung bleibt
bestehen). Gerätestatus vorher prüfen: `xcrun devicectl list devices` (muss `available (paired)`
zeigen, sonst `unavailable` bei getrenntem/gesperrtem Gerät - Sperrbildschirm verhindert auch den
App-Start: `FBSOpenApplicationErrorDomain error 7 "Locked"`).

**App per Kommandozeile installieren statt in Xcode auf "Copying shared cache symbols" zu warten**
(gefunden bei der Apple-Watch-Anbindung, 2026-07-28): Xcodes GUI zeigt beim erstmaligen Verbinden
eines Geräts in einer Xcode-Version (oder nach einem iOS-Update) "Copying shared cache symbols
from <Gerät> (x% completed)" - ein einmaliger Symbolisierungs-Download fürs spätere
Debugger-Attachen, der mehrere Minuten dauern kann und laut Dialog nicht übersprungen werden
kann. Für ein reines Bauen+Installieren+Starten (kein Live-Debugging mit Breakpoints nötig) lässt
sich das umgehen: `xcodebuild build -project RadFaehrte.xcodeproj -scheme RadFaehrte -destination
"id=<UDID>" -configuration Debug` (Signing läuft automatisch, keine zusätzlichen Flags nötig, im
Gegensatz zu den `CODE_SIGNING_ALLOWED=NO`-Build-Validierungen weiter oben) baut und signiert ganz
ohne diesen Wartescreen; anschließend `xcrun devicectl device install app --device <UDID>
<Pfad-zur-.app-in-DerivedData>` sowie `xcrun devicectl device process launch --device <UDID>
<Bundle-ID>` installieren und starten die App direkt. `<UDID>` per `xcrun devicectl list devices`
ermitteln (Spalte "Identifier").

**Screen-Recordings vom iPhone auswerten**: Der Nutzer nimmt testweise Bildschirmvideos auf
(landen synchronisiert in `~/Library/Mobile Documents/com~apple~CloudDocs/Downloads/`). Das `Read`-
Tool kann `.mp4` nicht direkt öffnen ("binary file"); da weder `ffmpeg` noch Homebrew auf diesem
Mac installiert sind, extrahiert stattdessen ein kleines Swift-Skript mit `AVFoundation`
(`AVAssetImageGenerator`) einzelne Frames als PNG, die dann normal per `Read` angeschaut werden
können - unter `/private/tmp/.../scratchpad/extract_frames.swift` (äquidistante Frames über die
Gesamtdauer) bzw. `extract_frames_range.swift` (dichte Abtastung eines Zeitfensters, z. B. für
Kompass-Wackeln) abgelegt, Aufruf jeweils `swift <script>.swift <video> <output-dir> [start end
step]`. Bei per-Hand eingegebenen iCloud-Downloads-Dateipfaden Vorsicht: gelegentlich kurz
"verschwundene" Dateien (iCloud-Sync-Zwischenzustand) - im Zweifel den Nutzer bitten, die Datei
direkt in einen nicht-iCloud-synchten Projektordner zu kopieren.

**Lehre aus der Zoom-Odyssee (s. o. "Manuelles Zoomen während der Navigation funktionierte
nicht")**: Nicht ohne Beleg annehmen, dass eine SwiftUI-Geste (hier `MagnificationGesture` auf
einer `Map`) "wahrscheinlich nicht feuert", weil ein anderer View-Typ (MapKit) intern eigene
Touch-Gesten hat - das kostete einen kompletten Anlauf umsonst. Live-Debug-Logging (s. o.) zeigte
schnell und eindeutig, dass sie zuverlässig feuerte; das eigentliche Problem war ein Wettlauf mit
einem Timer, keine fehlende Geste-Erkennung. Bei "geht manchmal, meistens nicht"-Symptomen zuerst
an Timing-Wettläufe zwischen zwei nebenläufigen Auslösern denken, nicht an grundsätzlich fehlende
Erkennung.
