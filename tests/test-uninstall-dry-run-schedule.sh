#!/usr/bin/env bash
# uninstall --dry-run (and schedule.sh --remove --dry-run) lists the scheduled
# jobs it would remove on every backend, and changes none of them.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

TMP_ROOT="$(ai_brain_test_root uninstall-dry-schedule)"
trap "cp \"\$TMP_ROOT/uninstall-dry.txt\" /tmp/cs-peek/ 2>/dev/null; rm -rf \"\$TMP_ROOT\"" EXIT

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

BIN="$TMP_ROOT/bin"
mkdir -p "$BIN"
ai_brain_mock_platform "$BIN"
ai_brain_mock_crontab "$BIN"
ai_brain_mock_git "$BIN"
ai_brain_mock_opencode "$BIN"
ai_brain_mock_windows "$BIN"
ai_brain_mock_plutil "$BIN"
cat > "$BIN/launchctl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_LAUNCHCTL_CALLS"
exit 0
SH
chmod +x "$BIN/launchctl"
export PATH="$BIN:$PATH"
export TMPDIR="$TMP_ROOT"
export BRAIN_STARTER_UPDATE=0
unset BRAIN_STARTER_PIN || true
JOBS=""
for job in "$PKG"/templates/jobs/*.sh; do JOBS="$JOBS $(basename "$job" .sh)"; done

# --- Linux (cron) through uninstall.sh ---------------------------------------------
VAULT="$TMP_ROOT/vault"
export MOCK_UNAME=Linux MOCK_VAULT="$VAULT"
export MOCK_GIT_CALLS="$TMP_ROOT/git-calls.log"
export MOCK_CRONTAB_STATE="$TMP_ROOT/crontab-state"
export MOCK_CRONTAB_CALLS="$TMP_ROOT/crontab-calls.log"
export MOCK_CRONTAB_WRITES="$TMP_ROOT/crontab-writes.log"
: > "$MOCK_GIT_CALLS"; : > "$MOCK_CRONTAB_STATE"; : > "$MOCK_CRONTAB_CALLS"; : > "$MOCK_CRONTAB_WRITES"
bash "$PKG/install.sh" "$VAULT" --with-schedule > "$TMP_ROOT/install.txt" 2>&1 \
  || { cat "$TMP_ROOT/install.txt" >&2; printf 'FAIL: fixture install failed\n' >&2; exit 1; }
cp "$MOCK_CRONTAB_STATE" "$TMP_ROOT/crontab-before"
cp "$VAULT/.opencode/brain-vault-install-manifest.json" "$TMP_ROOT/manifest-before"
: > "$MOCK_CRONTAB_WRITES"
bash "$PKG/uninstall.sh" "$VAULT" --dry-run > "$TMP_ROOT/uninstall-dry.txt" 2>&1 || fail "uninstall --dry-run failed"
for job in $JOBS; do
  grep -F '~ cron' "$TMP_ROOT/uninstall-dry.txt" | grep -Fq "/$job.sh'" \
    || fail "uninstall --dry-run does not list the cron entry of $job"
done
[ ! -s "$MOCK_CRONTAB_WRITES" ] || fail "uninstall --dry-run wrote the crontab"
cmp -s "$MOCK_CRONTAB_STATE" "$TMP_ROOT/crontab-before" || fail "uninstall --dry-run changed the crontab"
cmp -s "$VAULT/.opencode/brain-vault-install-manifest.json" "$TMP_ROOT/manifest-before" \
  || fail "uninstall --dry-run changed the ownership manifest"

# --- macOS (launchd) ---------------------------------------------------------------
MAC_VAULT="$TMP_ROOT/mac-vault"
mkdir -p "$MAC_VAULT/.opencode" "$TMP_ROOT/mac-user"
ai_brain_install_vault_libs "$PKG" "$MAC_VAULT"
export MOCK_LAUNCHCTL_CALLS="$TMP_ROOT/launchctl.log"
: > "$MOCK_LAUNCHCTL_CALLS"
HOME="$TMP_ROOT/mac-user" MOCK_UNAME=Darwin bash "$PKG/scripts/schedule.sh" "$MAC_VAULT" > "$TMP_ROOT/mac-install.txt" 2>&1 \
  || { fail "launchd fixture failed"; cat "$TMP_ROOT/mac-install.txt" >&2; }
: > "$MOCK_LAUNCHCTL_CALLS"
cp "$MAC_VAULT/.opencode/brain-vault-install-manifest.json" "$TMP_ROOT/mac-manifest-before"
HOME="$TMP_ROOT/mac-user" MOCK_UNAME=Darwin bash "$PKG/scripts/schedule.sh" "$MAC_VAULT" --remove --dry-run \
  > "$TMP_ROOT/mac-dry.txt" 2>&1 || fail "launchd --remove --dry-run failed"
for job in $JOBS; do
  grep -Fq "~ launch agent $TMP_ROOT/mac-user/Library/LaunchAgents/com.ai-brain.mac-vault.$job.plist" "$TMP_ROOT/mac-dry.txt" \
    || fail "launchd --remove --dry-run does not list $job"
  [ -f "$TMP_ROOT/mac-user/Library/LaunchAgents/com.ai-brain.mac-vault.$job.plist" ] || fail "launchd --remove --dry-run deleted $job"
done
! grep -Fq bootout "$MOCK_LAUNCHCTL_CALLS" || fail "launchd --remove --dry-run called launchctl bootout"
cmp -s "$MAC_VAULT/.opencode/brain-vault-install-manifest.json" "$TMP_ROOT/mac-manifest-before" \
  || fail "launchd --remove --dry-run changed the ownership manifest"

# --- Windows (schtasks) ------------------------------------------------------------
WIN_VAULT="$TMP_ROOT/win-vault"
mkdir -p "$WIN_VAULT/.opencode"
ai_brain_install_vault_libs "$PKG" "$WIN_VAULT"
export MOCK_SCHTASKS_CALLS="$TMP_ROOT/schtasks.log"
: > "$MOCK_SCHTASKS_CALLS"
MOCK_UNAME=MINGW64_NT-10.0 bash "$PKG/scripts/schedule.sh" "$WIN_VAULT" > "$TMP_ROOT/win-install.txt" 2>&1 \
  || { fail "schtasks fixture failed"; cat "$TMP_ROOT/win-install.txt" >&2; }
export MOCK_SCHTASKS_STATE="$TMP_ROOT/schtasks-state"
: > "$MOCK_SCHTASKS_STATE"
for job in $JOBS; do printf '"\\ai-brain win-vault %s","2026-01-01 21:00:00"\n' "$job" >> "$MOCK_SCHTASKS_STATE"; done
: > "$MOCK_SCHTASKS_CALLS"
cp "$WIN_VAULT/.opencode/brain-vault-install-manifest.json" "$TMP_ROOT/win-manifest-before"
MOCK_UNAME=MINGW64_NT-10.0 bash "$PKG/scripts/schedule.sh" "$WIN_VAULT" --remove --dry-run \
  > "$TMP_ROOT/win-dry.txt" 2>&1 || fail "schtasks --remove --dry-run failed"
for job in $JOBS; do
  grep -Fq "~ tarea ai-brain win-vault $job" "$TMP_ROOT/win-dry.txt" || fail "schtasks --remove --dry-run does not list $job"
done
! grep -Fq '/Delete' "$MOCK_SCHTASKS_CALLS" || fail "schtasks --remove --dry-run called schtasks /Delete"
cmp -s "$WIN_VAULT/.opencode/brain-vault-install-manifest.json" "$TMP_ROOT/win-manifest-before" \
  || fail "schtasks --remove --dry-run changed the ownership manifest"

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: uninstall dry-run schedule had %s failed assertions\n' "$failures" >&2
  exit 1
fi
printf 'PASS: uninstall --dry-run lists scheduled jobs on cron, launchd and schtasks without removing them\n'
