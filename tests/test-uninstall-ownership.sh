#!/usr/bin/env bash
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-brain-uninstall-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

VAULT="$TMP_ROOT/vault-user"
MOCK_STARTER="$VAULT/.opencode/skills/ai-brain-starter"
MOCK_CRONTAB_STATE="$TMP_ROOT/crontab-state"
MOCK_CRONTAB_CALLS="$TMP_ROOT/crontab-calls.log"
MOCK_CRONTAB_WRITES="$TMP_ROOT/crontab-writes.log"
MOCK_VAULT="$VAULT"
mkdir -p "$TMP_ROOT/bin" "$VAULT/.opencode/skills" "$VAULT/.opencode/commands" \
  "$VAULT/.opencode/plugins/brain-vault" "$VAULT/scripts/jobs" \
  "$VAULT/⚙️ Meta" "$TMP_ROOT/foreign/ai-brain-starter-legacy"

cat > "$TMP_ROOT/bin/uname" <<'SH'
#!/bin/sh
printf '%s\n' Linux
SH
cat > "$TMP_ROOT/bin/crontab" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_CRONTAB_CALLS"
case "${1:-}" in
  -l)
    [ -f "$MOCK_CRONTAB_STATE" ] || { printf 'no crontab for mock user\n' >&2; exit 1; }
    cat "$MOCK_CRONTAB_STATE"
    ;;
  -)
    printf '%s\n' "$*" >> "$MOCK_CRONTAB_WRITES"
    cat > "$MOCK_CRONTAB_STATE"
    ;;
  *)
    printf '%s\n' "$*" >> "$MOCK_CRONTAB_WRITES"
    if [ -f "${1:-}" ]; then cat "$1" > "$MOCK_CRONTAB_STATE"; fi
    ;;
esac
SH
cat > "$TMP_ROOT/bin/git" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = clone ]; then
  destination="${@: -1}"
  url="${@: -2:1}"
  mkdir -p "$destination"
  if [[ "$url" == *ai-brain-starter ]]; then
    mkdir -p "$destination/skills/journal" "$destination/commands" \
      "$destination/scripts" "$destination/floors" "$destination/templates/generated"
    printf '# Stub starter skill\n' > "$destination/SKILL.md"
    printf '# Stub journal skill\n' > "$destination/skills/journal/SKILL.md"
    printf '# Stub command\n' > "$destination/commands/brain-journal.md"
    cat > "$destination/scripts/generate_floor_stubs.py" <<'PY'
from pathlib import Path
floor = Path(__file__).resolve().parent.parent / "floors" / "stub-floor.md"
floor.write_text("# Stub floor\n", encoding="utf-8")
PY
    printf '#!/bin/sh\nexit 0\n' > "$destination/scripts/vendor-job.sh"
    cat > "$destination/templates/generated/claude-md-template.md" <<'MD'
# Stub vault instructions

## Vault Map
[FILL THIS IN]
MD
  elif [[ "$url" == *humanizer.git ]]; then
    printf '# Stub humanizer\n' > "$destination/README.md"
  else
    printf 'unexpected clone URL: %s\n' "$url" >&2
    exit 91
  fi
  exit 0
fi
if [ "${1:-}" = -C ]; then
  shift 2
  case "${1:-}" in
    log) printf 'deadbeef stub vendor\n'; exit 0 ;;
    init) mkdir -p "$MOCK_VAULT/.git"; exit 0 ;;
    status|add|commit) exit 0 ;;
  esac
fi
printf 'unexpected git command: %s\n' "$*" >&2
exit 92
SH
chmod +x "$TMP_ROOT/bin/uname" "$TMP_ROOT/bin/crontab" "$TMP_ROOT/bin/git"

printf '%s\n' '# User-managed schedule' '0 4 * * * echo keep-me # ai-brain vault-user' > "$MOCK_CRONTAB_STATE"
printf '%s\n' 'external note' > "$TMP_ROOT/foreign/ai-brain-starter-legacy/keep.md"
ln -s "$TMP_ROOT/foreign/ai-brain-starter-legacy/keep.md" "$VAULT/.opencode/skills/personal-link"
printf '%s\n' 'external command' > "$TMP_ROOT/foreign-command.md"
ln -s "$TMP_ROOT/foreign-command.md" "$VAULT/.opencode/commands/personal.md"
printf '%s\n' 'user plugin data' > "$VAULT/.opencode/plugins/brain-vault/personal.js"
printf '%s\n' 'user job' > "$VAULT/scripts/jobs/personal-job.sh"
cat > "$VAULT/opencode.json" <<'JSON'
{
  "mcp": {
    "servers": {
      "personal": {"type": "local", "command": ["personal-server"]}
    }
  }
}
JSON

