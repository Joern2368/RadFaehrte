//
//  GPXWriter.swift
//  RadFaehrte
//

import CoreLocation
import Foundation

/// Schreibt Streckenpunkte als GPX-Track - Gegenstück zu `GPXParser`, der GPX beim Import liest.
/// Bewusst minimal wie der Parser: nur `<trk>`/`<trkseg>`/`<trkpt>` mit Breiten-/Längengrad, keine
/// Höhe/Zeitstempel (die Koordinaten der App - kuratierte Radrouten, Direkte Fahrrad-Route,
/// aufgezeichnete Touren - haben ohnehin keine). Reicht als gültiges GPX 1.1 für Radcomputer
/// (Garmin, Wahoo o. Ä.) und andere Navigations-Apps zum Import.
enum GPXWriter {
    /// Mehrere Linien werden als eigene `<trkseg>` innerhalb eines gemeinsamen `<trk>` geschrieben
    /// (z. B. nicht zusammenhängende Liniensegmente einer Route) statt fälschlich zu einer
    /// durchgehenden Linie verbunden zu werden.
    static func gpxString(name: String, lines: [[CLLocationCoordinate2D]]) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="RadFährte" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><name>\(escaped(name))</name>

        """
        for line in lines where line.count >= 2 {
            xml += "<trkseg>\n"
            for coordinate in line {
                // Bewusst reine String-Interpolation statt `String(format: "%.6f", …)`: Letzteres
                // richtet sich ohne explizite Locale nach der Geräte-Region und würde auf einem
                // deutsch eingestellten iPhone ein Komma statt Punkt als Dezimaltrennzeichen liefern
                // - ungültiges GPX. `Double.description` ist immer punktbasiert.
                xml += "<trkpt lat=\"\(coordinate.latitude)\" lon=\"\(coordinate.longitude)\"/>\n"
            }
            xml += "</trkseg>\n"
        }
        xml += "</trk></gpx>"
        return xml
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static let invalidFilenameCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")

    /// Schreibt die GPX-Daten in eine temporäre Datei (fürs Teilen-Sheet, das eine Datei-URL
    /// braucht) und gibt deren Pfad zurück, oder `nil` bei leerer Geometrie/Schreibfehler.
    static func writeTemporaryFile(name: String, lines: [[CLLocationCoordinate2D]]) -> URL? {
        guard lines.contains(where: { $0.count >= 2 }) else { return nil }
        let sanitizedName = name
            .components(separatedBy: invalidFilenameCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = sanitizedName.isEmpty ? "Route" : sanitizedName
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).gpx")
        do {
            try gpxString(name: sanitizedName, lines: lines).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

/// Kapselt eine erzeugte Export-Datei fürs Teilen-Sheet (`.sheet(item:)` braucht `Identifiable`,
/// eine bloße `URL` ist das nicht).
struct GPXExportFile: Identifiable {
    let id = UUID()
    let url: URL
}
