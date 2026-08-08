#!/bin/bash
# Baut alle 16 Bundesländer-Wege-Graphen im v4-Format (Straßennamen mit UInt32-Index statt des
# fehlerhaften UInt16-Index aus dem zurückgezogenen v3, siehe build_way_graph.py) neu und lädt
# sie als Assets in den GitHub-Release way-graphs-v4 hoch.
set -uo pipefail
cd "$(dirname "$0")/.."

export PATH="$HOME/.local/bin:$PATH"

STATES="bremen baden-wuerttemberg bayern berlin brandenburg hamburg hessen mecklenburg-vorpommern niedersachsen nordrhein-westfalen rheinland-pfalz saarland sachsen sachsen-anhalt schleswig-holstein thueringen"

FAILED=""

for slug in $STATES; do
  echo "=== $slug: downloading ==="
  if ! curl -sL --fail -o "Scripts/data/${slug}-latest.osm.pbf" "https://download.geofabrik.de/europe/germany/${slug}-latest.osm.pbf"; then
    echo "=== $slug: DOWNLOAD FAILED ==="
    FAILED="$FAILED $slug(download)"
    continue
  fi

  echo "=== $slug: building graph ==="
  if ! ./Scripts/venv/bin/python3 Scripts/build_way_graph.py "Scripts/data/${slug}-latest.osm.pbf" "Scripts/data/${slug}_ways.sqlite"; then
    echo "=== $slug: BUILD FAILED ==="
    FAILED="$FAILED $slug(build)"
    rm -f "Scripts/data/${slug}-latest.osm.pbf"
    continue
  fi

  echo "=== $slug: uploading to way-graphs-v4 ==="
  if ! gh release upload way-graphs-v4 "Scripts/data/${slug}_ways.sqlite" --repo Joern2368/RadFaehrte --clobber; then
    echo "=== $slug: UPLOAD FAILED ==="
    FAILED="$FAILED $slug(upload)"
  fi

  echo "=== $slug: file size ==="
  ls -la "Scripts/data/${slug}_ways.sqlite"

  echo "=== $slug: cleaning up local files ==="
  rm -f "Scripts/data/${slug}-latest.osm.pbf" "Scripts/data/${slug}_ways.sqlite"

  echo "=== $slug: done ==="
done

echo "=== ALL DONE ==="
if [ -n "$FAILED" ]; then
  echo "FEHLGESCHLAGEN:$FAILED"
  exit 1
fi