export MOCK_CRONTAB_STATE MOCK_CRONTAB_CALLS MOCK_CRONTAB_WRITES MOCK_VAULT MOCK_STARTER
export PATH="$TMP_ROOT/bin:$PATH"
export TMPDIR="$TMP_ROOT"

bash "$PKG/install.sh" "$VAULT" --with-mcp --with-schedule > "$TMP_ROOT/install-output.txt"

# Simulate later user edits to files and configuration that the installer created.
printf '%s\n' 'user-modified job contents' > "$VAULT/scripts/jobs/journal-reminder.sh"
printf '%s\n' 'user-modified verifier contents' > "$VAULT/scripts/verify.sh"
ln "$VAULT/scripts/jobs/insights-weekly.sh" "$TMP_ROOT/insights-weekly-hardlink.sh"
python3 - "$VAULT/opencode.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["mcp"]["servers"]["granola"]["url"] = "https://user-modified.invalid/mcp"
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

bash "$PKG/uninstall.sh" "$VAULT" > "$TMP_ROOT/uninstall-output.txt"

failures=0
expect_exists() {
  if [ ! -e "$1" ] && [ ! -L "$1" ]; then
    printf 'FAIL: expected to preserve %s\n' "$1" >&2
    failures=$((failures + 1))
  fi
}
expect_missing() {
  if [ -e "$1" ] || [ -L "$1" ]; then
    printf 'FAIL: expected owned unchanged artifact to be removed: %s\n' "$1" >&2
    failures=$((failures + 1))
  fi
}
expect_contains() {
  if ! grep -Fq -- "$2" "$1"; then
    printf 'FAIL: expected %s to contain %s\n' "$1" "$2" >&2
    failures=$((failures + 1))
  fi
}
expect_exact_line() {
  if ! grep -Fqx -- "$2" "$1"; then
    printf 'FAIL: expected %s to preserve exact line: %s\n' "$1" "$2" >&2
    failures=$((failures + 1))
  fi
}

expect_contains "$MOCK_CRONTAB_STATE" '0 4 * * * echo keep-me # ai-brain vault-user'
expect_exists "$VAULT/.opencode/skills/personal-link"
expect_exists "$VAULT/.opencode/commands/personal.md"
expect_exists "$VAULT/.opencode/plugins/brain-vault/personal.js"
expect_exists "$VAULT/scripts/jobs/personal-job.sh"
expect_exists "$VAULT/scripts/jobs/journal-reminder.sh"
expect_contains "$VAULT/scripts/jobs/journal-reminder.sh" 'user-modified job contents'
expect_exists "$VAULT/scripts/jobs/insights-weekly.sh"
expect_exists "$TMP_ROOT/insights-weekly-hardlink.sh"
expect_exists "$VAULT/scripts/verify.sh"
expect_contains "$VAULT/scripts/verify.sh" 'user-modified verifier contents'
expect_missing "$VAULT/.opencode/plugins/brain-vault/index.js"
expect_missing "$VAULT/scripts/jobs/update-brain.sh"
expect_missing "$VAULT/.opencode/commands/brain-journal.md"
expect_missing "$VAULT/CLAUDE.md"

if ! python3 - "$VAULT/opencode.json" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
servers = data.get("mcp", {}).get("servers", {})
assert "personal" in servers, "unrelated MCP server was removed"
assert servers.get("granola", {}).get("url") == "https://user-modified.invalid/mcp", "user-modified package config was removed"
assert "chatprd" not in servers, "unchanged package-added config was not removed"
PY
then
  failures=$((failures + 1))
fi

# An exact matching line that predates reconciliation is not package-owned.
EXACT_VAULT="$TMP_ROOT/exact-vault"
EXACT_INSTANCE=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
mkdir -p "$EXACT_VAULT/.opencode" "$EXACT_VAULT/⚙️ Meta"
cat > "$EXACT_VAULT/⚙️ Meta/brain-config.json" <<'JSON'
{
  "journal": {"time": "20:30"},
  "schedule": {
    "insights_time": "21:00",
    "maintenance_time": "03:30",
    "update_time": "08:00"
  }
}
JSON
python3 - "$EXACT_VAULT/.opencode/brain-vault-install-manifest.json" "$EXACT_INSTANCE" <<'PY'
import hashlib, json, pathlib, sys

