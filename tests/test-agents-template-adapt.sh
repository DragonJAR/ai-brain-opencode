#!/usr/bin/env bash
# The generated AGENTS.md drops the vendor's Claude Code-only parts: the daily
# update check (step and section) and the "Last Session.md" start step.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

TMP_ROOT="$(ai_brain_test_root agents-template)"
trap 'rm -rf "$TMP_ROOT"' EXIT

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

BIN="$TMP_ROOT/bin"
VAULT="$TMP_ROOT/vault"
mkdir -p "$BIN"
cat > "$TMP_ROOT/vendor-template.md" <<'MD'
# Vault instructions

## Rules
8. **Your brain lives in the vault, not in Claude's memory.** Anything worth keeping becomes a file.

9. Keep notes small.

## Session protocol
1. Start: Read this file and `⚙️ Meta/Sessions/Last Session.md`.
2. **Run the daily AI brain setup update check** — once per day, compare the installed version with upstream.
3. During: log decisions as they happen.
4. End: The **session close cascade** runs on every close signal and writes Last Session.md.

## Vault Map
[FILL THIS IN]

## Session start — daily update check
Run `bash ~/.claude/skills/ai-brain-starter/scripts/check-update.sh` once per day.

## Session close — configuration (optional)
Edit the close cascade in settings.json.
MD

export MOCK_UNAME=Linux MOCK_VAULT="$VAULT"
export MOCK_GIT_CALLS="$TMP_ROOT/git-calls.log"
export MOCK_CRONTAB_STATE="$TMP_ROOT/crontab-state"
export MOCK_CRONTAB_CALLS="$TMP_ROOT/crontab-calls.log"
export MOCK_CRONTAB_WRITES="$TMP_ROOT/crontab-writes.log"
export MOCK_GIT_STARTER_TEMPLATE="$TMP_ROOT/vendor-template.md"
: > "$MOCK_GIT_CALLS"; : > "$MOCK_CRONTAB_CALLS"; : > "$MOCK_CRONTAB_WRITES"
ai_brain_mock_platform "$BIN"
ai_brain_mock_crontab "$BIN"
ai_brain_mock_git "$BIN"
ai_brain_mock_opencode "$BIN"
export PATH="$BIN:$PATH"
export TMPDIR="$TMP_ROOT"
unset BRAIN_STARTER_PIN || true

bash "$PKG/install.sh" "$VAULT" > "$TMP_ROOT/install.txt" 2>&1 \
  || { cat "$TMP_ROOT/install.txt" >&2; printf 'FAIL: install failed\n' >&2; exit 1; }
AGENTS="$VAULT/AGENTS.md"
[ -f "$AGENTS" ] || { printf 'FAIL: AGENTS.md was not generated\n' >&2; exit 1; }

for leftover in 'update check' 'check-update' 'Last Session' 'Session close — configuration' '.claude/'; do
  if grep -Fq "$leftover" "$AGENTS"; then fail "AGENTS.md still contains '$leftover'"; fi
done
grep -Fq '1. Start: lee este archivo y la sesión más reciente' "$AGENTS" || fail "AGENTS.md lost the adapted start step"
grep -Fq '2. During:' "$AGENTS" || fail "AGENTS.md did not renumber the 'During' step"
if grep -F 'la plantilla del vendor cambió' "$TMP_ROOT/install.txt"; then
  fail "the adaptation lost an anchor on a vendor-shaped template"
fi

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: AGENTS.md adaptation had %s failed assertions\n' "$failures" >&2
  exit 1
fi
printf 'PASS: AGENTS.md drops the daily update check and Last Session.md\n'
