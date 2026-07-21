//
//  GPXParser.swift
//  RadFaehrte
//

import CoreLocation
import Foundation

/// Minimaler GPX-Parser: liest nur Name und Streckenpunkte (`<trkpt>`/`<rtept>`) aus, ignoriert
/// Höhe, Zeitstempel und Wegpunkte (`<wpt>`, das sind POI-Marker, nicht Teil der Strecke).
/// Reicht für "fertige Touren" von Drittanbietern (z. B. Zeitungs-/Vereins-Downloads).
enum GPXParser {
    static func parse(data: Data) -> (name: String?, coordinates: [CLLocationCoordinate2D])? {
        let delegate = Delegate()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = delegate
        guard xmlParser.parse(), !delegate.coordinates.isEmpty else { return nil }
        return (delegate.routeName, delegate.coordinates)
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var coordinates: [CLLocationCoordinate2D] = []
        var routeName: String?
        private var currentElement = ""
        private var nameCharacters = ""
        private var capturedName = false

        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
        ) {
            currentElement = elementName
            switch elementName {
            case "trkpt", "rtept":
                if let latString = attributeDict["lat"], let lonString = attributeDict["lon"],
                   let lat = Double(latString), let lon = Double(lonString) {
                    coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                }
            case "name" where !capturedName:
                nameCharacters = ""
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard currentElement == "name", !capturedName else { return }
            nameCharacters += string
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            guard elementName == "name", !capturedName else { return }
            let trimmed = nameCharacters.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                routeName = trimmed
                capturedName = true
            }
        }
    }
}
