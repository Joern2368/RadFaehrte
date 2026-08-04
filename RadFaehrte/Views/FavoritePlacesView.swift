//
//  FavoritePlacesView.swift
//  RadFaehrte
//

import SwiftUI

/// Verwaltung der gespeicherten Favoriten-Orte (Zuhause/Arbeit/eigene) - Speichern selbst passiert
/// direkt in den Suchfeldern über das Stern-Symbol (s. `LocationSearchField`), hier nur zum
/// Nachschauen/Löschen.
struct FavoritePlacesView: View {
    let store: FavoritePlaceStore

    @State private var places: [FavoritePlace] = []

    var body: some View {
        Group {
            if places.isEmpty {
                ContentUnavailableView(
                    "Noch keine Favoriten",
                    systemImage: "star",
                    description: Text("In den Start-/Ziel-Feldern über das Stern-Symbol neben einem ausgewählten Ort speichern.")
                )
            } else {
                List {
                    ForEach(places) { place in
                        HStack {
                            Image(systemName: place.icon)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.displayName)
                                if !place.title.isEmpty {
                                    Text(place.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { store.delete(places[index]) }
                        places = store.loadAll()
                    }
                }
            }
        }
        .navigationTitle("Favoriten")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { places = store.loadAll() }
    }
}

#Preview {
    NavigationStack {
        FavoritePlacesView(store: FavoritePlaceStore())
    }
}
