#!/usr/bin/env bash
# Anti-drift: templates/brain-config.example.json must match plugin DEFAULTS,
# install seed (non-mutated keys), journal-reminder fallbacks, and schedule.sh
# package defaults when vault config is absent.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

EXAMPLE="$PKG/templates/brain-config.example.json"
[ -f "$EXAMPLE" ] || { printf 'FAIL: missing %s\n' "$EXAMPLE" >&2; exit 1; }

TMP_ROOT="$(ai_brain_test_root defaults-src)"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail_divergent() {
  # Usage: fail_divergent <key> <source_a> <value_a> <source_b> <value_b>
  printf 'FAIL: default drift on %s: %s=%s vs %s=%s\n' \
    "$1" "$2" "$3" "$4" "$5" >&2
  exit 1
}

assert_same() {
  local key="$1" src_a="$2" val_a="$3" src_b="$4" val_b="$5"
  if [ "$val_a" != "$val_b" ]; then
    fail_divergent "$key" "$src_a" "$val_a" "$src_b" "$val_b"
  fi
}

# Convert cron "MM HH" back to zero-padded HH:MM for HH:MM↔HH:MM messages.
cron_fields_to_hhmm() {
  python3 -c 'import sys; mm,hh=sys.argv[1].split(); print("%02d:%02d" % (int(hh), int(mm)))' "$1"
}

canon() {
  python3 - "$EXAMPLE" "$1" <<'PY'
import json, pathlib, sys
cur = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
for key in sys.argv[2].split("."):
    cur = cur[key]
if isinstance(cur, bool):
    print("true" if cur else "false")
elif isinstance(cur, list):
    print(json.dumps(cur, ensure_ascii=False, separators=(",", ":")))
else:
    print(cur)
PY
}

C_VAULT="$(canon vault_name)"
C_LANG="$(canon language)"
C_TZ="$(canon timezone)"
C_JTIME="$(canon journal.time)"
C_IT="$(canon schedule.insights_time)"
C_MT="$(canon schedule.maintenance_time)"
C_UT="$(canon schedule.update_time)"

# --- (a) plugin DEFAULTS via node -------------------------------------------
if command -v node >/dev/null; then
  node - "$PKG/plugin/brain-vault/index.js" "$TMP_ROOT/plugin-defaults.json" <<'JS'
const { readFileSync, writeFileSync } = require("node:fs")
const pluginPath = process.argv[2]
const outPath = process.argv[3]
const src = readFileSync(pluginPath, "utf8")
const start = src.indexOf("const DEFAULTS = ")
const end = src.indexOf("\nconst TIME_PATTERN")
if (start < 0 || end < 0) {
  console.error("FAIL: could not locate DEFAULTS object in plugin")
  process.exit(1)
}
const DEFAULTS = Function(
  "return (" + src.slice(start + "const DEFAULTS = ".length, end) + ")"
)()
writeFileSync(outPath, JSON.stringify(DEFAULTS, null, 2) + "\n")
JS
  pget() {
    python3 - "$TMP_ROOT/plugin-defaults.json" "$1" <<'PY'
import json, pathlib, sys
cur = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
for key in sys.argv[2].split("."):
    cur = cur[key]
if isinstance(cur, bool):
    print("true" if cur else "false")
elif isinstance(cur, list):
    print(json.dumps(cur, ensure_ascii=False, separators=(",", ":")))
else:
    print(cur)
PY
  }
  assert_same vault_name "templates/brain-config.example.json" "$C_VAULT" "plugin DEFAULTS" "$(pget vault_name)"
  assert_same language "templates/brain-config.example.json" "$C_LANG" "plugin DEFAULTS" "$(pget language)"
  assert_same timezone "templates/brain-config.example.json" "$C_TZ" "plugin DEFAULTS" "$(pget timezone)"
  assert_same journal.time "templates/brain-config.example.json" "$C_JTIME" "plugin DEFAULTS" "$(pget journal.time)"
  assert_same schedule.insights_time "templates/brain-config.example.json" "$C_IT" "plugin DEFAULTS" "$(pget schedule.insights_time)"
  assert_same schedule.maintenance_time "templates/brain-config.example.json" "$C_MT" "plugin DEFAULTS" "$(pget schedule.maintenance_time)"
  assert_same schedule.update_time "templates/brain-config.example.json" "$C_UT" "plugin DEFAULTS" "$(pget schedule.update_time)"
else
  printf 'SKIP: node no disponible; rama plugin DEFAULTS omitida\n'
fi

# --- (b) install.sh seed in sandbox -----------------------------------------
SEED_VAULT="$TMP_ROOT/seed-vault"
mkdir -p "$SEED_VAULT/⚙️ Meta"
SEED_BRC="$SEED_VAULT/⚙️ Meta/brain-config.json"
cp "$EXAMPLE" "$SEED_BRC"
python3 - "$PKG/install.sh" "$SEED_BRC" "seed-vault" <<'PY'
import pathlib, re, sys
install = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r"python3 - \"\$BRC\" \"\$SLUG\" <<'PZ'.*?\n(.*?)^PZ\n", install, re.S | re.M)
if not m:
    raise SystemExit("FAIL: could not extract install.sh seed block")
