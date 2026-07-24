#!/bin/bash
# Baut alle Bundesländer-Wege-Graphen im neuen v2-Format (mit Radweg-Versatz, siehe
# build_way_graph.py) neu und lädt sie als Assets in den GitHub-Release way-graphs-v2 hoch.
# Bremen wurde bereits manuell gebaut/hochgeladen und wird hier ausgelassen.
set -uo pipefail
cd "$(dirname "$0")/.."

export PATH="/private/tmp/claude-501/-Users-joern-Documents-Swift-FahrradApp/f5ff85bc-4c99-4218-867b-17bd83ed7c8e/scratchpad/gh/gh_2.96.0_macOS_arm64/bin:$PATH"

STATES="baden-wuerttemberg bayern berlin brandenburg hamburg hessen mecklenburg-vorpommern niedersachsen nordrhein-westfalen rheinland-pfalz saarland sachsen sachsen-anhalt schleswig-holstein thueringen"

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

  echo "=== $slug: uploading to way-graphs-v2 ==="
  if ! gh release upload way-graphs-v2 "Scripts/data/${slug}_ways.sqlite" --repo Joern2368/RadFaehrte --clobber; then
    echo "=== $slug: UPLOAD FAILED ==="
    FAILED="$FAILED $slug(upload)"
  fi

  echo "=== $slug: cleaning up local files ==="
  rm -f "Scripts/data/${slug}-latest.osm.pbf" "Scripts/data/${slug}_ways.sqlite"

  echo "=== $slug: done ==="
done

echo "=== ALL DONE ==="
if [ -n "$FAILED" ]; then
  echo "FEHLGESCHLAGEN:$FAILED"
  exit 1
fi
