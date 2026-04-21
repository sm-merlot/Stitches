#!/usr/bin/env bash
# Test PK PDF import/export via the real app CLI.
#
# Modes:
#   (no args)               inspect fixture PDFs
#   --inspect <path>        inspect a specific PDF
#   --import  <path>        import a specific PDF (print JSON)
#   --round-trip <stitches> export .stitches → PK PDF → re-import → compare
#   --round-trip            round-trip all fixtures/*.stitches (default fixture: sm_test.stitches)
#
# Run: ./scripts/test_pk_import.sh
#      ./scripts/test_pk_import.sh --round-trip test/fixtures/sm_test.stitches

set -euo pipefail
export PATH="/opt/homebrew/bin:$PATH"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_BINARY="$REPO_ROOT/build/macos/Build/Products/Debug/Stitches.app/Contents/MacOS/Stitches"

# ── Build if needed ──────────────────────────────────────────────────────────
if [[ ! -f "$APP_BINARY" ]]; then
  echo "▶ Building macOS debug app…" >&2
  (cd "$REPO_ROOT" && flutter build macos --debug 2>&1)
fi

if [[ ! -f "$APP_BINARY" ]]; then
  echo "❌ Build failed — binary not found at $APP_BINARY" >&2
  exit 1
fi

# ── Helpers ──────────────────────────────────────────────────────────────────

run_inspect() {
  local pdf="$1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  echo "INSPECT: $pdf" >&2
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  local out; out=$("$APP_BINARY" --inspect-pdf "$pdf" 2>/tmp/pk_stderr.txt || true)
  # Print [PKParser] lines
  grep '\[PKParser\]' /tmp/pk_stderr.txt || true
  # Summarise each page
  echo "$out" | python3 - <<'PYEOF'
import sys, json
raw = sys.stdin.read().strip()
if not raw:
    print("  (no output)")
    sys.exit(0)
data = json.loads(raw)
for page in data.get('pages', []):
    pi = page.get('page', '?')
    frags = page.get('fragmentCount', 0)
    chars = page.get('charCount', 0)
    print(f"  Page {pi}: {frags} fragments, {chars} chars")
    for f in page.get('fragments', [])[:8]:
        cp = ' '.join(f.get('codepoints', []))
        print(f"    [{f['text']!r:20s}] bounds=({f['left']:.1f},{f['top']:.1f},{f['right']:.1f},{f['bottom']:.1f}) {cp}")
    if page.get('fragmentsTruncated'):
        print(f"    ... +{page['fragmentsTruncated']} more")
pr = data.get('parseResult')
if pr:
    print(f"  ✅ Parse OK: {pr['width']}×{pr['height']}, {pr['threadCount']} threads, {pr['stitchCount']} stitches")
else:
    print("  ❌ Parse FAILED")
PYEOF
}

run_import() {
  local pdf="$1"
  "$APP_BINARY" --import-pdf "$pdf" 2>/tmp/pk_stderr.txt
}

# Round-trip: .stitches → PK PDF → import → compare
run_round_trip() {
  local stitches_path="$1"
  local pdf_path; pdf_path="/tmp/pk_rt_$(basename "$stitches_path" .stitches).pdf"

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "ROUND-TRIP: $stitches_path"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # 1. Export
  echo "▶ Export → $pdf_path"
  local export_out
  export_out=$("$APP_BINARY" --export-pk-pdf "$stitches_path" "$pdf_path" 2>/tmp/pk_stderr.txt)
  grep '\[export\]\|\[PKParser\]' /tmp/pk_stderr.txt || true

  # 2. Import
  echo "▶ Import"
  local import_out
  # Filter out the Flutter VM service URL that leaks to stdout in debug builds.
  import_out=$("$APP_BINARY" --import-pdf "$pdf_path" 2>/tmp/pk_stderr.txt | grep '^{')
  grep '\[PKParser\]' /tmp/pk_stderr.txt || true

  # 3. Compare via external script (avoids bash heredoc/pipe stdin conflict)
  echo "▶ Compare"
  local import_json_tmp; import_json_tmp=$(mktemp /tmp/pk_import_XXXXXX.json)
  echo "$import_out" > "$import_json_tmp"
  python3 "$REPO_ROOT/scripts/compare_round_trip.py" "$import_json_tmp" "$stitches_path"
  rm -f "$import_json_tmp"
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
MODE="${1:---inspect-fixtures}"
ARG="${2:-}"

case "$MODE" in
  --inspect)
    [[ -z "$ARG" ]] && { echo "Usage: $0 --inspect <path.pdf>" >&2; exit 1; }
    run_inspect "$ARG"
    ;;
  --import)
    [[ -z "$ARG" ]] && { echo "Usage: $0 --import <path.pdf>" >&2; exit 1; }
    run_import "$ARG"
    ;;
  --round-trip)
    TARGET="${ARG:-$REPO_ROOT/test/fixtures/sm_test.stitches}"
    if [[ -d "$TARGET" ]]; then
      for f in "$TARGET"/*.stitches; do run_round_trip "$f"; done
    else
      run_round_trip "$TARGET"
    fi
    ;;
  --inspect-fixtures|*)
    FIXTURES="$REPO_ROOT/test/fixtures/pdfs"
    for pdf in "$FIXTURES"/*.pdf; do
      [[ -f "$pdf" ]] && run_inspect "$pdf"
    done
    ;;
esac
