#!/usr/bin/env bash
# daily-maintenance snapshot on a real repository: a snapshot path the user's
# .gitignore ignores is skipped (git add used to abort the job), a tracked path
# that was deleted is committed as a deletion, and commit.gpgsign never blocks it.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

TMP_ROOT="$(ai_brain_test_root daily-snapshot)"
trap 'rm -rf "$TMP_ROOT"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

VAULT="$TMP_ROOT/vault"
JOB="$VAULT/scripts/jobs/daily-maintenance.sh"
mkdir -p "$VAULT/📓 Journals" "$VAULT/⚙️ Meta/Sessions" "$VAULT/⚙️ Meta/Decisions" "$VAULT/⚙️ Meta/logs"
ai_brain_install_vault_libs "$PKG" "$VAULT"
cp "$PKG/templates/jobs/daily-maintenance.sh" "$JOB"
vgit() { git -C "$VAULT" -c core.quotePath=false "$@"; }
vgit init -q
vgit config user.name Test
vgit config user.email "test@$(printf 'example.invalid')"
printf '{"snapshot_paths": ["📓 Journals", "⚙️ Meta/Sessions", "⚙️ Meta/Decisions"]}\n' \
  > "$VAULT/⚙️ Meta/brain-config.json"
printf 'old decision\n' > "$VAULT/⚙️ Meta/Decisions/d1.md"
printf 'seed\n' > "$VAULT/seed.txt"
vgit add seed.txt "⚙️ Meta/Decisions/d1.md"
vgit commit -q -m seed

# The user ignores Sessions; Decisions was deleted; a new journal entry exists.
printf '⚙️ Meta/Sessions/\n' > "$VAULT/.gitignore"
printf 'private session\n' > "$VAULT/⚙️ Meta/Sessions/s1.md"
rm -rf "$VAULT/⚙️ Meta/Decisions"
printf 'entry\n' > "$VAULT/📓 Journals/2026-01-01.md"
# A signing setup that cannot sign must not stop the unattended snapshot.
vgit config commit.gpgsign true
vgit config gpg.program false

bash "$JOB" < /dev/null > "$TMP_ROOT/out.txt" 2>&1 \
  || fail "daily-maintenance failed: $(cat "$TMP_ROOT/out.txt" "$VAULT/⚙️ Meta/logs/daily-maintenance.log" 2>/dev/null)"
[ "$(vgit log --format=%s -1)" = "chore: snapshot diario del vault" ] || fail "no snapshot commit was made"
COMMITTED="$(vgit show --name-status --format= HEAD)"
case "$COMMITTED" in *"A"*"Journals/2026-01-01.md"*) ;; *) fail "the new journal entry was not committed (got: $COMMITTED)" ;; esac
case "$COMMITTED" in *"D"*"Decisions/d1.md"*) ;; *) fail "the deleted snapshot path was not committed as a deletion (got: $COMMITTED)" ;; esac
case "$COMMITTED" in *"Sessions"*) fail "an ignored snapshot path was committed" ;; esac
[ -z "$(vgit status --porcelain -- '⚙️ Meta/Decisions' '📓 Journals')" ] || fail "snapshot paths left uncommitted changes"
grep -Fq 'Sessions' "$VAULT/⚙️ Meta/logs/daily-maintenance.log" || fail "the skipped ignored path was not logged"

printf 'daily snapshot: ok\n'
