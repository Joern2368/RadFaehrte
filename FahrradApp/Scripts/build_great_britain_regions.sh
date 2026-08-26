#!/bin/bash
# Baut die Offline-Wege-Graphen (Format v2) für die 49 großbritannischen Regionen (47 englische
# Grafschaften + Schottland + Wales) einzeln - analog Scripts/build_spain_regions.sh. Anders als
# bei Spanien/Norwegen sind die Grafschaften nicht alle unter demselben Geofabrik-Pfad-Präfix
# erreichbar: Grafschaften liegen unter europe/united-kingdom/england/<slug>, Schottland/Wales
# direkt unter europe/united-kingdom/<slug> - deshalb ein zweites, optionales Argument je Region
# in REGIONS (Pfad-Präfix nach "slug:prefix", Default "england" wenn nur der Slug angegeben ist).
#
# Nutzer-Wunsch: Bei 49 Regionen nicht wie bei Spanien/Norwegen alle unbeaufsichtigt am Stück,
# sondern in Fünfer-Gruppen mit Zwischen-Check aufrufen - deshalb nimmt dieses Skript die zu
# bauenden Regionen als Kommandozeilen-Argumente entgegen (Slugs, durch Leerzeichen getrennt)
# statt intern immer alle 49 zu durchlaufen. Beispiel: ein Fünfer-Batch mit
# `./Scripts/build_great_britain_regions.sh bedfordshire berkshire bristol buckinghamshire cambridgeshire`.
set -uo pipefail
cd "$(dirname "$0")/.."

export PATH="$HOME/.local/bin:$PATH"

# Slug -> Geofabrik-Pfad-Präfix (nur die beiden Ausnahmen, alle anderen sind Grafschaften unter
# .../england/).
prefix_for() {
  case "$1" in
    scotland|wales) echo "europe/united-kingdom" ;;
    *) echo "europe/united-kingdom/england" ;;
  esac
}

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <slug> [<slug> ...]" >&2
  exit 1
fi

SUMMARY="Scripts/data/great_britain_regions_summary.txt"
touch "$SUMMARY"

FAILED=""

for slug in "$@"; do
  PREFIX=$(prefix_for "$slug")

  echo "=== $slug: downloading ==="
  EXPECTED=$(curl -sIL --fail "https://download.geofabrik.de/${PREFIX}/${slug}-latest.osm.pbf" | grep -i content-length | tail -1 | tr -d '\r' | awk '{print $2}')
  if ! curl -L --fail --retry 3 -o "Scripts/data/${slug}-latest.osm.pbf" "https://download.geofabrik.de/${PREFIX}/${slug}-latest.osm.pbf"; then
    echo "=== $slug: DOWNLOAD FAILED ==="
    FAILED="$FAILED $slug(download)"
    continue
  fi
  ACTUAL=$(stat -f%z "Scripts/data/${slug}-latest.osm.pbf")
  if [ -n "$EXPECTED" ] && [ "$ACTUAL" -lt $((EXPECTED - 1000000)) ]; then
    echo "=== $slug: DOWNLOAD WIRKT ABGESCHNITTEN ($ACTUAL von $EXPECTED Bytes) ==="
    FAILED="$FAILED $slug(truncated)"
    rm -f "Scripts/data/${slug}-latest.osm.pbf"
    continue
  fi

  BBOX=$(./Scripts/venv/bin/python3 -c "
import osmium
h = osmium.io.Reader('Scripts/data/${slug}-latest.osm.pbf').header()
print(h.box())
" 2>/dev/null)

  echo "=== $slug: building graph ==="
  BUILD_START=$(date +%s)
  if ! ./Scripts/venv/bin/python3 Scripts/build_way_graph_v2.py "Scripts/data/${slug}-latest.osm.pbf" "Scripts/data/${slug}_ways.sqlite" > "Scripts/data/${slug}_build.log" 2>&1; then
    echo "=== $slug: BUILD FAILED ==="
    FAILED="$FAILED $slug(build)"
    rm -f "Scripts/data/${slug}-latest.osm.pbf"
    continue
  fi
  BUILD_END=$(date +%s)
  BUILD_SECS=$((BUILD_END - BUILD_START))

  SIZE_BYTES=$(stat -f%z "Scripts/data/${slug}_ways.sqlite")

  if [ "$SIZE_BYTES" -ge 2147483648 ]; then
    echo "=== $slug: AUSGABE ZU GROSS FÜR GITHUB (>2 GiB) ==="
    FAILED="$FAILED $slug(too-large)"
    rm -f "Scripts/data/${slug}-latest.osm.pbf" "Scripts/data/${slug}_ways.sqlite" "Scripts/data/${slug}_build.log"
    continue
  fi

  echo "=== $slug: uploading to way-graphs-gb-v1 ==="
  if ! gh release upload way-graphs-gb-v1 "Scripts/data/${slug}_ways.sqlite" --repo Joern2368/RadFaehrte --clobber; then
    echo "=== $slug: UPLOAD FAILED ==="
    FAILED="$FAILED $slug(upload)"
    rm -f "Scripts/data/${slug}-latest.osm.pbf" "Scripts/data/${slug}_ways.sqlite"
    continue
  fi

  STATS_LINE=$(grep -E "Knoten:|Kanten:|Straßennamen:" "Scripts/data/${slug}_build.log" | tr '\n' ' ')
  echo "${slug}|${SIZE_BYTES}|${BUILD_SECS}|${BBOX}|${STATS_LINE}" >> "$SUMMARY"

  echo "=== $slug: cleaning up local files ==="
  rm -f "Scripts/data/${slug}-latest.osm.pbf" "Scripts/data/${slug}_ways.sqlite" "Scripts/data/${slug}_build.log"

  echo "=== $slug: done (${SIZE_BYTES} bytes, ${BUILD_SECS}s) ==="
done

echo "=== BATCH DONE ==="
cat "$SUMMARY"
if [ -n "$FAILED" ]; then
  echo "FEHLGESCHLAGEN:$FAILED"
  exit 1
fi
