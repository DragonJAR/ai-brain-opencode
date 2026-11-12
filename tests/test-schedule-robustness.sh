#!/usr/bin/env bash
# scripts/schedule.sh edge cases: an exported CDPATH, a vault path with shell and
# cron metacharacters (it must reach the job literally), macOS protected folders
# (TCC) and the bootout/bootstrap race of launchd, and a schtasks CSV that is not
# UTF-8 (cp1252 or UTF-16).
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

TMP_ROOT="$(ai_brain_test_root schedule-robust)"
TMP_ROOT="$(cd "$TMP_ROOT" && pwd -P)"
trap 'rm -rf "$TMP_ROOT"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }

BIN="$TMP_ROOT/bin"
ai_brain_mock_platform "$BIN"
ai_brain_mock_crontab "$BIN"
ai_brain_mock_windows "$BIN"
ai_brain_mock_plutil "$BIN"
# launchctl: `print` says loaded; `bootstrap` fails MOCK_BOOTSTRAP_FAILS times per label.
cat > "$BIN/launchctl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_LAUNCHCTL_CALLS"
case "$1" in
  bootstrap)
    count_file="$MOCK_LAUNCHCTL_CALLS.$(basename "$3")"
    n=$(cat "$count_file" 2>/dev/null || echo 0)
    n=$((n + 1)); echo "$n" > "$count_file"
    if [ "$n" -le "${MOCK_BOOTSTRAP_FAILS:-0}" ]; then
      echo "Bootstrap failed: 5: Input/output error" >&2; exit 5
    fi ;;
esac
exit 0
SH
chmod +x "$BIN/launchctl"
export PATH="$BIN:$PATH" TMPDIR="$TMP_ROOT"
export MOCK_CRONTAB_STATE="$TMP_ROOT/crontab-state" MOCK_CRONTAB_CALLS="$TMP_ROOT/crontab-calls.log" \
  MOCK_CRONTAB_WRITES="$TMP_ROOT/crontab-writes.log" MOCK_LAUNCHCTL_CALLS="$TMP_ROOT/launchctl.log"

new_vault() {
  mkdir -p "$1/.opencode" "$1/⚙️ Meta/logs"
  ai_brain_install_vault_libs "$PKG" "$1"
}

# 1. An exported CDPATH must not break the package path computation.
CD_VAULT="$TMP_ROOT/cd-vault"
new_vault "$CD_VAULT"
if ! (cd "$PKG" && CDPATH="$PKG" MOCK_UNAME=Linux bash scripts/schedule.sh "$CD_VAULT" --dry-run) \
  > "$TMP_ROOT/cdpath.txt" 2>&1; then
  fail "schedule.sh failed with CDPATH exported: $(cat "$TMP_ROOT/cdpath.txt")"
fi

# 2. Cron: $HOME, a backtick, %, a space and a quote in the vault path stay literal.
# shellcheck disable=SC2016
ODD="$TMP_ROOT/v \$HOME \`id\` 100% it's"
new_vault "$ODD"
printf '#!/bin/sh\necho ran-literally\n' > "$ODD/scripts/jobs/journal-reminder.sh"
: > "$MOCK_CRONTAB_STATE"
MOCK_UNAME=Linux bash "$PKG/scripts/schedule.sh" "$ODD" > "$TMP_ROOT/odd.txt" 2>&1 \
  || fail "schedule.sh failed on a vault path with metacharacters: $(cat "$TMP_ROOT/odd.txt")"
LINE="$(grep -F 'journal-reminder' "$MOCK_CRONTAB_STATE" | head -1)"
# cron turns an unescaped % into a newline and drops the backslash of \%.
case "$(printf '%s' "$LINE" | sed 's/\\%//g')" in *%*) fail "cron line has an unescaped %: $LINE" ;; esac
CMD="$(printf '%s\n' "$LINE" | cut -d' ' -f6- | sed 's/\\%/%/g')"
sh -c "$CMD" 2>"$TMP_ROOT/cron-run.err" || true
LOGFILE="$ODD/⚙️ Meta/logs/journal-reminder.log"
grep -Fq ran-literally "$LOGFILE" 2>/dev/null \
  || fail "the cron command did not run the job at its literal path (line: $LINE; err: $(cat "$TMP_ROOT/cron-run.err"))"

