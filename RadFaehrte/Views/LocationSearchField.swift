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
    /// Meldet Fokus-Änderungen nach außen, damit `ContentView` z. B. die Ergebnisliste ausblenden
    /// kann, solange dieses Feld aktiv bearbeitet wird (mehr Platz für die Vorschlagsliste).
    var onFocusChange: ((Bool) -> Void)? = nil

    @State private var viewModel = LocationSearchViewModel()
    @FocusState private var isFocused: Bool

    private var showsFavoritesAndRecents: Bool {
        viewModel.queryFragment.isEmpty && (!favorites.isEmpty || !recents.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField(label, text: $viewModel.queryFragment)
                    .focused($isFocused)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

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

            if isFocused && (onUseCurrentLocation != nil || onPickOnMap != nil || showsFavoritesAndRecents || !viewModel.results.isEmpty) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let onPickOnMap {
                            Button {
                                onPickOnMap()
                                isFocused = false
                            } label: {
                                HStack {
                                    Image(systemName: "hand.tap.fill")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20)
                                    Text("Auf Karte wählen")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                }
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .accessibilityIdentifier("pickOnMap-\(label)")
                            Divider()
                        }
                        if let onUseCurrentLocation {
                            Button {
                                onUseCurrentLocation()
                                isFocused = false
                            } label: {
                                HStack {
                                    if isResolvingCurrentLocation {
                                        ProgressView()
                                            .frame(width: 20)
                                    } else {
                                        Image(systemName: "location.fill")
                                            .foregroundStyle(.secondary)
                                            .frame(width: 20)
                                    }
                                    Text("Aktuelle Position")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                }
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .disabled(isResolvingCurrentLocation)
                            .accessibilityIdentifier("useCurrentLocation-\(label)")
                            Divider()
                        }
                        if showsFavoritesAndRecents {
                            if !favorites.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(alignment: .top, spacing: 0) {
                                        ForEach(Array(favorites.enumerated()), id: \.element.id) { index, favorite in
                                            if index > 0 {
                                                Divider().frame(height: 36)
                                            }
                                            Button {
                                                select(favorite)
                                            } label: {
                                                HStack(spacing: 8) {
                                                    Image(systemName: favorite.icon)
                                                        .foregroundStyle(.secondary)
                                                    VStack(alignment: .leading, spacing: 1) {
                                                        Text(favorite.displayName)
                                                            .font(.body.weight(.semibold))
                                                            .foregroundStyle(.primary)
                                                            .lineLimit(1)
                                                        if !favorite.title.isEmpty {
                                                            Text(favorite.title)
                                                                .font(.caption)
                                                                .foregroundStyle(.secondary)
                                                                .lineLimit(1)
                                                        }
                                                    }
                                                }
                                                .padding(.horizontal, 12)
                                            }
                                            .accessibilityIdentifier("favorite-\(label)-\(favorite.id)")
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                                Divider()
                            }
                            if !recents.isEmpty {
                                Text("Zuletzt gesucht")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, favorites.isEmpty ? 0 : 4)
                                ForEach(recents) { recent in
                                    HStack {
                                        Button {
                                            select(recent)
                                        } label: {
                                            HStack {
                                                Image(systemName: "clock.arrow.circlepath")
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 20)
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
                                            .padding(.vertical, 6)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        if let onDeleteRecent {
                                            Button {
                                                onDeleteRecent(recent)
                                            } label: {
                                                Image(systemName: "xmark")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .accessibilityIdentifier("deleteRecent-\(label)-\(recent.id)")
                                        }
                                    }
                                    .accessibilityIdentifier("recent-\(label)-\(recent.id)")
                                    Divider()
                                }
                            }
                        }
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
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Divider()
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxHeight: 220)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 2)
            }
        }
        .onChange(of: isFocused) { _, newValue in
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
                isFocused = false
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
        isFocused = false
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
        isFocused = false
        onPlaceChosen?(recent.title, recent.subtitle, recent.clCoordinate)
    }

    private func clearSelection() {
        selectedPlace = nil
        viewModel.queryFragment = ""
    }
}
