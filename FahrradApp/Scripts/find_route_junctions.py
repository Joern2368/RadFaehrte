#!/usr/bin/env python3
"""
Findet Anschlussstellen zwischen benannten Radfernwegen (Netzwerke rcn/ncn/icn) über alle
gebündelten Routen-Datenbanken hinweg und schreibt sie als eigene Sidecar-DB
(route_junctions.sqlite), die ContentView/RouteMatcher zur Laufzeit für die Suche nach
kombinierten Routen (mehrere Fernwege verketten) nutzt.

Zwei Routen gelten als "verbunden", wenn ihre Geometrien sich auf höchstens JUNCTION_THRESHOLD_M
Meter annähern (typischerweise: sie berühren oder kreuzen sich an einem gemeinsamen Wegpunkt/einer
Kreuzung). Beschränkt auf rcn/ncn/icn (regionale/nationale/internationale Fernwege) - die deutlich
zahlreicheren lokalen lcn-Knotenpunktnetz-Fragmente sind dafür zu kleinteilig/unübersichtlich
(Analyse vom 2026-07-29: 7.018 benannte rcn/ncn/icn-Routen, davon 99% mit mind. einer
Anschlussstelle, ⌀ 12,4 Partner pro Route - siehe Referenzwerte im Sanity-Check unten).

Schwellenwert 2026-07-30 von 30 auf 75 m angehoben: Nutzer-Beispiel Lübeck→Wismar fand keine
Kombination, obwohl "Alte Salzstraße" (Lübeck→Travemünde) und der "Ostseeküsten-Radweg"/D2
(Travemünde→Wismar) sich in Travemünde erkennbar treffen - tatsächliche Distanz per Analyse-Skript
gemessen: 60,6 m (vermutlich unterschiedliche Straßenseiten/Hafen-/Fähranleger-Bereich). Mit 75 m
wächst der Anschluss-Graph nur moderat (24.067 → 24.314 ungerichtete Kanten, +8 zusätzlich vernetzte
Routen von 3.517 auf 3.525) - Stichprobe der neu hinzugekommenen Kanten zeigte ausschließlich
plausible, geografisch benachbarte Fernweg-Paare (u. a. Fluss-Zusammenflüsse wie Unstrutradweg/
Saaleradweg), keine erkennbaren Fehlverbindungen. Bestehende Sanity-Check-Referenzbeispiele
(Weser/Aller/Leine-Heide) weiterhin unverändert gefunden.

⚠️ WICHTIG: Diese Datei ist ein manuell zu regenerierendes Derivat der vier Quell-DBs
(routes.sqlite + netherlands/poland/sweden.sqlite). Ändert sich eine dieser Dateien (neue
Relationen, Resimplifizierung, ein weiteres Land kommt dazu), muss dieses Skript erneut laufen und
route_junctions.sqlite neu committet werden - sonst arbeitet die Kombinationssuche in der App mit
veralteten Anschlussdaten, ohne dass das auffällt. Gleiches Prinzip wie bei den Wege-Graphen
(s. ROADMAP.md, "vergiss nicht, X neu zu bauen").

Nutzung:
    Scripts/venv/bin/python3 Scripts/find_route_junctions.py \
        RadFaehrte/Resources/routes.sqlite \
        RadFaehrte/Resources/netherlands.sqlite \
        RadFaehrte/Resources/poland.sqlite \
        RadFaehrte/Resources/sweden.sqlite \
        --output RadFaehrte/Resources/route_junctions.sqlite

Fehlende Eingabedateien werden übersprungen (nicht jede Umgebung hat alle vier lokal). OSM-
Relation-IDs sind global eindeutig über alle vier Dateien hinweg (bereits bestehende Invariante,
s. RouteRepository.swift), daher werden alle zusammen verarbeitet - das erfasst nebenbei auch
grenzüberschreitende Anschlüsse (z. B. eine EuroVelo-Route, die nach Polen oder in die Niederlande
weiterläuft).
"""

import argparse
import math
import re
import struct
import sqlite3
import sys
from pathlib import Path

from shapely.geometry import LineString, MultiLineString
from shapely.ops import nearest_points
from shapely.strtree import STRtree

JUNCTION_THRESHOLD_M = 75.0
NETWORKS = ("rcn", "ncn", "icn")

