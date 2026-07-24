#!/bin/bash
set -e
cd "$(dirname "$0")/.."

STATES="bayern berlin brandenburg hamburg hessen mecklenburg-vorpommern niedersachsen nordrhein-westfalen rheinland-pfalz saarland sachsen sachsen-anhalt schleswig-holstein thueringen"

for slug in $STATES; do
  echo "=== $slug: downloading ==="
  curl -L -o "Scripts/data/${slug}-latest.osm.pbf" "https://download.geofabrik.de/europe/germany/${slug}-latest.osm.pbf"

  echo "=== $slug: building graph ==="
  ./Scripts/venv/bin/python3 Scripts/build_way_graph.py "Scripts/data/${slug}-latest.osm.pbf" "Scripts/data/${slug}_ways.sqlite"

  echo "=== $slug: done, size: ==="
  ls -lh "Scripts/data/${slug}_ways.sqlite"

  echo "=== $slug: removing source pbf to save space ==="
  rm "Scripts/data/${slug}-latest.osm.pbf"
done

echo "=== ALL DONE ==="
