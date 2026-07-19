#!/usr/bin/env python3
"""
Packt das JSON-Ergebnis von extract_way_graph.py in eine SQLite-Datenbank
mit Bbox-Index, bereit fürs App-Bundle.

Nutzung:
    python3 build_way_graph_sqlite.py data/bremen_graph.json ../RadFaehrte/Resources/ways_bremen.sqlite
"""
import json
import sqlite3
import struct
import sys


def pack_geometry(points):
    """Gleiches Binärformat wie routes.geometry in RouteRepository.swift:
    UInt32 numLines, je Line UInt32 numPoints, dann numPoints * (Float32 lon, Float32 lat).
    Eine Kante hat hier immer genau eine Line."""
    buf = struct.pack("<I", 1)  # numLines = 1
    buf += struct.pack("<I", len(points))
    for lon, lat in points:
        buf += struct.pack("<ff", lon, lat)
    return buf


def oneway_value(tag_value):
    if tag_value in ("yes", "true", "1"):
        return 1
    if tag_value in ("-1", "reverse"):
        return -1
    return 0


def main():
    if len(sys.argv) != 3:
        print(f"Nutzung: {sys.argv[0]} <input.json> <output.sqlite>")
        sys.exit(1)
    input_path, output_path = sys.argv[1], sys.argv[2]

    with open(input_path) as f:
        data = json.load(f)
    edges = data["edges"]
    print(f"{len(edges)} Kanten geladen")

    conn = sqlite3.connect(output_path)
    conn.execute("DROP TABLE IF EXISTS way_segments")
    conn.execute("""
        CREATE TABLE way_segments (
            id INTEGER PRIMARY KEY,
            from_node INTEGER NOT NULL,
            to_node INTEGER NOT NULL,
            highway TEXT, cycleway TEXT, surface TEXT,
            oneway INTEGER NOT NULL,
            name TEXT,
            min_lon REAL NOT NULL, min_lat REAL NOT NULL,
            max_lon REAL NOT NULL, max_lat REAL NOT NULL,
            geometry BLOB NOT NULL
        )
    """)

    rows = []
    for i, edge in enumerate(edges):
        pts = edge["points"]
        lons = [p[0] for p in pts]
        lats = [p[1] for p in pts]
        tags = edge["tags"]
        rows.append((
            i,
            edge["from_node"], edge["to_node"],
            tags["highway"], tags["cycleway"], tags["surface"],
            oneway_value(tags["oneway"]), tags["name"],
            min(lons), min(lats), max(lons), max(lats),
            pack_geometry(pts),
        ))

    conn.executemany(
        "INSERT INTO way_segments VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", rows
    )
    conn.execute(
        "CREATE INDEX idx_way_segments_bbox ON way_segments(min_lon, max_lon, min_lat, max_lat)"
    )
    conn.commit()
    conn.close()
    print(f"Geschrieben: {output_path}")


if __name__ == "__main__":
    main()
