//
//  HowItWorksView.swift
//  RadFaehrte
//

import SwiftUI

/// Kurze Erklärung der Kernfunktionen für Nutzer, die die App zum ersten Mal sehen oder sich
/// nicht mehr an eine Funktion erinnern - über Einstellungen erreichbar statt als erzwungenes
/// Onboarding beim ersten Start.
struct HowItWorksView: View {
    private struct Topic: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let text: String
    }

    private let topics: [Topic] = [
        Topic(
            icon: "magnifyingglass",
            title: "Route suchen",
            text: "Start und Ziel eingeben - RadFährte zeigt dir sowohl offizielle, beschilderte Radrouten in der Nähe als auch eine direkte Fahrrad-Route. Durch die Treffer wischt du einfach durch."
        ),
        Topic(
            icon: "location.north.line.fill",
            title: "Navigation",
            text: "Mit \"Los\" startest du die Navigation. Die Karte folgt automatisch deiner Position und Fahrtrichtung, die bereits gefahrene Strecke wird rot eingezeichnet. Weichst du bei der direkten Route ab, wird automatisch neu berechnet."
        ),
        Topic(
            icon: "hand.tap",
            title: "Steuerung während der Fahrt",
            text: "Oben rechts: Navigation beenden (✕), zwischen 2D- und 3D-Ansicht wechseln, sowie zwischen \"Gehrichtung oben\" und \"Norden oben\" umschalten. Verschiebst oder zoomst du die Karte selbst, pausiert die automatische Verfolgung - ein \"Zentrieren\"-Banner unten bringt dich mit einem Tipp zurück zu deiner Position."
        ),
        Topic(
            icon: "location.fill.viewfinder",
            title: "Bildschirm & Hintergrund",
            text: "Während der Navigation bleibt der Bildschirm an, statt sich automatisch zu sperren. Wechselst du in eine andere App oder sperrst das iPhone manuell, läuft die Standortverfolgung im Hintergrund weiter - ein blaues Symbol oben in der Statusleiste zeigt das an, ein Tipp darauf bringt dich zurück zu RadFährte."
        ),
        Topic(
            icon: "bicycle",
            title: "Eigene Routen",
            text: "Im Tab \"Eigene Routen\" importierst du fertige GPX-Touren (z. B. von einer Zeitung oder einem Verein) und fährst sie direkt los - unabhängig von der normalen Start/Ziel-Suche."
        ),
        Topic(
            icon: "clock.arrow.circlepath",
            title: "Verlauf",
            text: "Nach jeder beendeten Fahrt zeigt ein Abschluss-Fenster Strecke, Dauer und Durchschnittstempo - dort entscheidest du, ob die Tour im Verlauf-Tab gespeichert oder verworfen wird."
        ),
        Topic(
            icon: "arrow.down.circle",
            title: "Offline-Karten",
            text: "Für die \"Direkte Fahrrad-Route\" lassen sich in den Einstellungen Bundesländer herunterladen. Ist eins verfügbar, bevorzugt die App automatisch ruhige Wege und Radwege statt nur der kürzesten Verbindung - auch ganz ohne Internetverbindung. Verläuft neben der Straße ein baulich getrennter Radweg, wird die Linie dafür leicht seitlich versetzt dargestellt statt auf der Straßenmitte. Die Navigations-Kopfzeile zeigt dabei echte Anweisungen mit Straßennamen und geschätzter Abbiege-Richtung, keine reine \"Route folgen\"-Anzeige mehr."
        )
    ]

    var body: some View {
        Form {
            ForEach(topics) { topic in
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(topic.title)
                                .font(.headline)
                            Text(topic.text)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: topic.icon)
                            .foregroundStyle(Color(red: 0.110, green: 0.290, blue: 0.341))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Wie funktioniert's?")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        HowItWorksView()
    }
}
