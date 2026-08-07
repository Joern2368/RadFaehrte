#!/usr/bin/env python3
"""Ad-hoc: fuer die N naechsten Knoten zu einer Koordinate pruefen, wie viele davon zur
grossen Hauptkomponente (BFS ab einem bekannten gut angebundenen Punkt) gehoeren - hilft
abzuschaetzen, wie gross der Suchradius/die Kandidatenzahl in BikeRoutingEngine.nearestNodesPoolSize
tatsaechlich sein muesste, um eine isolierte Graph-Insel zu umgehen.

Nutzung:
    python3 debug_nearby_reachability.py <graph.bin> <mainLat> <mainLon> <queryLat> <queryLon> [N]
"""
import struct
import sys
from collections import deque


def load(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:4] == b"RFG2"
    node_count, edge_count, name_count = struct.unpack_from("<III", data, 4)
    off = 16
    nodes = struct.unpack_from(f"<{node_count * 2}f", data, off)
    off += node_count * 8
    edge_offsets = struct.unpack_from(f"<{node_count + 1}I", data, off)
    off += (node_count + 1) * 4
    edges_to = struct.unpack_from(f"<{edge_count}I", data, off) if False else None
    # Kanten-Satz enthaelt mehr als nur toNode (17 Byte/Kante) - toNode einzeln lesen.
    edges_to = []
    base = off
    for i in range(edge_count):
        to_node = struct.unpack_from("<I", data, base + i * 17)[0]
        edges_to.append(to_node)
    return node_count, edge_count, nodes, edge_offsets, edges_to


def nearest_node(nodes, node_count, lat, lon):
    best_idx, best_d = -1, 1e18
    for i in range(node_count):
        d = (nodes[i * 2] - lat) ** 2 + (nodes[i * 2 + 1] - lon) ** 2
        if d < best_d:
            best_d = d
            best_idx = i
    return best_idx


def bfs_reachable_set(node_count, edge_offsets, edges_to, start):
    seen = bytearray(node_count)
    seen[start] = 1
    q = deque([start])
    while q:
        n = q.popleft()
        for e in range(edge_offsets[n], edge_offsets[n + 1]):
            t = edges_to[e]
            if not seen[t]:
                seen[t] = 1
                q.append(t)
    return seen


def main():
    path = sys.argv[1]
    main_lat, main_lon = float(sys.argv[2]), float(sys.argv[3])
    q_lat, q_lon = float(sys.argv[4]), float(sys.argv[5])
    n = int(sys.argv[6]) if len(sys.argv) > 6 else 100

    print(f"Lade {path} ...")
    node_count, edge_count, nodes, edge_offsets, edges_to = load(path)
    print(f"Knoten: {node_count}, Kanten: {edge_count}")

    main_idx = nearest_node(nodes, node_count, main_lat, main_lon)
    print(f"Hauptkomponenten-Startknoten {main_idx} bei ({nodes[main_idx*2]:.5f},{nodes[main_idx*2+1]:.5f})")
    seen = bfs_reachable_set(node_count, edge_offsets, edges_to, main_idx)
    reachable_count = sum(seen)
    print(f"Hauptkomponente: {reachable_count}/{node_count} ({100*reachable_count/node_count:.2f}%)")

    metersPerDegreeLat = 111_320.0
    import math
    metersPerDegreeLon = metersPerDegreeLat * max(math.cos(math.radians(q_lat)), 0.1)

    dists = []
    for i in range(node_count):
        dy = (nodes[i * 2] - q_lat) * metersPerDegreeLat
        dx = (nodes[i * 2 + 1] - q_lon) * metersPerDegreeLon
        dists.append((dx * dx + dy * dy, i))
    dists.sort(key=lambda t: t[0])

    print(f"\n{n} naechste Knoten zu ({q_lat},{q_lon}):")
    first_main_component_rank = None
    for rank, (d2, idx) in enumerate(dists[:n]):
        in_main = bool(seen[idx])
        if in_main and first_main_component_rank is None:
            first_main_component_rank = rank
        if rank < 15 or in_main:
            print(f"  #{rank}: node={idx} dist={d2**0.5:.0f}m in_main_component={in_main}")
    print(f"\nErster Hauptkomponenten-Kandidat: Rang {first_main_component_rank} (von {n} geprueft)")


if __name__ == "__main__":
    main()
