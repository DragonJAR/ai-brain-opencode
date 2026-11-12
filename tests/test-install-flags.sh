#!/usr/bin/env bash
# Documented install flags must behave: --config seeding, invalid --config
# rejection without mutation, --config/--wire conflict, --with-obsidian
# platform guard on Windows, --yes accepted, and MOCK_GIT_CLEAN skip-commit path.
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

TMP_ROOT="$(ai_brain_test_root install-flags)"
trap 'rm -rf "$TMP_ROOT"' EXIT

BIN="$TMP_ROOT/bin"
mkdir -p "$BIN"
MOCK_UNAME=Linux
MOCK_VAULT="$TMP_ROOT/vault"
MOCK_GIT_CALLS="$TMP_ROOT/git-calls.log"
MOCK_CRONTAB_STATE="$TMP_ROOT/crontab-state"
MOCK_CRONTAB_CALLS="$TMP_ROOT/crontab-calls.log"
MOCK_CRONTAB_WRITES="$TMP_ROOT/crontab-writes.log"
: > "$MOCK_GIT_CALLS"
: > "$MOCK_CRONTAB_STATE"
: > "$MOCK_CRONTAB_CALLS"
: > "$MOCK_CRONTAB_WRITES"

ai_brain_mock_platform "$BIN"
ai_brain_mock_crontab "$BIN"
ai_brain_mock_git "$BIN"
ai_brain_mock_opencode "$BIN"

export MOCK_UNAME MOCK_VAULT MOCK_GIT_CALLS MOCK_CRONTAB_STATE MOCK_CRONTAB_CALLS MOCK_CRONTAB_WRITES
export PATH="$BIN:/usr/bin:/bin"
export TMPDIR="$TMP_ROOT"
export BRAIN_STARTER_UPDATE=0
unset BRAIN_STARTER_PIN || true

# 1. --config seeds the vault config verbatim; --yes is accepted.
CFG="$TMP_ROOT/cfg.json"
printf '%s\n' '{"language":"en","journal":{"time":"07:15"},"habits":["agua"],"schedule":{"insights_time":"22:30"}}' > "$CFG"
VAULT_CFG="$TMP_ROOT/vault-config"
if ! MOCK_GIT_CLEAN=1 bash "$PKG/install.sh" "$VAULT_CFG" --config "$CFG" --yes > "$TMP_ROOT/cfg.txt" 2>&1; then
  fail "--config --yes install failed"
  cat "$TMP_ROOT/cfg.txt" >&2
fi
python3 - "$VAULT_CFG/⚙️ Meta/brain-config.json" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
assert cfg["language"] == "en", cfg
assert cfg["journal"]["time"] == "07:15", cfg
assert cfg["schedule"]["insights_time"] == "22:30", cfg
assert cfg["habits"] == ["agua"], cfg
PY
[ $? -eq 0 ] || fail "seeded config does not match --config values"

# Clean-tree path: the base commit must be skipped, not attempted.
if grep -Eq ' commit -q' "$MOCK_GIT_CALLS"; then
  fail "MOCK_GIT_CLEAN=1 still attempted a base commit"
fi

# 2. Invalid --config JSON: installer fails, target untouched.
BAD="$TMP_ROOT/bad.json"
printf 'not-json\n' > "$BAD"
BAD_VAULT="$TMP_ROOT/vault-bad"
mkdir -p "$BAD_VAULT"
printf 'keep\n' > "$BAD_VAULT/keep.txt"
if bash "$PKG/install.sh" "$BAD_VAULT" --config "$BAD" > "$TMP_ROOT/bad.txt" 2>&1; then
  fail "invalid --config did not fail the install"
fi
[ -e "$BAD_VAULT/keep.txt" ] || fail "invalid --config mutated the target vault"
if [ -e "$BAD_VAULT/⚙️ Meta" ]; then fail "invalid --config created vault structure"; fi

# 3. --config with --wire is rejected.
WIRE_VAULT="$TMP_ROOT/vault-wire"
mkdir -p "$WIRE_VAULT"
if bash "$PKG/install.sh" "$WIRE_VAULT" --wire --config "$CFG" > "$TMP_ROOT/wire.txt" 2>&1; then
  fail "--wire --config combination was accepted"
fi
grep -Fq 'solo admite --with-schedule' "$TMP_ROOT/wire.txt" \
  || fail "--wire --config rejection did not explain the limitation"

# 4. --with-obsidian is macOS/Linux only: rejected on Windows native.
WIN_VAULT="$TMP_ROOT/vault-win"
mkdir -p "$WIN_VAULT"
if MOCK_UNAME=MINGW64_NT-10.0 bash "$PKG/install.sh" "$WIN_VAULT" --with-obsidian > "$TMP_ROOT/win.txt" 2>&1; then
  fail "--with-obsidian accepted on Windows native"
fi
grep -Fq 'macOS/Linux' "$TMP_ROOT/win.txt" \
  || fail "--with-obsidian rejection did not name macOS/Linux"

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: install flags contract had %s failures\n' "$failures" >&2
  exit 1
fi

printf 'PASS: --config/--yes/--with-obsidian behave and the clean-tree commit path is reachable\n'
