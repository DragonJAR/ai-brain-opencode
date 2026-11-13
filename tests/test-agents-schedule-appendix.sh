#!/usr/bin/env bash
# AGENTS.md schedule block from install.sh matches brain-config.example.json;
# dead keys schedule.enabled / insights_day / update_day must stay absent.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

EXAMPLE="$PKG/templates/brain-config.example.json"
[ -f "$EXAMPLE" ] || { printf 'FAIL: missing example config\n' >&2; exit 1; }

TMP_ROOT="$(ai_brain_test_root agents-appendix)"
trap 'rm -rf "$TMP_ROOT"' EXIT

VAULT="$TMP_ROOT/vault"
mkdir -p "$TMP_ROOT/bin" "$VAULT"
MOCK_UNAME=Linux
MOCK_GIT_CALLS="$TMP_ROOT/git-calls.log"
MOCK_CRONTAB_STATE="$TMP_ROOT/crontab-state"
MOCK_CRONTAB_CALLS="$TMP_ROOT/crontab-calls.log"
MOCK_CRONTAB_WRITES="$TMP_ROOT/crontab-writes.log"
MOCK_VAULT="$VAULT"
: > "$MOCK_GIT_CALLS"
: > "$MOCK_CRONTAB_CALLS"
: > "$MOCK_CRONTAB_WRITES"

ai_brain_mock_platform "$TMP_ROOT/bin"
ai_brain_mock_crontab "$TMP_ROOT/bin"
ai_brain_mock_git "$TMP_ROOT/bin"
ai_brain_mock_opencode "$TMP_ROOT/bin"

export MOCK_UNAME MOCK_GIT_CALLS MOCK_CRONTAB_STATE MOCK_CRONTAB_CALLS MOCK_CRONTAB_WRITES MOCK_VAULT
export PATH="$TMP_ROOT/bin:$PATH"
export TMPDIR="$TMP_ROOT"
unset BRAIN_STARTER_PIN || true

if ! bash "$PKG/install.sh" "$VAULT" >"$TMP_ROOT/install.txt" 2>&1; then
  printf 'FAIL: install failed\n' >&2
  cat "$TMP_ROOT/install.txt" >&2
  exit 1
fi

AGENTS="$VAULT/AGENTS.md"
[ -f "$AGENTS" ] || { printf 'FAIL: AGENTS.md not generated\n' >&2; exit 1; }

JT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8"))["journal"]["time"])' "$EXAMPLE")"
IT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8"))["schedule"]["insights_time"])' "$EXAMPLE")"
MT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8"))["schedule"]["maintenance_time"])' "$EXAMPLE")"
UT="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8"))["schedule"]["update_time"])' "$EXAMPLE")"
# install seed may rewrite timezone; times must still match the example.
SEED_TZ="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8"))["timezone"])' "$VAULT/⚙️ Meta/brain-config.json")"

missing=0
if ! grep -Fq "Recordatorio del diario: $JT" "$AGENTS"; then
  printf 'FAIL: AGENTS.md diario time != example (%s)\n' "$JT" >&2
  missing=1
fi
if ! grep -Fq "zona horaria declarada: $SEED_TZ" "$AGENTS"; then
  printf 'FAIL: AGENTS.md scheduler tz != seeded (%s)\n' "$SEED_TZ" >&2
  missing=1
fi
if ! grep -Fq "domingo $IT" "$AGENTS"; then
  printf 'FAIL: AGENTS.md insights time != example (%s)\n' "$IT" >&2
  missing=1
fi
if ! grep -Fq "Mantenimiento diario: $MT" "$AGENTS"; then
  printf 'FAIL: AGENTS.md maintenance time != example (%s)\n' "$MT" >&2
  missing=1
fi
if ! grep -Fq "Actualización del starter: lunes $UT" "$AGENTS"; then
  printf 'FAIL: AGENTS.md update time != example (%s)\n' "$UT" >&2
  missing=1
fi
if [ "$missing" -ne 0 ]; then
  grep -n 'Scheduler\|diario\|domingo\|Mantenimiento\|Actualización' "$AGENTS" >&2 || true
  exit 1
fi

# Dead keys must not reappear as schedule fields or product source references.
if ! python3 - "$EXAMPLE" <<'PY'
import json, pathlib, sys
cfg = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
sched = cfg.get("schedule") if isinstance(cfg.get("schedule"), dict) else {}
dead = [k for k in ("enabled", "insights_day", "update_day") if k in sched]
if dead:
    print("FAIL: example schedule has dead keys: " + ", ".join(dead))
    raise SystemExit(1)
PY
then
  exit 1
fi

DEAD_HITS="$(grep -RInE 'schedule\.enabled|insights_day|update_day' \
  "$PKG/install.sh" \
  "$PKG/scripts/schedule.sh" \
  "$PKG/plugin/brain-vault/index.js" \
  "$PKG/templates/agents-opencode-appendix.md" \
  "$PKG/templates/jobs" 2>/dev/null || true)"
if [ -n "$DEAD_HITS" ]; then
  printf 'FAIL: dead schedule keys present in product sources\n' >&2
  printf '%s\n' "$DEAD_HITS" >&2
  exit 1
fi

printf 'PASS: AGENTS.md schedule times match example; dead keys absent\n'
