#!/usr/bin/env bash
# Builds a release macOS app with the pdfrx WASM module excluded.
#
# The WASM module (~4 MB) is only needed for web builds. This script
# removes it before building and restores the pub-cache afterwards so
# other projects aren't affected.
#
# Usage: bash tool/build_release_macos.sh

set -euo pipefail

cd "$(dirname "$0")/.."

echo "→ flutter pub get"
flutter pub get

echo "→ removing pdfrx WASM module"
dart run pdfrx:remove_wasm_modules

echo "→ flutter build macos --release"
flutter build macos --release

echo "→ restoring pdfrx WASM module"
dart run pdfrx:remove_wasm_modules --revert

echo "✓ Build complete: build/macos/Build/Products/Release/stitches.app"
