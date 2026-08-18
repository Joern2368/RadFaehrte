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

    var body: some View {
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
        .sheet(isPresented: $isPresented, onDismiss: { isFocused = false }) {
            sheetContent
        }
        .onChange(of: isFocused) { _, newValue in
            if newValue { isPresented = true }
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
                            ForEach(favorites) { favorite in
                                Button {
                                    select(favorite)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: favorite.icon)
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(favorite.displayName)
                                                .foregroundStyle(.primary)
                                            if !favorite.title.isEmpty {
                                                Text(favorite.title)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("favorite-\(label)-\(favorite.id)")
                            }
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
        .presentationDetents([.medium, .large])
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
                isPresented = false
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
        isPresented = false
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
        isPresented = false
        onPlaceChosen?(recent.title, recent.subtitle, recent.clCoordinate)
    }

    private func clearSelection() {
        selectedPlace = nil
        viewModel.queryFragment = ""
    }
}