code = m.group(1)
code = re.sub(r'^print\("  \+ config por defecto.*\n', "", code, count=1, flags=re.M)
sys.argv = ["seed", sys.argv[2], sys.argv[3]]
exec(compile(code, "install.sh:seed", "exec"), {})
PY

sget() {
  python3 - "$SEED_BRC" "$1" <<'PY'
import json, pathlib, sys
cur = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
for key in sys.argv[2].split("."):
    cur = cur[key]
print(cur)
PY
}
assert_same journal.time "templates/brain-config.example.json" "$C_JTIME" "install.sh seed" "$(sget journal.time)"
assert_same language "templates/brain-config.example.json" "$C_LANG" "install.sh seed" "$(sget language)"
assert_same schedule.insights_time "templates/brain-config.example.json" "$C_IT" "install.sh seed" "$(sget schedule.insights_time)"
assert_same schedule.maintenance_time "templates/brain-config.example.json" "$C_MT" "install.sh seed" "$(sget schedule.maintenance_time)"
assert_same schedule.update_time "templates/brain-config.example.json" "$C_UT" "install.sh seed" "$(sget schedule.update_time)"

# --- (c) journal-reminder.sh fallbacks --------------------------------------
JR="$PKG/templates/jobs/journal-reminder.sh"
JR_NAME="$(python3 - "$JR" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r'print\(str\(cfg\.get\("vault_name"\) or "([^"]+)"\)\)', text)
print(m.group(1) if m else "")
PY
)"
JR_TIME="$(python3 - "$JR" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
m = re.search(r'print\(time if isinstance\(time, str\) and time else "([^"]+)"\)', text)
print(m.group(1) if m else "")
PY
)"
assert_same vault_name "templates/brain-config.example.json" "$C_VAULT" "journal-reminder.sh fallback" "$JR_NAME"
assert_same journal.time "templates/brain-config.example.json" "$C_JTIME" "journal-reminder.sh fallback" "$JR_TIME"

# --- (d) schedule.sh with absent vault config --------------------------------
# Darwin --dry-run prints launchd plists, not cron. Force Linux via mocked uname
# so we compare package defaults as minute-hour cron fields.
SCHED_VAULT="$TMP_ROOT/sched-vault"
mkdir -p "$SCHED_VAULT/scripts/jobs" "$SCHED_VAULT/.opencode" "$SCHED_VAULT/⚙️ Meta" "$TMP_ROOT/bin"
# intentionally no brain-config.json
ai_brain_mock_platform "$TMP_ROOT/bin"
SRC_SCHED="scripts/schedule.sh --dry-run (no vault config)"
env MOCK_UNAME=Linux PATH="$TMP_ROOT/bin:/usr/bin:/bin" \
  bash "$PKG/scripts/schedule.sh" "$SCHED_VAULT" --dry-run \
  >"$TMP_ROOT/sched.out" 2>"$TMP_ROOT/sched.err"

if grep -q '(dry-run)' "$TMP_ROOT/sched.out" 2>/dev/null || \
   ! grep -Eq '^[0-9]+ [0-9]+ ' "$TMP_ROOT/sched.out"; then
  printf 'FAIL: expected Linux cron dry-run lines (uname mock); got Darwin plist or empty output\n' >&2
  cat "$TMP_ROOT/sched.out" "$TMP_ROOT/sched.err" >&2 || true
  exit 1
fi

# Extract cron "MM HH" by job name, normalize both sides to HH:MM, then compare.
assert_schedule_default() {
  local key="$1" hhmm="$2" job="$3"
  local expected_mh actual_mh actual_hhmm
  expected_mh="$(cron_minute_hour "$hhmm")"
  actual_mh="$(awk -v job="$job" 'index($0, job) { print $1 " " $2; exit }' "$TMP_ROOT/sched.out")"
  if [ -z "$actual_mh" ]; then
    fail_divergent "$key" "templates/brain-config.example.json" "$hhmm" "$SRC_SCHED" "(missing cron line for $job)"
  fi
  # Same representation: compare minute-hour forms first (catches true drift).
  if [ "$expected_mh" != "$actual_mh" ]; then
    actual_hhmm="$(cron_fields_to_hhmm "$actual_mh")"
    fail_divergent "$key" \
      "templates/brain-config.example.json" "$hhmm" \
      "$SRC_SCHED" "$actual_hhmm"
  fi
}

assert_schedule_default journal.time "$C_JTIME" journal-reminder.sh
assert_schedule_default schedule.insights_time "$C_IT" insights-weekly.sh
assert_schedule_default schedule.maintenance_time "$C_MT" daily-maintenance.sh
assert_schedule_default schedule.update_time "$C_UT" update-brain.sh

printf 'PASS: defaults single-source anti-drift (example vs plugin/install/journal-reminder/schedule)\n'
