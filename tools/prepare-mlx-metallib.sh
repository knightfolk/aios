#!/bin/bash
# Builds mlx-swift's default.metallib from the generated kernel sources and
# installs it beside the built executables (MLX loads it colocated at runtime;
# SwiftPM does not produce it).
#
# Run once after `swift build` (and again after a clean):
#   ./tools/prepare-mlx-metallib.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$BASH_SOURCE[0]")/.." && pwd)"
GEN="$ROOT/.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
DEST="$ROOT/.build/arm64-apple-macosx/debug"

if [ ! -d "$GEN" ]; then
  echo "error: $GEN not found — run 'swift build' first" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for src in "$GEN"/*.metal; do
  name="$(basename "${src%.metal}")"
  xcrun -sdk macosx metal -x metal -c "$src" -I "$GEN" -o "$WORK/$name.air"
done
xcrun -sdk macosx metal -x metal -c \
  "$GEN/steel/attn/kernels/steel_attention.metal" \
  -I "$GEN" -I "$GEN/steel" -o "$WORK/steel_attention.air"

xcrun metallib "$WORK"/*.air -o "$DEST/mlx.metallib"
cp "$DEST/mlx.metallib" "$DEST/default.metallib"
echo "installed: $DEST/mlx.metallib (+ default.metallib copy) ($(du -h "$DEST/mlx.metallib" | cut -f1))"
