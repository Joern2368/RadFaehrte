//
//  HistoryView.swift
//  RadFaehrte
//

import SwiftUI
import MapKit

/// Liste der tatsächlich gefahrenen Touren (aufgezeichnet im Navigationsmodus, siehe
/// `ContentView.stopNavigating`). Anders als "Eigene Routen" (importierte Ziel-Touren zum
/// Nachfahren) ist das hier ein reines Protokoll bereits abgeschlossener Fahrten.
struct HistoryView: View {
    let store: DrivenTourStore
    /// Von `ContentView` hochgezählt, sobald eine Fahrt beendet und gespeichert wurde - lädt die
    /// Liste neu, auch wenn dieser Tab schon sichtbar ist/bleibt (analog `OwnRoutesView`).
    let refreshTrigger: Int

    @State private var tours: [DrivenTour] = []
    @State private var selectedTour: DrivenTour?

    var body: some View {
        NavigationStack {
            Group {
                if tours.isEmpty {
                    ContentUnavailableView(
                        "Noch keine Fahrten",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Nach jeder abgeschlossenen Fahrt im Route-Tab erscheint sie hier.")
                    )
                } else {
                    List {
                        ForEach(tours) { tour in
                            Button {
                                selectedTour = tour
                            } label: {
                                tourRow(tour)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Verlauf")
        }
        .onAppear { tours = store.loadAll() }
        .onChange(of: refreshTrigger) { tours = store.loadAll() }
        .sheet(item: $selectedTour) { tour in
            tourDetail(tour)
        }
    }

    private func tourRow(_ tour: DrivenTour) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tour.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.medium))
                Text(
                    "\(String(format: "%.1f", tour.distanceKm)) km · \(formattedTourDuration(tour.duration))"
                    + " · ⌀ \(String(format: "%.1f", tour.averageSpeedKmh)) km/h"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            store.delete(tours[index])
        }
        tours.remove(atOffsets: offsets)
    }

    @ViewBuilder
    private func tourDetail(_ tour: DrivenTour) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                let coordinates = tour.clCoordinates
                if coordinates.count >= 2 {
                    Map(initialPosition: .region(Self.regionToFit(coordinates))) {
                        MapPolyline(coordinates: coordinates)
                            .stroke(.blue, lineWidth: 4)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    detailRow(label: "Distanz", value: "\(String(format: "%.1f", tour.distanceKm)) km")
                    detailRow(label: "Dauer", value: formattedTourDuration(tour.duration))
                    detailRow(label: "Ø Tempo", value: "\(String(format: "%.1f", tour.averageSpeedKmh)) km/h")
                }
                .padding()
            }
            .navigationTitle(tour.date.formatted(date: .abbreviated, time: .shortened))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { selectedTour = nil }
                }
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private static func regionToFit(_ coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.3),
            longitudeDelta: max(0.01, (maxLon - minLon) * 1.3)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

#Preview {
    HistoryView(store: DrivenTourStore(), refreshTrigger: 0)
}
