#!/usr/bin/env python3
"""
Baut einen gewichteten Wege-Graphen wie `build_way_graph.py`, aber im neuen, `mmap`-freundlichen
Flachdatei-Format v2 statt als SQLite-Datei - Pilotversuch für die Niederlande (2026-07-27,
Nutzerwunsch: erste Ladezeit der Offline-Routing-Engine nochmal deutlich senken, s. ROADMAP.md
"Wege-Graph per mmap statt über SQLite lesen").

Unterschied zum bisherigen Format (siehe `WayGraphRepository.swift`, Format v1):
- Kanten liegen bereits **auf der Platte** nach `fromNode` sortiert/gruppiert vor (CSR-Layout) -
  die App muss sie nicht mehr selbst zur Laufzeit in zwei Durchläufen umsortieren.
- Jede Kante spart sich das `fromNode`-Feld (4 Byte) - die Position im sortierten Array codiert es
  bereits implizit (17 statt 21 Byte/Kante).
- Kein SQLite-Container mehr, reine Flachdatei mit festem Header + Sektionen - die App liest sie
  per `mmap` und dekodiert nur die tatsächlich angefassten Kanten on-demand, statt beim Laden den
  kompletten Graphen in eigene Swift-Arrays zu kopieren (das war bei großen Ländern der
  dominante Anteil der Ladezeit, s. ROADMAP.md).

Nutzung:
    Scripts/venv/bin/python3 Scripts/build_way_graph_v2.py \
        Scripts/data/netherlands-latest.osm.pbf Scripts/data/netherlands_ways_v2.bin

Dateiformat (little-endian):
    Header (16 Byte): "RFG2" (4 Byte Magic) + UInt32 nodeCount + UInt32 edgeCount + UInt32 nameCount
    Nodes-Sektion (nodeCount * 8 Byte): je Float32 lat, Float32 lon
    EdgeOffsets-Sektion ((nodeCount + 1) * 4 Byte): je UInt32 - Startindex der Kanten dieses
        Knotens im flachen, nach fromNode sortierten Kanten-Array (CSR-Layout)
    Edges-Sektion (edgeCount * 17 Byte), nach fromNode sortiert: je UInt32 toNode,
        Float32 distanceMeters, Float32 weight, UInt8 offsetSide, UInt32 nameIndex
    Names-Sektion (nameCount Einträge): je UInt16 byteLength + UTF-8-Bytes
"""

import struct
import sys
from pathlib import Path

import osmium

from build_way_graph import (
    direction,
    is_bikeable,
    offset_side,
    haversine_meters,
    weight_multiplier,
)

NO_NAME = 0xFFFFFFFF
MAGIC = b"RFG2"


def build(pbf_path: str, output_path: str):
    Path(output_path).unlink(missing_ok=True)

    node_index = {}
    node_coords = []
    # (from_index, to_index, distance_m, weight, offset_side, name_index)
    edge_rows = []
    name_index_map = {}
    name_list = []
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
                return NO_NAME
            name_index_map[name] = idx
            name_list.append(name)
        return idx

    print("Pass 1: Ways verarbeiten...")
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
                backward_side = {0: 0, 1: 2, 2: 1}[side]
                edge_rows.append((b_idx, a_idx, distance, weight, backward_side, name_idx))

    node_count = len(node_coords)
    edge_count = len(edge_rows)
    name_count = len(name_list)
    print(f"Wege verarbeitet: {way_count}")
    print(f"Knoten: {node_count}")
    print(f"Kanten: {edge_count}")
    print(f"Eindeutige Straßennamen: {name_count}")

    print("Pass 2: Kanten nach fromNode sortieren (CSR-Layout)...")
    edge_rows.sort(key=lambda e: e[0])

    print("Pass 3: EdgeOffsets berechnen...")
    edge_offsets = [0] * (node_count + 1)
    cursor = 0
    row_iter = iter(edge_rows)
    row = next(row_iter, None)
    for node in range(node_count):
        while row is not None and row[0] == node:
            cursor += 1
            row = next(row_iter, None)
        edge_offsets[node + 1] = cursor

    print("Schreibe Flachdatei...")
    # Byte-Blobs per `b"".join(generator)` statt vieler einzelner `f.write()`-Aufrufe (bei
    # Millionen Elementen sonst spürbar langsamer durch Python-/Syscall-Overhead pro Aufruf) -
    # gleiches Muster wie in `build_way_graph.py`.
    nodes_blob = b"".join(struct.pack("<ff", lat, lon) for lat, lon in node_coords)
    offsets_blob = b"".join(struct.pack("<I", offset) for offset in edge_offsets)
    edges_blob = b"".join(
        struct.pack("<IffBI", to, distance, weight, side, name_idx)
        for _from, to, distance, weight, side, name_idx in edge_rows
    )
    names_blob = b"".join(
        struct.pack("<H", len(encoded)) + encoded
        for encoded in (name.encode("utf-8") for name in name_list)
    )

    with open(output_path, "wb") as f:
        f.write(MAGIC)
        f.write(struct.pack("<III", node_count, edge_count, name_count))
        f.write(nodes_blob)
        f.write(offsets_blob)
        f.write(edges_blob)
        f.write(names_blob)

    size_mb = Path(output_path).stat().st_size / (1024 * 1024)
    print(f"Fertig: {output_path} ({size_mb:.1f} MB)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Nutzung: build_way_graph_v2.py <input.osm.pbf> <output.bin>")
        sys.exit(1)
    build(sys.argv[1], sys.argv[2])
