#!/usr/bin/env bash
# check-debug-markers.sh — fail if debug/temporary markers are found in lib/.
#
# Patterns to add here as new debug conventions are discovered.
# Each entry is a literal string matched case-sensitively.

set -euo pipefail

PATTERNS=(
  "// TEST"
  "// DEBUG"
  "// TEMP"
  "// HACK"
  "// WIP"
  "// DO NOT MERGE"
  "// DONOTMERGE"
  "// DO_NOT_MERGE"
  "// FIXME"
)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/lib"

violations=()

while IFS= read -r -d '' file; do
  rel="${file#"$ROOT/"}"
  lineno=0
  while IFS= read -r line; do
    lineno=$((lineno + 1))
    for pattern in "${PATTERNS[@]}"; do
      if [[ "$line" == *"$pattern"* ]]; then
        violations+=("$rel:$lineno  [$pattern]  ${line#"${line%%[! ]*}"}")
      fi
    done
  done < "$file"
done < <(find "$LIB" -name "*.dart" -print0)

if [[ ${#violations[@]} -eq 0 ]]; then
  echo "✔ No debug markers found."
  exit 0
fi

echo "✘ Found ${#violations[@]} debug marker(s) that must be removed before merging:"
for v in "${violations[@]}"; do
  echo "  $v"
done
exit 1
