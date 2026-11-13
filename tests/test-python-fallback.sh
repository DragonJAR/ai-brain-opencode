#!/usr/bin/env bash
# pick_python3 must find an interpreter through the documented fallbacks
# (`py -3`, then `python`) when `python3` is not usable — the Windows contract.
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

TMP_ROOT="$(ai_brain_test_root python-fallback)"
trap 'rm -rf "$TMP_ROOT"' EXIT

BIN="$TMP_ROOT/bin"
VAULT="$TMP_ROOT/vault"
mkdir -p "$BIN" "$VAULT"

MOCK_UNAME=MINGW64_NT-10.0
MOCK_VAULT="$VAULT"
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
ai_brain_mock_windows "$BIN"

# `python3` present but broken (simulates "not usable"), so pick_python3 must
# walk the documented fallbacks: py -3, then python.
cat > "$BIN/python3" <<'STUB'
#!/bin/sh
printf 'simulated broken python3\n' >&2
exit 1
STUB
real_py="$(command -v python3)"
cat > "$BIN/py" <<PYWRAP
#!/bin/sh
[ "\${1:-}" = "-3" ] && shift
exec "$real_py" "\$@"
PYWRAP
cat > "$BIN/python" <<PYWRAP
#!/bin/sh
exec "$real_py" "\$@"
PYWRAP
chmod +x "$BIN/python3" "$BIN/py" "$BIN/python"

export MOCK_UNAME MOCK_VAULT MOCK_GIT_CALLS MOCK_CRONTAB_STATE MOCK_CRONTAB_CALLS MOCK_CRONTAB_WRITES
export PATH="$BIN:/usr/bin:/bin"
export TMPDIR="$TMP_ROOT"
unset BRAIN_STARTER_PIN || true

if ! bash "$PKG/install.sh" "$VAULT" > "$TMP_ROOT/install.txt" 2>&1; then
  fail "install failed with broken python3 but fallback interpreters present"
  cat "$TMP_ROOT/install.txt" >&2
fi
[ -f "$VAULT/scripts/lib/python3.sh" ] || fail "python3.sh was not installed into the vault"
[ -f "$VAULT/⚙️ Meta/brain-config.json" ] || fail "brain-config.json was not seeded (python fallback broken)"

# The vault-side verifier must pick a fallback interpreter too.
mkdir -p "$VAULT/⚙️ Meta"
printf 'config del diario (fixture)\n' > "$VAULT/⚙️ Meta/journal-config.md"
if ! bash "$VAULT/scripts/verify.sh" > "$TMP_ROOT/verify.txt" 2>&1; then
  fail "vault verify failed with a fallback interpreter"
  cat "$TMP_ROOT/verify.txt" >&2
fi
grep -Eq 'python presente \((py -3|python)\)' "$TMP_ROOT/verify.txt" \
  || fail "verify did not report a fallback interpreter"

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: python fallback contract had %s failures\n' "$failures" >&2
  exit 1
fi

printf 'PASS: pick_python3 falls back to py -3 / python and vault tools follow\n'
