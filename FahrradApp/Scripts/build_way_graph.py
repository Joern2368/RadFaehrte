#!/usr/bin/env python3
"""
Baut einen gewichteten Wege-Graphen aus einem OSM-Bundesland-Extrakt (.osm.pbf) für die
"ruhige Wege"-Offline-Routing-Engine von RadFährte.

Anders als routes.sqlite (kartierte Radfernwege) enthält diese Datenbank den kompletten
lokal befahrbaren Straßen-/Wegegraphen, damit A* eine eigene Route zwischen zwei beliebigen
Punkten berechnen kann - mit einer Gewichtung, die Radwege und ruhige Straßen bevorzugt statt
nur die kürzeste/schnellste Verbindung zu suchen (das leistet bereits Apples MKDirections).

Nutzung:
    Scripts/venv/bin/python3 Scripts/build_way_graph.py Scripts/data/bremen-latest.osm.pbf \
        Scripts/data/bremen_ways.sqlite
"""

import sqlite3
import struct
import sys
from math import asin, cos, radians, sin, sqrt
from pathlib import Path

import osmium

# Gewichtungsfaktor pro `highway`-Tag: multipliziert mit der physischen Distanz (Meter), um die
# "Kosten" einer Kante zu erhalten. <1 = bevorzugt (Radweg/ruhige Straße), >1 = möglichst meiden.
# Werte grob geschätzt nach gängiger deutscher OSM-Kartierung, nicht wissenschaftlich hergeleitet -
# feinjustierbar, sobald echte Testrouten das nahelegen.
HIGHWAY_WEIGHTS = {
    "cycleway": 0.6,
    "living_street": 0.75,
    "residential": 0.85,
    "pedestrian": 0.9,
    "track": 0.9,
    "path": 0.9,
    "service": 1.0,
    "unclassified": 1.0,
    "tertiary": 1.1,
    "tertiary_link": 1.1,
    "secondary": 1.6,
    "secondary_link": 1.6,
    "primary": 2.5,
    "primary_link": 2.5,
    "trunk": 4.0,
    "trunk_link": 4.0,
}

# Für Fahrräder grundsätzlich nicht nutzbar/erlaubt.
EXCLUDED_HIGHWAYS = {
    "motorway", "motorway_link", "construction", "proposed", "steps", "razed", "abandoned",
}

# Fußwege/Treppen, die nicht schon über `is_bikeable()` erfasst sind (kein regulärer Radweg,
# keine Rad-Erlaubnis), aber zu Fuß mit geschobenem Rad passierbar - Nutzer-Wunsch 2026-08-29:
# Unterführung Hemelinger Bahnhof (Bremen) wäre als kurzer Fußweg-Abstecher deutlich kürzer
# gewesen als der ausgeschilderte Radweg-Umweg, den die Offline-Engine mangels Alternative
# vorschlug. `footway`/`path`/`pedestrian` mit `bicycle=designated` zählen bereits über
# `is_bikeable()` als normaler Radweg und werden hier bewusst nicht erneut erfasst (sonst
# doppelte Kanten mit widersprüchlicher Gewichtung), s. `is_pushable()`.
PUSH_HIGHWAYS = {"footway", "path", "pedestrian"}
STEPS_HIGHWAY = "steps"

