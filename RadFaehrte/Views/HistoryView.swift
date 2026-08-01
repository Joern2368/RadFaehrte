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
    @State private var exportFile: GPXExportFile?
    private let snapshotCache = TourMapSnapshotCache()

    /// Feste deutsche Locale, da die App-Oberfläche nicht lokalisiert ist und `.formatted()`
    /// sonst je nach Sprach-/Regionseinstellung des Geräts z.B. ein englisches "at" anzeigt.
    private static let dateFormat = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Locale(identifier: "de_DE"))
    private static let monthYearFormat = Date.FormatStyle(locale: Locale(identifier: "de_DE")).month(.wide).year()

    private struct MonthGroup: Identifiable {
        let year: Int
        let month: Int
        var tours: [DrivenTour]
        var id: String { "\(year)-\(month)" }
        var totalKm: Double { tours.reduce(0) { $0 + $1.distanceKm } }
        var title: String {
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = 1
            let date = Calendar.current.date(from: comps) ?? Date()
            return HistoryView.monthYearFormat.format(date)
        }
    }

    /// Fasst die (bereits nach Datum absteigend sortierten) Touren zu Monatsgruppen zusammen,
    /// jeweils mit Gesamtkilometern für die Section-Kopfzeile.
    private var monthGroups: [MonthGroup] {
        var groups: [MonthGroup] = []
        let calendar = Calendar.current
        for tour in tours {
            let comps = calendar.dateComponents([.year, .month], from: tour.date)
            guard let year = comps.year, let month = comps.month else { continue }
            if let last = groups.last, last.year == year, last.month == month {
                groups[groups.count - 1].tours.append(tour)
            } else {
                groups.append(MonthGroup(year: year, month: month, tours: [tour]))
            }
        }
        return groups
    }

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
                        ForEach(monthGroups) { group in
                            Section {
                                ForEach(group.tours) { tour in
                                    Button {
                                        selectedTour = tour
                                    } label: {
                                        tourRow(tour)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .onDelete { offsets in delete(group.tours, at: offsets) }
                            } header: {
                                HStack {
                                    Text(group.title)
                                    Spacer()
                                    Text("\(String(format: "%.1f", group.totalKm)) km")
                                }
                            }
                        }
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
        HStack(spacing: 12) {
            TourThumbnailView(tour: tour, cache: snapshotCache)
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.dateFormat.format(tour.date))
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 12) {
                    statLabel(systemImage: "ruler", text: "\(String(format: "%.1f", tour.distanceKm)) km")
                    statLabel(systemImage: "clock", text: formattedTourDuration(tour.duration))
                    statLabel(systemImage: "speedometer", text: "\(String(format: "%.1f", tour.averageSpeedKmh)) km/h")
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func statLabel(systemImage: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func delete(_ groupTours: [DrivenTour], at offsets: IndexSet) {
        let idsToDelete = Set(offsets.map { groupTours[$0].id })
        for tour in tours where idsToDelete.contains(tour.id) {
            store.delete(tour)
            snapshotCache.delete(for: tour.id)
        }
        tours.removeAll { idsToDelete.contains($0.id) }
    }

    @ViewBuilder
    private func tourDetail(_ tour: DrivenTour) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                let coordinates = tour.clCoordinates
                if coordinates.count >= 2 {
                    Map(initialPosition: .region(tour.region())) {
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
            .navigationTitle(Self.dateFormat.format(tour.date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { selectedTour = nil }
                }
                if tour.clCoordinates.count >= 2 {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            exportTour(tour)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Tour exportieren")
                    }
                }
            }
            .sheet(item: $exportFile) { file in
                ActivityView(activityItems: [file.url])
            }
        }
    }

    private func exportTour(_ tour: DrivenTour) {
        let name = "RadFährte Tour \(Self.dateFormat.format(tour.date))"
        guard let url = GPXWriter.writeTemporaryFile(name: name, lines: [tour.clCoordinates]) else { return }
        exportFile = GPXExportFile(url: url)
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
}

/// Kleines Kartenbild mit eingezeichneter Route für eine `tourRow` - lädt asynchron aus dem
/// `TourMapSnapshotCache` (Cache-Treffer oder frische Generierung), zeigt bis dahin eine leere
/// abgerundete Fläche.
private struct TourThumbnailView: View {
    let tour: DrivenTour
    let cache: TourMapSnapshotCache

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(width: 48, height: 48)
        .task(id: tour.id) {
            image = await cache.image(for: tour)
        }
    }
}

#Preview {
    HistoryView(store: DrivenTourStore(), refreshTrigger: 0)
}
