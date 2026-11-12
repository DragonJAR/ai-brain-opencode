#!/usr/bin/env bash
# journal-reminder reads brain-config once; osascript receives vault name via argv.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

TMP_ROOT="$(ai_brain_test_root journal-once)"
trap 'rm -rf "$TMP_ROOT"' EXIT

VAULT="$TMP_ROOT/vault"
JOB="$VAULT/scripts/jobs/journal-reminder.sh"
CFG="$VAULT/⚙️ Meta/brain-config.json"
NAME='Vault "Quoted" & Co'
mkdir -p "$VAULT/scripts/jobs" "$VAULT/⚙️ Meta/logs" "$TMP_ROOT/bin"
ai_brain_install_vault_libs "$PKG" "$VAULT"
cp "$PKG/templates/jobs/journal-reminder.sh" "$JOB"
chmod +x "$JOB"
cat > "$CFG" <<JSON
{
  "vault_name": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$NAME"),
  "journal": {"time": "20:30"}
}
JSON

REAL_PY="$(command -v python3)"
CFG_OPENS="$TMP_ROOT/cfg-opens.log"
: > "$CFG_OPENS"
cat > "$TMP_ROOT/bin/python3" <<SH
#!/bin/sh
# Count argv mentions of brain-config.json (journal-reminder: python3 - "\$CFG").
for arg in "\$@"; do
  case "\$arg" in
    *brain-config.json) printf 'open\n' >> "$CFG_OPENS" ;;
  esac
done
exec "$REAL_PY" "\$@"
SH
chmod +x "$TMP_ROOT/bin/python3"

OSA_LOG="$TMP_ROOT/osascript.log"
cat > "$TMP_ROOT/bin/osascript" <<SH
#!/bin/sh
printf 'ARGV:' >> "$OSA_LOG"
for a in "\$@"; do
  printf ' <%s>' "\$a" >> "$OSA_LOG"
done
printf '\n' >> "$OSA_LOG"
# Consume heredoc from stdin
cat >/dev/null
exit 0
SH
chmod +x "$TMP_ROOT/bin/osascript"

ai_brain_mock_platform "$TMP_ROOT/bin"
export MOCK_UNAME=Darwin
export PATH="$TMP_ROOT/bin:/usr/bin:/bin"

bash "$JOB" >"$TMP_ROOT/out.txt" 2>"$TMP_ROOT/err.txt" || true

opens="$(wc -l < "$CFG_OPENS" | tr -d ' ')"
if [ "$opens" != "1" ]; then
  printf 'FAIL: brain-config.json opened %s times (want 1)\n' "$opens" >&2
  cat "$CFG_OPENS" >&2
  exit 1
fi

if [ ! -s "$OSA_LOG" ]; then
  printf 'FAIL: osascript was not invoked under Darwin mock\n' >&2
  cat "$TMP_ROOT/out.txt" "$TMP_ROOT/err.txt" >&2
  exit 1
fi

# Name must travel as an argv element (osascript - NAME MESSAGE), not via shell interpolation into AppleScript.
if ! grep -F "<$NAME>" "$OSA_LOG" >/dev/null; then
  printf 'FAIL: osascript argv missing vault name as discrete argument\n' >&2
  cat "$OSA_LOG" >&2
  exit 1
fi

# AppleScript body in the job must use argv items, not embedded NAME.
if grep -nE "display notification .*$NAME|with title \"$NAME" "$JOB" >/dev/null 2>&1; then
  printf 'FAIL: journal-reminder interpolates name into AppleScript body\n' >&2
  exit 1
fi
if ! grep -q 'item 1 of argv' "$JOB" || ! grep -q 'osascript - "\$NAME"' "$JOB"; then
  printf 'FAIL: journal-reminder no longer passes name via osascript argv\n' >&2
  exit 1
fi

# Linux under cron: no DBUS_SESSION_BUS_ADDRESS, so the job points notify-send
# at the user's session bus (cron leaves XDG_RUNTIME_DIR unset: /run/user/<uid>).
# A short path: macOS limits unix socket paths to 104 bytes.
BUS_DIR="$(mktemp -d /tmp/aib-bus.XXXXXX)"
trap 'rm -rf "$TMP_ROOT" "$BUS_DIR"' EXIT
"$REAL_PY" -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$BUS_DIR/bus"
NOTIFY_LOG="$TMP_ROOT/notify-send.log"
cat > "$TMP_ROOT/bin/notify-send" <<SH
#!/bin/sh
printf '%s\n' "\${DBUS_SESSION_BUS_ADDRESS:-unset}" >> "$NOTIFY_LOG"
SH
chmod +x "$TMP_ROOT/bin/notify-send"
env -u DBUS_SESSION_BUS_ADDRESS MOCK_UNAME=Linux XDG_RUNTIME_DIR="$BUS_DIR" bash "$JOB" > "$TMP_ROOT/linux.txt" 2>&1 || true
if [ "$(cat "$NOTIFY_LOG" 2>/dev/null)" != "unix:path=$BUS_DIR/bus" ]; then
  printf 'FAIL: notify-send did not get the session bus address (got: %s)\n' "$(cat "$NOTIFY_LOG" 2>/dev/null || echo 'not called')" >&2
  exit 1
fi
: > "$NOTIFY_LOG"
DBUS_SESSION_BUS_ADDRESS="unix:path=/custom/bus" MOCK_UNAME=Linux XDG_RUNTIME_DIR="$BUS_DIR" bash "$JOB" > "$TMP_ROOT/linux.txt" 2>&1 || true
[ "$(cat "$NOTIFY_LOG")" = "unix:path=/custom/bus" ] \
  || { printf 'FAIL: journal-reminder overrode an existing DBUS_SESSION_BUS_ADDRESS\n' >&2; exit 1; }

printf 'PASS: journal-reminder reads config once; osascript gets name via argv; notify-send gets the session bus\n'
