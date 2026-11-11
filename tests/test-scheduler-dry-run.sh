#!/usr/bin/env bash
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/mocks.sh
. "$PKG/tests/lib/mocks.sh"
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

# A malformed schedule value must not produce an invalid cron line.
cat > "$TMP_ROOT/vault/⚙️ Meta/brain-config.json" <<'JSON'
{
  "journal": {"time": "25:99"},
  "schedule": {"insights_time": ["no", "es", "una", "hora"]}
}
JSON
bash "$PKG/scripts/schedule.sh" "$TMP_ROOT/vault" --dry-run > "$TMP_ROOT/output-bad.txt" 2> "$TMP_ROOT/output-bad.err"
if ! head -1 "$TMP_ROOT/output-bad.txt" | grep -q '^20 30 \* \* 1-5 '; then
  printf 'FAIL: invalid journal.time did not fall back to 20:30: ' >&2
  head -1 "$TMP_ROOT/output-bad.txt" >&2
  exit 1
fi
if ! grep -q 'journal.time inválida' "$TMP_ROOT/output-bad.err"; then
  printf 'FAIL: invalid journal.time did not emit a warning\n' >&2
  exit 1
fi

printf 'PASS: Linux --dry-run is side-effect free and invalid times fall back safely\n'
