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
    var biasCoordinate: CLLocationCoordinate2D? = nil

    @State private var viewModel = LocationSearchViewModel()
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField(label, text: $viewModel.queryFragment)
                    .focused($isFocused)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

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

            if isFocused && (onUseCurrentLocation != nil || !viewModel.results.isEmpty) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
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
