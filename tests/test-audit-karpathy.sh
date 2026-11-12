#!/usr/bin/env bash
# Tests for Karpathy Ingestion scaffolding, Audit integrity tool, and Executive commands.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

TMP_ROOT="$(ai_brain_test_root audit-karpathy)"
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
export BRAIN_STARTER_UPDATE=0
unset BRAIN_STARTER_PIN || true

# 1. Install fresh vault
if ! bash "$PKG/install.sh" "$VAULT" >"$TMP_ROOT/install.txt" 2>&1; then
  printf 'FAIL: install failed\n' >&2
  cat "$TMP_ROOT/install.txt" >&2
  exit 1
fi

# 2. Assert canonical directory Notes/Raw and .gitkeep
if [ ! -d "$VAULT/📝 Notes/Raw" ] || [ ! -f "$VAULT/📝 Notes/Raw/.gitkeep" ]; then
  printf 'FAIL: 📝 Notes/Raw/.gitkeep was not created by installer\n' >&2
  exit 1
fi

# 3. Assert package commands exist in .opencode/commands
for cmd in ingest audit today ideas create; do
  if [ ! -f "$VAULT/.opencode/commands/$cmd.md" ]; then
    printf 'FAIL: command .opencode/commands/%s.md missing\n' "$cmd" >&2
    exit 1
  fi
done

# 4. Assert scripts/audit.py installed and executable
AUDIT_BIN="$VAULT/scripts/audit.py"
if [ ! -f "$AUDIT_BIN" ] || [ ! -x "$AUDIT_BIN" ]; then
  printf 'FAIL: scripts/audit.py missing or not executable\n' >&2
  exit 1
fi

# 5. Clean vault audit passes
if ! python3 "$AUDIT_BIN" "$VAULT" --strict >"$TMP_ROOT/audit-clean.txt" 2>&1; then
  printf 'FAIL: fresh vault failed audit\n' >&2
  cat "$TMP_ROOT/audit-clean.txt" >&2
  exit 1
fi

# 6. Test broken wikilink detection
cat > "$VAULT/📝 Notes/nota-prueba.md" <<'EOF'
---
type: note
created: 2026-11-11
---

Esta nota enlaza a un destino roto: [[NotaInexistente]].
EOF

audit_broken_out="$TMP_ROOT/audit-broken.json"
python3 "$AUDIT_BIN" "$VAULT" --json > "$audit_broken_out"
if ! grep -Fq 'NotaInexistente' "$audit_broken_out"; then
  printf 'FAIL: audit did not detect broken wikilink\n' >&2
  cat "$audit_broken_out" >&2
  exit 1
fi

# --strict must exit 1 when broken link exists
set +e
python3 "$AUDIT_BIN" "$VAULT" --strict >/dev/null 2>&1
strict_rc=$?
set -e
if [ "$strict_rc" -ne 1 ]; then
  printf 'FAIL: audit --strict did not exit 1 on broken wikilink (rc=%s)\n' "$strict_rc" >&2
  exit 1
fi

# 7. Test pending raw source detection
touch "$VAULT/📝 Notes/Raw/articulo-investigacion.pdf"
python3 "$AUDIT_BIN" "$VAULT" --json > "$TMP_ROOT/audit-raw.json"
if ! grep -Fq 'articulo-investigacion.pdf' "$TMP_ROOT/audit-raw.json"; then
  printf 'FAIL: audit did not detect pending raw file\n' >&2
  cat "$TMP_ROOT/audit-raw.json" >&2
  exit 1
fi

# Simulate ingest log entry
mkdir -p "$VAULT/⚙️ Meta/logs"
cat >> "$VAULT/⚙️ Meta/logs/ingest.log" <<'EOF'
## [2026-11-11 22:00] ingest | 📝 Notes/Raw/articulo-investigacion.pdf -> [[📝 Notes/articulo-investigacion]]
EOF

python3 "$AUDIT_BIN" "$VAULT" --json > "$TMP_ROOT/audit-raw-cleared.json"
if grep -Fq 'articulo-investigacion.pdf' "$TMP_ROOT/audit-raw-cleared.json"; then
  printf 'FAIL: raw source still marked pending after ingest.log entry\n' >&2
  cat "$TMP_ROOT/audit-raw-cleared.json" >&2
  exit 1
fi

# 8. Clean up test notes before uninstall test
rm -f "$VAULT/📝 Notes/nota-prueba.md" "$VAULT/📝 Notes/Raw/articulo-investigacion.pdf"

# 9. Test uninstall removes audit.py and package commands cleanly
if ! bash "$PKG/uninstall.sh" "$VAULT" >"$TMP_ROOT/uninstall.txt" 2>&1; then
  printf 'FAIL: uninstall failed\n' >&2
  cat "$TMP_ROOT/uninstall.txt" >&2
  exit 1
fi

if [ -f "$VAULT/scripts/audit.py" ]; then
  printf 'FAIL: uninstall did not remove scripts/audit.py\n' >&2
  exit 1
fi

for cmd in ingest audit today ideas create; do
  if [ -f "$VAULT/.opencode/commands/$cmd.md" ]; then
    printf 'FAIL: uninstall did not remove .opencode/commands/%s.md\n' "$cmd" >&2
    exit 1
  fi
done

printf 'PASS: Karpathy wiki scaffolding, audit integrity, and executive commands\n'