# Viele Regionen taggen ihr lokales Knotenpunkt-Wegenetz (einzelne Wegabschnitte zwischen
# nummerierten Knoten) mit network=rcn statt lcn - nicht allein am network-Tag von einem echten
# Fernweg zu unterscheiden. Gefunden beim ersten Testlauf der Kombinationssuche (Bremen->Hannover
# verlor sich zunächst in Bremens eigenem "Grüner Ring"-Knotennetz statt über den Weser-Radweg zu
# laufen). Zwei beobachtete Namensmuster (2026-07-29 gegen die echte routes.sqlite geprüft):
# rein numerisch ("31-32", 812 von 7.018 Treffern) und Ort+Knotennummer ("Lohne (76) -
# Dinklage (78)", 3.586 von 7.018 Treffern - über die Hälfte aller benannten rcn/ncn/icn-Routen!).
# Keine bekannte echte Fernweg-Route (Weser-Radweg, Aller-Radweg, Leine-Heide-Radweg, ...) matcht
# eines der beiden Muster - ausgeschlossen, damit der Anschluss-Graph nur "echte" Fernwege verbindet.
#
# Zwei weitere Muster gefunden beim Live-Test Berlin->Den Haag (2026-07-29): Die App verkettete
# u. a. "Knotenpunktwegweisung Oberhavel", "Knotenpunktnetz Landkreis Ostprignitz-Ruppin" (beides
# eindeutig lokale Knotenpunkt-Netze, am Namen als solche erkennbar, aber keins der beiden obigen
# Muster) sowie "71 - Rübehorst (72)" (Mischform aus rein-numerischem und Ort+Nummer-Muster, von
# keinem der beiden bisherigen Patterns erfasst) in eine "kombinierte Route" ein. Ergänzt:
# Namen mit "Knotenpunkt" (deutschsprachiger Fachbegriff, keine bekannte echte Fernweg-Route
# verwendet ihn im Namen) sowie die Mischform "Zahl - Text (Zahl)"/"Text (Zahl) - Zahl".
#
# Zwei weitere Muster gefunden bei der Untersuchung eines größeren JUNCTION_THRESHOLD_M (2026-07-30,
# Nutzer-Beispiel Brückenradweg/Friedensroute Bremen-Osnabrück-Münster): Bei testweise 300 m
# (nicht übernommen, s. u.) wären u. a. "OSL 37-46"/"OSL36-58" (Landkreis-Präfix + Knotenpunkt-
# Zahlen) und die nackte Zahl "37" fälschlich mit echten Fernwegen verkettet worden - beide
# gegen die komplette Datenbank geprüft (40 bzw. 1 Treffer), keiner davon sieht wie eine echte
# Fernweg-Route aus. Ein drittes, breiteres Muster ("beliebiger Name, endet auf '(Zahl)'", 21
# Treffer) bewusst NICHT ergänzt - darunter "Fünf-Flüsse-Radweg (07)", eine Route, die bereits
# nachweislich Teil einer echten Kombination war (München->Nürnberg-Beispiel) - ob das "(07)" eine
# Etappennummer oder ein Knotenpunkt-Verweis ist, ließ sich ohne die zugrundeliegenden OSM-Tags
# nicht sicher klären, das Risiko eines Fehlausschlusses war hier höher als bei den beiden engen
# Mustern unten.
NODE_TO_NODE_NAME_PATTERNS = [
    re.compile(r"^\d+\s*-\s*\d+$"),
    re.compile(r".*\(\d+\).*-.*\(\d+\).*"),
    re.compile(r"^\d+\s*-\s*.+\(\d+\)\s*$"),
    re.compile(r"^.+\(\d+\)\s*-\s*\d+$"),
    re.compile(r"^\d+$"),
    re.compile(r"^[A-Za-zÄÖÜäöüß]{1,6}\s*\d+\s*-\s*\d+$"),
]


def is_node_to_node_segment(name):
    if "knotenpunkt" in name.lower():
        return True
    return any(pattern.match(name) for pattern in NODE_TO_NODE_NAME_PATTERNS)

# Grobe mittlere Breite für Deutschland/Mitteleuropa, reicht für eine lokale Meter-Näherung bei
# einem Schwellenwert von wenigen zehn Metern völlig aus (kein geodätisch exaktes Modell nötig).
LAT0 = 51.0
M_PER_DEG_LAT = 111_320.0
M_PER_DEG_LON = 111_320.0 * math.cos(math.radians(LAT0))