# Gewichtungsfaktor für Schiebe-Kanten (`is_pushable()`). Beide Werte sind unabhängig von den
# Nutzer-Einstellungsschaltern "Fußwege/Treppen als Abkürzung einbeziehen" (s.
# `BikeRoutingEngine.swift`) - die Kanten liegen immer mit dieser Gewichtung im Graphen, die App
# blendet sie zur Laufzeit per Kategorie ein/aus, statt den Graphen pro Schalterzustand neu bauen
# zu müssen.
#
# `FOOTWAY_PUSH_MULTIPLIER`: ursprünglich 3.5 (deutlich teurer als jeder reguläre
# `HIGHWAY_WEIGHTS`-Wert), damit Fußwege nur bei einer klaren Abkürzung genutzt werden - das
# passte für den auslösenden Fall (Unterführung Hemelinger Bahnhof, ein kurzer, singulärer
# Abstecher), machte aber vielgenutzte, gepflasterte Uferwege (Nutzer-Fund 2026-08-30: Weser-
# Promenade Rot-Weiß-Tennisverein -> Paulaner's im Wehrschloss, u. a. `bicycle=dismount`-Abschnitte
# mit DE:239-Schild) trotz starkem Radverkehr in der Praxis unattraktiv, da sich die Kanten-Kosten
# über einen längeren durchgehenden Fußweg-Abschnitt aufsummierten. Nutzer-Entscheidung: bei
# aktiviertem Schalter sollen Fußwege generell so attraktiv wie ein normaler `path`/`pedestrian`-
# Weg sein (0.9, s. `HIGHWAY_WEIGHTS`) - ein direkt danebenliegender echter Radweg (0.6, ggf. mit
# `CYCLE_INFRA_BONUS`) gewinnt dadurch weiterhin automatisch, ohne dass es dafür einer eigenen
# Sonderregel bedarf. Treppen bleiben bei der ursprünglichen, hohen Gewichtung (auch weiterhin
# separat abschaltbar, Standard aus) - dort ging es nie um "genauso attraktiv wie ein Gehweg",
# sondern weiterhin nur um eine Notlösung bei klarem Vorteil.
FOOTWAY_PUSH_MULTIPLIER = HIGHWAY_WEIGHTS["pedestrian"]
STEPS_PUSH_MULTIPLIER = 6.0

# Eigene Rad-Infrastruktur neben einer größeren Straße (cycleway=track/lane bzw.
# cycleway:left/right/both) senkt die Kosten dieser Straße zusätzlich, auch wenn der
# highway-Typ selbst nicht radfreundlich ist.
CYCLE_INFRA_BONUS = 0.7
CYCLE_INFRA_TAGS = ("cycleway", "cycleway:left", "cycleway:right", "cycleway:both")
CYCLE_INFRA_VALUES = {"track", "lane", "opposite_track", "opposite_lane", "share_busway"}

# Grobe Wegeart-Kategorie pro Kante, unabhängig von `weight_multiplier` (das feiner fürs Routing
# gewichtet) - für die spätere Nutzer-Anzeige "X km Landstraße, Y km Radweg usw." entlang einer
# Route. Bewusst wenige, für Laien verständliche Kategorien statt der vollen OSM-`highway`-Palette.
WAY_CATEGORY_CYCLEWAY = 0
WAY_CATEGORY_QUIET_ROAD = 1
WAY_CATEGORY_MAIN_ROAD = 2
WAY_CATEGORY_UNPAVED = 3
WAY_CATEGORY_OTHER = 4
# Nutzer-Wunsch 2026-08-17: ein Radweg, der direkt neben einer Landstraße verläuft (s.
# `MainRoadIndex`/`NEARBY_MAIN_ROAD_METERS` unten), separat von einem freistehenden Radweg
# (Nebenstraße, freies Feld) ausweisen.
WAY_CATEGORY_CYCLEWAY_NEAR_MAIN_ROAD = 5
# Schiebe-Kanten (s. `is_pushable()`/`PUSH_HIGHWAYS` oben) - Nutzer-Wunsch 2026-08-29, getrennt
# von `WAY_CATEGORY_OTHER` ausgewiesen, damit die Routenanzeige klar macht, wo geschoben statt
# gefahren wird, statt das unter "Sonstiger Weg" zu verstecken. Treppen separat von normalen
# Fußwegen, da spürbar unangenehmer/schwerer (Rad tragen statt nur schieben).
WAY_CATEGORY_PUSH = 6
WAY_CATEGORY_STEPS = 7

