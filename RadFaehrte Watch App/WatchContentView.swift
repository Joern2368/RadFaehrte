//
//  WatchContentView.swift
//  RadFaehrte Watch App
//

import MapKit
import SwiftUI

struct WatchContentView: View {
    @StateObject private var session = WatchSessionManager.shared

    var body: some View {
        if session.state.isNavigating {
            VStack(spacing: 4) {
                instructionRow
                if !session.routeLines.isEmpty {
                    routeMap
                }
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "bicycle")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Keine Navigation aktiv")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    /// Kompakte Kopfzeile (Icon + Anweisung + Entfernung) - ersetzt die frühere zentrierte,
    /// großflächige Anzeige, seit darunter die Karte (`routeMap`) den meisten Platz beansprucht.
    private var instructionRow: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: instructionIcon)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(session.state.instructionText)
                    .font(.caption2)
                    .lineLimit(1)
                Text(session.state.distanceText)
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }

    /// Routen-Linie + aktuelle Position, per `WatchSessionManager.routeLines`/`session.state.
    /// currentCoordinate` vom iPhone übertragen (s. dort). Kamera folgt der Position eng gezoomt
    /// und in Fahrtrichtung gedreht (Heading-up, wie beim iPhone) - auf dem winzigen Display
    /// bringt eine Gesamtübersicht der Route wenig, der nähere Streckenverlauf (nächste
    /// Abbiegung) ist relevanter.
    ///
    /// `cameraPosition` bewusst als reiner Lese-Binding direkt aus `session.state` berechnet statt
    /// über ein separates `@State` + `.onChange` nachgeführt: Ein erster Versuch mit `@State` +
    /// `.onChange(of: session.state)` aktualisierte die Karte beim Live-Test nicht sichtbar (Punkt
    /// blieb stehen, keine Rotation) - vermutlich, weil `.onChange` in diesem Zusammenspiel mit
    /// `@StateObject`/`@Published` nicht zuverlässig auslöste. Der direkte Binding-Zugriff liest
    /// bei jeder Neuzeichnung (durch `@Published state`-Änderungen ohnehin ausgelöst) den
    /// aktuellen Stand frisch - keine zusätzliche Synchronisation nötig.
    private var routeMap: some View {
        Map(position: cameraPosition) {
            ForEach(Array(session.routeLines.enumerated()), id: \.offset) { _, line in
                MapPolyline(coordinates: line)
                    .stroke(.blue, lineWidth: 3)
            }
            if let coordinate = session.state.currentCoordinate {
                Annotation("", coordinate: coordinate) {
                    Circle()
                        .fill(.blue)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
    }

    private var cameraPosition: Binding<MapCameraPosition> {
        Binding(
            get: {
                guard let coordinate = session.state.currentCoordinate else { return .automatic }
                return .camera(MapCamera(
                    centerCoordinate: coordinate, distance: 400, heading: session.state.heading ?? 0, pitch: 0
                ))
            },
            set: { _ in }
        )
    }

    private var instructionIcon: String {
        switch session.state.direction {
        case .straight: return "arrow.up"
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        }
    }
}

#Preview {
    WatchContentView()
}
