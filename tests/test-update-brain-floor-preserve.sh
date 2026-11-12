#!/usr/bin/env bash
# A user-edited floor note must survive update-brain.sh (cp -n).
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

TMP_ROOT="$(ai_brain_test_root floor-preserve)"
trap 'rm -rf "$TMP_ROOT"' EXIT

VAULT="$TMP_ROOT/vault"
STARTER="$VAULT/.opencode/skills/ai-brain-starter"
mkdir -p "$VAULT/scripts/jobs" "$VAULT/⚙️ Meta/Floors" "$VAULT/⚙️ Meta/logs" \
  "$STARTER/floors" "$STARTER/scripts"

cp "$PKG/templates/jobs/update-brain.sh" "$VAULT/scripts/jobs/update-brain.sh"
chmod +x "$VAULT/scripts/jobs/update-brain.sh"

# Vendor floor that would overwrite the user's file if cp lacked -n.
cat > "$STARTER/floors/shared-floor.md" <<'MD'
# Vendor floor (would clobber)
MD
# Generator present so the copy path runs; keep it a no-op success.
cat > "$STARTER/scripts/generate_floor_stubs.py" <<'PY'
from pathlib import Path
# Ensure the vendor floor exists for the copy step.
Path(__file__).resolve().parent.parent.joinpath("floors").mkdir(parents=True, exist_ok=True)
PY

USER_MARK="USER-EDITED-FLOOR-$(date +%s)"
cat > "$VAULT/⚙️ Meta/Floors/shared-floor.md" <<MD
# $USER_MARK
MD
cp "$VAULT/⚙️ Meta/Floors/shared-floor.md" "$TMP_ROOT/floor.snapshot"

# Darwin cp -n may exit 1 when skipping an existing file; the contract is
# preservation of user content, not a specific cp exit status.
set +e
bash "$VAULT/scripts/jobs/update-brain.sh" >"$TMP_ROOT/out.txt" 2>"$TMP_ROOT/err.txt"
set -e

if ! cmp -s "$VAULT/⚙️ Meta/Floors/shared-floor.md" "$TMP_ROOT/floor.snapshot"; then
  printf 'FAIL: update-brain.sh overwrote user-edited floor\n' >&2
  printf '%s\n' 'before:' >&2
  cat "$TMP_ROOT/floor.snapshot" >&2
  printf '%s\n' 'after:' >&2
  cat "$VAULT/⚙️ Meta/Floors/shared-floor.md" >&2
  cat "$TMP_ROOT/out.txt" "$TMP_ROOT/err.txt" >&2 || true
  exit 1
fi

# Behavior, not implementation: a NEW vendor floor added by the starter must be
# copied on the next run, while the user-edited floor stays untouched.
cat > "$STARTER/floors/brand-new-floor.md" <<'MD'
# New vendor floor (must be copied)
MD
bash "$VAULT/scripts/jobs/update-brain.sh" >>"$TMP_ROOT/out.txt" 2>>"$TMP_ROOT/err.txt"
if [ ! -f "$VAULT/⚙️ Meta/Floors/brand-new-floor.md" ]; then
  printf 'FAIL: update-brain.sh did not copy the new vendor floor\n' >&2
  cat "$TMP_ROOT/out.txt" "$TMP_ROOT/err.txt" >&2 || true
  exit 1
fi
if ! cmp -s "$VAULT/⚙️ Meta/Floors/shared-floor.md" "$TMP_ROOT/floor.snapshot"; then
  printf 'FAIL: second update-brain.sh run overwrote the user-edited floor\n' >&2
  exit 1
fi

printf 'PASS: user-edited floor survived update-brain.sh and new floors get copied\n'