WAY_CATEGORY_LABELS = {
    WAY_CATEGORY_CYCLEWAY: "Radweg",
    WAY_CATEGORY_QUIET_ROAD: "Ruhige Straße",
    WAY_CATEGORY_MAIN_ROAD: "Landstraße",
    WAY_CATEGORY_UNPAVED: "Unbefestigter Weg",
    WAY_CATEGORY_OTHER: "Sonstiger Weg",
    WAY_CATEGORY_CYCLEWAY_NEAR_MAIN_ROAD: "Radweg an Landstraße",
    WAY_CATEGORY_PUSH: "Schiebestrecke",
    WAY_CATEGORY_STEPS: "Treppe",
}

MAIN_ROAD_HIGHWAYS = {
    "tertiary", "tertiary_link", "secondary", "secondary_link",
    "primary", "primary_link", "trunk", "trunk_link",
}
QUIET_ROAD_HIGHWAYS = {"living_street", "residential", "service", "unclassified", "pedestrian"}

# `surface`-Werte, die einen Weg unabhängig vom `highway`-Tag als "unbefestigt" einstufen - das ist
# für Rennrad- vs. Trekkingrad-Nutzer oft die praktisch relevantere Info als der Straßentyp (s.
# ROADMAP.md "Oberflächentyp anzeigen").
UNPAVED_SURFACES = {
    "unpaved", "gravel", "fine_gravel", "dirt", "ground", "grass", "sand",
    "compacted", "pebblestone", "mud", "earth", "woodchips",
}

# ~15 m Toleranz für "ein Radweg verläuft direkt neben dieser Landstraße" (s. `MainRoadIndex`
# unten) - eng genug gewählt, um nicht versehentlich eine unbeteiligte, zufällig parallel
# verlaufende Straße zu erwischen (ein begleitender Radweg liegt in der Praxis meist nur wenige
# Meter von der Fahrbahn entfernt - Bordstein, schmaler Grünstreifen), großzügig genug für normale
# Digitalisierungs-Ungenauigkeiten zwischen den beiden separat kartierten OSM-Wegen. Nutzer-Wunsch
# 2026-08-17, tunable ohne Code-Änderung an der App - nur ein erneuter Bau nötig.
NEARBY_MAIN_ROAD_METERS = 15.0
# Rastergröße für `MainRoadIndex` - grob 150 m bei deutschen Breitengraden. Nur eine grobe
# Vorauswahl (die 3x3-Nachbarschaft um den Suchpunkt wird durchsucht), die tatsächliche Distanz
# wird danach exakt per Punkt-zu-Strecke-Berechnung geprüft - die Zellgröße muss deshalb nur
# "deutlich größer als `NEARBY_MAIN_ROAD_METERS`" sein, nicht exakt kalibriert.
MAIN_ROAD_GRID_CELL_DEGREES = 0.0015


def point_to_segment_distance_meters(lat, lon, lat1, lon1, lat2, lon2):
    """Abstand von `(lat, lon)` zur Strecke `(lat1, lon1)-(lat2, lon2)` in Metern - lokale ebene
    Näherung (wie `WayGraphRepository.nearestNodes` in der App), für die hier relevanten
    Distanzen (wenige zehn Meter) ausreichend genau und viel schneller als echte
    Großkreis-Punkt-zu-Strecke-Geometrie."""
    meters_per_degree_lat = 111_320.0
    meters_per_degree_lon = meters_per_degree_lat * max(cos(radians(lat1)), 0.1)

    px = (lon - lon1) * meters_per_degree_lon
    py = (lat - lat1) * meters_per_degree_lat
    dx = (lon2 - lon1) * meters_per_degree_lon
    dy = (lat2 - lat1) * meters_per_degree_lat

    length_squared = dx * dx + dy * dy
    if length_squared == 0:
        return sqrt(px * px + py * py)
    t = max(0.0, min(1.0, (px * dx + py * dy) / length_squared))
    closest_x, closest_y = dx * t, dy * t
    return sqrt((px - closest_x) ** 2 + (py - closest_y) ** 2)


