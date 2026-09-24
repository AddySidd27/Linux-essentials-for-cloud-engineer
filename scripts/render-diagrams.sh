#!/usr/bin/env bash
# render-diagrams.sh - export images/src/*.drawio to images/*.png
#
# Usage: bash scripts/render-diagrams.sh
#
# Uses the open-source draw.io web app in headless Chromium, so the PNGs look
# the same as an export from draw.io. Needs git, node, npm and python3.
# First run downloads the draw.io web app and Chromium into $DRAWIO_WORK.

set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
work="${DRAWIO_WORK:-/tmp/drawio-render}"
mkdir -p "$work"

if [[ ! -d "$work/drawio/src/main/webapp/js" ]]; then
  git clone -q --depth 1 --filter=blob:none --sparse https://github.com/jgraph/drawio.git "$work/drawio"
  git -C "$work/drawio" sparse-checkout set --no-cone \
    '/src/main/webapp/*' '!/src/main/webapp/templates/' '!/src/main/webapp/resources/'
fi

cd "$work"
if [[ ! -d node_modules/playwright ]]; then
  npm init -y > /dev/null
  npm install --silent playwright
  npx playwright install --with-deps chromium
fi
cp "$repo/scripts/render.js" "$work/render.js"

python3 -m http.server 8765 --bind 127.0.0.1 --directory "$work/drawio/src/main/webapp" > /dev/null 2>&1 &
server=$!
trap 'kill "$server"' EXIT
sleep 2

for src in "$repo"/images/src/*.drawio; do
  name=$(basename "${src%.drawio}")
  node render.js "$src" "$repo/images/$name.png" 2
done
