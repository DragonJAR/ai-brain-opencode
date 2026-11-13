#!/usr/bin/env bash
# --with-mcp runs after the vault is installed: an opencode.json with comments
# (JSONC) or an opencode.jsonc must be left alone with a warning, never abort
# the install and never get a second, competing opencode.json.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

TMP_ROOT="$(ai_brain_test_root install-mcp-jsonc)"
trap 'rm -rf "$TMP_ROOT"' EXIT
BIN="$TMP_ROOT/bin"
ai_brain_mock_platform "$BIN"
ai_brain_mock_git "$BIN"
ai_brain_mock_opencode "$BIN"
export MOCK_UNAME=Linux MOCK_GIT_CLEAN=1
export PATH="$BIN:/usr/bin:/bin" TMPDIR="$TMP_ROOT"
unset BRAIN_STARTER_PIN || true

mcp_records() {
  python3 - "$1/.opencode/brain-vault-install-manifest.json" <<'PY'
import json, sys
print(len(json.load(open(sys.argv[1], encoding="utf-8"))["config"]))
PY
}

# 1. opencode.json with comments: kept byte for byte, install exits 0 with a warning.
V="$TMP_ROOT/vault-jsonc-content"
mkdir -p "$V"
printf '{\n  // my provider\n  "provider": {},\n}\n' > "$V/opencode.json"
cp "$V/opencode.json" "$TMP_ROOT/opencode.before"
if ! MOCK_VAULT="$V" bash "$PKG/install.sh" "$V" --with-mcp > "$TMP_ROOT/out-1.txt" 2> "$TMP_ROOT/err-1.txt"; then
  fail "--with-mcp aborted the install on an opencode.json with comments"
  tail -3 "$TMP_ROOT/err-1.txt" >&2
fi
cmp -s "$V/opencode.json" "$TMP_ROOT/opencode.before" || fail "--with-mcp rewrote a JSONC opencode.json"
grep -Fq 'MCP' "$TMP_ROOT/err-1.txt" || fail "skipping MCP on JSONC was not warned on stderr"
[ "$(mcp_records "$V")" = 0 ] || fail "MCP entries were recorded although none were written"

# 2. opencode.jsonc present: no opencode.json is created next to it.
W="$TMP_ROOT/vault-jsonc-file"
mkdir -p "$W"
printf '{ /* mine */ }\n' > "$W/opencode.jsonc"
if ! MOCK_VAULT="$W" bash "$PKG/install.sh" "$W" --with-mcp > "$TMP_ROOT/out-2.txt" 2> "$TMP_ROOT/err-2.txt"; then
  fail "--with-mcp aborted the install next to an opencode.jsonc"
fi
[ ! -e "$W/opencode.json" ] || fail "--with-mcp created opencode.json next to an existing opencode.jsonc"
grep -Fq 'opencode.jsonc' "$TMP_ROOT/err-2.txt" || fail "skipping MCP next to opencode.jsonc was not warned"

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: --with-mcp JSONC handling had %s failures\n' "$failures" >&2
  exit 1
fi
printf 'PASS: --with-mcp skips JSONC configs with a warning and never aborts the install\n'
