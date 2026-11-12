#!/usr/bin/env bash
# install.sh --update pulls the package checkout (git pull --ff-only) only when
# its origin is github.com/DragonJAR/ai-brain-opencode, on a branch, with no
# local changes; with a vault it then re-wires it like --wire.
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

TMP_ROOT="$(ai_brain_test_root install-update)"
trap 'rm -rf "$TMP_ROOT"' EXIT
REAL_GIT="$(command -v git)"
BIN="$TMP_ROOT/bin"
ai_brain_mock_platform "$BIN"
ai_brain_mock_git "$BIN"
ai_brain_mock_opencode "$BIN"
export MOCK_UNAME=Linux MOCK_GIT_REAL="$REAL_GIT" MOCK_GIT_PULL_RC=0 MOCK_GIT_CALLS="$TMP_ROOT/git-calls.log"
export PATH="$BIN:/usr/bin:/bin" TMPDIR="$TMP_ROOT" HOME="$TMP_ROOT/userhome" BRAIN_STARTER_UPDATE=0
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=Test GIT_COMMITTER_NAME=Test
GIT_AUTHOR_EMAIL="test@$(printf 'example.invalid')"
GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
export GIT_AUTHOR_EMAIL GIT_COMMITTER_EMAIL
unset BRAIN_STARTER_PIN || true
mkdir -p "$HOME"

# A package checkout with the working tree under test (uncommitted changes included).
COPY="$TMP_ROOT/pkg"
mkdir -p "$COPY"
tar -C "$PKG" --exclude=./.git --exclude=./.codegraph --exclude=./odd --exclude=__pycache__ -cf - . 2>/dev/null \
  | tar -C "$COPY" -xf -
"$REAL_GIT" -C "$COPY" init -q -b main 2>/dev/null || { "$REAL_GIT" -C "$COPY" init -q; "$REAL_GIT" -C "$COPY" symbolic-ref HEAD refs/heads/main; }
"$REAL_GIT" -C "$COPY" add -A
"$REAL_GIT" -C "$COPY" commit -q -m package
"$REAL_GIT" -C "$COPY" remote add origin https://github.com/DragonJAR/ai-brain-opencode.git
"$REAL_GIT" -C "$COPY" config branch.main.remote origin
"$REAL_GIT" -C "$COPY" config branch.main.merge refs/heads/main

pulled() { grep -q -- 'pull --ff-only' "$MOCK_GIT_CALLS" 2>/dev/null; }
run_update() {
  : > "$MOCK_GIT_CALLS"
  local rc=0
  bash "$COPY/install.sh" --update "$@" > "$TMP_ROOT/out" 2> "$TMP_ROOT/err" || rc=$?
  return "$rc"
}
set_origin() { "$REAL_GIT" -C "$COPY" remote set-url origin "$1"; }

# 1. The official remote, in every accepted spelling, is pulled with --ff-only.
for url in https://github.com/DragonJAR/ai-brain-opencode.git https://github.com/DragonJAR/ai-brain-opencode \
           https://github.com/DragonJAR/ai-brain-opencode/ git@github.com:DragonJAR/ai-brain-opencode.git \
           git@github.com:DragonJAR/ai-brain-opencode; do
  set_origin "$url"
  run_update || fail "--update refused the official remote $url: $(cat "$TMP_ROOT/err")"
  pulled || fail "--update did not run git pull --ff-only for $url"
done

# 2. Any other remote is refused before pulling, with a Spanish message.
OFFICIAL="github.com/DragonJAR/ai-brain-opencode"
REPO_PATH="${OFFICIAL#github.com/}"
for url in https://github.com/evil/ai-brain-opencode.git "https://$OFFICIAL-fork" \
           "https://github.com.evil.example/$REPO_PATH" "git@gitlab.com:$REPO_PATH.git" \
           "https://evil.example/$OFFICIAL"; do
  set_origin "$url"
  if run_update; then fail "--update accepted the foreign remote $url"; fi
  pulled && fail "--update pulled from the foreign remote $url"
  grep -q 'solo se actualiza desde' "$TMP_ROOT/err" || fail "the refusal of $url was not explained: $(cat "$TMP_ROOT/err")"
