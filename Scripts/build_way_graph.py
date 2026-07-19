#!/usr/bin/env python3
"""
Extrahiert alle fahrradtauglichen Straßen/Wege aus einem OSM-PBF-Extrakt,
verdichtet sie zu einem Routing-Graphen (nur echte Kreuzungen als Knoten,
Formpunkte dazwischen werden in die Kanten-Geometrie eingefaltet) und
schreibt sie direkt in eine SQLite-Datenbank mit Bbox-Index, bereit fürs
App-Bundle.

Ersetzt das frühere Zwei-Skript-Design (extract_way_graph.py +
build_way_graph_sqlite.py mit JSON-Zwischendatei): das hielt sowohl alle
Knoten-Koordinaten der Datei in einem Python-Dict als auch das komplette
Kanten-Ergebnis im Speicher. Für kleine Extrakte (z. B. Bremen, 21 MB)
unproblematisch, für ganz Deutschland (~4,8 GB) hätte das mutmaßlich
15-25+ GB RAM gebraucht. Dieses Skript nutzt stattdessen osmiums nativen
Location-Index (kompaktes natives Array statt Python-Objekte pro Knoten)
und schreibt Kanten sofort gebatcht in SQLite, statt sie zu sammeln.

Nutzung:
    python3 build_way_graph.py data/germany-latest.osm.pbf ../RadFaehrte/Resources/ways_germany.sqlite
"""
import sqlite3
import struct
import sys

import osmium

# Straßentypen, die für Radfahrer grundsätzlich nutzbar sind. Autobahnen und
# autobahnähnliche Straßen sind ausgeschlossen (nicht radtauglich).
ALLOWED_HIGHWAY = {
    "residential", "living_street", "unclassified", "tertiary", "secondary",
    "primary", "tertiary_link", "secondary_link", "primary_link",
    "cycleway", "path", "track", "service", "pedestrian",
}

BATCH_SIZE = 5000
PROGRESS_EVERY = 1_000_000


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


class RefCounter(osmium.SimpleHandler):
    """Pass 1: zählt nur, wie oft jede Node-ID von relevanten Ways
    referenziert wird - keine Koordinaten, keine Tags, um diesen Durchlauf
    so klein wie möglich zu halten."""

    def __init__(self):
        super().__init__()
        self.node_ref_count = {}
        self.ways_seen = 0

    def way(self, w):
        highway = w.tags.get("highway")
        if highway not in ALLOWED_HIGHWAY:
            return
        if w.tags.get("bicycle") == "no":
            return
        if len(w.nodes) < 2:
            return

        self.ways_seen += 1
        if self.ways_seen % PROGRESS_EVERY == 0:
            print(f"  Pass 1: {self.ways_seen} relevante Ways gezählt...")

        for n in w.nodes:
            nid = n.ref
            self.node_ref_count[nid] = self.node_ref_count.get(nid, 0) + 1


class EdgeWriter(osmium.SimpleHandler):
    """Pass 2: bildet Kanten (Knoten-Koordinaten bereits über den
    Location-Index von `lh` aufgelöst) und schreibt sie gebatcht direkt in
    SQLite, statt sie in einer Python-Liste zu sammeln."""

    def __init__(self, node_ref_count, conn):
        super().__init__()
        self.node_ref_count = node_ref_count
        self.conn = conn
        self.batch = []
        self.edges_written = 0

    def is_graph_node(self, node_id, is_endpoint):
        return is_endpoint or self.node_ref_count.get(node_id, 0) >= 2

    def way(self, w):
        highway = w.tags.get("highway")
        if highway not in ALLOWED_HIGHWAY:
            return
        if w.tags.get("bicycle") == "no":
            return
        if len(w.nodes) < 2:
            return

        tags = {
            "highway": highway,
            "cycleway": w.tags.get("cycleway") or w.tags.get("cycleway:both") or "",
            "surface": w.tags.get("surface", ""),
            "oneway": w.tags.get("oneway", ""),
            "name": w.tags.get("name", ""),
        }

        segment_nodes = []  # Liste von (node_id, lon, lat)
        nodes = w.nodes
        for i, n in enumerate(nodes):
            if not n.location.valid():
                continue
            is_endpoint = (i == 0 or i == len(nodes) - 1)
            segment_nodes.append((n.ref, n.location.lon, n.location.lat))
            if self.is_graph_node(n.ref, is_endpoint) and len(segment_nodes) >= 2:
                self._emit_edge(segment_nodes, tags)
                segment_nodes = [(n.ref, n.location.lon, n.location.lat)]

    def _emit_edge(self, segment_nodes, tags):
        pts = [(lon, lat) for _, lon, lat in segment_nodes]
        lons = [p[0] for p in pts]
        lats = [p[1] for p in pts]
        self.batch.append((
            self.edges_written,
            segment_nodes[0][0], segment_nodes[-1][0],
            tags["highway"], tags["cycleway"], tags["surface"],
            oneway_value(tags["oneway"]), tags["name"],
            min(lons), min(lats), max(lons), max(lats),
            pack_geometry(pts),
        ))
        self.edges_written += 1
        if len(self.batch) >= BATCH_SIZE:
            self.flush()
        if self.edges_written % PROGRESS_EVERY == 0:
            print(f"  Pass 2: {self.edges_written} Kanten geschrieben...")

    def flush(self):
        if not self.batch:
            return
        self.conn.executemany(
            "INSERT INTO way_segments VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)", self.batch
        )
        self.conn.commit()
        self.batch = []


def main():
    if len(sys.argv) != 3:
        print(f"Nutzung: {sys.argv[0]} <input.osm.pbf> <output.sqlite>")
        sys.exit(1)
    input_path, output_path = sys.argv[1], sys.argv[2]

    print("Pass 1/2: Node-Referenzen zählen (um Kreuzungen zu erkennen)...")
    counter = RefCounter()
    counter.apply_file(input_path)
    print(f"  {counter.ways_seen} relevante Ways, {len(counter.node_ref_count)} referenzierte Knoten")

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
    conn.commit()

    print("Pass 2/2: Kanten bilden und in SQLite schreiben...")
    idx = osmium.index.create_map("sparse_mem_array")
    lh = osmium.NodeLocationsForWays(idx)
    lh.ignore_errors()
    writer = EdgeWriter(counter.node_ref_count, conn)
    osmium.apply(input_path, lh, writer)
    writer.flush()
    print(f"  {writer.edges_written} Graph-Kanten geschrieben")

    print("Erzeuge Bbox-Index...")
    conn.execute(
        "CREATE INDEX idx_way_segments_bbox ON way_segments(min_lon, max_lon, min_lat, max_lat)"
    )
    conn.commit()
    conn.close()
    print(f"Fertig: {output_path}")


if __name__ == "__main__":
    main()
