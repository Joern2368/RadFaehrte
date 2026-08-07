#!/usr/bin/env python3
"""Ad-hoc Diagnose-Skript: BFS-Erreichbarkeit im v2-Wege-Graphen ab einem Startpunkt.

Nutzung:
    python3 debug_reachability.py <graph.bin> <lat> <lon> [<lat2> <lon2> ...]

Findet für jeden angegebenen Punkt den naehesten Knoten (lineare Suche, fuer Diagnose ok) und
gibt die Groesse der von dort per BFS (nur ausgehende Kanten) erreichbaren Komponente aus.
"""
import struct
import sys
from collections import deque


def load(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:4] == b"RFG2", "kein RFG2-Header"
    node_count, edge_count, name_count = struct.unpack_from("<III", data, 4)
    off = 16
    nodes = struct.unpack_from(f"<{node_count * 2}f", data, off)
    off += node_count * 8
    edge_offsets = struct.unpack_from(f"<{node_count + 1}I", data, off)
    off += (node_count + 1) * 4
    edges_to = []
    edges_start = off
    for i in range(edge_count):
        to_node = struct.unpack_from("<I", data, edges_start + i * 17)[0]
        edges_to.append(to_node)
    return node_count, edge_count, nodes, edge_offsets, edges_to


def nearest_node(nodes, node_count, lat, lon):
    best_idx, best_d = -1, 1e18
    for i in range(node_count):
        nlat = nodes[i * 2]
        nlon = nodes[i * 2 + 1]
        d = (nlat - lat) ** 2 + (nlon - lon) ** 2
        if d < best_d:
            best_d = d
            best_idx = i
    return best_idx


def bfs_reachable(node_count, edge_offsets, edges_to, start):
    seen = bytearray(node_count)
    seen[start] = 1
    q = deque([start])
    count = 1
    while q:
        n = q.popleft()
        for e in range(edge_offsets[n], edge_offsets[n + 1]):
            t = edges_to[e]
            if not seen[t]:
                seen[t] = 1
                count += 1
                q.append(t)
    return count, seen


def main():
    path = sys.argv[1]
    coords = [float(x) for x in sys.argv[2:]]
    assert len(coords) % 2 == 0
    points = list(zip(coords[0::2], coords[1::2]))

    print(f"Lade {path} ...")
    node_count, edge_count, nodes, edge_offsets, edges_to = load(path)
    print(f"Knoten: {node_count}, Kanten: {edge_count}")

    for lat, lon in points:
        idx = nearest_node(nodes, node_count, lat, lon)
        nlat, nlon = nodes[idx * 2], nodes[idx * 2 + 1]
        reachable, seen = bfs_reachable(node_count, edge_offsets, edges_to, idx)
        pct = 100.0 * reachable / node_count
        print(
            f"Punkt ({lat},{lon}) -> Knoten {idx} bei ({nlat:.5f},{nlon:.5f}): "
            f"{reachable}/{node_count} erreichbar ({pct:.2f}%)"
        )


if __name__ == "__main__":
    main()
