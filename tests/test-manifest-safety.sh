#!/usr/bin/env bash
# Manifest safety: one lock around every load→save (install, uninstall and the
# update job through wire.py), record paths that cannot escape the vault on
# Windows, an uninstall that fails loudly when ownership cannot be proven, and a
# .gitignore that stays while the vendor clones it hides are still there.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

TMP_ROOT="$(ai_brain_test_root manifest-safety)"
trap 'rm -rf "$TMP_ROOT"' EXIT
OWN="$PKG/scripts/lib/ownership.py"

# --- Lock ----------------------------------------------------------------------
V="$TMP_ROOT/lock-vault"
M="$V/.opencode/brain-vault-install-manifest.json"
LOCK="$V/.opencode/.manifest.lock"
mkdir -p "$V/.opencode"
printf 'x\n' > "$V/file.txt"
python3 "$OWN" "$M" init 1 || fail "manifest init failed"

# 1. A lock held by a live process blocks every writer, wire.py included.
mkdir "$LOCK"
printf '%s\n' "$$" > "$LOCK/pid"
cp "$M" "$TMP_ROOT/manifest.before"
if BRAIN_MANIFEST_LOCK_TIMEOUT=1 python3 "$OWN" "$M" record-file "a.txt" "$V/file.txt" 2> "$TMP_ROOT/locked.err"; then
  fail "record-file wrote the manifest while another process held the lock"
fi
cmp -s "$M" "$TMP_ROOT/manifest.before" || fail "the manifest changed while the lock was held"
grep -Fq 'en uso' "$TMP_ROOT/locked.err" || fail "a held lock was not explained (got: $(cat "$TMP_ROOT/locked.err"))"
if BRAIN_MANIFEST_LOCK_TIMEOUT=1 python3 "$PKG/scripts/lib/wire.py" "$V" --mode link > /dev/null 2> "$TMP_ROOT/wire-locked.err"; then
  fail "wire.py (update-brain) ignored the manifest lock"
fi
grep -Fq 'en uso' "$TMP_ROOT/wire-locked.err" || fail "wire.py did not report the held lock"
[ -d "$LOCK" ] || fail "a waiting writer removed a live process's lock"

# 2. A lock left by a dead process is stale: it is reclaimed and released.
sleep 0 &
dead_pid=$!
wait "$dead_pid"
printf '%s\n' "$dead_pid" > "$LOCK/pid"
BRAIN_MANIFEST_LOCK_TIMEOUT=5 python3 "$OWN" "$M" record-file "a.txt" "$V/file.txt" \
  || fail "a stale lock from a dead process was not reclaimed"
[ ! -e "$LOCK" ] || fail "the lock was not released after the write"

# 3. Concurrent writers lose no record.
i=1
while [ "$i" -le 12 ]; do
  python3 "$OWN" "$M" record-file "f$i.txt" "$V/file.txt" &
  i=$((i + 1))
done
wait
python3 - "$M" <<'PY' || fail "concurrent writers lost manifest records"
import json, sys
files = json.load(open(sys.argv[1], encoding="utf-8"))["files"]
missing = [f"f{i}.txt" for i in range(1, 13) if f"f{i}.txt" not in files]
assert not missing, missing
PY

# --- Record paths ----------------------------------------------------------------
# 4. Backslashes, drive letters and colons are Windows escapes, not vault paths.
for bad in 'scripts\..\..\x' 'C:/Windows/x' 'C:x' 'a:b'; do
  if python3 "$OWN" "$M" record-file "$bad" "$V/file.txt" 2>/dev/null; then
    fail "record-file accepted the escaping path '$bad'"
  fi
done

# --- Uninstall -------------------------------------------------------------------
BIN="$TMP_ROOT/bin"
ai_brain_mock_platform "$BIN"
ai_brain_mock_crontab "$BIN"
ai_brain_mock_git "$BIN"
ai_brain_mock_opencode "$BIN"
MOCK_UNAME=Linux
MOCK_CRONTAB_STATE="$TMP_ROOT/crontab-state"
MOCK_CRONTAB_CALLS="$TMP_ROOT/crontab-calls.log"
MOCK_CRONTAB_WRITES="$TMP_ROOT/crontab-writes.log"
: > "$MOCK_CRONTAB_STATE"; : > "$MOCK_CRONTAB_CALLS"; : > "$MOCK_CRONTAB_WRITES"
export MOCK_UNAME MOCK_CRONTAB_STATE MOCK_CRONTAB_CALLS MOCK_CRONTAB_WRITES
export PATH="$BIN:/usr/bin:/bin" TMPDIR="$TMP_ROOT"
unset BRAIN_STARTER_PIN || true

# 5. Missing or invalid manifest: non-zero exit, nothing removed, no "Listo".
for kind in missing invalid; do
  U="$TMP_ROOT/vault-$kind"
  mkdir -p "$U/.opencode/plugins/brain-vault" "$U/scripts/jobs"
  printf 'plugin\n' > "$U/.opencode/plugins/brain-vault/index.js"
  [ "$kind" = invalid ] && printf 'not json\n' > "$U/.opencode/brain-vault-install-manifest.json"
  : > "$MOCK_CRONTAB_CALLS"
  rc=0
  bash "$PKG/uninstall.sh" "$U" > "$TMP_ROOT/un-$kind.txt" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "uninstall with a $kind manifest exited 0"
  grep -Fq 'Listo' "$TMP_ROOT/un-$kind.txt" && fail "uninstall with a $kind manifest still said 'Listo'"
  grep -Fq 'no se eliminó nada' "$TMP_ROOT/un-$kind.txt" \
    || fail "uninstall with a $kind manifest did not say that nothing was removed"
  [ -s "$MOCK_CRONTAB_CALLS" ] && fail "uninstall with a $kind manifest touched the schedule"
  [ -f "$U/.opencode/plugins/brain-vault/index.js" ] || fail "uninstall with a $kind manifest removed a file"
done

# 6. Without --purge-clones the clones stay, and so does the .gitignore hiding them.
G="$TMP_ROOT/vault-gitignore"
MOCK_VAULT="$G" bash "$PKG/install.sh" "$G" > "$TMP_ROOT/install-g.txt" 2>&1 || fail "fixture install failed"
bash "$PKG/uninstall.sh" "$G" > "$TMP_ROOT/un-g.txt" 2>&1 || fail "uninstall of a fresh install failed"
[ -d "$G/.opencode/skills/ai-brain-starter" ] || fail "uninstall without --purge-clones removed the starter clone"
[ -f "$G/.gitignore" ] || fail "uninstall removed .gitignore while the vendor clones remain"

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: manifest safety had %s failures\n' "$failures" >&2
  exit 1
fi
printf 'PASS: manifest lock, record paths, honest uninstall without ownership, .gitignore kept with clones\n'
