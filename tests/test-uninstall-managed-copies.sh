#!/usr/bin/env bash
# Uninstall must remove registered copy-mode artifacts (python3.sh, Windows
# ai-brain-run.cmd wrapper, regular CLAUDE.md), rmdir empty scripts/jobs and
# scripts/lib, and preserve a user-modified registered file.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

TMP_ROOT="$(ai_brain_test_root uninstall-copies)"
trap 'rm -rf "$TMP_ROOT"' EXIT

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

mkdir -p "$TMP_ROOT/bin"
MOCK_UNAME=Linux
MOCK_CRONTAB_STATE="$TMP_ROOT/crontab-state"
MOCK_CRONTAB_CALLS="$TMP_ROOT/crontab-calls.log"
MOCK_CRONTAB_WRITES="$TMP_ROOT/crontab-writes.log"
: > "$MOCK_CRONTAB_CALLS"
: > "$MOCK_CRONTAB_WRITES"
: > "$MOCK_CRONTAB_STATE"
ai_brain_mock_platform "$TMP_ROOT/bin"
ai_brain_mock_crontab "$TMP_ROOT/bin"
export MOCK_UNAME MOCK_CRONTAB_STATE MOCK_CRONTAB_CALLS MOCK_CRONTAB_WRITES
export PATH="$TMP_ROOT/bin:$PATH"
export TMPDIR="$TMP_ROOT"

V="$TMP_ROOT/vault"
mkdir -p "$V/scripts/jobs" "$V/scripts/lib" "$V/.opencode"

# Three package-owned copy artifacts that must disappear on uninstall.
# Plus a copy-mode wiring tree (Windows-style skill copy) that must go WITHOUT --purge-clones.
mkdir -p "$V/.opencode/skills/journal"
printf '%s\n' '# copied skill' > "$V/.opencode/skills/journal/SKILL.md"
printf '%s\n' '# pick_python3 stub' > "$V/scripts/lib/python3.sh"
chmod 644 "$V/scripts/lib/python3.sh"
printf '%s\r\n' \
  '@echo off' \
  'set "JOB=%~1"' \
  'if "%JOB%"=="" exit /b 2' \
  'bash "%~dp0%JOB%.sh"' \
  'exit /b %ERRORLEVEL%' \
  > "$V/scripts/jobs/ai-brain-run.cmd"
chmod 644 "$V/scripts/jobs/ai-brain-run.cmd"
printf '%s\n' '# vault instructions (Windows copy of AGENTS.md)' > "$V/CLAUDE.md"
chmod 644 "$V/CLAUDE.md"

# Registered file the user will edit after the seal — must be preserved.
printf '%s\n' '#!/usr/bin/env bash' 'echo original-verify' > "$V/scripts/verify.sh"
chmod 755 "$V/scripts/verify.sh"

# Sealed manifest (same seal recipe as the scripts/ symlink refuse fixture).
python3 - "$V" "$PKG/scripts/lib" <<'PY'
import hashlib, json, pathlib, stat, sys

sys.path.insert(0, sys.argv[2])
import ownership

vault = pathlib.Path(sys.argv[1])
paths = [
    "scripts/lib/python3.sh",
    "scripts/jobs/ai-brain-run.cmd",
    "CLAUDE.md",
    "scripts/verify.sh",
]
files = {}
for rel in paths:
    target = vault / rel
    st = target.stat()
    files[rel] = {
        "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
        "mode": stat.S_IMODE(st.st_mode),
        "nlink": st.st_nlink,
    }
data = {
    "format": 1,
    "owner": "ai-brain-opencode",
    "instance": "a" * 32,
    "cron_ownership_version": 2,
    "files": files,
    "symlinks": {},
    "config": {},
    "cron_lines": [],
    "launch_agents": {},
    "trees": {".opencode/skills/journal": ownership.tree_hash(vault / ".opencode/skills/journal")},
}
body = {k: v for k, v in data.items() if k != "seal"}
data["seal"] = hashlib.sha256(
    json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
).hexdigest()
(vault / ".opencode/brain-vault-install-manifest.json").write_text(
    json.dumps(data, sort_keys=True, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8",
)
PY

# User edits a registered file after install — fingerprint no longer matches.
printf '%s\n' '#!/usr/bin/env bash' 'echo user-edited-verify' > "$V/scripts/verify.sh"
chmod 755 "$V/scripts/verify.sh"

set +e
bash "$PKG/uninstall.sh" "$V" >"$TMP_ROOT/uninstall.txt" 2>"$TMP_ROOT/uninstall.err"
rc=$?
set -e
cat "$TMP_ROOT/uninstall.txt" "$TMP_ROOT/uninstall.err" >"$TMP_ROOT/uninstall.all"

if [ "$rc" -ne 0 ]; then
  fail "uninstall exited $rc for sealed copy-mode artifacts"
  cat "$TMP_ROOT/uninstall.all" >&2
fi

for rel in "scripts/lib/python3.sh" "scripts/jobs/ai-brain-run.cmd" "CLAUDE.md" ".opencode/skills/journal"; do
  if [ -e "$V/$rel" ] || [ -L "$V/$rel" ]; then
    fail "owned copy artifact still present: $rel"
  fi
done
if ! grep -Fq 'árbol copiado sin cambios .opencode/skills/journal' "$TMP_ROOT/uninstall.all"; then
  fail "uninstall did not report the removed copy-mode tree"
fi

if [ -d "$V/scripts/jobs" ]; then
  fail "empty scripts/jobs was not removed"
fi
if [ -d "$V/scripts/lib" ]; then
  fail "empty scripts/lib was not removed"
fi

if [ ! -f "$V/scripts/verify.sh" ]; then
  fail "user-modified scripts/verify.sh was removed"
elif ! grep -Fq 'user-edited-verify' "$V/scripts/verify.sh"; then
  fail "user-modified scripts/verify.sh content was altered"
fi

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: uninstall managed-copy residuals had %s failed assertions\n' "$failures" >&2
  exit 1
fi
printf 'PASS: uninstall removes python3.sh, ai-brain-run.cmd, CLAUDE.md copy; cleans empty jobs/lib; preserves user edits\n'