class MainRoadIndex:
    """Räumlicher Index über alle Landstraßen-Kantensegmente (s. `MAIN_ROAD_HIGHWAYS`) eines
    Extrakts - für `way_category()`s "läuft dieser Radweg-Abschnitt direkt neben einer
    Landstraße?"-Prüfung. Muss **vor** dem eigentlichen Kanten-Bau vollständig befüllt sein (s.
    separater, vorgezogener Durchlauf in `build()`/`build_way_graph_v2.py`), damit auch Radwege,
    die im Datei-Stream vor "ihrer" Landstraße vorkommen, korrekt geprüft werden können - Ways
    liegen in einer `.osm.pbf` in beliebiger Reihenfolge, nicht geografisch sortiert."""

    def __init__(self):
        self._segments = []  # (lat1, lon1, lat2, lon2)
        self._grid = {}  # (cell_lat, cell_lon) -> [segment_index, ...]

    @staticmethod
    def _cell(lat, lon):
        return (int(lat // MAIN_ROAD_GRID_CELL_DEGREES), int(lon // MAIN_ROAD_GRID_CELL_DEGREES))

    def add_segment(self, lat1, lon1, lat2, lon2):
        segment_index = len(self._segments)
        self._segments.append((lat1, lon1, lat2, lon2))
        # Beide Endpunkt-Zellen statt aller Zellen entlang der Strecke - bei den kurzen
        # Kantensegmenten hier (meist deutlich unter der Zellgröße) reicht das, `nearby()`
        # durchsucht ohnehin die 3x3-Nachbarschaft um den jeweiligen Suchpunkt mit.
        for cell in {self._cell(lat1, lon1), self._cell(lat2, lon2)}:
            self._grid.setdefault(cell, []).append(segment_index)

    def nearby(self, lat, lon, max_meters=NEARBY_MAIN_ROAD_METERS):
        cell_lat, cell_lon = self._cell(lat, lon)
        candidates = set()
        for d_lat in (-1, 0, 1):
            for d_lon in (-1, 0, 1):
                candidates.update(self._grid.get((cell_lat + d_lat, cell_lon + d_lon), ()))
        for idx in candidates:
            lat1, lon1, lat2, lon2 = self._segments[idx]
            if point_to_segment_distance_meters(lat, lon, lat1, lon1, lat2, lon2) <= max_meters:
                return True
        return False

# Ein `cycleway=track/lane`-Tag beschreibt einen baulich getrennten Radweg, der aber in OSM
# i. d. R. NICHT als eigene, seitlich versetzte Geometrie gezeichnet ist, sondern nur als
# Attribut an der Straßen-Mittellinie hängt. Damit die App trotzdem eine plausible, seitlich
# versetzte Linie darstellen kann (statt optisch auf der Fahrbahn zu "kleben"), wird pro Kante
# festgehalten, auf welcher Seite (bezogen auf die digitalisierte Richtung from -> to dieser
# konkreten Kante) sich der Radweg befindet. 0 = kein Versatz, 1 = rechts, 2 = links.
OFFSET_NONE, OFFSET_RIGHT, OFFSET_LEFT = 0, 1, 2

# Sentinel für "kein `name`-Tag" (unbenannter Weg, z. B. viele Wirtschaftswege/Trampelpfade).
# Erster Versuch nutzte UInt16 (0xFFFF, max. 65.534 Namen) um die Hälfte Platz zu sparen -
# Baden-Württemberg erreichte beim echten Bau aber exakt 65.535 eindeutige Namen (die Grenze),
# hätte also weitere Namen fälschlich als "unbenannt" behandelt. UInt32 hat dafür ausreichend
# Reserve.
NO_NAME = 0xFFFFFFFF


def offset_side(tags):
    """Seite des Radwegs relativ zur digitalisierten Richtung des Ways (erster -> letzter
    Knoten in `way.nodes`). Nur bei eindeutigem `cycleway:right`/`cycleway:left` wird versetzt
    dargestellt (tag-treu). Bei `cycleway:both` oder unqualifiziertem `cycleway=track/lane` gibt
    OSM die Seite schlicht nicht her - dort **kein Versatz** (Linie bleibt auf der
    Straßen-Mittellinie), statt eine Seite zu raten.

    ⚠️ Historie: Frühere Versionen versuchten hier zu raten - erst "immer links" (nach einem
    Live-Test an Findorffstraße/Crüsemannallee/Richtweg, die damals mit tag-treuer Logik links
    statt rechts zeigten), dann "immer rechts" (nach gängiger deutscher OSM-Konvention, plus
    Overpass-Beleg bei "Außer der Schleifmühle" mit eindeutigem `cycleway:right`-Tag, das durch
    die "immer links"-Regel falsch herum landete). Beide Rate-Regeln wurden live widerlegt: Der
    Nutzer verifizierte 2026-07-26 nach der "immer rechts"-Umstellung erneut vor Ort, dass
    Richtweg und Findorffstraße (beide größtenteils unqualifiziertes `cycleway=track`, keine
    separat kartierte Radweg-Geometrie in der Nähe laut Overpass) wieder falsch herum zeigten -
    diesmal weil der reale Weg dort links liegt. Fazit: Bei fehlender Seitenangabe im Tag gibt es
    keine zuverlässige Standardseite, jeder feste Rateversuch ist auf einem Teil der Straßen
    falsch. Deshalb jetzt bewusst kein Versatz mehr bei mehrdeutigen Tags - lieber ungenau
    (Linie auf der Straße, keine Seite behauptet) als aktiv falsch. Falls hier oder an der
    Kanten-Richtungslogik (`forward`/`backward` weiter unten) künftig etwas geändert wird,
    unbedingt gegen echte Fahrten testen, nicht nur gegen die OSM-Tag-Definition."""
    if tags.get("cycleway:right") in CYCLE_INFRA_VALUES:
        return OFFSET_RIGHT
    if tags.get("cycleway:left") in CYCLE_INFRA_VALUES:
        return OFFSET_LEFT
    return OFFSET_NONE


def haversine_meters(lon1, lat1, lon2, lat2):
    r = 6_371_000.0
    p1, p2 = radians(lat1), radians(lat2)
    dphi = radians(lat2 - lat1)
    dlambda = radians(lon2 - lon1)
    a = sin(dphi / 2) ** 2 + cos(p1) * cos(p2) * sin(dlambda / 2) ** 2
    return 2 * r * asin(sqrt(a))


def is_bikeable(tags):
    highway = tags.get("highway")
    if highway is None or highway in EXCLUDED_HIGHWAYS:
        return False
    bicycle = tags.get("bicycle")
    if bicycle == "no":
        return False
    access = tags.get("access")
    if access in ("no", "private") and bicycle not in ("yes", "designated", "permissive"):
        return False
    return highway in HIGHWAY_WEIGHTS or bicycle in ("yes", "designated", "permissive")


def is_pushable(tags):
    """Fußweg/Treppe außerhalb von `is_bikeable()` (s. `PUSH_HIGHWAYS`/`STEPS_HIGHWAY` oben), die/
    der zu Fuß mit geschobenem Rad passierbar ist - eigene, teure Kategorie statt regulärer
    Radweg-Kante. Anders als `is_bikeable()` schließt `bicycle=no` hier NICHT aus: Ein
    Rad-Fahrverbot auf einem Fußweg verbietet nicht automatisch auch das Schieben. Nur
    `foot=no`/`access=no|private` (ohne explizites `foot=yes/designated/permissive`) sperren den
    Weg auch fürs Schieben."""
    highway = tags.get("highway")
    if highway not in PUSH_HIGHWAYS and highway != STEPS_HIGHWAY:
        return False
    if tags.get("foot") == "no":
        return False
    access = tags.get("access")
    if access in ("no", "private") and tags.get("foot") not in ("yes", "designated", "permissive"):
        return False
    return True


def weight_multiplier(tags):
    highway = tags.get("highway")
    bicycle = tags.get("bicycle")
    # Ein eigener, ausgewiesener Rad-/Fußweg (highway=path/footway/pedestrian mit
    # bicycle=designated) ist ein echter Radweg, keine x-beliebige Trampelpfad-Qualität -
    # genauso attraktiv gewichten wie highway=cycleway, statt der pauschalen path/pedestrian-
    # Werte (0.9) bzw. dem generischen Default (footway steht gar nicht in HIGHWAY_WEIGHTS,
    # bekäme sonst den schlechtesten Wert von allen, 1.2). Live-Fund (Nutzer-Meldung, Findorff-
    # straße Bremen): ohne diese Regel war ein danebenliegender, richtig ausgewiesener Radweg
    # kaum attraktiver gewichtet als die Straße selbst, wodurch der Router gelegentlich einen
    # kurzen Straßen-Abstecher vorzog statt konsequent auf dem Radweg zu bleiben.
    if highway in ("path", "footway", "pedestrian") and bicycle == "designated":
        return HIGHWAY_WEIGHTS["cycleway"]
    if not is_bikeable(tags) and is_pushable(tags):
        return STEPS_PUSH_MULTIPLIER if highway == STEPS_HIGHWAY else FOOTWAY_PUSH_MULTIPLIER
    multiplier = HIGHWAY_WEIGHTS.get(highway, 1.2)
    if any(tags.get(key) in CYCLE_INFRA_VALUES for key in CYCLE_INFRA_TAGS):
        multiplier *= CYCLE_INFRA_BONUS
    # `bicycle=use_sidepath` heißt "hier gibt es eine benutzungspflichtige Radwegausweisung
    # nebenan, auf der Fahrbahn selbst soll eigentlich nicht Rad gefahren werden" - deutlich
    # unattraktiver machen statt die Straße wie eine normale, uneingeschränkt radfreundliche
    # Straße zu behandeln (derselbe Live-Fund wie oben).
    if bicycle == "use_sidepath":
        multiplier *= 2.0
    return multiplier


def way_category(tags, near_main_road=False):
    """Kategorie für die Wegeart-Anzeige (s. `WAY_CATEGORY_*` oben). `surface` schlägt `highway`:
    ein unbefestigter Radweg ist für die Anzeige in erster Linie "unbefestigt", nicht "Radweg".

    ⚠️ Live-Fund (2026-08-15, Demo-Lauf Bremen Hauptbahnhof -> Bürgerpark): Ein separat kartierter
    Radweg neben einer größeren Straße ist in OSM meist **kein** eigener `highway=cycleway`-Way,
    sondern nur ein `cycleway:right/left=track`-Attribut an der Straßen-Mittellinie selbst (exakt
    dieselben Tags, die auch `offset_side()`/`CYCLE_INFRA_BONUS` oben schon auswerten, um die
    Linie seitlich zu versetzen bzw. die Straße fürs Routing günstiger zu gewichten). Ohne diesen
    Check landete z. B. die Theodor-Heuss-Allee/Admiralstraße (durchgehend `cycleway:right/left=
    track`) komplett in der Kategorie "Landstraße" statt "Radweg" - für die Anzeige ("X km
    Radweg") die irreführendere der beiden Kategorien, weil der Nutzer ja tatsächlich auf dem
    separaten Radweg fährt, nicht auf der Fahrbahn.

    `near_main_road`: vom Aufrufer per `MainRoadIndex` vorberechnet (s. dort) - True, wenn dieser
    Kantenabschnitt innerhalb von `NEARBY_MAIN_ROAD_METERS` einer Landstraßen-Kante liegt.
    Unterscheidet dann zwischen einem Radweg direkt an einer Landstraße
    (`WAY_CATEGORY_CYCLEWAY_NEAR_MAIN_ROAD`) und einem freistehenden Radweg (`WAY_CATEGORY_
    CYCLEWAY` - Nebenstraße, freies Feld, Wald usw.), Nutzer-Wunsch 2026-08-17. Gilt für beide
    Cycleway-Erkennungswege oben (eigener `highway=cycleway`-Way **und** `cycleway:right/left`-Tag
    an der Straße selbst) einheitlich - beim zweiten Fall matcht der Index praktisch immer
    (dieselbe Straße liegt ja bereits im Index, falls sie selbst ein `MAIN_ROAD_HIGHWAYS`-Typ ist),
    beim ersten Fall entscheidet die tatsächliche Nachbarschaft im Gelände.

    Schiebe-Kanten (`is_pushable()`, s. dort) werden VOR dem `surface`-Check ausgewertet: Für die
    Anzeige ist "hier musst du schieben" die wichtigere Information als die Oberfläche - ein
    unbefestigter Schiebe-Fußweg soll als "Schiebestrecke"/"Treppe" erscheinen, nicht als
    "Unbefestigter Weg"."""
    highway = tags.get("highway")
    bicycle = tags.get("bicycle")
    if not is_bikeable(tags) and is_pushable(tags):
        return WAY_CATEGORY_STEPS if highway == STEPS_HIGHWAY else WAY_CATEGORY_PUSH
    if tags.get("surface") in UNPAVED_SURFACES:
        return WAY_CATEGORY_UNPAVED
    is_cycleway = (
        highway == "cycleway"
        or (highway in ("path", "footway", "pedestrian", "track") and bicycle == "designated")
        or any(tags.get(key) in CYCLE_INFRA_VALUES for key in CYCLE_INFRA_TAGS)
    )
    if is_cycleway:
        return WAY_CATEGORY_CYCLEWAY_NEAR_MAIN_ROAD if near_main_road else WAY_CATEGORY_CYCLEWAY
    if highway in MAIN_ROAD_HIGHWAYS:
        return WAY_CATEGORY_MAIN_ROAD
    if highway in QUIET_ROAD_HIGHWAYS:
        return WAY_CATEGORY_QUIET_ROAD
    return WAY_CATEGORY_OTHER


def direction(tags):
    """('forward', 'backward') je danach, ob die Kante(n) befahrbar sind - Fahrräder dürfen
    entgegen einer Einbahnstraße fahren, wenn `oneway:bicycle=no` explizit erlaubt ist (in
    deutschen Städten sehr verbreitet)."""
    oneway = tags.get("oneway")
    oneway_bicycle = tags.get("oneway:bicycle")
    if oneway_bicycle == "no":
        return True, True
    if oneway in ("yes", "1", "true"):
        return True, False
    if oneway == "-1":
        return False, True
    return True, True


def build(pbf_path: str, output_path: str):
    # Alte Datei komplett neu anlegen statt eine bestehende wiederzuverwenden - sonst können
    # Altlasten (freigegebene, aber nicht zurückgegebene Seiten einer vorherigen Version) die
    # Dateigröße unnötig aufblähen.
    Path(output_path).unlink(missing_ok=True)

    # Kompaktes Binärformat statt einer Zeile pro Knoten/Kante mit Indizes: Die App lädt beim
    # Start ohnehin den kompletten Graphen in den Speicher (nie per SQL-Abfrage einzeln
    # nachgeladen), daher bringen Indizes hier nichts außer Speicherplatz zu kosten - bei
    # Baden-Württemberg allein ~700 MB von 1,8 GB. Zusätzlich: dichte 0-basierte Knoten-Indizes
    # (UInt32) statt der langen OSM-IDs (Int64) halbieren die Kantengröße, Float32 statt SQLite
    # REAL (Float64) halbiert nochmal - Format angelehnt an das bestehende Geometrie-Blob in
    # routes.sqlite.
    node_index = {}  # osm_id -> dense index
    node_coords = []  # index -> (lat, lon)
    edge_rows = []  # (from_index, to_index, distance_m, weight, offset_side, name_index)
    name_index_map = {}  # name string -> dense index (Deduplizierung - viele Kanten teilen sich
    # denselben Straßennamen, ihn pro Kante als Text zu wiederholen wäre reine Platzverschwendung)
    name_list = []  # index -> name string
    way_count = 0

    def index_for(osm_id, location):
        idx = node_index.get(osm_id)
        if idx is None:
            idx = len(node_coords)
            node_index[osm_id] = idx
            node_coords.append((location.lat, location.lon))
        return idx

    def name_index_for(name):
        if not name:
            return NO_NAME
        idx = name_index_map.get(name)
        if idx is None:
            idx = len(name_list)
            if idx >= NO_NAME:
                # Praktisch nie erreicht (>4 Mrd. eindeutige Namen in einem Bundesland), aber
                # ohne diese Bremse würde ein Überlauf den Sentinel-Wert selbst überschreiben.
                return NO_NAME
            name_index_map[name] = idx
            name_list.append(name)
        return idx

    for way in osmium.FileProcessor(pbf_path).with_locations():
        if not way.is_way():
            continue
        tags = dict(way.tags)
        if not is_bikeable(tags):
            continue

        nodes = [n for n in way.nodes if n.location.valid()]
        if len(nodes) < 2:
            continue

        multiplier = weight_multiplier(tags)
        forward, backward = direction(tags)
        side = offset_side(tags)
        name_idx = name_index_for(tags.get("name"))
        way_count += 1

        for i in range(len(nodes) - 1):
            a, b = nodes[i], nodes[i + 1]
            distance = haversine_meters(
                a.location.lon, a.location.lat, b.location.lon, b.location.lat
            )
            if distance <= 0:
                continue
            weight = distance * multiplier
            a_idx = index_for(a.ref, a.location)
            b_idx = index_for(b.ref, b.location)

            if forward:
                edge_rows.append((a_idx, b_idx, distance, weight, side, name_idx))
            if backward:
                # gleicher physischer Radweg, aber aus umgekehrter Fahrtrichtung gesehen liegt
                # er auf der jeweils anderen Seite. Der Straßenname bleibt unabhängig von der
                # Fahrtrichtung derselbe.
                backward_side = {OFFSET_NONE: OFFSET_NONE, OFFSET_RIGHT: OFFSET_LEFT, OFFSET_LEFT: OFFSET_RIGHT}[side]
                edge_rows.append((b_idx, a_idx, distance, weight, backward_side, name_idx))

    nodes_blob = b"".join(struct.pack("<ff", lat, lon) for lat, lon in node_coords)
    edges_blob = b"".join(
        struct.pack("<IIffBI", f, t, d, w, s, n) for f, t, d, w, s, n in edge_rows
    )
    # Namenstabelle: pro eindeutigem Namen `UInt16 byteLength` + UTF-8-Bytes, in Index-Reihenfolge
    # (Index 0 = erster in `name_list` usw.) - so kann die App beim Lesen einfach der Reihe nach
    # durchgehen, ohne Trennzeichen im Text selbst zu riskieren.
    names_blob = b"".join(
        struct.pack("<H", len(encoded)) + encoded
        for encoded in (name.encode("utf-8") for name in name_list)
    )

    conn = sqlite3.connect(output_path)
    conn.execute("DROP TABLE IF EXISTS graph")
    conn.execute(
        "CREATE TABLE graph ("
        "node_count INTEGER, edge_count INTEGER, nodes BLOB, edges BLOB, "
        "name_count INTEGER, names BLOB)"
    )
    conn.execute(
        "INSERT INTO graph VALUES (?, ?, ?, ?, ?, ?)",
        (len(node_coords), len(edge_rows), nodes_blob, edges_blob, len(name_list), names_blob),
    )
    conn.commit()
    conn.execute("VACUUM")

    print(f"Wege verarbeitet: {way_count}")
    print(f"Knoten: {len(node_coords)}")
    print(f"Kanten: {len(edge_rows)}")
    print(f"Eindeutige Straßennamen: {len(name_list)}")
    conn.close()


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Nutzung: build_way_graph.py <input.osm.pbf> <output.sqlite>")
        sys.exit(1)
    build(sys.argv[1], sys.argv[2])
