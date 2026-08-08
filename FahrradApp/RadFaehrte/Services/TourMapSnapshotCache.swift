//
//  TourMapSnapshotCache.swift
//  RadFaehrte
//

import MapKit
import UIKit

/// Erzeugt und cached kleine Kartenbilder mit eingezeichneter Route für die Verlauf-Liste
/// (`HistoryView`), damit dort nicht bei jedem Erscheinen einer Zeile neu ein
/// `MKMapSnapshotter`-Rendering laufen muss. Ablage als PNG unter
/// `Documents/DrivenTours/Snapshots/<Touren-ID>.png`, analog zu `DrivenTourStore`s JSON-Ablage
/// im übergeordneten Ordner.
final class TourMapSnapshotCache {
    private let directory: URL
    private let renderSize = CGSize(width: 96, height: 96)

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents.appendingPathComponent("DrivenTours/Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Liefert das Vorschaubild für die Tour - aus dem Cache, oder frisch generiert und dabei
    /// gleich gecached.
    func image(for tour: DrivenTour) async -> UIImage? {
        if let cached = UIImage(contentsOfFile: fileURL(for: tour.id).path) {
            return cached
        }
        guard let generated = await generate(for: tour) else { return nil }
        try? generated.pngData()?.write(to: fileURL(for: tour.id))
        return generated
    }

    func delete(for id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    private func generate(for tour: DrivenTour) async -> UIImage? {
        let coordinates = tour.clCoordinates
        guard coordinates.count >= 2 else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = tour.region(padding: 1.5)
        options.size = renderSize
        options.scale = 2
        options.showsBuildings = false

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let renderer = UIGraphicsImageRenderer(size: renderSize)
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)

            let path = UIBezierPath()
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            for (index, coordinate) in coordinates.enumerated() {
                let point = snapshot.point(for: coordinate)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }

            // Weißer Rand unter der blauen Linie sorgt für Lesbarkeit über beliebigem
            // Kartenuntergrund (Straßen, Wasser, Grünflächen).
            UIColor.white.setStroke()
            path.lineWidth = 4.5
            path.stroke()

            UIColor.systemBlue.setStroke()
            path.lineWidth = 2.5
            path.stroke()

            drawEndpoint(snapshot.point(for: coordinates[0]))
            drawEndpoint(snapshot.point(for: coordinates[coordinates.count - 1]))
        }
    }

    private func drawEndpoint(_ point: CGPoint) {
        let outerRadius: CGFloat = 4
        let innerRadius: CGFloat = 2.5
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(
            x: point.x - outerRadius, y: point.y - outerRadius,
            width: outerRadius * 2, height: outerRadius * 2
        )).fill()
        UIColor.systemBlue.setFill()
        UIBezierPath(ovalIn: CGRect(
            x: point.x - innerRadius, y: point.y - innerRadius,
            width: innerRadius * 2, height: innerRadius * 2
        )).fill()
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).png")
    }
}
