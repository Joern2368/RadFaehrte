#!/usr/bin/env python3
"""
Extrahiert alle route=bicycle-Relationen aus einem Länder-/Regions-OSM-Extrakt (.osm.pbf) und
baut daraus eine SQLite-DB im selben Format wie die gebündelte Deutschland-Datenbank
(FahrradApp/RadFaehrte/Resources/routes.sqlite), aber für ein weiteres Land.

Die ursprüngliche Deutschland-Pipeline (extract_routes.py/build_sqlite.py/simplify_routes.py) ist
nicht mehr vorhanden (s. ROADMAP.md) - dieses Skript deckt denselben Ablauf in einer Datei ab:
Relationen sammeln (inkl. Sub-Relationen für Superrouten) -> Way-Geometrien auflösen ->
Douglas-Peucker-Vereinfachung -> binär gepackte SQLite-DB, Schema identisch zu routes.sqlite.

Nutzung:
    Scripts/venv/bin/python3 Scripts/extract_bicycle_routes.py \
        Scripts/data/netherlands-latest.osm.pbf Scripts/data/netherlands_routes.sqlite
"""

import sqlite3
import struct
import sys
from pathlib import Path

import osmium
from shapely.geometry import LineString

SIMPLIFY_TOLERANCE_DEG = 0.0001  # ~11 m, wie in der Deutschland-Pipeline (s. ROADMAP.md)


def is_bicycle_route(tags):
    return tags.get("type") in ("route", "superroute") and tags.get("route") == "bicycle"


def collect_relations(pbf_path):
    """Pass 1: alle route=bicycle-Relationen einsammeln (Tags + Mitglieder). Mitglieder aller
    route/superroute-Relationen werden gespeichert (nicht nur der bicycle-getaggten), damit
    Superrouten ihre Sub-Relationen (Etappen) rekursiv auflösen können, auch wenn diese selbst
    kein eigenes route=bicycle-Tag tragen."""
    relation_tags = {}
    relation_members = {}

    for obj in osmium.FileProcessor(pbf_path).with_filter(
        osmium.filter.EntityFilter(osmium.osm.RELATION)
    ):
        if not obj.is_relation():
            continue
        tags = dict(obj.tags)
        if tags.get("type") not in ("route", "superroute"):
            continue
        relation_members[obj.id] = [(m.type, m.ref) for m in obj.members]
        if is_bicycle_route(tags):
            relation_tags[obj.id] = tags

    return relation_tags, relation_members


def resolve_ways(relation_id, relation_members, visited=None):
    """Löst eine Relation rekursiv zu ihrer flachen Liste referenzierter Way-IDs auf (steigt bei
    Superrouten in Sub-Relationen ab). `visited` schützt vor (in OSM seltenen, aber möglichen)
    Zirkelbezügen."""
    if visited is None:
        visited = set()
    if relation_id in visited:
        return []
    visited.add(relation_id)

    ways = []
    for member_type, member_ref in relation_members.get(relation_id, []):
        if member_type == "w":
            ways.append(member_ref)
        elif member_type == "r":
            ways.extend(resolve_ways(member_ref, relation_members, visited))
    return ways


def resolve_way_geometries(pbf_path, needed_way_ids):
    """Pass 2: Koordinaten aller benötigten Ways auflösen (mit Node-Locations)."""
    geometries = {}
    for way in osmium.FileProcessor(pbf_path).with_locations():
        if not way.is_way():
            continue
        if way.id not in needed_way_ids:
            continue
        coords = [(n.location.lon, n.location.lat) for n in way.nodes if n.location.valid()]
        if len(coords) >= 2:
            geometries[way.id] = coords
    return geometries


def simplify_line(coords):
    if len(coords) < 3:
        return coords
    simplified = LineString(coords).simplify(SIMPLIFY_TOLERANCE_DEG, preserve_topology=False)
    return list(simplified.coords)


def pack_geometry(lines):
    parts = [struct.pack("<I", len(lines))]
    for line in lines:
        parts.append(struct.pack("<I", len(line)))
        for lon, lat in line:
            parts.append(struct.pack("<ff", lon, lat))
    return b"".join(parts)


def build(pbf_path, output_path):
    print("Pass 1: Relationen sammeln...")
    relation_tags, relation_members = collect_relations(pbf_path)
    print(f"  {len(relation_tags)} route=bicycle-Relationen gefunden")

    resolved_ways = {rel_id: resolve_ways(rel_id, relation_members) for rel_id in relation_tags}
    needed_way_ids = {w for ways in resolved_ways.values() for w in ways}
    print(f"  {len(needed_way_ids)} benötigte Ways")

    print("Pass 2: Way-Geometrien auflösen (das dauert am längsten)...")
    geometries = resolve_way_geometries(pbf_path, needed_way_ids)
    print(f"  {len(geometries)} Way-Geometrien geladen")

    Path(output_path).unlink(missing_ok=True)
    conn = sqlite3.connect(output_path)
    conn.execute(
        """
        CREATE TABLE routes (
            id INTEGER PRIMARY KEY,
            name TEXT,
            network TEXT,
            ref TEXT,
            distance_km REAL,
            operator TEXT,
            min_lon REAL NOT NULL,
            min_lat REAL NOT NULL,
            max_lon REAL NOT NULL,
            max_lat REAL NOT NULL,
            geometry BLOB NOT NULL
        )
        """
    )

    written = 0
    skipped_no_geometry = 0
    for rel_id, tags in relation_tags.items():
        lines = []
        for way_id in resolved_ways[rel_id]:
            coords = geometries.get(way_id)
            if coords:
                lines.append(simplify_line(coords))
        if not lines:
            skipped_no_geometry += 1
            continue

        all_points = [p for line in lines for p in line]
        min_lon = min(p[0] for p in all_points)
        max_lon = max(p[0] for p in all_points)
        min_lat = min(p[1] for p in all_points)
        max_lat = max(p[1] for p in all_points)

        distance_km = None
        if tags.get("distance"):
            try:
                distance_km = float(tags["distance"])
            except ValueError:
                distance_km = None

        conn.execute(
            "INSERT INTO routes VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                rel_id,
                tags.get("name"),
                tags.get("network"),
                tags.get("ref"),
                distance_km,
                tags.get("operator"),
                min_lon,
                min_lat,
                max_lon,
                max_lat,
                pack_geometry(lines),
            ),
        )
        written += 1

    conn.execute("CREATE INDEX idx_routes_bbox ON routes(min_lon, max_lon, min_lat, max_lat)")
    conn.commit()
    conn.execute("VACUUM")
    conn.close()
    print(f"Übersprungen (keine auflösbare Geometrie): {skipped_no_geometry}")
    print(f"Fertig: {written} Routen geschrieben -> {output_path}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Nutzung: extract_bicycle_routes.py <input.osm.pbf> <output.sqlite>")
        sys.exit(1)
    build(sys.argv[1], sys.argv[2])
