#!/usr/bin/env bash
# Each scheduled job has one log, <job>.log: the job writes it and every
# scheduler backend points at the same file, so rotation covers all output.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

TMP_ROOT="$(ai_brain_test_root job-log-names)"
trap 'rm -rf "$TMP_ROOT"' EXIT

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

BIN="$TMP_ROOT/bin"
VAULT="$TMP_ROOT/vault"
mkdir -p "$BIN" "$VAULT/.opencode" "$TMP_ROOT/plists"
ai_brain_mock_platform "$BIN"
ai_brain_mock_plutil "$BIN"
ai_brain_mock_opencode "$BIN"
ai_brain_install_vault_libs "$PKG" "$VAULT"
cp "$PKG"/templates/jobs/*.sh "$VAULT/scripts/jobs/"
export PATH="$BIN:$PATH"
export TMPDIR="$TMP_ROOT"
export MOCK_PLUTIL_CAPTURE="$TMP_ROOT/plists"
VAULT_REAL="$(cd "$VAULT" && pwd -P)"
LOGS="$VAULT_REAL/⚙️ Meta/logs"

JOBS=""
for job in "$PKG"/templates/jobs/*.sh; do JOBS="$JOBS $(basename "$job" .sh)"; done

# 1. launchd: StandardOutPath/StandardErrorPath are <job>.log.
MOCK_UNAME=Darwin bash "$PKG/scripts/schedule.sh" "$VAULT" --dry-run > "$TMP_ROOT/launchd.txt" 2>&1 \
  || { fail "launchd --dry-run failed"; cat "$TMP_ROOT/launchd.txt" >&2; }
for job in $JOBS; do
  plist="$(find "$TMP_ROOT/plists" -name "ai-brain-com.ai-brain.*.$job.*" | head -n 1)"
  if [ -z "$plist" ]; then
    fail "launchd --dry-run produced no plist for $job"
    continue
  fi
  for key in StandardOutPath StandardErrorPath; do
    grep -Fq "<key>$key</key><string>$LOGS/$job.log</string>" "$plist" \
      || fail "launchd $key of $job is not $job.log"
  done
done

# 2. cron: each line appends its output to the same <job>.log.
MOCK_UNAME=Linux bash "$PKG/scripts/schedule.sh" "$VAULT" --dry-run > "$TMP_ROOT/cron.txt"
for job in $JOBS; do
  grep -F "/$job.sh\"" "$TMP_ROOT/cron.txt" | grep -Fq ">> \"$LOGS/$job.log\" 2>&1" \
    || fail "cron line of $job does not log to $job.log"
done

# 3. The jobs themselves write <job>.log and no other log.
for job in $JOBS; do
  MOCK_UNAME=Linux bash "$VAULT/scripts/jobs/$job.sh" > "$TMP_ROOT/run-$job.txt" 2>&1 || true
  [ -s "$LOGS/$job.log" ] || fail "$job did not write $job.log"
done
for log in "$LOGS"/*.log; do
  case " $JOBS " in *" $(basename "$log" .log) "*) ;; *) fail "a job wrote a log named after no job: $(basename "$log")" ;; esac
done

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: job log names had %s failed assertions\n' "$failures" >&2
  exit 1
fi
printf 'PASS: job log names (jobs, launchd and cron share <job>.log)\n'
