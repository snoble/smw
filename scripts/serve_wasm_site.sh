#!/usr/bin/env bash
# Serve the Snapshot-exported site locally (WASM needs http://, not file://).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE="$ROOT/site"
[[ -d "$SITE" ]] || { echo "No site/ yet — run scripts/build_wasm_site.jl first"; exit 1; }
cd "$SITE"
PORT="${PORT:-8765}"
echo "Serving $SITE at http://127.0.0.1:$PORT/"
echo "Open the .html notebook file linked from the directory listing."
python3 -m http.server "$PORT" --bind 127.0.0.1