manifest = pathlib.Path(sys.argv[1])
data = {
    "format": 1,
    "owner": "ai-brain-opencode",
    "instance": sys.argv[2],
    "files": {},
    "symlinks": {},
    "config": {},
    "cron_lines": [],
    "launch_agents": {},
    "trees": {},
}
body = json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
data["seal"] = hashlib.sha256(body).hexdigest()
manifest.write_text(json.dumps(data, sort_keys=True, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
DRY_RUN_LINE="$(bash "$PKG/scripts/schedule.sh" "$EXACT_VAULT" --dry-run | sed -n '1p')"
EXACT_LINE="${DRY_RUN_LINE% owner=<dry-run>} owner=$EXACT_INSTANCE"
UNRELATED_LINE='0 4 * * * echo preserve-this-entry'
printf '%s\n' "$EXACT_LINE" "$UNRELATED_LINE" > "$MOCK_CRONTAB_STATE"
expect_exact_line "$MOCK_CRONTAB_STATE" "$EXACT_LINE"
bash "$PKG/scripts/schedule.sh" "$EXACT_VAULT" > "$TMP_ROOT/exact-schedule-install.txt"
expect_exact_line "$MOCK_CRONTAB_STATE" "$EXACT_LINE"
bash "$PKG/scripts/schedule.sh" "$EXACT_VAULT" --remove > "$TMP_ROOT/exact-schedule-remove.txt"
expect_exact_line "$MOCK_CRONTAB_STATE" "$EXACT_LINE"
expect_exact_line "$MOCK_CRONTAB_STATE" "$UNRELATED_LINE"

# Missing ownership metadata must fail closed without querying or writing crontab.
MISSING_MANIFEST_VAULT="$TMP_ROOT/missing-manifest-vault"
mkdir -p "$MISSING_MANIFEST_VAULT"
cp "$MOCK_CRONTAB_STATE" "$TMP_ROOT/crontab-before-missing-manifest"
cp "$MOCK_CRONTAB_CALLS" "$TMP_ROOT/calls-before-missing-manifest"
cp "$MOCK_CRONTAB_WRITES" "$TMP_ROOT/writes-before-missing-manifest"
bash "$PKG/scripts/schedule.sh" "$MISSING_MANIFEST_VAULT" --remove > "$TMP_ROOT/missing-manifest-remove.txt" 2>&1
if ! cmp -s "$MOCK_CRONTAB_STATE" "$TMP_ROOT/crontab-before-missing-manifest"; then
  printf 'FAIL: missing-manifest removal changed the crontab\n' >&2
  failures=$((failures + 1))
fi
if ! cmp -s "$MOCK_CRONTAB_CALLS" "$TMP_ROOT/calls-before-missing-manifest"; then
  printf 'FAIL: missing-manifest removal queried crontab\n' >&2
  failures=$((failures + 1))
fi
if ! cmp -s "$MOCK_CRONTAB_WRITES" "$TMP_ROOT/writes-before-missing-manifest"; then
  printf 'FAIL: missing-manifest removal invoked the crontab writer\n' >&2
  failures=$((failures + 1))
fi

# Legacy artifacts without a trustworthy manifest remain untouched.
LEGACY_VAULT="$TMP_ROOT/legacy-vault"
mkdir -p "$LEGACY_VAULT/.opencode/plugins/brain-vault" \
  "$LEGACY_VAULT/.opencode/commands" "$LEGACY_VAULT/scripts/jobs"
printf '%s\n' 'legacy plugin' > "$LEGACY_VAULT/.opencode/plugins/brain-vault/index.js"
printf '%s\n' 'legacy job' > "$LEGACY_VAULT/scripts/jobs/journal-reminder.sh"
printf '%s\n' 'legacy command' > "$TMP_ROOT/legacy-command.md"
ln -s "$TMP_ROOT/legacy-command.md" "$LEGACY_VAULT/.opencode/commands/journal.md"
printf '%s\n' 'not a valid ownership manifest' > "$LEGACY_VAULT/.opencode/brain-vault-install-manifest.json"
cp "$MOCK_CRONTAB_STATE" "$TMP_ROOT/crontab-before-legacy"
cp "$MOCK_CRONTAB_WRITES" "$TMP_ROOT/writes-before-legacy"
bash "$PKG/uninstall.sh" "$LEGACY_VAULT" > "$TMP_ROOT/legacy-uninstall-output.txt"
expect_contains "$LEGACY_VAULT/.opencode/plugins/brain-vault/index.js" 'legacy plugin'
expect_contains "$LEGACY_VAULT/scripts/jobs/journal-reminder.sh" 'legacy job'
expect_exists "$LEGACY_VAULT/.opencode/commands/journal.md"
expect_exists "$LEGACY_VAULT/.opencode/brain-vault-install-manifest.json"
if ! cmp -s "$MOCK_CRONTAB_STATE" "$TMP_ROOT/crontab-before-legacy"; then
  printf 'FAIL: legacy uninstall changed the crontab\n' >&2
  failures=$((failures + 1))
fi
if ! cmp -s "$MOCK_CRONTAB_WRITES" "$TMP_ROOT/writes-before-legacy"; then
  printf 'FAIL: legacy uninstall invoked the crontab writer\n' >&2
  failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: uninstall ownership safety had %s failed assertions\n' "$failures" >&2
  exit 1
fi

printf 'PASS: uninstall removed only owned unchanged artifacts and preserved unrelated or user-modified content\n'
