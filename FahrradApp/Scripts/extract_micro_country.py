#!/usr/bin/env python3
"""
Schneidet einen kleinen Staat (San Marino, Vatikanstadt), der bei Geofabrik keinen eigenen
Extrakt hat (in italy.osm.pbf enthalten), per Grenz-Polygon aus einem größeren PBF (hier:
Italien) aus - Ersatz für "osmium extract --polygon" (osmium-tool selbst ist auf diesem Rechner
nicht installiert, nur die Python-Bindings pyosmium). Das Grenz-Polygon kommt von Nominatim
(GeoJSON, s. `Scripts/data/<land>-boundary.json`).

Vorgehen (mehrere Durchgänge über die große PBF, da pyosmium keinen wahlfreien Zugriff bietet):
1. Alle Knoten innerhalb des Grenz-Polygons einsammeln (Bounding-Box als billiger Vorfilter,
   danach echter Punkt-in-Polygon-Test).
2. Alle Ways, die mindestens einen dieser Knoten referenzieren, behalten - inklusive aller ihrer
   Knoten (auch außerhalb des Polygons), damit die Way-Geometrie nicht abgeschnitten wird.
3. Relationen (route=bicycle/superroute), die mindestens einen der behaltenen Ways referenzieren.
4. Knoten-Koordinaten für alle benötigten IDs (Schritt 1 + zusätzliche aus Schritt 2) einsammeln.
5. Alles in eine neue .osm.pbf schreiben.

Nutzung:
    Scripts/venv/bin/python3 Scripts/extract_micro_country.py \
        Scripts/data/italy-latest.osm.pbf Scripts/data/san-marino-boundary.json \
        Scripts/data/san-marino-latest.osm.pbf
"""

import json
import sys

import osmium
from shapely.geometry import Point, Polygon, shape


def load_polygon(path):
    with open(path) as f:
        data = json.load(f)
    geojson = data[0]["geojson"]
    return shape(geojson)


class BBoxNodeCollector(osmium.SimpleHandler):
    def __init__(self, polygon):
        super().__init__()
        self.polygon = polygon
        self.min_lon, self.min_lat, self.max_lon, self.max_lat = polygon.bounds
        self.node_ids = set()

    def node(self, n):
        lon, lat = n.location.lon, n.location.lat
        if self.min_lon <= lon <= self.max_lon and self.min_lat <= lat <= self.max_lat:
            if self.polygon.contains(Point(lon, lat)):
                self.node_ids.add(n.id)


class WayCollector(osmium.SimpleHandler):
    def __init__(self, inside_node_ids):
        super().__init__()
        self.inside_node_ids = inside_node_ids
        self.kept_ways = []  # (id, tags dict, [node ids])
        self.needed_node_ids = set()

    def way(self, w):
        refs = [n.ref for n in w.nodes]
        if any(r in self.inside_node_ids for r in refs):
            self.kept_ways.append((w.id, dict(w.tags), refs))
            self.needed_node_ids.update(refs)


class RelationCollector(osmium.SimpleHandler):
    def __init__(self, kept_way_ids):
        super().__init__()
        self.kept_way_ids = kept_way_ids
        self.kept_relations = []  # (id, tags dict, [(type, ref, role)])

    def relation(self, r):
        tags = dict(r.tags)
        if tags.get("type") not in ("route", "superroute"):
            return
        if any(m.type == "w" and m.ref in self.kept_way_ids for m in r.members):
            members = [(m.type, m.ref, m.role) for m in r.members]
            self.kept_relations.append((r.id, tags, members))


class NodeCoordCollector(osmium.SimpleHandler):
    def __init__(self, needed_node_ids):
        super().__init__()
        self.needed_node_ids = needed_node_ids
        self.coords = {}  # id -> (lon, lat)

    def node(self, n):
        if n.id in self.needed_node_ids:
            self.coords[n.id] = (n.location.lon, n.location.lat)


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <source.osm.pbf> <boundary.json> <output.osm.pbf>", file=sys.stderr)
        sys.exit(1)

    source_path, boundary_path, output_path = sys.argv[1:4]

    polygon = load_polygon(boundary_path)
    print("Pass 1: Knoten innerhalb des Grenz-Polygons sammeln...")
    bbox_nodes = BBoxNodeCollector(polygon)
    bbox_nodes.apply_file(source_path)
    print(f"  {len(bbox_nodes.node_ids)} Knoten innerhalb der Grenze")

    print("Pass 2: Ways sammeln, die mindestens einen dieser Knoten referenzieren...")
    ways = WayCollector(bbox_nodes.node_ids)
    ways.apply_file(source_path)
    print(f"  {len(ways.kept_ways)} Ways, {len(ways.needed_node_ids)} benötigte Knoten insgesamt")

    kept_way_ids = {w[0] for w in ways.kept_ways}
    print("Pass 3: Relationen (route=bicycle/superroute) sammeln...")
    relations = RelationCollector(kept_way_ids)
    relations.apply_file(source_path)
    print(f"  {len(relations.kept_relations)} Routen-Relationen")

    print("Pass 4: Knoten-Koordinaten für alle benötigten IDs sammeln...")
    coords = NodeCoordCollector(ways.needed_node_ids)
    coords.apply_file(source_path)
    print(f"  {len(coords.coords)} Knoten-Koordinaten geladen")

    print(f"Schreibe {output_path}...")
    writer = osmium.SimpleWriter(output_path)
    for node_id, (lon, lat) in sorted(coords.coords.items()):
        writer.add_node(osmium.osm.mutable.Node(id=node_id, location=(lon, lat), version=1))
    for way_id, tags, refs in ways.kept_ways:
        writer.add_way(osmium.osm.mutable.Way(id=way_id, nodes=refs, tags=tags, version=1))
    for rel_id, tags, members in relations.kept_relations:
        writer.add_relation(osmium.osm.mutable.Relation(id=rel_id, tags=tags, members=members, version=1))
    writer.close()
    print("Fertig.")


if __name__ == "__main__":
    main()
