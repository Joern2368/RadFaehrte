#!/bin/bash
set -e
cd "$(dirname "$0")/.."

# Bremen ist bereits mit Bänken (per Raster ausgedünnt) neu gebaut - hier alle restlichen 15
# Bundesländer, die noch die alte Fassung ganz ohne Bänke haben und deshalb komplett neu gebaut
# (nicht nur ergänzt) werden müssen.
STATES="niedersachsen baden-wuerttemberg bayern berlin brandenburg hamburg hessen mecklenburg-vorpommern nordrhein-westfalen rheinland-pfalz saarland sachsen sachsen-anhalt schleswig-holstein thueringen"

for slug in $STATES; do
  if [ -f "Scripts/data/${slug}-latest.osm.pbf" ]; then
    echo "=== $slug: bereits heruntergeladen, überspringe Download ==="
  else
    echo "=== $slug: downloading ==="
    curl -L -o "Scripts/data/${slug}-latest.osm.pbf" "https://download.geofabrik.de/europe/germany/${slug}-latest.osm.pbf"
  fi

  echo "=== $slug: building rest stops ==="
  ./Scripts/venv/bin/python3 Scripts/build_rest_stops.py "Scripts/data/${slug}-latest.osm.pbf" "Scripts/data/${slug}_reststops.sqlite"

  echo "=== $slug: uploading ==="
  gh release upload rest-stops-v1 "Scripts/data/${slug}_reststops.sqlite" --repo Joern2368/RadFaehrte --clobber

  echo "=== $slug: done, size: ==="
  ls -lh "Scripts/data/${slug}_reststops.sqlite"

  echo "=== $slug: removing source pbf to save space ==="
  rm "Scripts/data/${slug}-latest.osm.pbf"
done

echo "=== ALL DONE ==="
