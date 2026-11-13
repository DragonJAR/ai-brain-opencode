#!/usr/bin/env bash
# Starter commands are written for Claude Code ("the Skill tool", ~/.claude/...).
# wire.py copies them rewritten for OpenCode on every platform (never a symlink),
# records each copy by hash, refreshes unchanged copies when the vendor changes,
# preserves user edits, and the uninstall removes only unchanged copies.
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

TMP_ROOT="$(ai_brain_test_root starter-commands)"
trap 'rm -rf "$TMP_ROOT"' EXIT
BIN="$TMP_ROOT/bin"
ai_brain_mock_platform "$BIN"
ai_brain_mock_git "$BIN"
ai_brain_mock_opencode "$BIN"

# shellcheck disable=SC2088  # literal vendor text, never expanded
CLAUDE_HOME='~/.claude'
CLAUDE_BOOTSTRAP="$CLAUDE_HOME/skills/ai-brain-starter/bootstrap.sh"
UPDATE_JOB='scripts/jobs/update-brain.sh'
COMMAND_SRC="$TMP_ROOT/command.md"
printf -- '---\ndescription: "Journal"\n---\n\nInvoke the `daily-journal` skill via the Skill tool. If it is missing, suggest running `bash %s` to install it.\nThe setup script is %s.\n' \
  "$CLAUDE_BOOTSTRAP" "$CLAUDE_BOOTSTRAP" > "$COMMAND_SRC"
TEMPLATE="$TMP_ROOT/template.md"
printf '# Vault\n\nUse the Skill tool; setup: `bash %s`.\n\n## Vault Map\n[FILL THIS IN]\n' "$CLAUDE_BOOTSTRAP" > "$TEMPLATE"

V="$TMP_ROOT/vault"
CMD="$V/.opencode/commands/brain-journal.md"
MANIFEST="$V/.opencode/brain-vault-install-manifest.json"
if ! MOCK_UNAME=Linux MOCK_GIT_CLEAN=1 MOCK_VAULT="$V" MOCK_GIT_STARTER_COMMAND="$COMMAND_SRC" MOCK_GIT_STARTER_TEMPLATE="$TEMPLATE" \
     PATH="$BIN:/usr/bin:/bin" TMPDIR="$TMP_ROOT" bash "$PKG/install.sh" "$V" > "$TMP_ROOT/install.out" 2>&1; then
  fail "install failed: $(tail -3 "$TMP_ROOT/install.out")"
fi

assert_opencode_text() {
  local file="$1" what="$2"
  grep -q 'Skill tool' "$file" && fail "$what still says 'Skill tool'"
  grep -Fq "$CLAUDE_HOME" "$file" && fail "$what still points at $CLAUDE_HOME"
  grep -Fq '`skill` tool' "$file" || fail "$what does not name OpenCode's \`skill\` tool"
  grep -Fq "bash $UPDATE_JOB" "$file" || fail "$what does not suggest the vault's update job (bash $UPDATE_JOB)"
  grep -Fq 'bootstrap.sh' "$file" && fail "$what still suggests the vendor bootstrap.sh"
  return 0
}

# 1. POSIX install: a rewritten copy, recorded by hash, whose suggested job exists.
[ -f "$CMD" ] && [ ! -L "$CMD" ] || fail "the starter command is not a regular copy on POSIX"
assert_opencode_text "$CMD" "the wired starter command"
grep -Fq "The setup script is $UPDATE_JOB." "$CMD" || fail "a bare bootstrap.sh path was not rewritten to $UPDATE_JOB"
[ -f "$V/$UPDATE_JOB" ] || fail "the suggested update job does not exist in the vault"
assert_opencode_text "$V/AGENTS.md" "AGENTS.md"
record() {
  python3 - "$MANIFEST" "$CMD" <<'PY'
import hashlib, json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
rel = ".opencode/commands/brain-journal.md"
digest = hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest()
if rel in data["symlinks"]:
    print("symlink")
elif data["files"].get(rel, {}).get("sha256") == digest and rel in data["wired"]:
    print("copy")
else:
    print("missing")
PY
}
[ "$(record)" = copy ] || fail "the command copy is not recorded by hash in the manifest (got $(record))"

# 2. Windows wiring (copy mode) produces the same bytes.
cp "$CMD" "$TMP_ROOT/posix.md"
python3 "$PKG/scripts/lib/wire.py" "$V" --mode copy --only commands > /dev/null 2>&1 || fail "wire.py --mode copy failed"
cmp -s "$CMD" "$TMP_ROOT/posix.md" || fail "copy mode wrote different bytes than link mode"

