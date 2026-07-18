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

    @State private var viewModel = LocationSearchViewModel()
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField(label, text: $viewModel.queryFragment)
                    .focused($isFocused)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                if let onUseCurrentLocation, selectedPlace == nil {
                    Button(action: onUseCurrentLocation) {
                        if isResolvingCurrentLocation {
                            ProgressView()
                        } else {
                            Image(systemName: "location.fill")
                        }
                    }
                    .disabled(isResolvingCurrentLocation)
                    .accessibilityIdentifier("useCurrentLocation-\(label)")
                }

                if selectedPlace != nil {
                    Button {
                        clearSelection()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("clearSelection-\(label)")
                }
            }

            if isFocused && !viewModel.results.isEmpty {
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
        .onChange(of: selectedPlace) { _, newValue in
            if let newValue, newValue.title != viewModel.queryFragment {
                viewModel.queryFragment = newValue.title
            }
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
            } catch {
                // Auflösung fehlgeschlagen (z. B. kein Treffer) – Auswahl bleibt leer
            }
        }
    }

    private func clearSelection() {
        selectedPlace = nil
        viewModel.queryFragment = ""
    }
}
