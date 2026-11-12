#!/usr/bin/env bash
# Job runtime in scripts/lib/common.sh: the lock admits exactly one run (even
# when many start at once over a stale lock), a fresh lock without a pid is not
# stolen, the log rotates only under the lock, and a timeout kills the whole
# process tree (process group on POSIX, `taskkill /T` on Git Bash).
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

TMP_ROOT="$(ai_brain_test_root job-runtime)"
STRAYS=""
cleanup() {
  local pid
  for pid in $STRAYS; do kill -9 "$pid" 2>/dev/null || true; done
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

VAULT="$TMP_ROOT/vault"
LOGS="$VAULT/⚙️ Meta/logs"
LOCK="$LOGS/.probe.lock"
MARKS="$TMP_ROOT/marks"
mkdir -p "$LOGS"
ai_brain_install_vault_libs "$PKG" "$VAULT"
cat > "$VAULT/scripts/jobs/probe.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
job_init
printf 'ran\n' >> "$PROBE_MARKS"
sleep "${PROBE_SLEEP:-0}"
SH
export PROBE_MARKS="$MARKS"

dead_pid() { sh -c 'exit 0' & wait "$!" 2>/dev/null || true; printf '%s' "$!"; }
runs() { if [ -f "$MARKS" ]; then wc -l < "$MARKS" | tr -d ' '; else printf 0; fi; }

# 1. Many runs at once over a stale lock (dead pid): exactly one runs.
rm -f "$MARKS"
mkdir "$LOCK"
dead_pid > "$LOCK/pid"
pids=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  PROBE_SLEEP=2 bash "$VAULT/scripts/jobs/probe.sh" 2>>"$TMP_ROOT/err.txt" &
  pids="$pids $!"
done
for pid in $pids; do wait "$pid" || true; done
[ "$(runs)" = 1 ] || fail "concurrent runs over a stale lock: $(runs) ran (want 1)"
[ ! -e "$LOCK" ] || fail "the lock was left behind after the run"

# 2. Many runs at once with no lock: exactly one runs.
rm -f "$MARKS"
pids=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  PROBE_SLEEP=2 bash "$VAULT/scripts/jobs/probe.sh" 2>>"$TMP_ROOT/err.txt" &
  pids="$pids $!"
done
for pid in $pids; do wait "$pid" || true; done
[ "$(runs)" = 1 ] || fail "concurrent runs with no lock: $(runs) ran (want 1)"

# 3. A fresh lock without a pid belongs to a run that has not written it yet.
rm -f "$MARKS"
mkdir "$LOCK"
bash "$VAULT/scripts/jobs/probe.sh" 2>>"$TMP_ROOT/err.txt" || fail "probe failed on a fresh pid-less lock"
[ "$(runs)" = 0 ] || fail "a fresh lock with no pid was treated as stale"
[ -d "$LOCK" ] || fail "a fresh lock with no pid was removed"

# 4. The same pid-less lock, once old, is stale.
touch -t 202001010000 "$LOCK"
bash "$VAULT/scripts/jobs/probe.sh" 2>>"$TMP_ROOT/err.txt" || fail "probe failed on an old pid-less lock"
[ "$(runs)" = 1 ] || fail "an old lock with no pid was never taken over"

# 5. A run that finds the job busy does not rotate the running job's log.
rm -f "$MARKS" "$LOGS/probe.1.log"
mkdir "$LOCK"
printf '%s\n' "$$" > "$LOCK/pid"
head -c 1100000 /dev/zero | tr '\0' 'x' > "$LOGS/probe.log"
bash "$VAULT/scripts/jobs/probe.sh" 2>>"$TMP_ROOT/err.txt" || fail "probe failed while the job was busy"
[ "$(runs)" = 0 ] || fail "probe ran while another run held the lock"
[ ! -e "$LOGS/probe.1.log" ] || fail "the log was rotated by a run that did not hold the lock"
rm -rf "$LOCK"
bash "$VAULT/scripts/jobs/probe.sh" 2>>"$TMP_ROOT/err.txt" || fail "probe failed after the lock was released"
[ -e "$LOGS/probe.1.log" ] || fail "the lock holder did not rotate an oversized log"

# 6. POSIX timeout kills the grandchild too, not just the direct child.
run_timeout() {
  # shellcheck disable=SC2016
  bash -c '. "$1/scripts/lib/common.sh"; require_python3; shift
    run_with_timeout 1 sh -c "sleep 100 & printf %s \$! > \"\$0\"; wait" "$@"' _ "$VAULT" "$1"
}
GRAND="$TMP_ROOT/grandchild.pid"
rc=0
run_timeout "$GRAND" || rc=$?
[ "$rc" = 124 ] || fail "run_with_timeout returned $rc on timeout (want 124)"
gpid="$(cat "$GRAND")"
STRAYS="$STRAYS $gpid"
sleep 0.5
if kill -0 "$gpid" 2>/dev/null; then fail "timeout left the grandchild (pid $gpid) running"; fi

# 7. Git Bash: the tree is killed with taskkill /T /F on the child's pid.
ai_brain_mock_platform "$TMP_ROOT/bin"
ai_brain_mock_windows "$TMP_ROOT/bin"
export MOCK_TASKKILL_CALLS="$TMP_ROOT/taskkill.log"
: > "$MOCK_TASKKILL_CALLS"
rc=0
MOCK_UNAME=MINGW64_NT-10.0 PATH="$TMP_ROOT/bin:$PATH" run_timeout "$GRAND.win" || rc=$?
STRAYS="$STRAYS $(cat "$GRAND.win" 2>/dev/null || true)"
[ "$rc" = 124 ] || fail "run_with_timeout returned $rc on timeout under Git Bash (want 124)"
grep -Eq '^/T /F /PID [0-9]+$' "$MOCK_TASKKILL_CALLS" \
  || fail "Git Bash timeout did not call 'taskkill /T /F /PID <pid>' (got: $(cat "$MOCK_TASKKILL_CALLS"))"

printf 'job runtime: ok\n'
