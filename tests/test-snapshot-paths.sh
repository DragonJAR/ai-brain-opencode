#!/usr/bin/env bash
# snapshot_paths reaches `git add`/`git commit`: only plain vault-relative paths
# survive. A dangerous entry is dropped with a warning; when nothing valid is
# left, the documented default applies.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

TMP_ROOT="$(ai_brain_test_root snapshot-paths)"
trap 'rm -rf "$TMP_ROOT"' EXIT

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

BRC="$TMP_ROOT/brain-config.json"
list_paths() { python3 "$PKG/scripts/lib/brain_config.py" "$BRC" list snapshot_paths; }
DEFAULT="$(python3 "$PKG/scripts/lib/brain_config.py" "$TMP_ROOT/missing.json" list snapshot_paths)"

# 1. Each dangerous value is dropped (with a warning) and the valid entry stays.
for bad in '.' './' '..\\x' 'a\\b' ':/' ':(glob)**' ':!📓 Journals' '*' '📓 Journals/*.md' 'a?' '[ab]' \
           '/etc' '../x' '-n' 'C:/x' '.git' '.git/config'; do
  python3 - "$BRC" "$bad" <<'PY'
import json, sys
json.dump({"snapshot_paths": [sys.argv[2], "📓 Journals"]}, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False)
PY
  out="$(list_paths 2> "$TMP_ROOT/err.txt")" || { fail "list failed for '$bad'"; continue; }
  [ "$out" = "📓 Journals" ] || fail "snapshot_paths kept the dangerous entry '$bad' (got: $(printf '%s' "$out" | tr '\n' '|'))"
  grep -Fq 'snapshot_paths' "$TMP_ROOT/err.txt" || fail "no warning on stderr for '$bad'"
done

# 2. Nothing valid left: the documented default, never the whole vault.
printf '{"snapshot_paths": [".", "*"]}\n' > "$BRC"
out="$(list_paths 2> "$TMP_ROOT/err.txt")"
[ "$out" = "$DEFAULT" ] || fail "an all-invalid snapshot_paths did not fall back to the default (got: $(printf '%s' "$out" | tr '\n' '|'))"
grep -Fq 'snapshot_paths' "$TMP_ROOT/err.txt" || fail "no warning when falling back to the default"

# 3. Plain paths, including nested ones and spaces, are kept as written.
printf '{"snapshot_paths": ["📝 Notes", "⚙️ Meta/journal-index.json", "./👤 CRM"]}\n' > "$BRC"
out="$(list_paths 2> "$TMP_ROOT/err.txt")"
[ "$out" = "$(printf '📝 Notes\n⚙️ Meta/journal-index.json\n./👤 CRM')" ] || fail "valid snapshot_paths were altered (got: $(printf '%s' "$out" | tr '\n' '|'))"
[ ! -s "$TMP_ROOT/err.txt" ] || fail "valid snapshot_paths produced a warning: $(cat "$TMP_ROOT/err.txt")"

# 4. install --config shows the same warnings the reader prints.
BIN="$TMP_ROOT/bin"
mkdir -p "$BIN"
ai_brain_mock_platform "$BIN"
ai_brain_mock_opencode "$BIN"
printf '{"snapshot_paths": [".", "📓 Journals"]}\n' > "$BRC"
if ! PATH="$BIN:$PATH" MOCK_UNAME=Linux bash "$PKG/install.sh" "$TMP_ROOT/dry-vault" --dry-run --config "$BRC" \
     > "$TMP_ROOT/install.txt" 2>&1; then
  fail "install --dry-run --config failed"
  cat "$TMP_ROOT/install.txt" >&2
fi
grep -Fq 'snapshot_paths' "$TMP_ROOT/install.txt" || fail "install --config hid the snapshot_paths warning"

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: snapshot_paths validation had %s failed assertions\n' "$failures" >&2
  exit 1
fi
printf 'PASS: snapshot_paths validation (dangerous entries dropped, default fallback)\n'
