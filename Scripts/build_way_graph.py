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

# Eigene Rad-Infrastruktur neben einer größeren Straße (cycleway=track/lane bzw.
# cycleway:left/right/both) senkt die Kosten dieser Straße zusätzlich, auch wenn der
# highway-Typ selbst nicht radfreundlich ist.
CYCLE_INFRA_BONUS = 0.7
CYCLE_INFRA_TAGS = ("cycleway", "cycleway:left", "cycleway:right", "cycleway:both")
CYCLE_INFRA_VALUES = {"track", "lane", "opposite_track", "opposite_lane", "share_busway"}

# Ein `cycleway=track/lane`-Tag beschreibt einen baulich getrennten Radweg, der aber in OSM
# i. d. R. NICHT als eigene, seitlich versetzte Geometrie gezeichnet ist, sondern nur als
# Attribut an der Straßen-Mittellinie hängt. Damit die App trotzdem eine plausible, seitlich
# versetzte Linie darstellen kann (statt optisch auf der Fahrbahn zu "kleben"), wird pro Kante
# festgehalten, auf welcher Seite (bezogen auf die digitalisierte Richtung from -> to dieser
# konkreten Kante) sich der Radweg befindet. 0 = kein Versatz, 1 = rechts, 2 = links.
OFFSET_NONE, OFFSET_RIGHT, OFFSET_LEFT = 0, 1, 2


def offset_side(tags):
    """Seite des Radwegs relativ zur digitalisierten Richtung des Ways (erster -> letzter
    Knoten in `way.nodes`). `cycleway:right`/`cycleway:left` sind eindeutig; bei `cycleway:both`
    oder unqualifiziertem `cycleway=track/lane` ist die Seite in OSM nicht angebbar - dort wird
    vereinfachend rechts angenommen (in Deutschland die deutlich häufigere Lage)."""
    if tags.get("cycleway:right") in CYCLE_INFRA_VALUES:
        return OFFSET_RIGHT
    if tags.get("cycleway:left") in CYCLE_INFRA_VALUES:
        return OFFSET_LEFT
    if tags.get("cycleway:both") in CYCLE_INFRA_VALUES:
        return OFFSET_RIGHT
    if tags.get("cycleway") in CYCLE_INFRA_VALUES:
        return OFFSET_RIGHT
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


def weight_multiplier(tags):
    highway = tags.get("highway")
    multiplier = HIGHWAY_WEIGHTS.get(highway, 1.2)
    if any(tags.get(key) in CYCLE_INFRA_VALUES for key in CYCLE_INFRA_TAGS):
        multiplier *= CYCLE_INFRA_BONUS
    return multiplier


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
    edge_rows = []  # (from_index, to_index, distance_m, weight)
    way_count = 0

    def index_for(osm_id, location):
        idx = node_index.get(osm_id)
        if idx is None:
            idx = len(node_coords)
            node_index[osm_id] = idx
            node_coords.append((location.lat, location.lon))
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
                edge_rows.append((a_idx, b_idx, distance, weight, side))
            if backward:
                # gleicher physischer Radweg, aber aus umgekehrter Fahrtrichtung gesehen liegt
                # er auf der jeweils anderen Seite.
                backward_side = {OFFSET_NONE: OFFSET_NONE, OFFSET_RIGHT: OFFSET_LEFT, OFFSET_LEFT: OFFSET_RIGHT}[side]
                edge_rows.append((b_idx, a_idx, distance, weight, backward_side))

    nodes_blob = b"".join(struct.pack("<ff", lat, lon) for lat, lon in node_coords)
    edges_blob = b"".join(
        struct.pack("<IIffB", f, t, d, w, s) for f, t, d, w, s in edge_rows
    )

    conn = sqlite3.connect(output_path)
    conn.execute("DROP TABLE IF EXISTS graph")
    conn.execute(
        "CREATE TABLE graph (node_count INTEGER, edge_count INTEGER, nodes BLOB, edges BLOB)"
    )
    conn.execute(
        "INSERT INTO graph VALUES (?, ?, ?, ?)",
        (len(node_coords), len(edge_rows), nodes_blob, edges_blob),
    )
    conn.commit()
    conn.execute("VACUUM")

    print(f"Wege verarbeitet: {way_count}")
    print(f"Knoten: {len(node_coords)}")
    print(f"Kanten: {len(edge_rows)}")
    conn.close()


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Nutzung: build_way_graph.py <input.osm.pbf> <output.sqlite>")
        sys.exit(1)
    build(sys.argv[1], sys.argv[2])
