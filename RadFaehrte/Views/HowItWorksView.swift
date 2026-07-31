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
            text: "Start und Ziel eingeben - RadFährte zeigt dir sowohl offizielle, beschilderte Radrouten in der Nähe als auch eine direkte Fahrrad-Route. Durch die Treffer wischt du einfach durch. Zusätzlich sucht RadFährte im Hintergrund nach einer Kombination mehrerer Fernwege, die an Anschlussstellen ineinander übergehen (z. B. Weser-Radweg → Aller-Radweg → Leine-Heide-Radweg für Bremen → Hannover) - erkennbar an den durch \"→\" getrennten Routennamen in der Ergebniszeile. Das kann auch dann noch eine sinnvolle Alternative sein, wenn schon durchgehende Einzelrouten gefunden wurden, und erscheint als eigene Sektion unterhalb, sobald diese Suche fertig ist - sie kann einige Sekunden dauern, bei größerer Entfernung zwischen Start und Ziel auch spürbar länger, da dafür mehrere mögliche Streckenkombinationen durchsucht werden. Über das kleine Listen-Symbol neben einer Kombination öffnet sich eine Übersicht aller Etappen mit ihrer jeweiligen Länge, falls der Titel bei vielen Etappen abgeschnitten ist. Findet RadFährte mehrere solcher Kombinationen, kannst du auch hier durch die Alternativen wischen, genau wie bei einzelnen Radrouten. Liegt dabei ein bekannter internationaler Fernweg (EuroVelo, D-Route) in der Nähe von Start oder Ziel, erscheint er als ganz normal wählbarer Treffer, auch wenn er an dieser Stelle nicht durchgehend kartiert ist - statt einer Streckenlänge zeigt er dann \"Kartendaten hier lückenhaft\" an, lässt sich aber trotzdem antippen und nutzen. Die Adressvorschläge sind auf deine Nähe eingegrenzt - suchst du z. B. von unterwegs eine Adresse in einer weit entfernten Stadt (etwa zu Hause), wird sie manchmal nicht vorgeschlagen. Ergänze in dem Fall den Ort in der Sucheingabe (z. B. \"Bückeburger Straße, Bremen\")."
        ),
        Topic(
            icon: "location.north.line.fill",
            title: "Navigation",
            text: "Mit \"Los\" startest du die Navigation. Die Karte folgt automatisch deiner Position und Fahrtrichtung, die bereits gefahrene Strecke wird rot eingezeichnet. Weichst du bei der direkten Route ab, wird automatisch neu berechnet."
        ),
        Topic(
            icon: "square.grid.3x2",
            title: "Statistik-Leiste anpassen",
            text: "Die Zeile unter der Anweisung während der Navigation zeigt 3 oder 6 frei wählbare Werte - z. B. aktuelles oder maximales Tempo, zurückgelegte Strecke, Entfernung zum Ziel, aktuelle Höhe, Höhenmeter berg­auf/-ab, Durchschnittstempo, Fahrtzeit, reine Fahrzeit ohne Stopps, geschätzte Ankunftszeit oder Restzeit bis zum Ziel. In den Einstellungen unter \"Navigation\" > \"Statistik-Leiste\" stellst du Anzahl und Belegung jedes einzelnen Feldes ein."
        ),
        Topic(
            icon: "hand.tap",
            title: "Steuerung während der Fahrt",
            text: "Oben links: Navigation beenden (Pause-Symbol, mit Sicherheitsabfrage). Oben rechts: zwischen 2D- und 3D-Ansicht wechseln, zwischen \"Gehrichtung oben\" und \"Norden oben\" umschalten, sowie über das Zahnrad-Symbol die wichtigsten Einstellungen (Tempo, Sichtweite, Kartenstil, Statistik-Leiste) direkt während der Fahrt ändern, ohne die Navigation zu verlassen. Den Anweisungs-Banner samt Statistik-Leiste blendest du per Wisch nach oben aus - dann geht die Karte bis an den Bildschirmrand; ein kleiner Griff oben holt ihn per Tipp oder Wisch nach unten zurück. Verschiebst oder zoomst du die Karte selbst, pausiert die automatische Verfolgung - ein \"Zentrieren\"-Banner unten bringt dich mit einem Tipp zurück zu deiner Position."
        ),
        Topic(
            icon: "applewatch",
            title: "Apple Watch",
            text: "Ist eine Apple Watch mit installierter RadFährte-Watch-App gekoppelt, zeigt sie während der Navigation automatisch die aktuelle Anweisung samt Entfernung am Handgelenk an - bei der \"Direkten Fahrrad-Route\" kurz vor einer Abbiegung zusätzlich mit einer kurzen Vibration. Bei kuratierten Radrouten ohne Schritt-für-Schritt-Anweisungen zeigt die Watch stattdessen den Routennamen."
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
            text: "Für die \"Direkte Fahrrad-Route\" lassen sich in den Einstellungen unter \"Offline-Karten Deutschland\" Bundesländer und unter \"Offline-Karten Europa\" weitere Länder (bisher Niederlande, Polen und Schweden) herunterladen. Ist eine Region verfügbar, bevorzugt die App dort automatisch ruhige Wege und Radwege statt nur der kürzesten Verbindung - auch ganz ohne Internetverbindung. Verläuft neben der Straße ein baulich getrennter Radweg, wird die Linie dafür leicht seitlich versetzt dargestellt statt auf der Straßenmitte. Die Navigations-Kopfzeile zeigt dabei echte Anweisungen mit Straßennamen und geschätzter Abbiege-Richtung, keine reine \"Route folgen\"-Anzeige mehr. Das funktioniert innerhalb einer heruntergeladenen Region - liegen Start und Ziel in zwei unterschiedlichen heruntergeladenen Regionen (z. B. eine Fahrt von einem Bundesland ins Nachbar-Bundesland), sucht die App automatisch den gemeinsamen Grenzübergang und verbindet beide Abschnitte weiterhin offline. Nur wenn eine der beiden Regionen gar nicht heruntergeladen ist oder kein sinnvoller Grenzübergang gefunden wird, berechnet die App die Strecke stattdessen online, wofür dann eine Internetverbindung nötig ist. Bei großen Ländern kann vor allem die erste Berechnung nach dem Öffnen der App spürbar länger dauern als bei einem kleinen Bundesland (die Straßendaten werden einmal geladen) - kein Fehler, einfach kurz warten. Danach ist es in derselben Sitzung wieder schnell, da die geladenen Daten zwischengespeichert werden."
        ),
        Topic(
            icon: "circle.lefthalf.filled",
            title: "Erscheinungsbild",
            text: "In den Einstellungen stellst du zwischen \"System\", \"Hell\" und \"Dunkel\" um. \"System\" folgt automatisch der Geräteeinstellung (z. B. abends automatisch dunkel), die anderen beiden erzwingen unabhängig davon immer dieselbe Darstellung."
        ),
        Topic(
            icon: "map",
            title: "Kartenansicht anpassen",
            text: "In den Einstellungen unter \"Karte\" wählst du den Kartenstil (Standard, Satellit oder Hybrid) sowie die Ausrichtung, mit der eine neue Navigation startet (Fahrtrichtung oben oder Norden oben) - während der Fahrt bleibt der Umschalt-Button dafür wie gewohnt verfügbar."
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