def decode_geometry(blob):
    """Spiegelt RouteRepository.decodeGeometry: LE UInt32 numLines, je Linie UInt32 numPoints,
    dann numPoints * (Float32 lon, Float32 lat)."""
    offset = 0
    (num_lines,) = struct.unpack_from("<I", blob, offset)
    offset += 4
    lines = []
    for _ in range(num_lines):
        (num_points,) = struct.unpack_from("<I", blob, offset)
        offset += 4
        pts = []
        for _ in range(num_points):
            lon, lat = struct.unpack_from("<ff", blob, offset)
            offset += 8
            pts.append((lon, lat))
        lines.append(pts)
    return lines


def to_local_meters(lon, lat):
    return (lon * M_PER_DEG_LON, lat * M_PER_DEG_LAT)


def to_lon_lat(x, y):
    return (x / M_PER_DEG_LON, y / M_PER_DEG_LAT)


def load_routes(db_paths):
    """Lädt benannte rcn/ncn/icn-Routen aus allen vorhandenen DBs. Gibt dict routeId -> {name,
    network, ref, lines (Liste von Punktlisten in lokalen Metern)} zurück.

    Bewusst KEINE zusammengesetzte shapely-Geometrie pro Route (MultiLineString über die
    Gesamtstrecke) - das Buffern/Distanzmessen ganzer, teils tausende Punkte langer Routen
    geometrisch ist extrem teuer (erster Versuch brauchte >39 Min. ohne Ergebnis). Stattdessen wie
    in der validierten Machbarkeitsprüfung auf Ebene einzelner, kurzer Liniensegmente arbeiten -
    jedes Segment einzeln puffern/indizieren ist um Größenordnungen billiger."""
    routes = {}
    for path in db_paths:
        if not Path(path).exists():
            print(f"  überspringe (nicht gefunden): {path}")
            continue
        con = sqlite3.connect(path)
        rows = con.execute(
            "SELECT id, name, network, ref, geometry FROM routes "
            "WHERE name IS NOT NULL AND name != '' AND network IN (?, ?, ?)",
            NETWORKS,
        ).fetchall()
        con.close()
        print(f"  {path}: {len(rows)} benannte rcn/ncn/icn-Routen")
        for rid, name, network, ref, blob in rows:
            if rid in routes:
                print(f"  WARNUNG: doppelte Route-ID {rid} über mehrere DBs hinweg - übersprungen")
                continue
            if is_node_to_node_segment(name):
                continue
            lines = decode_geometry(blob)
            local_lines = [
                [to_local_meters(lon, lat) for lon, lat in line] for line in lines if len(line) >= 2
            ]
            if not local_lines:
                continue
            routes[rid] = {"name": name, "network": network, "ref": ref, "lines": local_lines}
    return routes


def find_junctions(routes):
    """Liefert eine Liste (route_a, route_b, lon, lat) - eine Zeile je Richtung, damit die App
    mit einem einzigen `WHERE route_a = ?` abfragen kann.

    Arbeitet auf Ebene einzelner Liniensegmente (Punktpaare) statt ganzer Routen-Geometrien:
    ein STRtree über alle Segmente aller Routen, pro Segment ein 30m-Buffer-Query gegen den Baum.
    Das ist die exakte Vorgehensweise aus der vorab durchgeführten Machbarkeitsprüfung (dort für
    7.018 Routen mit ~1,08 Mio. Segmenten in ca. 5-6 Min. durchgelaufen)."""
    segment_geoms = []
    segment_route_id = []
    for rid, r in routes.items():
        for line in r["lines"]:
            segment_geoms.append(LineString(line))
            segment_route_id.append(rid)

    print(f"  {len(segment_geoms)} Liniensegmente insgesamt (statt {len(routes)} Gesamt-Geometrien)")
    tree = STRtree(segment_geoms)

    results = []
    seen_pairs = set()
    for idx, geom in enumerate(segment_geoms):
        rid_a = segment_route_id[idx]
        buffered = geom.buffer(JUNCTION_THRESHOLD_M)
        for j in tree.query(buffered):
            rid_b = segment_route_id[j]
            if rid_b == rid_a:
                continue
            pair_key = (min(rid_a, rid_b), max(rid_a, rid_b))
            if pair_key in seen_pairs:
                continue
            other_geom = segment_geoms[j]
            if not buffered.intersects(other_geom):
                continue
            seen_pairs.add(pair_key)
            point_a, point_b = nearest_points(geom, other_geom)
            mid_x = (point_a.x + point_b.x) / 2
            mid_y = (point_a.y + point_b.y) / 2
            lon, lat = to_lon_lat(mid_x, mid_y)
            results.append((rid_a, rid_b, lon, lat))
            results.append((rid_b, rid_a, lon, lat))
    return results