# 2b. A copy written by an older rewrite (bootstrap.sh path) is refreshed on re-wire.
python3 - "$PKG/scripts/lib" "$MANIFEST" "$CMD" <<'PY'
import hashlib, sys
sys.path.insert(0, sys.argv[1])
import ownership
path = sys.argv[3]
old = open(path, encoding="utf-8").read().replace(
    "scripts/jobs/update-brain.sh", ".opencode/skills/ai-brain-starter/bootstrap.sh")
open(path, "w", encoding="utf-8").write(old)
data = ownership.load(sys.argv[2])
data["files"][".opencode/commands/brain-journal.md"]["sha256"] = hashlib.sha256(old.encode("utf-8")).hexdigest()
ownership.save(sys.argv[2], data)
PY
python3 "$PKG/scripts/lib/wire.py" "$V" --mode link > /dev/null 2>&1 || fail "re-wire over an older copy failed"
assert_opencode_text "$CMD" "a copy re-wired from an older rewrite"
[ "$(record)" = copy ] || fail "the refreshed older copy is not recorded by its new hash"

# 3. A vendor change refreshes an unchanged copy.
STARTER_CMD="$V/.opencode/skills/ai-brain-starter/commands/brain-journal.md"
printf '\nNew vendor line for the Skill tool.\n' >> "$STARTER_CMD"
python3 "$PKG/scripts/lib/wire.py" "$V" --mode link > /dev/null 2>&1 || fail "re-wire after a vendor change failed"
grep -Fq 'New vendor line for the `skill` tool.' "$CMD" || fail "an unchanged copy was not refreshed when the vendor changed"
[ "$(record)" = copy ] || fail "the refreshed copy is not recorded by its new hash"

if ai_brain_need_symlinks "migración de un comando enlazado por una instalación POSIX anterior"; then
  # 4. A previous POSIX install recorded the command as a symlink: it becomes a copy.
  rm -f "$CMD"
  ln -s ../skills/ai-brain-starter/commands/brain-journal.md "$CMD"
  python3 - "$PKG/scripts/lib" "$MANIFEST" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import ownership
data = ownership.load(sys.argv[2])
rel = ".opencode/commands/brain-journal.md"
data["files"].pop(rel, None)
data["wired"] = [item for item in data["wired"] if item != rel]
data["symlinks"][rel] = "../skills/ai-brain-starter/commands/brain-journal.md"
ownership.save(sys.argv[2], data)
PY
  python3 "$PKG/scripts/lib/wire.py" "$V" --mode link > "$TMP_ROOT/migrate.out" 2>&1 || fail "re-wire over a legacy symlink failed"
  [ -f "$CMD" ] && [ ! -L "$CMD" ] || fail "a legacy owned symlink was not replaced by a rewritten copy"
  [ "$(record)" = copy ] || fail "the legacy symlink record was not replaced by a copy record (got $(record))"
fi

# 5. verify.sh counts the copies.
(cd "$V" && PATH="$BIN:/usr/bin:/bin" bash scripts/verify.sh > "$TMP_ROOT/verify.out" 2>&1) || true
grep -q '✓ comandos copiados (1)' "$TMP_ROOT/verify.out" \
  || fail "verify.sh does not count the command copies: $(grep 'comandos' "$TMP_ROOT/verify.out" || echo none)"

# 6. User edits survive a vendor change; uninstall removes unchanged copies only.
printf '\nmy note\n' >> "$CMD"
cp "$CMD" "$TMP_ROOT/edited.md"
printf '\nAnother vendor line.\n' >> "$STARTER_CMD"
python3 "$PKG/scripts/lib/wire.py" "$V" --mode link > "$TMP_ROOT/edited.out" 2>&1 || true
cmp -s "$CMD" "$TMP_ROOT/edited.md" || fail "a user-edited command copy was overwritten"
python3 "$PKG/scripts/lib/ownership.py" "$MANIFEST" uninstall "$V" 0 0 > "$TMP_ROOT/uninstall.out" 2>&1 || true
[ -f "$CMD" ] || fail "uninstall removed a user-edited command copy"

W="$TMP_ROOT/vault-clean"
MOCK_UNAME=Linux MOCK_GIT_CLEAN=1 MOCK_VAULT="$W" MOCK_GIT_STARTER_COMMAND="$COMMAND_SRC" \
  PATH="$BIN:/usr/bin:/bin" TMPDIR="$TMP_ROOT" bash "$PKG/install.sh" "$W" > /dev/null 2>&1 || fail "second install failed"
python3 "$PKG/scripts/lib/ownership.py" "$W/.opencode/brain-vault-install-manifest.json" uninstall "$W" 0 0 > /dev/null 2>&1 \
  || fail "uninstall of a clean vault failed"
[ ! -e "$W/.opencode/commands/brain-journal.md" ] || fail "uninstall left an unchanged command copy"

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: starter commands for OpenCode had %s failures\n' "$failures" >&2
  exit 1
fi
printf 'PASS: starter commands are rewritten copies for OpenCode, owned by hash on every platform\n'
