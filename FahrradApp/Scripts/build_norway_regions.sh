#!/bin/bash
# Baut die Offline-Wege-Graphen (Format v2) für die 6 norwegischen Regionen einzeln - analog
# Scripts/build_spain_regions.sh. Vorsorglich aufgeteilt statt als eine Datei (Norwegens
# Gesamt-PBF ~1,37 GB, in der Größenordnung von Polen/Schweden, die zwar erfolgreich als
# Einzeldatei gebaut wurden, aber Italiens Lehre - Ausgabe teils größer als PBF durch dichte
# Kartierung - macht das Risiko real genug, direkt aufzuteilen). Geofabrik bietet Norwegen in 5
# "echten" Regionen (Fylker-Gruppierungen) plus der Exklave Svalbard/Jan Mayen an. Tatsächliche
# Wege-Graph-Größen nach dem Build: zwischen ~1,1 MB (Svalbard/Jan Mayen) und 536 MB (Østlandet) -
# analog Ceuta/Melilla bei Spanien wird die winzige Exklave mit aufgenommen statt gesondert
# behandelt.
set -uo pipefail
cd "$(dirname "$0")/.."

export PATH="$HOME/.local/bin:$PATH"

REGIONS="nord-norge ostlandet sorlandet svalbard-janmayen trondelag vestlandet"

SUMMARY="Scripts/data/norway_regions_summary.txt"
> "$SUMMARY"

FAILED=""

for slug in $REGIONS; do
  echo "=== $slug: downloading ==="
  EXPECTED=$(curl -sIL --fail "https://download.geofabrik.de/europe/norway/${slug}-latest.osm.pbf" | grep -i content-length | tail -1 | tr -d '\r' | awk '{print $2}')
  if ! curl -L --fail --retry 3 -o "Scripts/data/${slug}-latest.osm.pbf" "https://download.geofabrik.de/europe/norway/${slug}-latest.osm.pbf"; then
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

  echo "=== $slug: uploading to way-graphs-no-v1 ==="
  if ! gh release upload way-graphs-no-v1 "Scripts/data/${slug}_ways.sqlite" --repo Joern2368/RadFaehrte --clobber; then
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

echo "=== ALL DONE ==="
cat "$SUMMARY"
if [ -n "$FAILED" ]; then
  echo "FEHLGESCHLAGEN:$FAILED"
  exit 1
fi
