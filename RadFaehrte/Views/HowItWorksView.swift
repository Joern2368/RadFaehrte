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
            text: "Start und Ziel eingeben - RadFährte zeigt dir sowohl offizielle, beschilderte Radrouten in der Nähe als auch eine direkte Fahrrad-Route. Durch die Treffer wischt du einfach durch. Zusätzlich sucht RadFährte im Hintergrund nach einer Kombination mehrerer Fernwege, die an Anschlussstellen ineinander übergehen (z. B. Weser-Radweg → Aller-Radweg → Leine-Heide-Radweg für Bremen → Hannover) - erkennbar an den durch \"→\" getrennten Routennamen in der Ergebniszeile. Das kann auch dann noch eine sinnvolle Alternative sein, wenn schon durchgehende Einzelrouten gefunden wurden, und erscheint als eigene Sektion unterhalb, sobald diese Suche fertig ist - sie kann einige Sekunden dauern, bei größerer Entfernung zwischen Start und Ziel auch spürbar länger, da dafür mehrere mögliche Streckenkombinationen durchsucht werden. Über das kleine Listen-Symbol neben einer Kombination öffnet sich eine Übersicht aller Etappen mit ihrer jeweiligen Länge, falls der Titel bei vielen Etappen abgeschnitten ist, sowie - sofern der Wege-Graph der betroffenen Region(en) heruntergeladen ist - darunter die zusammengeführten Straßennamen/Abbiege-Hinweise über alle Etappen hinweg. Findet RadFährte mehrere solcher Kombinationen, kannst du auch hier durch die Alternativen wischen, genau wie bei einzelnen Radrouten. Liegt dabei ein bekannter internationaler Fernweg (EuroVelo, D-Route) in der Nähe von Start oder Ziel, erscheint er als ganz normal wählbarer Treffer, auch wenn er an dieser Stelle nicht durchgehend kartiert ist - statt einer Streckenlänge zeigt er dann \"Kartendaten hier lückenhaft\" an, lässt sich aber trotzdem antippen und nutzen. Die Adressvorschläge sind auf deine Nähe eingegrenzt - suchst du z. B. von unterwegs eine Adresse in einer weit entfernten Stadt (etwa zu Hause), wird sie manchmal nicht vorgeschlagen. Ergänze in dem Fall den Ort in der Sucheingabe (z. B. \"Bückeburger Straße, Bremen\"). Statt einer Adresse tippst du im Ziel-Feld auch auf \"Auf Karte wählen\" und setzt dein Ziel direkt per Fingertipp auf der Karte - praktisch, wenn du die genaue Adresse nicht kennst, aber die Stelle auf der Karte siehst. Tippst du in ein leeres Ziel-Feld, erscheinen dort - wie bei Google Maps - zunächst deine Favoriten (\"Zuhause\"/\"Arbeit\"/eigene) sowie zuletzt gesuchte Ziele, beide direkt antippbar ohne erneute Adresssuche; sobald du zu tippen beginnst, weichen sie den passenden Adressvorschlägen. Im Start-Feld erscheinen sie bewusst nicht - dort ist meist ohnehin \"Aktuelle Position\" die richtige Wahl. Ist bei einem ausgewählten Ort (Start oder Ziel) das Stern-Symbol neben dem Suchfeld zu sehen, lässt er sich darüber als \"Zuhause\", \"Arbeit\" oder mit einem eigenen Namen als Favorit merken; verwaltet (angeschaut, gelöscht) werden gespeicherte Favoriten unter Einstellungen → Favoriten, einzelne \"Zuletzt gesucht\"-Einträge über das kleine Kreuz daneben. Über das kleine Listen-Symbol neben einem einzelnen Treffer (keine Kombination) öffnet sich - sofern der Wege-Graph der betroffenen Region unter \"Offline-Karten\" heruntergeladen ist - eine Vorschau der Straßennamen und Abbiege-Hinweise entlang der Strecke, unabhängig davon, ob der Treffer gerade ausgewählt ist. Liegt zwischen Start und Ziel eine echte Lücke in der Streckengeometrie selbst (derselbe Grund wie bei \"Kartendaten hier lückenhaft\" oben), zeigt diese Vorschau trotzdem die Straßennamen auf beiden Seiten bis zur Lücke an, mit einem Hinweis auf deren ungefähre Größe dazwischen, statt gar nichts anzuzeigen."
        ),
        Topic(
            icon: "location.north.line.fill",
            title: "Navigation",
            text: "Mit \"Los\" startest du die Navigation. Die Karte folgt automatisch deiner Position und Fahrtrichtung, die bereits gefahrene Strecke wird rot eingezeichnet. Weichst du bei der direkten Route ab, wird automatisch neu berechnet. Liegt für einen ausgewählten einzelnen Treffer oder eine kombinierte Kette mehrerer Fernwege der Wege-Graph der betroffenen Region(en) als Download vor, zeigt die Kopfzeile auch dort echte Abbiege-Hinweise mit Straßennamen statt nur \"Route folgen\" - genau wie bei der direkten Route, nur ohne deren automatische Neuberechnung bei Abweichung, da du hier bewusst der offiziellen Strecke folgen willst. Kurz bevor eine dieser Abbiegungen ansteht, liest RadFährte sie zusätzlich laut vor - lässt sich in den Einstellungen unter \"Navigation\" abschalten."
        ),
        Topic(
            icon: "square.and.arrow.up",
            title: "Route exportieren",
            text: "Über das Teilen-Symbol neben \"Los\" exportierst du die gerade gewählte Route (Einzeltreffer, Kombination mehrerer Fernwege oder Direkte Fahrrad-Route) als .gpx-Datei - z. B. um sie auf einen Fahrradcomputer zu übertragen oder an jemanden zu schicken, der sie mit einer anderen App öffnet. Bei einem Einzeltreffer wird dabei nur der gesuchte Abschnitt zwischen Start und Ziel exportiert, nicht die komplette Fernroute."
        ),
        Topic(
            icon: "square.grid.3x2",
            title: "Statistik-Leiste anpassen",
            text: "Die Zeile unter der Anweisung während der Navigation zeigt 3 oder 6 frei wählbare Werte - z. B. aktuelles oder maximales Tempo, zurückgelegte Strecke, Entfernung zum Ziel, aktuelle Höhe, Höhenmeter berg­auf/-ab, Durchschnittstempo, Fahrtzeit, reine Fahrzeit ohne Stopps, geschätzte Ankunftszeit oder Restzeit bis zum Ziel. In den Einstellungen unter \"Navigation\" > \"Statistik-Leiste\" stellst du Anzahl und Belegung jedes einzelnen Feldes ein."
        ),
        Topic(
            icon: "hand.tap",
            title: "Steuerung während der Fahrt",
            text: "Oben links: Navigation beenden (Pause-Symbol, mit Sicherheitsabfrage). Oben rechts: zwischen 2D- und 3D-Ansicht wechseln, zwischen \"Gehrichtung oben\" und \"Norden oben\" umschalten, sowie über das Zahnrad-Symbol die wichtigsten Einstellungen (Tempo, Sichtweite, Kartenstil, Statistik-Leiste, Sprachausgabe) direkt während der Fahrt ändern, ohne die Navigation zu verlassen. Den Anweisungs-Banner samt Statistik-Leiste blendest du per Wisch nach oben aus - dann geht die Karte bis an den Bildschirmrand; ein kleiner Griff oben holt ihn per Tipp oder Wisch nach unten zurück. Verschiebst oder zoomst du die Karte selbst, pausiert die automatische Verfolgung - ein \"Zentrieren\"-Banner unten bringt dich mit einem Tipp zurück zu deiner Position."
        ),
        Topic(
            icon: "applewatch",
            title: "Apple Watch",
            text: "Ist eine Apple Watch mit installierter RadFährte-Watch-App gekoppelt, zeigt sie während der Navigation automatisch die aktuelle Anweisung samt Entfernung am Handgelenk an - bei der \"Direkten Fahrrad-Route\" kurz vor einer Abbiegung zusätzlich mit spürbarer, für Links-/Rechtsabbiegungen unterschiedlicher Vibration. Bei kuratierten Radrouten ohne Schritt-für-Schritt-Anweisungen zeigt die Watch stattdessen den Routennamen. Darunter zeigt eine kleine, eng um die aktuelle Position gezoomte Karte den nahen Streckenverlauf, damit du die Route auch am Handgelenk visuell verfolgen kannst. Öffnest du die Watch-App während einer laufenden Navigation zusätzlich selbst auf der Uhr, startet dort automatisch ein Radfahr-Training (dafür fragt sie beim ersten Mal um Health-Zugriff) - das hält die Watch-App zuverlässig aktiv, statt dass sie im Hintergrund pausiert. Ohne geöffnete Watch-App bleibt die Uhr bewusst inaktiv, um Akku zu sparen. Endet die Navigation, endet auch das Training automatisch."
        ),
        Topic(
            icon: "location.fill.viewfinder",
            title: "Bildschirm & Hintergrund",
            text: "Während der Navigation bleibt der Bildschirm an, statt sich automatisch zu sperren. Wechselst du in eine andere App oder sperrst das iPhone manuell, läuft die Standortverfolgung im Hintergrund weiter - ein blaues Symbol oben in der Statusleiste zeigt das an, ein Tipp darauf bringt dich zurück zu RadFährte."
        ),
        Topic(
            icon: "bicycle",
            title: "Eigene Routen",
            text: "Im Tab \"Eigene Routen\" importierst du fertige GPX-Touren (z. B. von einer Zeitung oder einem Verein) und fährst sie direkt los - unabhängig von der normalen Start/Ziel-Suche. Unter dem Namen jeder Tour steht neben der Streckenlänge auch eine grobe Schätzung der Fahrzeit, basierend auf der unter \"Einstellungen > Navigation\" hinterlegten Wunschgeschwindigkeit."
        ),
        Topic(
            icon: "clock.arrow.circlepath",
            title: "Verlauf",
            text: "Nach jeder beendeten Fahrt zeigt ein Abschluss-Fenster Strecke, Dauer und Durchschnittstempo - dort entscheidest du, ob die Tour im Verlauf-Tab gespeichert oder verworfen wird. In der Detailansicht einer gespeicherten Fahrt lässt sich die aufgezeichnete Strecke über das Teilen-Symbol ebenfalls als .gpx-Datei exportieren. Unabhängig von dieser Verlauf-Entscheidung landet jede ausreichend lange Fahrt automatisch als Radfahr-Training in Apple Health (einmalige Berechtigungsanfrage beim ersten Mal) und zählt zu deinen Aktivitätsringen - auch ganz ohne Apple Watch."
        ),
        Topic(
            icon: "arrow.down.circle",
            title: "Offline-Karten",
            text: "Für die \"Direkte Fahrrad-Route\" lassen sich in den Einstellungen unter \"Offline-Karten Deutschland\" Bundesländer und unter \"Offline-Karten Europa\" weitere Länder (bisher Niederlande, Polen, Schweden, Dänemark, Belgien, Luxemburg, die Schweiz, Frankreich, Österreich, Tschechien, die Slowakei, Albanien, Italien, Spanien, Portugal, Malta, Andorra, Liechtenstein, Monaco, Nordmazedonien, Kosovo, Montenegro, Bosnien und Herzegowina, Serbien, Kroatien, Slowenien, Bulgarien, Ungarn und Rumänien) herunterladen - Frankreich, Italien und Spanien sind als einzelne Datei zu groß und deshalb als eigene Einträge in dieser Liste nach Regionen aufgeteilt (analog zu den deutschen Bundesländern). Ist eine Region verfügbar, bevorzugt die App dort automatisch ruhige Wege und Radwege statt nur der kürzesten Verbindung - auch ganz ohne Internetverbindung. Verläuft neben der Straße ein baulich getrennter Radweg, wird die Linie dafür leicht seitlich versetzt dargestellt statt auf der Straßenmitte. Die Navigations-Kopfzeile zeigt dabei echte Anweisungen mit Straßennamen und geschätzter Abbiege-Richtung, keine reine \"Route folgen\"-Anzeige mehr. Das funktioniert innerhalb einer heruntergeladenen Region - liegen Start und Ziel in zwei unterschiedlichen heruntergeladenen Regionen (z. B. eine Fahrt von einem Bundesland ins Nachbar-Bundesland), sucht die App automatisch den gemeinsamen Grenzübergang und verbindet beide Abschnitte weiterhin offline. Das klappt auch, wenn die Strecke dabei noch eine dritte heruntergeladene Region mittig durchquert, ohne dass Start oder Ziel selbst darin liegen. Nur wenn eine beteiligte Region gar nicht heruntergeladen ist oder kein sinnvoller Grenzübergang gefunden wird, berechnet die App die Strecke stattdessen online, wofür dann eine Internetverbindung nötig ist. Auch bei großen Ländern ist selbst die erste Berechnung nach dem Öffnen der App zügig, da die Straßendaten nicht komplett geladen werden, sondern die App aus der heruntergeladenen Datei immer nur den tatsächlich benötigten Ausschnitt liest."
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
        ),
        Topic(
            icon: "list.bullet",
            title: "Alle Routen",
            text: "In den Einstellungen unter \"Alle Routen\" durchsuchst du den kompletten Bestand an bekannten Radrouten - z. B. um zu prüfen, ob ein dir bekannter lokaler Radweg in der App hinterlegt ist. Zwei Sucharten stehen zur Wahl: \"In der Nähe\" zeigt Routen im Umkreis eines eingegebenen Orts oder deiner aktuellen Position, \"Nach Name\" findet Routen anhand eines (auch nur teilweise eingegebenen) Namens. Das Badge neben jedem Treffer zeigt, ob es sich um eine internationale, nationale, regionale oder lokale Route handelt. Ein Tipp auf einen Treffer zeigt ihren Streckenverlauf auf der Karte, darunter Streckenlänge und eine grobe Schätzung der Fahrzeit (basierend auf der unter \"Einstellungen > Navigation\" hinterlegten Wunschgeschwindigkeit)."
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
