//
//  LocationSearchViewModel.swift
//  RadFaehrte
//

import Foundation
import MapKit
import Observation

@Observable
final class LocationSearchViewModel: NSObject, MKLocalSearchCompleterDelegate {

    var queryFragment: String = "" {
        didSet {
            completer.queryFragment = queryFragment
        }
    }

    private(set) var results: [MKLocalSearchCompletion] = []

    private let completer: MKLocalSearchCompleter

    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 51.1657, longitude: 10.4515),
            span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
        )
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    /// Engt die Suche auf eine Region um `coordinate` ein, damit z. B. "Nienburger Straße"
    /// bevorzugt in der Nähe des Nutzers statt irgendwo in Deutschland gefunden wird.
    func updateRegion(around coordinate: CLLocationCoordinate2D?, spanDegrees: Double = 1.0) {
        guard let coordinate else { return }
        completer.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: spanDegrees, longitudeDelta: spanDegrees)
        )
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }

    /// Löst einen ausgewählten Vorschlag in eine konkrete Koordinate auf.
    ///
    /// `MKLocalSearch.Request(completion:)` liefert manchmal mehrere `mapItems` zurück, deren
    /// **erster** Treffer nicht der tatsächlich ausgewählten Adresse entspricht (Live-Fund: Auswahl
    /// von "Bückeburger Straße 9" resolvte auf eine andere, parallel liegende Straße). Deshalb wird
    /// bevorzugt der Treffer genommen, dessen Name zum Titel des Vorschlags passt, statt blind den
    /// ersten zu nehmen.
    func resolve(_ completion: MKLocalSearchCompletion) async throws -> CLLocationCoordinate2D {
        let searchRequest = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: searchRequest)
        let response = try await search.start()
        guard !response.mapItems.isEmpty else {
            throw ResolveError.noResult
        }
        let bestMatch = response.mapItems.first { matches($0, completionTitle: completion.title) }
            ?? response.mapItems[0]
        return bestMatch.location.coordinate
    }

    private func matches(_ mapItem: MKMapItem, completionTitle: String) -> Bool {
        guard let name = mapItem.name else { return false }
        return normalize(name) == normalize(completionTitle)
    }

    private func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
            .trimmingCharacters(in: .whitespaces)
    }

    enum ResolveError: Error {
        case noResult
    }
}