done

# 3. insteadOf cannot redirect the official URL elsewhere.
set_origin https://github.com/DragonJAR/ai-brain-opencode.git
"$REAL_GIT" -C "$COPY" config url."https://evil.example/".insteadOf "https://github.com/"
if run_update; then fail "--update followed an insteadOf redirection"; fi
pulled && fail "--update pulled through an insteadOf redirection"
"$REAL_GIT" -C "$COPY" config --unset url."https://evil.example/".insteadOf

# 4. A branch that tracks another remote is refused.
"$REAL_GIT" -C "$COPY" remote add fork https://github.com/evil/ai-brain-opencode.git
"$REAL_GIT" -C "$COPY" config branch.main.remote fork
if run_update; then fail "--update pulled a branch that tracks another remote"; fi
pulled && fail "--update pulled from the branch's foreign upstream"
"$REAL_GIT" -C "$COPY" config branch.main.remote origin

# 5. Local changes and a detached HEAD are refused.
printf '\n# local edit\n' >> "$COPY/VERSION"
if run_update; then fail "--update accepted a checkout with local changes"; fi
pulled && fail "--update pulled over local changes"
grep -q 'cambios locales' "$TMP_ROOT/err" || fail "the dirty-tree refusal was not explained"
"$REAL_GIT" -C "$COPY" checkout -q -- VERSION
"$REAL_GIT" -C "$COPY" checkout -q --detach
if run_update; then fail "--update accepted a detached HEAD"; fi
pulled && fail "--update pulled on a detached HEAD"
"$REAL_GIT" -C "$COPY" checkout -q main

# 6. Not a git checkout: refused.
PLAIN="$TMP_ROOT/plain"
mkdir -p "$PLAIN"
tar -C "$COPY" --exclude=./.git -cf - . 2>/dev/null | tar -C "$PLAIN" -xf -
: > "$MOCK_GIT_CALLS"
if bash "$PLAIN/install.sh" --update > "$TMP_ROOT/out" 2> "$TMP_ROOT/err"; then fail "--update accepted a package that is not a git checkout"; fi
pulled && fail "--update pulled outside a git checkout"

# 7. A failed pull is an error; --update <vault> re-wires the vault after pulling.
MOCK_GIT_PULL_RC=1 run_update && fail "--update exited 0 although git pull failed"
V="$TMP_ROOT/vault"
MOCK_VAULT="$V" bash "$COPY/install.sh" "$V" > "$TMP_ROOT/install.out" 2>&1 || fail "install of the fixture vault failed: $(tail -3 "$TMP_ROOT/install.out")"
run_update "$V" || fail "--update <vault> failed: $(tail -3 "$TMP_ROOT/err")"
pulled || fail "--update <vault> did not pull"
grep -q 'Re-cableado completo' "$TMP_ROOT/out" || fail "--update <vault> did not re-wire the vault"
if bash "$COPY/install.sh" --update --with-mcp > /dev/null 2>&1; then fail "--update accepted --with-mcp"; fi

# 8. The scheduled update job never fetches the package itself.
UPD="$PKG/templates/jobs/update-brain.sh"
grep -Eq 'github\.com|git@' "$UPD" && fail "update-brain.sh references a package remote"
# Nor does it pull the vendor clones: they follow the commits the package pins.
[ "$(grep -c 'git .*pull' "$UPD")" = 0 ] || fail "update-brain.sh pulls a repository on its own"
grep -q 'install.sh --update' "$UPD" || fail "update-brain.sh does not say the package updates with install.sh --update"

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: install.sh --update had %s failures\n' "$failures" >&2
  exit 1
fi
printf 'PASS: install.sh --update pulls only github.com/DragonJAR/ai-brain-opencode and re-wires\n'
