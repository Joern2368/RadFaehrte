//
//  LocationSearchField.swift
//  RadFaehrte
//

import SwiftUI
import MapKit

struct LocationSearchField: View {
    let label: String
    @Binding var selectedPlace: SelectedPlace?
    var isResolvingCurrentLocation: Bool = false
    var onUseCurrentLocation: (() -> Void)? = nil
    /// Nur beim Ziel-Feld gesetzt (Nutzer-Idee: Ziel per Fingertipp auf der Karte statt nur über
    /// die Adresssuche setzen) - aktiviert in `ContentView` den Karten-Auswahlmodus
    /// (`isPickingZielOnMap`), der eigentliche Tap wird dort per `handleMapTap` verarbeitet.
    var onPickOnMap: (() -> Void)? = nil
    /// Gespeicherte Orte (Zuhause/Arbeit/eigene) - wie `recents` nur sichtbar, solange noch nichts
    /// eingetippt ist (analog Google Maps: verschwindet zugunsten der Adress-Suchergebnisse, sobald
    /// eine Eingabe beginnt). Leer, solange keine Favoriten gespeichert sind.
    var favorites: [FavoritePlace] = []
    /// Zeigt einen Stern-Button neben dem Lösch-Icon, sobald ein Ort ausgewählt ist - `ContentView`
    /// öffnet darüber den Dialog zum Speichern als Favorit für genau dieses Feld.
    var onSaveFavorite: (() -> Void)? = nil
    /// Zuletzt über dieses oder das andere Suchfeld gewählte Ziele (analog "Zuletzt gesucht" bei
    /// Google Maps) - wie `favorites` nur bei leerem Suchfeld sichtbar.
    var recents: [RecentPlace] = []
    var onDeleteRecent: ((RecentPlace) -> Void)? = nil
    /// Meldet jede erfolgreiche Adressauswahl (Tipp-Ergebnis oder erneut angetippter Recent-Eintrag)
    /// nach außen, damit `ContentView` sie in `RecentPlaceStore` festhält bzw. auffrischt.
    var onPlaceChosen: ((_ title: String, _ subtitle: String, _ coordinate: CLLocationCoordinate2D) -> Void)? = nil
    var biasCoordinate: CLLocationCoordinate2D? = nil
    /// Meldet Änderungen am Bearbeitungsstatus (Sheet offen/geschlossen) nach außen, damit
    /// `ContentView` z. B. die Ergebnisliste ausblenden kann, solange dieses Feld aktiv bearbeitet
    /// wird (mehr Platz für die Vorschlagsliste).
    var onFocusChange: ((Bool) -> Void)? = nil
    /// Wenn `false`, öffnet sich beim Antippen kein Vollbild-Sheet mehr - stattdessen erscheinen
    /// "Aktuelle Position" und Tipp-Ergebnisse als Inline-Liste direkt unter dem Textfeld
    /// (`inlineSuggestions`). Bisher nur fürs Start-Feld gedacht (Nutzer-Beobachtung: dort wählt man
    /// ohnehin meist "Aktuelle Position" statt eine Adresse zu tippen, ein Vollbild-Sheet dafür ist
    /// unnötig) - Favoriten/Zuletzt-gesucht werden im Inline-Modus deshalb bewusst nicht gerendert,
    /// da das Start-Feld beides nicht übergibt.
    var usesSheet: Bool = true

    @State private var viewModel = LocationSearchViewModel()
    @FocusState private var isFocused: Bool
    /// Ob die Auswahl-Sheet gerade angezeigt wird - getrennt von `isFocused`, weil das eigentliche
    /// Sucheingabefeld während der Sheet-Anzeige ins Sheet wandert (`sheetContent`) und das äußere
    /// Feld dafür aus dem Baum entfernt wird (kein doppelt gleichnamiges Textfeld gleichzeitig -
    /// würde `app.textFields["Start"/"Ziel"]` in den UI-Tests mehrdeutig machen). `isFocused` dient
    /// nur noch als Auslöser zum Öffnen; für "wird dieses Feld gerade bearbeitet" (siehe
    /// `onFocusChange`) ist `isPresented` maßgeblich, da `isFocused` beim Entfernen des äußeren
    /// Feldes aus dem Baum automatisch wieder auf `false` zurückfällt, während das Sheet noch offen
    /// ist.
    @State private var isPresented = false
    @FocusState private var isSheetFieldFocused: Bool

    private var showsFavoritesAndRecents: Bool {
        viewModel.queryFragment.isEmpty && (!favorites.isEmpty || !recents.isEmpty)
    }