# 3. launchd: a vault under ~/Documents (TCC-protected) gets a warning.
MAC_HOME="$TMP_ROOT/mac-user"
TCC_VAULT="$MAC_HOME/Documents/tcc-vault"
new_vault "$TCC_VAULT"
HOME="$MAC_HOME" MOCK_UNAME=Darwin bash "$PKG/scripts/schedule.sh" "$TCC_VAULT" --dry-run > "$TMP_ROOT/tcc.txt" 2>&1 \
  || fail "launchd --dry-run failed under ~/Documents: $(cat "$TMP_ROOT/tcc.txt")"
grep -Fq 'carpeta protegida' "$TMP_ROOT/tcc.txt" || fail "no TCC warning for a vault under ~/Documents"
PLAIN_VAULT="$TMP_ROOT/plain-vault"
new_vault "$PLAIN_VAULT"
HOME="$MAC_HOME" MOCK_UNAME=Darwin bash "$PKG/scripts/schedule.sh" "$PLAIN_VAULT" --dry-run > "$TMP_ROOT/plain.txt" 2>&1 || true
! grep -Fq 'carpeta protegida' "$TMP_ROOT/plain.txt" || fail "TCC warning for a vault outside protected folders"

# 4. launchd: bootstrap racing the previous bootout is retried a bounded number of times.
: > "$MOCK_LAUNCHCTL_CALLS"; rm -f "$MOCK_LAUNCHCTL_CALLS".*
HOME="$MAC_HOME" MOCK_UNAME=Darwin MOCK_BOOTSTRAP_FAILS=1 bash "$PKG/scripts/schedule.sh" "$PLAIN_VAULT" \
  > "$TMP_ROOT/race.txt" 2>&1 || fail "launchd install gave up after one transient bootstrap failure: $(cat "$TMP_ROOT/race.txt")"
: > "$MOCK_LAUNCHCTL_CALLS"; rm -f "$MOCK_LAUNCHCTL_CALLS".*
if HOME="$MAC_HOME" MOCK_UNAME=Darwin MOCK_BOOTSTRAP_FAILS=99 bash "$PKG/scripts/schedule.sh" "$PLAIN_VAULT" \
  > "$TMP_ROOT/race-fail.txt" 2>&1; then
  fail "launchd install succeeded although bootstrap always fails"
fi
tries="$(cat "$MOCK_LAUNCHCTL_CALLS.com.ai-brain.plain-vault.journal-reminder.plist" 2>/dev/null || echo 0)"
[ "$tries" -ge 2 ] && [ "$tries" -le 5 ] || fail "bootstrap was tried $tries times (want a bounded retry, 2-5)"

# 5. schtasks: a CSV in cp1252 or UTF-16 is decoded, not dropped or mangled.
WIN_VAULT="$TMP_ROOT/win-vault"
new_vault "$WIN_VAULT"
export MOCK_SCHTASKS_STATE="$TMP_ROOT/schtasks-state" MOCK_SCHTASKS_CALLS="$TMP_ROOT/schtasks.log"
: > "$MOCK_SCHTASKS_STATE"
MOCK_UNAME=MINGW64_NT-10.0 bash "$PKG/scripts/schedule.sh" "$WIN_VAULT" > "$TMP_ROOT/win-install.txt" 2>&1 \
  || fail "schtasks fixture install failed: $(cat "$TMP_ROOT/win-install.txt")"
for enc in cp1252 utf-16; do
  python3 -c 'import sys; open(sys.argv[1], "wb").write("\"\\\\ai-brain caf\u00e9 viejo\",\"N/A\",\"Listo\"\r\n\"\\\\Otra\",\"N/A\",\"Listo\"\r\n".encode(sys.argv[2]))' \
    "$MOCK_SCHTASKS_STATE" "$enc"
  MOCK_UNAME=MINGW64_NT-10.0 bash "$PKG/scripts/schedule.sh" "$WIN_VAULT" --remove --dry-run > "$TMP_ROOT/win-$enc.txt" 2>&1 \
    || fail "schtasks --remove --dry-run failed on a $enc CSV: $(cat "$TMP_ROOT/win-$enc.txt")"
  grep -Fq 'tarea ajena preservada: ai-brain café viejo' "$TMP_ROOT/win-$enc.txt" \
    || fail "the $enc schtasks CSV was not decoded (got: $(cat "$TMP_ROOT/win-$enc.txt"))"
done

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: schedule robustness had %s failed assertions\n' "$failures" >&2
  exit 1
fi
printf 'schedule robustness: ok\n'
