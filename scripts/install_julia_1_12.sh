#!/usr/bin/env bash
# Install a local Julia 1.12 (aarch64 macOS) for Snapshot.jl / WasmTarget.jl.
# Snapshot requires julia ~1.12; the project nix-shell stays on 1.11 for the model.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="${JULIA_WASM_VERSION:-1.12.6}"
DEST="$ROOT/.julia_versions/$VER"
URL="https://julialang-s3.julialang.org/bin/mac/aarch64/${VER%.*}/julia-${VER}-macaarch64.tar.gz"

if [[ -x "$DEST/bin/julia" ]]; then
  echo "Julia $VER already at $DEST"
  "$DEST/bin/julia" --version
  exit 0
fi

mkdir -p "$ROOT/.julia_versions"
TMP="$(mktemp -d)"
echo "Downloading Julia $VER …"
curl -L "$URL" | tar -xz -C "$TMP"
mv "$TMP"/julia-"$VER" "$DEST"
rm -rf "$TMP"
echo "Installed:"
"$DEST/bin/julia" --version
