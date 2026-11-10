#!/usr/bin/env bash
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-brain-schedule-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$TMP_ROOT/bin" "$TMP_ROOT/tmp" "$TMP_ROOT/vault/⚙️ Meta"
cat > "$TMP_ROOT/bin/uname" <<'SH'
#!/bin/sh
printf '%s\n' Linux
SH
cat > "$TMP_ROOT/bin/crontab" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_CRONTAB_CALLS"
case "${1:-}" in
  -l)
    [ -f "$MOCK_CRONTAB_STATE" ] || exit 1
    cat "$MOCK_CRONTAB_STATE"
    ;;
  *)
    printf '%s\n' "$*" >> "$MOCK_CRONTAB_WRITES"
    if [ "${1:-}" = "-" ]; then
      cat > "$MOCK_CRONTAB_STATE"
    elif [ -f "${1:-}" ]; then
      cat "$1" > "$MOCK_CRONTAB_STATE"
    fi
    ;;
esac
SH
chmod +x "$TMP_ROOT/bin/uname" "$TMP_ROOT/bin/crontab"

cat > "$TMP_ROOT/vault/⚙️ Meta/brain-config.json" <<'JSON'
{
  "journal": {"time": "20:30"},
  "schedule": {
    "insights_time": "21:00",
    "maintenance_time": "03:30",
    "update_time": "08:00"
  }
}
JSON

export MOCK_CRONTAB_CALLS="$TMP_ROOT/crontab-calls.log"
export MOCK_CRONTAB_STATE="$TMP_ROOT/crontab-state"
export MOCK_CRONTAB_WRITES="$TMP_ROOT/crontab-writes.log"
export PATH="$TMP_ROOT/bin:$PATH"
export TMPDIR="$TMP_ROOT/tmp"

bash "$PKG/scripts/schedule.sh" "$TMP_ROOT/vault" --dry-run > "$TMP_ROOT/output.txt"

if [ -s "$MOCK_CRONTAB_WRITES" ]; then
  printf 'FAIL: Linux --dry-run invoked crontab writer: ' >&2
  cat "$MOCK_CRONTAB_WRITES" >&2
  exit 1
fi

printf 'PASS: Linux --dry-run did not invoke a mutating crontab command\n'
