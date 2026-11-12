#!/usr/bin/env bash
# The package edits the vault's opencode.json through one place (ownership.py
# configure / uninstall): it hides the vendor installer skill, adds the MCP
# servers only on request, keeps what the user wrote, and reverts exactly its
# own entries.
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

TMP_ROOT="$(ai_brain_test_root opencode-config)"
trap 'rm -rf "$TMP_ROOT"' EXIT
BIN="$TMP_ROOT/bin"
ai_brain_mock_platform "$BIN"
ai_brain_mock_crontab "$BIN"
ai_brain_mock_git "$BIN"
ai_brain_mock_opencode "$BIN"
export MOCK_UNAME=Linux MOCK_GIT_CALLS="$TMP_ROOT/git-calls.log"
export MOCK_CRONTAB_STATE="$TMP_ROOT/crontab-state" MOCK_CRONTAB_CALLS="$TMP_ROOT/crontab-calls.log"
export MOCK_CRONTAB_WRITES="$TMP_ROOT/crontab-writes.log"
: > "$MOCK_CRONTAB_STATE"; : > "$MOCK_CRONTAB_CALLS"; : > "$MOCK_CRONTAB_WRITES"
export PATH="$BIN:$PATH" TMPDIR="$TMP_ROOT" BRAIN_STARTER_UPDATE=0
unset BRAIN_STARTER_PIN || true

config_check() {  # <opencode.json> <python assertion body>
  python3 - "$1" "$PKG/scripts/lib" <<PY
import json, pathlib, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[2])
import vault_layout
path = pathlib.Path(sys.argv[1])
config = json.loads(path.read_text(encoding="utf-8")) if path.exists() else None
rules = [{"action": "skill", "resource": skill, "effect": "deny"} for skill in vault_layout.DENIED_SKILLS]
$2
PY
}

# 1. A fresh vault hides every denied skill and gets no MCP server unless asked.
FRESH="$TMP_ROOT/fresh"
MOCK_VAULT="$FRESH" bash "$PKG/install.sh" "$FRESH" > "$TMP_ROOT/fresh.txt" 2>&1 || fail "fresh install failed"
config_check "$FRESH/opencode.json" 'assert config and all(r in config["permissions"] for r in rules) and "mcp" not in config, config' \
  || fail "a fresh vault does not hide the vendor installer skill, or got MCP servers without --with-mcp"
MOCK_VAULT="$FRESH" bash "$PKG/install.sh" "$FRESH" > "$TMP_ROOT/fresh-2.txt" 2>&1 || fail "second install failed"
config_check "$FRESH/opencode.json" 'assert sum(r in rules for r in config["permissions"]) == len(rules), config' \
  || fail "a second install duplicated the permission rule"
MOCK_VAULT="$FRESH" bash "$PKG/uninstall.sh" "$FRESH" > "$TMP_ROOT/fresh-un.txt" 2>&1 || fail "uninstall of the fresh vault failed"
[ ! -e "$FRESH/opencode.json" ] || fail "uninstall left the opencode.json the package created and nothing else uses"

# 2. The user's own opencode.json keeps everything it had; only our rule comes and goes.
OWN="$TMP_ROOT/own"
mkdir -p "$OWN"
printf '%s\n' '{"model": "x/y", "permissions": [{"action": "shell", "resource": "rm *", "effect": "deny"}]}' > "$OWN/opencode.json"
MOCK_VAULT="$OWN" bash "$PKG/install.sh" "$OWN" --with-mcp > "$TMP_ROOT/own.txt" 2>&1 || fail "install over the user's opencode.json failed"
config_check "$OWN/opencode.json" 'assert config["model"] == "x/y" and config["permissions"][0]["action"] == "shell" and all(r in config["permissions"] for r in rules) and set(config["mcp"]["servers"]) == set(vault_layout.MCP_SERVERS), config' \
  || fail "the user's opencode.json lost content or did not receive the package entries"
MOCK_VAULT="$OWN" bash "$PKG/uninstall.sh" "$OWN" > "$TMP_ROOT/own-un.txt" 2>&1 || fail "uninstall over the user's opencode.json failed"
config_check "$OWN/opencode.json" 'assert config == {"model": "x/y", "permissions": [{"action": "shell", "resource": "rm *", "effect": "deny"}]}, config' \
  || fail "uninstall did not restore the user's opencode.json exactly"

# 3. A config the package cannot edit safely is left byte-identical, with the rule to add by hand.
for kind in jsonc comments; do
  V="$TMP_ROOT/skip-$kind"
  mkdir -p "$V"
  if [ "$kind" = jsonc ]; then TARGET="$V/opencode.jsonc"; else TARGET="$V/opencode.json"; fi
  printf '%s\n' '{ // user comment' '  "model": "x/y" }' > "$TARGET"
  cp "$TARGET" "$TMP_ROOT/skip-$kind.before"
  MOCK_VAULT="$V" bash "$PKG/install.sh" "$V" > "$TMP_ROOT/skip-$kind.txt" 2> "$TMP_ROOT/skip-$kind.err" \
    || fail "install aborted on a $kind config instead of skipping it"
  cmp -s "$TARGET" "$TMP_ROOT/skip-$kind.before" || fail "install modified a $kind config"
  [ "$kind" != jsonc ] || [ ! -e "$V/opencode.json" ] || fail "install created a second config next to opencode.jsonc"
  grep -Fq '"resource":"ai-brain-starter"' "$TMP_ROOT/skip-$kind.err" || fail "skipping a $kind config did not print the rule to add by hand"
done

# 4. install.sh holds no opencode.json editing of its own.
if grep -nE 'json\.(loads|dumps)|"mcp"' "$PKG/install.sh" | grep -n 'opencode' >/dev/null; then
  fail "install.sh edits opencode.json itself instead of calling ownership.py configure"
fi

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: opencode.json handling had %s failures\n' "$failures" >&2
  exit 1
fi
printf 'PASS: opencode.json gets and loses only the package entries; the vendor installer skill is hidden\n'
