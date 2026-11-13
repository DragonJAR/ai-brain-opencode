#!/usr/bin/env bash
# Temporary files and the job lock go through one EXIT handler in
# scripts/lib/common.sh (brain_mktemp, brain_cleanup_add). Nothing is left in
# TMPDIR when a script aborts halfway, and no second `trap EXIT` can replace the
# handler and leak what it registered.
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

TMP_ROOT="$(ai_brain_test_root temp-cleanup)"
trap 'rm -rf "$TMP_ROOT"' EXIT
SCRATCH="$TMP_ROOT/tmp"
mkdir -p "$SCRATCH"
leftovers() { find "$SCRATCH" -mindepth 1 -name 'ai-brain-*' -print; }

# 1. Every way a script can stop removes what brain_mktemp created.
for ending in "false" "die stop" "exit 3" "true"; do
  set +e
  TMPDIR="$SCRATCH" bash -c '
    set -euo pipefail
    . "$1/scripts/lib/common.sh"
    brain_mktemp first one
    brain_mktemp second two
    [ -f "$first" ] && [ -f "$second" ] || exit 9
    '"$ending"'
  ' _ "$PKG" > /dev/null 2>&1
  rc=$?
  set -e
  [ "$rc" != 9 ] || fail "brain_mktemp did not create its files"
  [ -z "$(leftovers)" ] || fail "temporary files survived a script ending with '$ending': $(leftovers | tr '\n' ' ')"
done

# 2. A temp file made inside a function the caller runs directly is cleaned too.
TMPDIR="$SCRATCH" bash -c '
  set -euo pipefail
  . "$1/scripts/lib/common.sh"
  make_one() { local path; brain_mktemp path inner; printf "%s" "$path" > "$2"; }
  make_one x "$2"
  false
' _ "$PKG" "$TMP_ROOT/inner-path" > /dev/null 2>&1 || true
[ -s "$TMP_ROOT/inner-path" ] || fail "brain_mktemp did not set the caller's local variable"
[ -z "$(leftovers)" ] || fail "a temp file created inside a function survived"

# 3. schedule.sh aborting after creating its files (crontab cannot be read) leaves none.
BIN="$TMP_ROOT/bin"
ai_brain_mock_platform "$BIN"
cat > "$BIN/crontab" <<'SH'
#!/bin/sh
echo "crontab: simulated failure" >&2
exit 7
SH
chmod +x "$BIN/crontab"
VAULT="$TMP_ROOT/vault"
mkdir -p "$VAULT/scripts/jobs" "$VAULT/.opencode"
python3 "$PKG/scripts/lib/ownership.py" "$VAULT/.opencode/brain-vault-install-manifest.json" init
if MOCK_UNAME=Linux PATH="$BIN:$PATH" TMPDIR="$SCRATCH" bash "$PKG/scripts/schedule.sh" "$VAULT" > "$TMP_ROOT/sched.txt" 2>&1; then
  fail "schedule.sh succeeded although crontab could not be read"
fi
[ -z "$(leftovers)" ] || fail "schedule.sh left temporary files after aborting: $(leftovers | tr '\n' ' ')"

# 4. A scheduled job releases its lock when it fails halfway.
JV="$TMP_ROOT/job-vault"
mkdir -p "$JV/scripts/jobs"
ai_brain_install_vault_libs "$PKG" "$JV"
printf '#!/usr/bin/env bash\nset -euo pipefail\n. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"\njob_init\njob_fail "boom"\n' \
  > "$JV/scripts/jobs/probe-job.sh"
bash "$JV/scripts/jobs/probe-job.sh" > /dev/null 2>&1 && fail "the probe job did not fail"
[ ! -e "$JV/⚙️ Meta/logs/.probe-job.lock" ] || fail "a failed job kept its lock"

# 5. No product script installs its own EXIT trap next to the shared handler.
for script in "$PKG"/install.sh "$PKG"/uninstall.sh "$PKG"/scripts/schedule.sh "$PKG"/templates/jobs/*.sh; do
  if grep -nE '^[^#]*\btrap\b[^#]*\bEXIT\b' "$script" >/dev/null; then
    fail "${script#"$PKG"/} sets its own EXIT trap, replacing the shared cleanup in common.sh"
  fi
done
grep -nE '^[^#]*\$\(mktemp ' "$PKG/scripts/schedule.sh" >/dev/null \
  && fail "schedule.sh creates a temp file without brain_mktemp"

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: temp cleanup had %s failures\n' "$failures" >&2
  exit 1
fi
printf 'PASS: temp files and job locks are removed through one EXIT handler, also when a script aborts\n'
