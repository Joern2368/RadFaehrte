#!/usr/bin/env python3
"""
Extrahiert alle fahrradtauglichen Straßen/Wege aus einem OSM-PBF-Extrakt und
verdichtet sie zu einem Routing-Graphen (nur echte Kreuzungen als Knoten,
Formpunkte dazwischen werden in die Kanten-Geometrie eingefaltet).

Ausgabe: JSON-Datei mit "edges" (Liste von Kanten) für build_way_graph_sqlite.py.

Nutzung:
    python3 extract_way_graph.py data/bremen-latest.osm.pbf data/bremen_graph.json
"""
import json
import sys

import osmium

# Straßentypen, die für Radfahrer grundsätzlich nutzbar sind. Autobahnen und
# autobahnähnliche Straßen sind ausgeschlossen (nicht radtauglich).
ALLOWED_HIGHWAY = {
    "residential", "living_street", "unclassified", "tertiary", "secondary",
    "primary", "tertiary_link", "secondary_link", "primary_link",
    "cycleway", "path", "track", "service", "pedestrian",
}


class WayCollector(osmium.SimpleHandler):
    """Erster Durchlauf: sammelt alle relevanten Ways und zählt, wie oft
    jeder Knoten referenziert wird (um Kreuzungen zu erkennen)."""

    def __init__(self):
        super().__init__()
        self.ways = []  # Liste von (way_id, tags-dict, [node_ids])
        self.node_ref_count = {}

    def way(self, w):
        highway = w.tags.get("highway")
        if highway not in ALLOWED_HIGHWAY:
            return
        if w.tags.get("bicycle") == "no":
            return
        if len(w.nodes) < 2:
            return

        node_ids = [n.ref for n in w.nodes]
        tags = {
            "highway": highway,
            "cycleway": w.tags.get("cycleway") or w.tags.get("cycleway:both") or "",
            "surface": w.tags.get("surface", ""),
            "oneway": w.tags.get("oneway", ""),
            "name": w.tags.get("name", ""),
        }
        self.ways.append((w.id, tags, node_ids))
        for nid in node_ids:
            self.node_ref_count[nid] = self.node_ref_count.get(nid, 0) + 1


def main():
    if len(sys.argv) != 3:
        print(f"Nutzung: {sys.argv[0]} <input.osm.pbf> <output.json>")
        sys.exit(1)
    input_path, output_path = sys.argv[1], sys.argv[2]

    print("Durchlauf 1/2: Ways sammeln...")
    collector = WayCollector()
    collector.apply_file(input_path)
    print(f"  {len(collector.ways)} relevante Ways gefunden")

    # Graph-Knoten = Endpunkt eines Ways ODER von >= 2 Ways geteilt (Kreuzung)
    def is_graph_node(node_id, is_endpoint):
        return is_endpoint or collector.node_ref_count.get(node_id, 0) >= 2

    print("Durchlauf 2/2: Knoten-Koordinaten auflösen und Kanten bilden...")
    fp = osmium.FileProcessor(input_path).with_locations()
    coords = {}
    for obj in fp:
        if obj.is_node():
            coords[obj.id] = (obj.location.lon, obj.location.lat)

    edges = []
    for way_id, tags, node_ids in collector.ways:
        segment_nodes = []
        for i, nid in enumerate(node_ids):
            is_endpoint = (i == 0 or i == len(node_ids) - 1)
            segment_nodes.append(nid)
            if is_graph_node(nid, is_endpoint) and len(segment_nodes) >= 2:
                pts = [coords[n] for n in segment_nodes if n in coords]
                if len(pts) >= 2:
                    edges.append({
                        "way_id": way_id,
                        "from_node": segment_nodes[0],
                        "to_node": segment_nodes[-1],
                        "tags": tags,
                        "points": pts,  # [(lon, lat), ...]
                    })
                segment_nodes = [nid]

    print(f"  {len(edges)} Graph-Kanten erzeugt")

    with open(output_path, "w") as f:
        json.dump({"edges": edges}, f)
    print(f"Geschrieben: {output_path}")


if __name__ == "__main__":
    main()
