#!/usr/bin/env bash
# The base commit holds only what the package owns. Installing over an existing
# vault must not commit the user's opencode.json, their own agents, the ownership
# manifest or a vendor clone as a gitlink; an existing .gitignore is completed,
# never replaced; and paths the user's .gitignore ignores are skipped, not fatal.
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

TMP_ROOT="$(ai_brain_test_root install-base-commit)"
trap 'rm -rf "$TMP_ROOT"' EXIT
REAL_GIT="$(command -v git)"
BIN="$TMP_ROOT/bin"
ai_brain_mock_platform "$BIN"
ai_brain_mock_git "$BIN"
ai_brain_mock_opencode "$BIN"

MOCK_UNAME=Linux
MOCK_GIT_REAL="$REAL_GIT"
export MOCK_UNAME MOCK_GIT_REAL
export PATH="$BIN:/usr/bin:/bin"
export TMPDIR="$TMP_ROOT" HOME="$TMP_ROOT/userhome" XDG_CONFIG_HOME="$TMP_ROOT/userhome/.config"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid
unset BRAIN_STARTER_PIN || true
mkdir -p "$HOME"

# A real nested git repository at the starter path: `git add .opencode` would
# record it as a 160000 gitlink when the user's .gitignore lacks the clone lines.
make_starter_clone() {
  local starter="$1/.opencode/skills/ai-brain-starter"
  mkdir -p "$starter/skills/journal" "$starter/commands" "$starter/scripts" "$starter/floors" \
    "$starter/templates/generated"
  printf '# Stub starter skill\n' > "$starter/SKILL.md"
  printf '# Stub journal skill\n' > "$starter/skills/journal/SKILL.md"
  printf '# Stub command\n' > "$starter/commands/brain-journal.md"
  printf 'print("stub")\n' > "$starter/scripts/generate_floor_stubs.py"
  printf '# Stub floor\n' > "$starter/floors/stub-floor.md"
  printf '# Stub vault instructions\n\n## Vault Map\n[FILL THIS IN]\n' \
    > "$starter/templates/generated/claude-md-template.md"
  "$REAL_GIT" -C "$starter" init -q
  "$REAL_GIT" -C "$starter" add -A
  "$REAL_GIT" -C "$starter" commit -q -m vendor
}

# 1. Existing vault with its own config, agent, .gitignore and a nested clone.
VAULT="$TMP_ROOT/vault"
mkdir -p "$VAULT/.opencode/agents"
"$REAL_GIT" -C "$VAULT" init -q
printf '{"provider":{"x":{"apiKey":"sk-user-secret"}}}\n' > "$VAULT/opencode.json"
printf '# my agent\n' > "$VAULT/.opencode/agents/x.md"
printf 'private/\r\n*.tmp\n' > "$VAULT/.gitignore"
make_starter_clone "$VAULT"

if ! bash "$PKG/install.sh" "$VAULT" --with-mcp > "$TMP_ROOT/install-1.txt" 2>&1; then
  fail "install over an existing vault failed"
  cat "$TMP_ROOT/install-1.txt" >&2
fi
if "$REAL_GIT" -C "$VAULT" rev-parse -q --verify HEAD >/dev/null; then
  TREE="$("$REAL_GIT" -C "$VAULT" -c core.quotePath=false ls-tree -r HEAD)"
  NAMES="$("$REAL_GIT" -C "$VAULT" -c core.quotePath=false ls-tree -r --name-only HEAD)"
  printf '%s\n' "$NAMES" | grep -qx 'opencode.json' && fail "base commit contains the user's opencode.json"
  printf '%s\n' "$NAMES" | grep -qx '.opencode/agents/x.md' && fail "base commit contains the user's own agent"
  printf '%s\n' "$NAMES" | grep -qx '.opencode/brain-vault-install-manifest.json' \
    && fail "base commit contains the ownership manifest"
  printf '%s\n' "$TREE" | grep -q '^160000 ' && fail "base commit contains a gitlink: $(printf '%s\n' "$TREE" | grep '^160000 ')"
  printf '%s\n' "$NAMES" | grep -qx '.opencode/plugins/brain-vault/index.js' || fail "base commit lacks the plugin"
  printf '%s\n' "$NAMES" | grep -qx 'scripts/verify.sh' || fail "base commit lacks scripts/verify.sh"
  printf '%s\n' "$NAMES" | grep -qx '📓 Journals/.gitkeep' || fail "base commit lacks the empty structure"
else
  fail "install over an existing vault made no base commit"
fi
grep -q '^private/' "$VAULT/.gitignore" || fail "the user's .gitignore lines were lost"
grep -qx '\*.tmp' "$VAULT/.gitignore" || fail "the user's .gitignore lines were lost"
grep -qx '.opencode/skills/ai-brain-starter/' "$VAULT/.gitignore" \
  || fail "the existing .gitignore was not completed with the vendor clone lines"
grep -q 'sk-user-secret' "$VAULT/opencode.json" || fail "the user's opencode.json lost its content"

# 2. Re-running adds no duplicate ignore lines.
bash "$PKG/install.sh" "$VAULT" > "$TMP_ROOT/install-2.txt" 2>&1 || fail "second install failed"
[ "$(grep -cx '.opencode/skills/humanizer/' "$VAULT/.gitignore")" = 1 ] || fail "re-install duplicated .gitignore lines"

# 3. A .gitignore that ignores `scripts` must not abort the install.
IGN="$TMP_ROOT/vault-ignored"
mkdir -p "$IGN"
"$REAL_GIT" -C "$IGN" init -q
printf 'scripts\n' > "$IGN/.gitignore"
if ! bash "$PKG/install.sh" "$IGN" > "$TMP_ROOT/install-ign.txt" 2>&1; then
  fail "install aborted when the user's .gitignore ignores scripts"
  tail -5 "$TMP_ROOT/install-ign.txt" >&2
fi
"$REAL_GIT" -C "$IGN" ls-tree -r --name-only HEAD 2>/dev/null | grep -q '^scripts/' \
  && fail "base commit force-added an ignored path"

# 4. A fresh vault commits the opencode.json that --with-mcp created.
FRESH="$TMP_ROOT/vault-fresh"
bash "$PKG/install.sh" "$FRESH" --with-mcp > "$TMP_ROOT/install-fresh.txt" 2>&1 || fail "fresh install failed"
"$REAL_GIT" -C "$FRESH" ls-tree -r --name-only HEAD 2>/dev/null | grep -qx 'opencode.json' \
  || fail "base commit lacks the opencode.json the installer created"

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: install base commit had %s failures\n' "$failures" >&2
  exit 1
fi
printf 'PASS: the base commit holds only package-owned paths and respects the user .gitignore\n'
