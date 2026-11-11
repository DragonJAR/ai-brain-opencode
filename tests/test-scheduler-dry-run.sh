#!/usr/bin/env bash
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/mocks.sh
. "$PKG/tests/lib/mocks.sh"

assert_cron_prefix() {
  local file="$1" hhmm="$2" schedule="$3"
  local prefix schedule_re
  prefix="$(cron_minute_hour "$hhmm")"
  schedule_re="$(printf '%s\n' "$schedule" | sed 's/[*]/\\*/g')"
  if ! grep -q "^${prefix} ${schedule_re} " "$file"; then
    printf 'FAIL: %s did not schedule %s as "%s %s":\n' "$file" "$hhmm" "$prefix" "$schedule" >&2
    cat "$file" >&2
    exit 1
  fi
}
TMP_ROOT="$(ai_brain_test_root schedule-test)"
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$TMP_ROOT/bin" "$TMP_ROOT/tmp" "$TMP_ROOT/vault/⚙️ Meta"
ai_brain_mock_platform "$TMP_ROOT/bin"
ai_brain_mock_crontab "$TMP_ROOT/bin"

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

journal_time="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["journal"]["time"])' "$TMP_ROOT/vault/⚙️ Meta/brain-config.json")"
insights_time="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["schedule"]["insights_time"])' "$TMP_ROOT/vault/⚙️ Meta/brain-config.json")"
maintenance_time="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["schedule"]["maintenance_time"])' "$TMP_ROOT/vault/⚙️ Meta/brain-config.json")"
update_time="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["schedule"]["update_time"])' "$TMP_ROOT/vault/⚙️ Meta/brain-config.json")"
assert_cron_prefix "$TMP_ROOT/output.txt" "$journal_time" '* * 1-5'
assert_cron_prefix "$TMP_ROOT/output.txt" "$insights_time" '* * 0'
assert_cron_prefix "$TMP_ROOT/output.txt" "$maintenance_time" '* * *'
assert_cron_prefix "$TMP_ROOT/output.txt" "$update_time" '* * 1'

# A malformed schedule value falls back to the documented HH:MM default, still minute-then-hour.
cat > "$TMP_ROOT/vault/⚙️ Meta/brain-config.json" <<'JSON'
{
  "journal": {"time": "25:99"},
  "schedule": {"insights_time": ["no", "es", "una", "hora"]}
}
JSON
bash "$PKG/scripts/schedule.sh" "$TMP_ROOT/vault" --dry-run > "$TMP_ROOT/output-bad.txt" 2> "$TMP_ROOT/output-bad.err"
assert_cron_prefix "$TMP_ROOT/output-bad.txt" "20:30" '* * 1-5'
if ! grep -q 'journal.time inválida' "$TMP_ROOT/output-bad.err"; then
  printf 'FAIL: invalid journal.time did not emit a warning\n' >&2
  exit 1
fi

cat > "$TMP_ROOT/vault/⚙️ Meta/brain-config.json" <<'JSON'
{
  "journal": {"time": "00:30"},
  "schedule": {
    "insights_time": "08:00",
    "maintenance_time": "23:59",
    "update_time": "20:05"
  }
}
JSON
bash "$PKG/scripts/schedule.sh" "$TMP_ROOT/vault" --dry-run > "$TMP_ROOT/output-edges.txt"
assert_cron_prefix "$TMP_ROOT/output-edges.txt" "00:30" '* * 1-5'
assert_cron_prefix "$TMP_ROOT/output-edges.txt" "08:00" '* * 0'
assert_cron_prefix "$TMP_ROOT/output-edges.txt" "23:59" '* * *'
assert_cron_prefix "$TMP_ROOT/output-edges.txt" "20:05" '* * 1'

# Old owned lines are removed, user lines stay, and the new minute-hour lines are recorded.
EDGE_CFG="$TMP_ROOT/vault/⚙️ Meta/brain-config.json"
cat > "$EDGE_CFG" <<'JSON'
{
  "journal": {"time": "20:30"},
  "schedule": {
    "insights_time": "21:00",
    "maintenance_time": "03:30",
    "update_time": "08:00"
  }
}
JSON
JOBS="$TMP_ROOT/vault/scripts/jobs"
mkdir -p "$TMP_ROOT/vault/.opencode"
OLD_LINE="20 30 * * 1-5 /bin/bash \"$JOBS/journal-reminder.sh\" # ai-brain vault owner=old"
USER_LINE="15 9 * * * echo user-keeps-this"
MANIFEST="$TMP_ROOT/vault/.opencode/brain-vault-install-manifest.json"
python3 "$PKG/scripts/lib/ownership.py" "$MANIFEST" init >/dev/null
python3 - "$OLD_LINE" "$MANIFEST" "$PKG/scripts/lib/ownership.py" <<'PY'
import json, subprocess, sys
old, manifest, tool = sys.argv[1:]
subprocess.check_call([sys.executable, tool, manifest, "set-cron", json.dumps([old], ensure_ascii=False)])
PY
printf '%s\n%s\n' "$OLD_LINE" "$USER_LINE" > "$MOCK_CRONTAB_STATE"
: > "$MOCK_CRONTAB_WRITES"
bash "$PKG/scripts/schedule.sh" "$TMP_ROOT/vault" > "$TMP_ROOT/reconcile.txt"
if grep -Fxq "$OLD_LINE" "$MOCK_CRONTAB_STATE"; then
  printf 'FAIL: reconcile left the old swapped cron line\n' >&2
  exit 1
fi
if ! grep -Fxq "$USER_LINE" "$MOCK_CRONTAB_STATE"; then
  printf 'FAIL: reconcile dropped a user crontab line\n' >&2
  exit 1
fi
assert_cron_prefix "$MOCK_CRONTAB_STATE" "20:30" '* * 1-5'
bash "$PKG/scripts/schedule.sh" "$TMP_ROOT/vault" --remove > "$TMP_ROOT/remove-1.txt"
cp "$MOCK_CRONTAB_STATE" "$TMP_ROOT/crontab-after-first-remove.txt"
bash "$PKG/scripts/schedule.sh" "$TMP_ROOT/vault" --remove > "$TMP_ROOT/remove-2.txt"
if ! grep -Fxq "$USER_LINE" "$MOCK_CRONTAB_STATE"; then
  printf 'FAIL: --remove deleted a user crontab line\n' >&2
  exit 1
fi
if ! cmp -s "$MOCK_CRONTAB_STATE" "$TMP_ROOT/crontab-after-first-remove.txt"; then
  printf 'FAIL: second --remove was not idempotent\n' >&2
  exit 1
fi
gone_prefix="$(cron_minute_hour "20:30")"
if grep -q "^${gone_prefix} \\* \\* 1-5 " "$MOCK_CRONTAB_STATE"; then
  printf 'FAIL: --remove left an owned package line\n' >&2
  cat "$MOCK_CRONTAB_STATE" >&2
  exit 1
fi

printf 'PASS: Linux --dry-run is side-effect free and invalid times fall back safely\n'
