#!/usr/bin/env bash
# Builds the public site into build/site:
#   /       the Simplek website (website/)
#   /app/   the Simplek web app (Flutter)
# Upload build/simplek-site.zip (or the build/site folder) to any static host.
set -euo pipefail
cd "$(dirname "$0")/.."

MSYS_NO_PATHCONV=1 flutter build web --release --base-href /app/

rm -rf build/site
mkdir -p build/site/app
cp -r website/. build/site/
cp -r build/web/. build/site/app/
echo "Site ready in build/site"

dart run tool/zip_site.dart
