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
            text: "Start und Ziel eingeben - RadFährte zeigt offizielle Radrouten in der Nähe sowie eine direkte Fahrrad-Route, durch die Treffer wischst du durch. Ist erst der Start gesetzt, erscheint darunter schon eine Vorschau \"Radrouten in der Nähe\", sortiert nach Anfahrt (kürzeste zuerst, kurze Stadtradwege unter 20 km werden dabei nicht berücksichtigt). Im Hintergrund sucht die App zusätzlich nach Kombinationen mehrerer Fernwege (erkennbar an \"→\" im Namen), die als eigene Sektion erscheinen, sobald die Suche fertig ist. Über das Listen-Symbol neben einem Treffer siehst du Etappen bzw. Straßennamen entlang der Strecke, sofern der Wege-Graph der Region heruntergeladen ist. Ziel lässt sich auch per Fingertipp auf der Karte wählen; im leeren Ziel-Feld erscheinen Favoriten und zuletzt gesuchte Orte. Ein Stern-Symbol beim gewählten Ort speichert ihn als Favorit (\"Zuhause\", \"Arbeit\" oder eigener Name). Über dem Karten-Ausschnitt sitzt ein schmaler Griff - antippen oder nach oben ziehen blendet Suchfelder und Routenvorschläge aus, sodass die Karte den ganzen Bildschirm füllt; ein Griff über der dann vollflächigen Karte holt sie per Antippen oder Wisch nach unten zurück."
        ),
        Topic(
            icon: "location.north.line.fill",
            title: "Navigation",
            text: "Mit \"Los\" startest du die Navigation. Die Karte folgt deiner Position und Fahrtrichtung, die gefahrene Strecke wird rot eingezeichnet. Bei der direkten Route wird bei Abweichung automatisch neu berechnet; bei kuratierten Radrouten mit heruntergeladenem Wege-Graph zeigt die Kopfzeile ebenfalls Abbiege-Hinweise mit Straßennamen statt nur \"Route folgen\", allerdings ohne automatische Neuberechnung - \"Route folgen\" bedeutet dort schlicht, dass der aktuelle Wegabschnitt in den Kartendaten keinen Namen hat. Führt eine graue \"Anfahrt\"-Linie erst zum Beginn der kuratierten Route, zeigt die Kopfzeile auch dort schon echte Abbiege-Hinweise mit Straßennamen und wechselt automatisch, sobald du die eigentliche Route erreichst. Kurz vor einer Abbiegung liest die App den Hinweis zusätzlich laut vor - abschaltbar unter Einstellungen > Navigation."
        ),
        Topic(
            icon: "square.and.arrow.up",
            title: "Route exportieren",
            text: "Über das Teilen-Symbol neben \"Los\" exportierst du die aktuell gewählte Route als .gpx-Datei, z. B. für einen Fahrradcomputer oder eine andere App. Bei Einzeltreffern wird nur der gesuchte Abschnitt exportiert, nicht die komplette Fernroute."
        ),
        Topic(
            icon: "square.grid.3x2",
            title: "Statistik-Leiste anpassen",
            text: "Die Zeile unter der Anweisung während der Navigation zeigt 3 oder 6 frei wählbare Werte, z. B. Tempo, Strecke, Höhenmeter, Fahrzeit, Ankunftszeit, Fortschritt in %, Fahrtrichtung, Akkustand, Uhrzeit oder Sonnenuntergangszeit. Anzahl und Belegung stellst du unter Einstellungen > Navigation > Statistik-Leiste ein."
        ),
        Topic(
            icon: "hand.tap",
            title: "Steuerung während der Fahrt",
            text: "Oben links beendest du die Navigation (mit Sicherheitsabfrage), oben rechts wechselst du zwischen 2D/3D-Ansicht und \"Gehrichtung oben\"/\"Norden oben\" und öffnest über das Zahnrad die wichtigsten Einstellungen direkt während der Fahrt. Den Anweisungs-Banner blendest du per Wisch nach oben aus; ein kleiner Griff holt ihn zurück. Verschiebst du die Karte selbst, pausiert die automatische Verfolgung - ein \"Zentrieren\"-Banner bringt dich zurück."
        ),
        Topic(
            icon: "applewatch",
            title: "Apple Watch",
            text: "Eine gekoppelte Apple Watch mit installierter RadFährte-App zeigt während der Navigation die aktuelle Anweisung samt Entfernung sowie eine kleine Karte des nahen Streckenverlaufs am Handgelenk, bei der direkten Route zusätzlich mit Vibration vor Abbiegungen. Öffnest du die Watch-App während der Fahrt selbst auf der Uhr, startet automatisch ein Radfahr-Training, das sie aktiv hält; ohne geöffnete App bleibt die Uhr inaktiv, um Akku zu sparen."
        ),
        Topic(
            icon: "location.fill.viewfinder",
            title: "Bildschirm & Hintergrund",
            text: "Während der Navigation bleibt der Bildschirm an. Wechselst du in eine andere App oder sperrst das iPhone, läuft die Standortverfolgung im Hintergrund weiter - ein blaues Symbol in der Statusleiste zeigt das an und bringt dich per Tipp zurück."
        ),
        Topic(
            icon: "bicycle",
            title: "Eigene Routen",
            text: "Im Tab \"Eigene Routen\" importierst du fertige GPX-Touren (z. B. von einem Verein) und fährst sie direkt los, unabhängig von der Start/Ziel-Suche. Neben der Streckenlänge zeigt die App eine grobe Fahrzeit-Schätzung basierend auf deiner unter Einstellungen > Navigation hinterlegten Wunschgeschwindigkeit."
        ),
        Topic(
            icon: "clock.arrow.circlepath",
            title: "Verlauf",
            text: "Nach jeder Fahrt zeigt ein Abschluss-Fenster Strecke, Dauer und Durchschnittstempo - du entscheidest, ob die Tour im Verlauf-Tab gespeichert wird. Gespeicherte Touren lassen sich dort umbenennen (nach links wischen oder Stift-Symbol in der Detailansicht), erneut starten (Starten-Button in der Liste bzw. Play-Symbol in der Detailansicht) und als .gpx exportieren. Unabhängig davon landet jede ausreichend lange Fahrt automatisch als Radfahr-Training in Apple Health und zählt zu deinen Aktivitätsringen."
        ),
        Topic(
            icon: "arrow.down.circle",
            title: "Offline-Karten",
            text: "In den Einstellungen unter \"Offline-Karten\" lädst du deutsche Bundesländer sowie zahlreiche europäische Länder für die direkte Fahrrad-Route herunter. In heruntergeladenen Regionen bevorzugt die App automatisch ruhige Wege und Radwege statt nur der kürzesten Verbindung, zeigt echte Abbiege-Hinweise mit Straßennamen und funktioniert komplett offline - auch über mehrere heruntergeladene Regionen hinweg, indem sie automatisch den gemeinsamen Grenzübergang findet. Fehlt eine beteiligte Region, berechnet die App die Strecke stattdessen online. Bei der direkten Route lässt sich zusätzlich zur ruhigen Offline-Route per Wischen die Online-Route (meist die direkteste Verbindung, ohne Bevorzugung ruhiger Wege) einblenden und auswählen. Über das Listen-Symbol neben einer Route siehst du außerdem, wie sich die Strecke auf Wegearten verteilt - z. B. wie viele Kilometer auf Radwegen statt auf Landstraßen liegen; bei der Online-Route klappt das nur, wenn für die durchquerte Gegend ebenfalls eine Region heruntergeladen ist."
        ),
        Topic(
            icon: "circle.lefthalf.filled",
            title: "Erscheinungsbild",
            text: "In den Einstellungen stellst du zwischen \"System\", \"Hell\" und \"Dunkel\" um. \"System\" folgt automatisch der Geräteeinstellung, die anderen beiden erzwingen immer dieselbe Darstellung."
        ),
        Topic(
            icon: "map",
            title: "Kartenansicht anpassen",
            text: "In den Einstellungen unter \"Karte\" wählst du den Kartenstil (Standard, Satellit oder Hybrid) sowie die Ausrichtung, mit der eine neue Navigation startet (Fahrtrichtung oben oder Norden oben)."
        ),
        Topic(
            icon: "list.bullet",
            title: "Alle Routen",
            text: "In den Einstellungen unter \"Alle Routen\" durchsuchst du den kompletten Routenbestand - nach Nähe oder nach Namen. Ein Badge zeigt, ob eine Route international, national, regional oder lokal ist; ein Tipp auf einen Treffer zeigt Streckenverlauf, Länge und geschätzte Fahrzeit."
        ),
        Topic(
            icon: "mappin.and.ellipse",
            title: "POIs",
            text: "In den Einstellungen unter \"POIs\" lädst du für dein Bundesland oder ein unterstütztes Land außerhalb Deutschlands Trinkwasserstellen, Cafés, Aussichtspunkte, Fahrrad-Reparaturstationen, Bänke, Biergärten, Toiletten, E-Bike-Ladestationen und Bäckereien aus OpenStreetMap herunter. Unter \"POI-Kategorien\" schaltest du jede dieser neun Kategorien einzeln ein oder aus. Ist eine Region heruntergeladen und der Schalter \"POIs anzeigen\" aktiv, erscheinen die aktivierten Kategorien beim ausreichend nahen Heranzoomen als Pins auf der Karte; ein Tipp auf einen Pin zeigt Kategorie, Name (falls vorhanden) und Koordinate. Während der Navigation erreichst du alles auch über das Zahnrad-Symbol auf der Karte, ohne die Fahrt zu unterbrechen."
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
