# Spezifikation: Fahrradnavigations-App (Arbeitstitel)

## Projektübersicht

iOS-App (Swift/SwiftUI), die bei Eingabe von Start und Ziel nicht die kürzeste
Route vorschlägt, sondern prüft, ob ein ausgeschilderter Radfernweg oder eine
thematische Radroute in der Nähe beider Punkte verläuft – und diese als
schönere Alternative anzeigt.

**Auslöser/Beispiel:** Bei der Strecke Bremen–Achim schlagen Google Maps und
Apple Karten die kurze Route über die Landstraße vor, obwohl der Weserradweg
als deutlich schönere (aber längere) Alternative existiert. Diese Lücke soll
die App schließen.

- Zielgruppe: privater Gebrauch des Entwicklers
- Geplante Veröffentlichung: App Store (Entwicklerkonto vorhanden)
- Geografischer Umfang: ganz Deutschland, von Anfang an

## Funktionsumfang MVP (Version 1)

1. **Start/Ziel-Eingabe**
   - Adresssuche mit Autovervollständigung (`MKLocalSearch`)
   - Alternativ: Punkt direkt auf der Karte antippen
2. **Matching-Logik**
   - Ermitteln, welche erfassten Radfernwege/Radrouten in der Nähe von
     sowohl Start- als auch Zielpunkt verlaufen
   - Ergebnisliste mit passenden Routen anzeigen (Name, ggf. ungefähre
     zusätzliche Distanz gegenüber der direkten Strecke)
3. **Routenanzeige**
   - Ausgewählte Route als Linie auf der Karte darstellen (`MapPolyline`)
   - Nur Anzeige zum Nachfahren – **keine** Turn-by-Turn-Navigation

## Explizit nicht im MVP enthalten

Bewusst ausgeklammert, um den Umfang für die erste Version realistisch zu halten:

- Turn-by-Turn-Navigation mit Sprachansage
- Eigener Routing-Algorithmus mit allgemeiner Wegpräferenz (z. B. via
  BRouter-Profil) – MVP matcht nur vorhandene, benannte Routen
- Eigenes Backend/Server – alle Daten werden fest in die App gebündelt

## Datengrundlage

- **Quelle:** OpenStreetMap – Radrouten sind dort als Routen-Relationen
  erfasst (Tag `route=bicycle`, `network=lcn/rcn/ncn/icn`), jeweils mit Namen
  und vollständigem Streckenverlauf. Beispiel: Weserradweg (als Superroute
  mit mehreren Unterrelationen für Teilabschnitte).
- **Umfang:** möglichst breite Erfassung – nicht nur die 12 nationalen
  D-Routen, sondern auch regionale und thematische Routen.
- **Beschaffung:** einmalige Extraktion über die Overpass API
  (deutschlandweite Abfrage aller passenden Routen-Relationen), Export als
  GeoJSON.
- **Aufbereitung:** Geometrie ggf. vereinfachen (z. B. Douglas-Peucker-
  Algorithmus), um Dateigröße zu reduzieren – bei „möglichst vielen" Routen
  kann die Rohdatenmenge sonst groß werden.
- **Einbindung in die App:** als Ressource im App-Bundle (GeoJSON oder in ein
  performanteres Format konvertiert, z. B. vorab in SQLite), keine
  Internetverbindung zur Laufzeit für die Matching-Logik nötig.

## Matching-Algorithmus (grobe Idee, im Detail mit Claude Code auszuarbeiten)

1. Für Start- und Zielpunkt jeweils die kürzeste Distanz zu jeder
   Routen-Geometrie berechnen.
2. Eine Route qualifiziert sich, wenn beide Punkte innerhalb eines
   Schwellenwerts liegen (Größenordnung ggf. experimentell ermitteln,
   z. B. 5–10 km).
3. Treffer sortieren, z. B. nach Gesamtdistanz zu Start + Ziel oder nach
   Länge des nutzbaren Streckenabschnitts.
4. Performance: bei vielen Routen mit vielen Koordinatenpunkten lohnt sich
   eine Bounding-Box-Vorprüfung, bevor die genaue Distanzberechnung läuft.

## Technischer Stack

- Swift / SwiftUI
- MapKit für Kartenanzeige und Routenlinien (kostenlos, nativ, kein API-Key)
- `MKLocalSearch` für die Adresssuche
- Keine Backend-Abhängigkeit

## Offene Punkte für die Umsetzung mit Claude Code

- Genauer Schwellenwert für „in der Nähe" von Start/Ziel
- Umgang mit Superrouten/Unterrelationen (z. B. Weserradweg besteht aus
  mehreren Teilrelationen – müssen ggf. zusammengeführt werden)
- Zielgröße der gebündelten Datendatei im Blick behalten (App-Größe,
  Ladezeit beim Start)
- Wie viele Ergebnisse maximal anzeigen, wenn mehrere Routen passen