def write_output(junctions, routes, output_path):
    Path(output_path).unlink(missing_ok=True)
    con = sqlite3.connect(output_path)
    con.execute(
        """
        CREATE TABLE junctions (
            route_a INTEGER NOT NULL,
            route_b INTEGER NOT NULL,
            lon REAL NOT NULL,
            lat REAL NOT NULL,
            route_a_name TEXT,
            route_b_name TEXT
        )
        """
    )
    con.executemany(
        "INSERT INTO junctions (route_a, route_b, lon, lat, route_a_name, route_b_name) "
        "VALUES (?, ?, ?, ?, ?, ?)",
        [
            (a, b, lon, lat, routes[a]["name"], routes[b]["name"])
            for a, b, lon, lat in junctions
        ],
    )
    con.execute("CREATE INDEX idx_junctions_route_a ON junctions(route_a)")
    con.commit()
    con.execute("VACUUM")
    con.close()


def print_sanity_check(routes, junctions):
    """Vergleicht gegen die am 2026-07-29 gegen die echte routes.sqlite gemessenen Referenzwerte
    (7.018 Routen, 99% vernetzt, ⌀12,4 Partner, ~43.090 ungerichtete Kanten) und prüft konkret das
    validierte Nutzerbeispiel Weser-/Aller-/Leine-Heide-Radweg."""
    print("\n--- Sanity-Check ---")
    print(f"Benannte rcn/ncn/icn-Routen insgesamt: {len(routes)}")
    undirected = len(junctions) // 2
    print(f"Ungerichtete Anschluss-Kanten: {undirected} (Referenz: ~43.090)")

    involved = {a for a, b, lon, lat in junctions}
    print(f"Routen mit mind. 1 Anschluss: {len(involved)} von {len(routes)} "
          f"(Referenz: 6.956 von 7.018 ≈ 99%)")
    if involved:
        from collections import Counter
        deg = Counter(a for a, b, lon, lat in junctions)
        avg_deg = sum(deg.values()) / len(deg)
        print(f"⌀ Anschluss-Partner: {avg_deg:.1f} (Referenz: 12,4), Max: {max(deg.values())} "
              f"(Referenz: 522)")

    def find_by_substr(sub):
        return [rid for rid, r in routes.items() if sub.lower() in (r["name"] or "").lower()]

    weser_ids = set(find_by_substr("weser-radweg"))
    aller_ids = set(find_by_substr("aller-radweg"))
    leine_ids = set(find_by_substr("leine-heide-radweg"))

    def has_junction(set_a, set_b):
        return any(
            (a in set_a and b in set_b) or (a in set_b and b in set_a)
            for a, b, lon, lat in junctions
        )

    weser_aller_ok = has_junction(weser_ids, aller_ids) if weser_ids and aller_ids else None
    aller_leine_ok = has_junction(aller_ids, leine_ids) if aller_ids and leine_ids else None
    print(f"\nNutzerbeispiel Weser-Radweg <-> Aller-Radweg: "
          f"{'✓ gefunden' if weser_aller_ok else '✗ NICHT gefunden' if weser_aller_ok is False else '(Route nicht in Datenbestand gefunden)'}")
    print(f"Nutzerbeispiel Aller-Radweg <-> Leine-Heide-Radweg: "
          f"{'✓ gefunden' if aller_leine_ok else '✗ NICHT gefunden' if aller_leine_ok is False else '(Route nicht in Datenbestand gefunden)'}")

    if weser_aller_ok is False or aller_leine_ok is False:
        print("\n⚠️  WARNUNG: Das bekannte, bereits validierte Nutzerbeispiel wurde nicht "
              "gefunden - Threshold/Filter/Projektion prüfen, bevor die Datei committet wird!")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("inputs", nargs="+", help="Pfade zu routes.sqlite und ggf. Länder-DBs")
    parser.add_argument("--output", required=True, help="Zielpfad für route_junctions.sqlite")
    args = parser.parse_args()

    print("Lade Routen...")
    routes = load_routes(args.inputs)
    print(f"Insgesamt geladen: {len(routes)} Routen")

    print("\nSuche Anschlussstellen (Schwellenwert {:.0f} m)...".format(JUNCTION_THRESHOLD_M))
    junctions = find_junctions(routes)
    print(f"Gefunden: {len(junctions) // 2} ungerichtete Anschluss-Kanten")

    print(f"\nSchreibe {args.output}...")
    write_output(junctions, routes, args.output)

    print_sanity_check(routes, junctions)
    print(f"\nFertig: {args.output}")


if __name__ == "__main__":
    sys.exit(main())