    /// Geschätzte Höhe einer Ergebniszeile in `inlineSuggestions` (Titel + Untertitel + Padding) -
    /// zusammen mit der Zeilenzahl unten die Grundlage für die feste `.frame(height:)`, die
    /// mindestens ~4 Zeilen sichtbar hält, ohne bei wenigen Treffern unnötig viel leeren Raum zu
    /// reservieren.
    private let inlineResultRowHeight: CGFloat = 60
    private var inlineResultsHeight: CGFloat {
        min(CGFloat(viewModel.results.count), 4.5) * inlineResultRowHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if isPresented {
                    Text(viewModel.queryFragment.isEmpty ? label : viewModel.queryFragment)
                        .foregroundStyle(viewModel.queryFragment.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                } else {
                    TextField(label, text: $viewModel.queryFragment)
                        .focused($isFocused)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }

                if selectedPlace != nil {
                    if let onSaveFavorite {
                        Button {
                            onSaveFavorite()
                        } label: {
                            Image(systemName: "star")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("saveFavorite-\(label)")
                    }
                    Button {
                        clearSelection()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("clearSelection-\(label)")
                }
            }

            if !usesSheet && isFocused {
                inlineSuggestions
            }
        }
        .sheet(isPresented: $isPresented, onDismiss: { isFocused = false }) {
            sheetContent
        }
        .onChange(of: isFocused) { _, newValue in
            if usesSheet {
                if newValue { isPresented = true }
            } else {
                onFocusChange?(newValue)
            }
        }
        .onChange(of: isPresented) { _, newValue in
            onFocusChange?(newValue)
        }
        .onChange(of: selectedPlace) { _, newValue in
            if let newValue, newValue.title != viewModel.queryFragment {
                viewModel.queryFragment = newValue.title
            }
        }
        .onChange(of: biasCoordinate?.latitude) { _, _ in
            viewModel.updateRegion(around: biasCoordinate)
        }
        .onChange(of: biasCoordinate?.longitude) { _, _ in
            viewModel.updateRegion(around: biasCoordinate)
        }
        .onAppear {
            viewModel.updateRegion(around: biasCoordinate)
            // Nutzer-Beobachtung (2026-08-09, Karten-Ziehgriff `routeFormCollapseGrabber`): Das
            // Ein-/Ausklappen des umgebenden Suchfelder-Bereichs entfernt diese View per `if` komplett
            // aus dem Baum und erzeugt sie beim Wiedereinblenden neu - dabei geht `viewModel` (und
            // damit der angezeigte `queryFragment`-Text) als eigener `@State` verloren, obwohl
            // `selectedPlace` selbst unverändert blieb. Der `onChange(of: selectedPlace)`-Sync weiter
            // oben greift nur bei einer echten Änderung, nicht beim ersten Erscheinen einer frischen
            // View-Instanz - ohne diesen zusätzlichen Abgleich blieb das Feld leer, obwohl Route und
            // Karte weiterhin die vorherige Auswahl zeigten.
            if let selectedPlace, viewModel.queryFragment.isEmpty {
                viewModel.queryFragment = selectedPlace.title
            }
        }
    }

    /// Ersatz für `sheetContent` im Inline-Modus (`usesSheet == false`) - erscheint direkt unter dem
    /// Textfeld statt in einem Vollbild-Sheet. Rendert bewusst nur "Aktuelle Position" + Tipp-
    /// Ergebnisse, keine Favoriten/Zuletzt-gesucht/"Auf Karte wählen": Inline-Modus wird aktuell nur
    /// fürs Start-Feld verwendet, das keinen dieser drei Parameter übergibt.
    @ViewBuilder
    private var inlineSuggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let onUseCurrentLocation {
                Button {
                    onUseCurrentLocation()
                    dismissSuggestions()
                } label: {
                    Label {
                        Text("Aktuelle Position")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    } icon: {
                        if isResolvingCurrentLocation {
                            ProgressView()
                        } else {
                            Image(systemName: "location.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(isResolvingCurrentLocation)
                .accessibilityIdentifier("useCurrentLocation-\(label)")
                .padding(.vertical, 8)
                .padding(.horizontal, 8)

                if !viewModel.results.isEmpty {
                    Divider()
                }
            }

            // Nutzer-Beobachtung (2026-09-01): Ohne Höhenbegrenzung wuchs diese Liste mit allen
            // Tipp-Treffern beliebig weit nach unten und schob dabei das Textfeld selbst über den
            // sichtbaren Bereich hinaus - man sah beim Tippen nicht mehr, was man eingibt. Ein reines
            // `maxHeight` reicht als Gegenmaßnahme aber nicht: Diese View steht in `ContentView` im
            // selben `VStack` wie die Kartenvorschau, und ohne feste Mindesthöhe wird sie beim
            // Platzverteilen genauso stark zusammengequetscht wie die (ebenfalls flexible) Karte -
            // sichtbar waren dadurch je nach Bildschirm nur 1-2 Ergebniszeilen statt der gewünschten
            // mindestens 4. Eine feste `.frame(height:)` (statt nur `maxHeight`) erzwingt dagegen die
            // Reservierung dieses Platzes, exakt wie schon bei `resultsSectionMaxHeight` in
            // `ContentView` für dasselbe Problem gelöst.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.results, id: \.self) { completion in
                        Button {
                            select(completion)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title)
                                    .foregroundStyle(.primary)
                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)

                        if completion != viewModel.results.last {
                            Divider()
                        }
                    }
                }
            }
            .frame(height: inlineResultsHeight)
        }
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var sheetContent: some View {
        VStack(spacing: 0) {
            TextField(label, text: $viewModel.queryFragment)
                .focused($isSheetFieldFocused)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .padding()

            List {
                if let onPickOnMap {
                    Button {
                        onPickOnMap()
                        isPresented = false
                    } label: {
                        Label {
                            Text("Auf Karte wählen")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: "hand.tap.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pickOnMap-\(label)")
                }
                if let onUseCurrentLocation {
                    Button {
                        onUseCurrentLocation()
                        isPresented = false
                    } label: {
                        Label {
                            Text("Aktuelle Position")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                        } icon: {
                            if isResolvingCurrentLocation {
                                ProgressView()
                            } else {
                                Image(systemName: "location.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isResolvingCurrentLocation)
                    .accessibilityIdentifier("useCurrentLocation-\(label)")
                }

                if showsFavoritesAndRecents {
                    if !favorites.isEmpty {
                        Section("Favoriten") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 20) {
                                    ForEach(favorites) { favorite in
                                        Button {
                                            select(favorite)
                                        } label: {
                                            VStack(spacing: 4) {
                                                Image(systemName: favorite.icon)
                                                    .font(.body)
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 44, height: 44)
                                                    .background(Color(.systemGray5))
                                                    .clipShape(Circle())
                                                Text(favorite.displayName)
                                                    .font(.caption)
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 72)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("favorite-\(label)-\(favorite.id)")
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                    if !recents.isEmpty {
                        Section("Zuletzt gesucht") {
                            ForEach(recents) { recent in
                                Button {
                                    select(recent)
                                } label: {
                                    HStack {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(recent.title)
                                                .foregroundStyle(.primary)
                                            if !recent.subtitle.isEmpty {
                                                Text(recent.subtitle)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("recent-\(label)-\(recent.id)")
                                .swipeActions(edge: .trailing) {
                                    if let onDeleteRecent {
                                        Button(role: .destructive) {
                                            onDeleteRecent(recent)
                                        } label: {
                                            Label("Löschen", systemImage: "trash")
                                        }
                                        .accessibilityIdentifier("deleteRecent-\(label)-\(recent.id)")
                                    }
                                }
                            }
                        }
                    }
                }

                if !viewModel.results.isEmpty {
                    Section("Ergebnisse") {
                        ForEach(viewModel.results, id: \.self) { completion in
                            Button {
                                select(completion)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(completion.title)
                                        .foregroundStyle(.primary)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            isSheetFieldFocused = true
        }
    }

    private func select(_ completion: MKLocalSearchCompletion) {
        Task {
            do {
                let coordinate = try await viewModel.resolve(completion)
                selectedPlace = SelectedPlace(
                    title: completion.title,
                    subtitle: completion.subtitle,
                    coordinate: coordinate
                )
                viewModel.queryFragment = completion.title
                dismissSuggestions()
                onPlaceChosen?(completion.title, completion.subtitle, coordinate)
            } catch {
                // Auflösung fehlgeschlagen (z. B. kein Treffer) – Auswahl bleibt leer
            }
        }
    }

    /// Anders als `select(_ completion:)` keine asynchrone Adressauflösung nötig - die Koordinate
    /// liegt beim Favoriten schon vor.
    private func select(_ favorite: FavoritePlace) {
        selectedPlace = SelectedPlace(
            title: favorite.title,
            subtitle: favorite.subtitle,
            coordinate: favorite.clCoordinate
        )
        viewModel.queryFragment = favorite.title
        dismissSuggestions()
    }

    /// Wie `select(_ favorite:)` ohne erneute Adressauflösung - meldet die Auswahl zusätzlich über
    /// `onPlaceChosen`, damit der Eintrag in `RecentPlaceStore` an die erste Stelle rückt.
    private func select(_ recent: RecentPlace) {
        selectedPlace = SelectedPlace(
            title: recent.title,
            subtitle: recent.subtitle,
            coordinate: recent.clCoordinate
        )
        viewModel.queryFragment = recent.title
        dismissSuggestions()
        onPlaceChosen?(recent.title, recent.subtitle, recent.clCoordinate)
    }

    /// Schließt die Vorschlagsliste nach einer Auswahl - im Sheet-Modus das Sheet, im Inline-Modus
    /// (`usesSheet == false`) stattdessen einfach den Fokus, da dort keine `isPresented`-Sheet-
    /// Präsentation existiert.
    private func dismissSuggestions() {
        isPresented = false
        isFocused = false
    }

    private func clearSelection() {
        selectedPlace = nil
        viewModel.queryFragment = ""
    }
}
