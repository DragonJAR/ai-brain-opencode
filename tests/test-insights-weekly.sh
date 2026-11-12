#!/usr/bin/env bash
# insights-weekly runs `opencode run` unattended and invokes /insights the way
# the installed CLI supports: `--command insights` when `run --help` offers it,
# otherwise a prompt that names the `insights` skill (OpenCode v2 sends the
# message as plain text, so "/insights" mid-sentence is never run as a command).
# Without --auto a headless run rejects every permission and cannot save.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

TMP_ROOT="$(ai_brain_test_root insights-weekly)"
trap 'rm -rf "$TMP_ROOT"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

VAULT="$TMP_ROOT/vault"
JOB="$VAULT/scripts/jobs/insights-weekly.sh"
mkdir -p "$VAULT/📓 Journals" "$VAULT/⚙️ Meta/logs" "$TMP_ROOT/bin"
ai_brain_install_vault_libs "$PKG" "$VAULT"
cp "$PKG/templates/jobs/insights-weekly.sh" "$JOB"
printf 'entry\n' > "$VAULT/📓 Journals/2026-01-04.md"
ai_brain_mock_opencode "$TMP_ROOT/bin"
export PATH="$TMP_ROOT/bin:$PATH"
export MOCK_OPENCODE_CALLS="$TMP_ROOT/opencode.log"

run_job() {
  : > "$MOCK_OPENCODE_CALLS"
  bash "$JOB" > "$TMP_ROOT/out.txt" 2>&1 || fail "insights-weekly failed: $(cat "$TMP_ROOT/out.txt")"
  CALL="$(grep -F '<run>' "$MOCK_OPENCODE_CALLS" | grep -vF '<--help>' || true)"
  [ -n "$CALL" ] || fail "opencode run was never called (calls: $(cat "$MOCK_OPENCODE_CALLS"))"
}
has() { case "$CALL" in *"$1"*) ;; *) fail "$2 (argv: $CALL)" ;; esac; }

# 1. OpenCode v2 (no --command): unattended flags and the skill named explicitly.
run_job
has '<--auto>' "opencode run lacks --auto, so every permission is auto-rejected"
has '<--archived>' "the headless session is not archived out of the session list"
case "$CALL" in *' /insights'*|*'</insights'*) fail "the prompt still asks for /insights mid-sentence (argv: $CALL)" ;; esac
case "$CALL" in *'skill `insights`'*) ;; *) fail "the prompt does not name the insights skill (argv: $CALL)" ;; esac

# 2. A CLI whose `run` offers --command gets the command itself.
printf '%s\n' 'FLAGS' '  --command string' '  --auto' > "$TMP_ROOT/help-v1.txt"
MOCK_OPENCODE_HELP="$TMP_ROOT/help-v1.txt" run_job
has '<--command><insights>' "a CLI with --command did not get '--command insights'"
has '<--auto>' "opencode run --command lacks --auto"
case "$CALL" in *'<--archived>'*) fail "passed --archived to a CLI that does not offer it (argv: $CALL)" ;; esac

# 3. A CLI without --auto cannot run unattended: the job fails loudly.
printf '%s\n' 'FLAGS' '  --agent string' > "$TMP_ROOT/help-noauto.txt"
: > "$MOCK_OPENCODE_CALLS"
if MOCK_OPENCODE_HELP="$TMP_ROOT/help-noauto.txt" bash "$JOB" > "$TMP_ROOT/out.txt" 2>&1; then
  fail "insights-weekly succeeded with a CLI that cannot auto-approve"
fi
grep -F '<run>' "$MOCK_OPENCODE_CALLS" | grep -vqF '<--help>' && fail "ran opencode without --auto"

printf 'insights weekly: ok\n'
