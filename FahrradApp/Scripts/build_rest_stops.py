#!/usr/bin/env python3
"""
Extrahiert Rastplatz-POIs (Trinkwasser, Bänke, Cafés, Aussichtspunkte,
Fahrrad-Reparaturstationen, Biergärten, Toiletten) aus einem OSM-Bundesland-Extrakt (.osm.pbf) für
die "Rastplätze"-Kartenanzeige von RadFährte.

Bänke (amenity=bench) waren in einem ersten Test komplett ausgeschlossen: Sie überluden die
Kartenanzeige (in Bremen allein 4033 von 4388 Treffern, 93 % - Nutzer-Feedback 2026-08-19 "zu
unruhig auf der Karte, zu viele Pins"). Jetzt per Raster ausgedünnt (`BENCH_GRID_METERS`) statt
komplett weggelassen: pro Rasterzelle wird nur die erste gefundene Bank behalten, alle weiteren
in derselben Zelle übersprungen - deutlich weniger Pins/Speicher, ohne die Kategorie ganz zu
verlieren. Reine Downsampling-Heuristik (keine "beste"/repräsentativste Bank pro Zelle,
einfach die erste im Datei-Stream), für den Zweck "es gibt hier ungefähr eine Sitzgelegenheit"
ausreichend.

Anders als build_way_graph.py werden hier nur einzelne OSM-Knoten gelesen, keine
Way-Geometrie aus referenzierten Knoten aufgelöst - deshalb ohne `.with_locations()`
(das würde nur unnötig einen kompletten Knoten-Ortsindex aufbauen).

v1-Einschränkung: erfasst nur als Knoten kartierte POIs, keine als Fläche/Way kartierten
(z. B. ein Café, das als Gebäudeumriss mit amenity=cafe gezeichnet ist) - in der Praxis die
große Mehrheit dieser Kategorien, bei Bedarf später nachrüstbar.

Nutzung:
    Scripts/venv/bin/python3 Scripts/build_rest_stops.py Scripts/data/bremen-latest.osm.pbf \
        Scripts/data/bremen_reststops.sqlite
"""

import sqlite3
import sys
from math import cos, radians
from pathlib import Path

import osmium

KIND_DRINKING_WATER = 0
KIND_CAFE = 1
KIND_VIEWPOINT = 2
KIND_BICYCLE_REPAIR_STATION = 3
KIND_BENCH = 4
KIND_BEER_GARDEN = 5
KIND_TOILETS = 6

KIND_LABELS = {
    KIND_DRINKING_WATER: "Trinkwasser",
    KIND_CAFE: "Café",
    KIND_VIEWPOINT: "Aussichtspunkt",
    KIND_BICYCLE_REPAIR_STATION: "Fahrrad-Reparaturstation",
    KIND_BENCH: "Bank",
    KIND_BEER_GARDEN: "Biergarten",
    KIND_TOILETS: "Toilette",
}

# Rastergröße für die Bänke-Ausdünnung (s. Modul-Docstring) - grob "eine Sitzgelegenheit pro
# Häuserblock/Parkabschnitt" statt jede einzelne kartierte Bank. Tunable ohne App-Änderung, nur
# ein erneuter Bau nötig.
BENCH_GRID_METERS = 40.0
_METERS_PER_DEGREE_LAT = 111_320.0


def bench_grid_cell(lat, lon):
    meters_per_degree_lon = _METERS_PER_DEGREE_LAT * max(cos(radians(lat)), 0.1)
    cell_lat_deg = BENCH_GRID_METERS / _METERS_PER_DEGREE_LAT
    cell_lon_deg = BENCH_GRID_METERS / meters_per_degree_lon
    return (int(lat // cell_lat_deg), int(lon // cell_lon_deg))


def kind_for(tags):
    if tags.get("amenity") == "drinking_water":
        return KIND_DRINKING_WATER
    if tags.get("amenity") == "cafe":
        return KIND_CAFE
    if tags.get("tourism") == "viewpoint":
        return KIND_VIEWPOINT
    if tags.get("amenity") == "bicycle_repair_station":
        return KIND_BICYCLE_REPAIR_STATION
    if tags.get("amenity") == "bench":
        return KIND_BENCH
    if tags.get("amenity") == "biergarten":
        return KIND_BEER_GARDEN
    if tags.get("amenity") == "toilets":
        return KIND_TOILETS
    return None


def build(pbf_path: str, output_path: str):
    Path(output_path).unlink(missing_ok=True)

    rows = []  # (osm_id, kind, name, opening_hours, lat, lon)
    counts = {kind: 0 for kind in KIND_LABELS}
    seen_bench_cells = set()
    skipped_benches = 0

    for entity in osmium.FileProcessor(pbf_path):
        if not entity.is_node():
            continue
        if not entity.location.valid():
            continue
        tags = dict(entity.tags)
        kind = kind_for(tags)
        if kind is None:
            continue
        if kind == KIND_BENCH:
            cell = bench_grid_cell(entity.location.lat, entity.location.lon)
            if cell in seen_bench_cells:
                skipped_benches += 1
                continue
            seen_bench_cells.add(cell)
        name = tags.get("name")
        # Rohtext im OSM-eigenen `opening_hours`-Syntax (z. B. "Mo-Fr 08:00-18:00; Sa 09:00-14:00"),
        # bewusst nicht geparst/ausgewertet ("gerade geöffnet?") - das wäre eine eigene kleine
        # DSL-Interpretation (inkl. Feiertage, Sonderfälle) und deutlich mehr Aufwand als den Text
        # einfach anzuzeigen. Nicht jeder POI hat das Tag gesetzt, dann `None`.
        opening_hours = tags.get("opening_hours")
        rows.append((entity.id, kind, name, opening_hours, entity.location.lat, entity.location.lon))
        counts[kind] += 1

    conn = sqlite3.connect(output_path)
    conn.execute("DROP TABLE IF EXISTS rest_stops")
    conn.execute(
        "CREATE TABLE rest_stops ("
        "id INTEGER PRIMARY KEY, kind INTEGER NOT NULL, name TEXT, opening_hours TEXT, "
        "lat REAL NOT NULL, lon REAL NOT NULL)"
    )
    conn.executemany("INSERT OR IGNORE INTO rest_stops VALUES (?, ?, ?, ?, ?, ?)", rows)
    conn.execute("CREATE INDEX idx_rest_stops_geo ON rest_stops(lat, lon)")
    conn.commit()
    conn.execute("VACUUM")
    conn.close()

    print(f"Rastplätze insgesamt: {len(rows)}")
    for kind, label in KIND_LABELS.items():
        print(f"  {label}: {counts[kind]}")
    print(f"  (Bänke durch {BENCH_GRID_METERS:.0f}-m-Raster übersprungen: {skipped_benches})")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Nutzung: build_rest_stops.py <input.osm.pbf> <output.sqlite>")
        sys.exit(1)
    build(sys.argv[1], sys.argv[2])
