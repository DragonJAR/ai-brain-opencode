#!/usr/bin/env bash
# One regression per defect found in the project audit. Each block states the
# behavior that was broken, so a failure names the bug that came back.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

TMP_ROOT="$(ai_brain_test_root audit-regressions)"
trap 'rm -rf "$TMP_ROOT"' EXIT
REAL_GIT="$(command -v git)"
REAL_PATH="$PATH"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
real_git() { "$REAL_GIT" -c user.name=Test -c user.email=test@example.invalid "$@"; }

# --- Fixture: one mocked Linux install shared by the blocks below ----------------
BIN="$TMP_ROOT/bin"
VAULT="$TMP_ROOT/vault"
mkdir -p "$BIN" "$VAULT"
MOCK_UNAME=Linux
MOCK_VAULT="$VAULT"
MOCK_GIT_CALLS="$TMP_ROOT/git-calls.log"
MOCK_CRONTAB_STATE="$TMP_ROOT/crontab-state"
MOCK_CRONTAB_CALLS="$TMP_ROOT/crontab-calls.log"
MOCK_CRONTAB_WRITES="$TMP_ROOT/crontab-writes.log"
: > "$MOCK_GIT_CALLS"; : > "$MOCK_CRONTAB_STATE"; : > "$MOCK_CRONTAB_CALLS"; : > "$MOCK_CRONTAB_WRITES"
ai_brain_mock_platform "$BIN"
ai_brain_mock_crontab "$BIN"
ai_brain_mock_git "$BIN"
ai_brain_mock_opencode "$BIN"
ai_brain_mock_windows "$BIN"
export MOCK_UNAME MOCK_VAULT MOCK_GIT_CALLS MOCK_CRONTAB_STATE MOCK_CRONTAB_CALLS MOCK_CRONTAB_WRITES
export PATH="$BIN:$PATH"
export TMPDIR="$TMP_ROOT"
export BRAIN_STARTER_UPDATE=0
unset BRAIN_STARTER_PIN || true

# 1. --dry-run validates and prints the plan without creating the vault.
DRY_VAULT="$TMP_ROOT/dry-vault"
if ! bash "$PKG/install.sh" "$DRY_VAULT" --dry-run > "$TMP_ROOT/dry.txt" 2>&1; then
  fail "install --dry-run exited non-zero"
fi
[ ! -e "$DRY_VAULT" ] || fail "install --dry-run created the vault"
grep -Fq 'no se modificó nada' "$TMP_ROOT/dry.txt" || fail "install --dry-run did not state that nothing changed"

if ! bash "$PKG/install.sh" "$VAULT" > "$TMP_ROOT/install-1.txt" 2>&1; then
  fail "fixture install failed"
  cat "$TMP_ROOT/install-1.txt" >&2
  exit 1
fi

# 2. A second install is quiet: it used to warn that CLAUDE.md's "parent
#    directory" was a symlink, because a root-level file was its own parent.
bash "$PKG/install.sh" "$VAULT" > "$TMP_ROOT/install-2.txt" 2>&1 || fail "second install failed"
if grep -F 'preservad' "$TMP_ROOT/install-2.txt" | grep -Fv 'AGENTS.md existe' | grep -q .; then
  fail "re-install reported a preserved path on an untouched vault"
  grep -F 'preservad' "$TMP_ROOT/install-2.txt" >&2
fi
! grep -Fq 'directorio padre symlink' "$TMP_ROOT/install-2.txt" || fail "re-install printed the false 'directorio padre symlink' warning"
[ -L "$VAULT/CLAUDE.md" ] || fail "CLAUDE.md is not the managed symlink"

# 3. The commands the product and the vendor skills tell the user to type exist
#    in the installed vault: /journal and /setup-brain were named but never wired.
[ -f "$VAULT/.opencode/commands/journal.md" ] && [ -f "$VAULT/.opencode/commands/setup-brain.md" ] \
  || fail "the package did not install /journal and /setup-brain"
grep -Fq '/setup-brain' "$PKG/install.sh" || fail "the installer does not point the user at /setup-brain"

# 4. Every scheduled job in the table has its script, on every backend. The
#    macOS agent used to point at update-brain-weekly.sh, which never existed.
bash "$PKG/scripts/schedule.sh" "$VAULT" --dry-run > "$TMP_ROOT/cron.txt"
MOCK_UNAME=MINGW64_NT-10.0 bash "$PKG/scripts/schedule.sh" "$VAULT" --dry-run > "$TMP_ROOT/schtasks.txt"
for job in "$PKG"/templates/jobs/*.sh; do
  name="$(basename "$job" .sh)"
  grep -Fq "/$name.sh'" "$TMP_ROOT/cron.txt" || fail "cron does not schedule $name"
  grep -Eq "ai-brain-run\.cmd\" $name\$" "$TMP_ROOT/schtasks.txt" || fail "schtasks does not schedule $name"
done
[ "$(wc -l < "$TMP_ROOT/cron.txt" | tr -d ' ')" = "$(find "$PKG/templates/jobs" -name '*.sh' | wc -l | tr -d ' ')" ] \
  || fail "cron schedules a job that has no script in templates/jobs"
if [ "$(command uname -s)" = "Darwin" ] && command -v plutil >/dev/null; then
  MOCK_UNAME=Darwin bash "$PKG/scripts/schedule.sh" "$VAULT" --dry-run > "$TMP_ROOT/launchd.txt"
  for job in "$PKG"/templates/jobs/*.sh; do
    grep -Eq "\.$(basename "$job" .sh)\$" "$TMP_ROOT/launchd.txt" || fail "launchd does not schedule $(basename "$job" .sh)"
  done
fi

# 5. Scheduled jobs carry a PATH: cron and launchd start with a minimal one
#    where opencode is not found.
grep -Eq "^[0-9]+ [0-9]+ \* \* [^ ]+ PATH='[^']*${BIN}[^']*' /bin/bash " "$TMP_ROOT/cron.txt" \
  || fail "cron lines do not carry the PATH of the scheduling shell"

# 6. schtasks gets its /Flags untouched (Git Bash path conversion disabled) and
#    never overwrites a same-named task that belongs to another vault.
MOCK_SCHTASKS_CALLS="$TMP_ROOT/schtasks-calls.log"
MOCK_SCHTASKS_ENV="$TMP_ROOT/schtasks-env.log"
MOCK_SCHTASKS_STATE="$TMP_ROOT/schtasks-state"
WIN_VAULT="$TMP_ROOT/vault-win/shared-name"
mkdir -p "$WIN_VAULT/scripts/jobs" "$WIN_VAULT/.opencode"
printf '"\\ai-brain shared-name insights-weekly","2026-01-01 21:00:00"\n' > "$MOCK_SCHTASKS_STATE"
: > "$MOCK_SCHTASKS_CALLS"; : > "$MOCK_SCHTASKS_ENV"
export MOCK_SCHTASKS_CALLS MOCK_SCHTASKS_ENV MOCK_SCHTASKS_STATE
if MOCK_UNAME=MINGW64_NT-10.0 bash "$PKG/scripts/schedule.sh" "$WIN_VAULT" > "$TMP_ROOT/win-apply.txt" 2>&1; then
  fail "schtasks apply succeeded although a foreign task holds one of the names"
fi
if grep -Fq '/Create /F /TN ai-brain shared-name insights-weekly' "$MOCK_SCHTASKS_CALLS"; then
  fail "schtasks /Create /F overwrote a task owned by another vault"
fi
grep -Fq '/Create /F /TN ai-brain shared-name update-brain' "$MOCK_SCHTASKS_CALLS" \
  || fail "the non-colliding tasks were not created"
if grep -qv '^1$' "$MOCK_SCHTASKS_ENV"; then
  fail "schtasks was called without MSYS_NO_PATHCONV=1"
fi
python3 - "$WIN_VAULT/.opencode/brain-vault-install-manifest.json" <<'PY' || fail "manifest claims the foreign schtasks task"
import json, sys
names = json.load(open(sys.argv[1], encoding="utf-8"))["cron_lines"]
assert "ai-brain shared-name insights-weekly" not in names and len(names) == 3, names
PY
grep -Fq 'where bash' "$WIN_VAULT/scripts/jobs/ai-brain-run.cmd" || fail "runner lost the PATH fallback"
if [ "$(grep -n 'BRAIN_BASH%" goto' "$WIN_VAULT/scripts/jobs/ai-brain-run.cmd" | cut -d: -f1)" -gt \
     "$(grep -n 'where bash' "$WIN_VAULT/scripts/jobs/ai-brain-run.cmd" | cut -d: -f1)" ]; then
  fail "runner tries 'where bash' (often the WSL launcher) before Git's own bash"
fi
unset MOCK_SCHTASKS_STATE

# 7. A starter update is wired without the package: new entries appear, entries
#    the starter dropped are pruned, and package commands are left alone.
STARTER="$VAULT/.opencode/skills/ai-brain-starter"
mkdir -p "$STARTER/skills/added-skill"
printf '# added\n' > "$STARTER/skills/added-skill/SKILL.md"
rm -f "$STARTER/commands/brain-journal.md"
# A starter command the package replaces (vault_layout.REPLACED_COMMANDS) is never
# copied over the package version, not even by the vault-side re-wire.
printf -- '---\ndescription: "vendor"\n---\nVENDOR-DIAGNOSE for Claude Code\n' > "$STARTER/commands/diagnose.md"
python3 "$VAULT/scripts/lib/wire.py" "$VAULT" --mode link > "$TMP_ROOT/wire.txt" 2>&1 || fail "vault-side wire.py failed"
[ -L "$VAULT/.opencode/skills/added-skill" ] || fail "wire.py did not link the skill the starter added"
if [ -e "$VAULT/.opencode/commands/brain-journal.md" ] || [ -L "$VAULT/.opencode/commands/brain-journal.md" ]; then
  fail "wire.py left a dangling link to a command the starter dropped"
fi
[ -f "$VAULT/.opencode/commands/audit.md" ] || fail "wire.py removed a package command"
if grep -q 'VENDOR-DIAGNOSE' "$VAULT/.opencode/commands/diagnose.md" 2>/dev/null; then
  fail "wire.py copied the vendor /diagnose over the package one"
fi
grep -q 'scripts/verify.sh' "$VAULT/.opencode/commands/diagnose.md" || fail "the package /diagnose is not installed"

# 8. The vault verifier sees a broken symlink on every platform (`find -xtype`
#    is GNU-only and failed silently on macOS).
if ai_brain_need_symlinks "verify.sh detecta un symlink roto" \
   && ln -s "missing-target" "$VAULT/.opencode/commands/broken.md" 2>/dev/null; then
  bash "$VAULT/scripts/verify.sh" > "$TMP_ROOT/verify-broken.txt" 2>&1 || true
  grep -Fq '✗ symlinks rotos: 1' "$TMP_ROOT/verify-broken.txt" || fail "verify did not report the broken symlink"
  rm -f "$VAULT/.opencode/commands/broken.md"
fi

# 9. Verify reports drift: a deleted managed file fails, a user-edited one is only noted.
printf 'edited by the user\n' >> "$VAULT/scripts/jobs/update-brain.sh"
rm -f "$VAULT/scripts/jobs/insights-weekly.sh"
bash "$VAULT/scripts/verify.sh" > "$TMP_ROOT/verify-drift.txt" 2>&1 || true
grep -Fq 'falta: archivo scripts/jobs/insights-weekly.sh' "$TMP_ROOT/verify-drift.txt" \
  || fail "verify did not flag the missing managed file"
grep -Fq 'modificado por ti: archivo scripts/jobs/update-brain.sh' "$TMP_ROOT/verify-drift.txt" \
  || fail "verify did not note the user-edited managed file"

# 10. uninstall --dry-run lists and removes nothing.
find "$VAULT" -not -path '*/.git/*' | sort > "$TMP_ROOT/before-dry-uninstall.txt"
bash "$PKG/uninstall.sh" "$VAULT" --dry-run > "$TMP_ROOT/uninstall-dry.txt" 2>&1 || fail "uninstall --dry-run failed"
find "$VAULT" -not -path '*/.git/*' | sort > "$TMP_ROOT/after-dry-uninstall.txt"
cmp -s "$TMP_ROOT/before-dry-uninstall.txt" "$TMP_ROOT/after-dry-uninstall.txt" || fail "uninstall --dry-run changed the vault"
grep -Fq '~ archivo .opencode/plugins/brain-vault/index.js' "$TMP_ROOT/uninstall-dry.txt" \
  || fail "uninstall --dry-run did not list what it would remove"

# --- Blocks with a real git repository --------------------------------------------
export PATH="$REAL_PATH"
GIT_VAULT="$TMP_ROOT/git-vault"
mkdir -p "$GIT_VAULT/📓 Journals" "$GIT_VAULT/📝 Notes" "$GIT_VAULT/scripts/jobs"
ai_brain_install_vault_libs "$PKG" "$GIT_VAULT"
cp "$PKG"/templates/jobs/*.sh "$GIT_VAULT/scripts/jobs/"
real_git -C "$GIT_VAULT" init -q
real_git -C "$GIT_VAULT" config user.name Test
real_git -C "$GIT_VAULT" config user.email test@example.invalid
printf 'seed\n' > "$GIT_VAULT/seed.txt"
real_git -C "$GIT_VAULT" add seed.txt
real_git -C "$GIT_VAULT" commit -q -m seed

# 11. The daily snapshot commits only its own paths: something the user staged
#     elsewhere used to ride along in "snapshot diario".
printf 'draft the user staged on their own\n' > "$GIT_VAULT/📝 Notes/draft.md"
real_git -C "$GIT_VAULT" add "📝 Notes/draft.md"
printf 'entry\n' > "$GIT_VAULT/📓 Journals/2026-01-01.md"
bash "$GIT_VAULT/scripts/jobs/daily-maintenance.sh" > "$TMP_ROOT/maint.txt" 2>&1 || fail "daily-maintenance failed"
COMMITTED="$(real_git -C "$GIT_VAULT" -c core.quotePath=false show --name-only --format= HEAD)"
case "$COMMITTED" in *"Journals/2026-01-01.md"*) ;; *) fail "daily snapshot did not commit the journal entry" ;; esac
case "$COMMITTED" in *"draft.md"*) fail "daily snapshot committed a file the user had staged on their own" ;; esac
real_git -C "$GIT_VAULT" -c core.quotePath=false diff --cached --name-only | grep -Fq 'draft.md' \
  || fail "the user's staged file did not stay staged"

# 12. A value of the wrong shape in the config never breaks a job.
mkdir -p "$GIT_VAULT/⚙️ Meta"
printf '{"snapshot_paths": "not-a-list", "journal": {"time": "99:99"}}\n' > "$GIT_VAULT/⚙️ Meta/brain-config.json"
bash "$GIT_VAULT/scripts/jobs/daily-maintenance.sh" > "$TMP_ROOT/maint-bad.txt" 2>&1 || fail "daily-maintenance failed on a malformed config"

# 13. update-brain exits 0 on every run (it failed from the second one on, when
#     `cp -n` skipped the floors that already existed), and third-party content
#     only moves to the commit the installed package pins: the job never pulls.
VENDOR_ORIGIN="$TMP_ROOT/vendor-origin"
mkdir -p "$VENDOR_ORIGIN/floors" "$VENDOR_ORIGIN/scripts"
printf '# floor\n' > "$VENDOR_ORIGIN/floors/one.md"
printf 'pass\n' > "$VENDOR_ORIGIN/scripts/generate_floor_stubs.py"
real_git -C "$VENDOR_ORIGIN" init -q
real_git -C "$VENDOR_ORIGIN" config uploadpack.allowAnySHA1InWant true
real_git -C "$VENDOR_ORIGIN" add .
real_git -C "$VENDOR_ORIGIN" commit -q -m pinned
PINNED="$(real_git -C "$VENDOR_ORIGIN" rev-parse HEAD)"
printf '# newer floor\n' > "$VENDOR_ORIGIN/floors/two.md"
real_git -C "$VENDOR_ORIGIN" add .
real_git -C "$VENDOR_ORIGIN" commit -q -m newer
UPD_STARTER="$GIT_VAULT/.opencode/skills/ai-brain-starter"
real_git clone -q "$VENDOR_ORIGIN" "$UPD_STARTER"
# The vault-side lock is the installed package's: point it at the fixture.
python3 - "$GIT_VAULT/scripts/lib/vault_layout.py" "$VENDOR_ORIGIN" "$PINNED" <<'PY'
import pathlib, re, sys
path, origin, commit = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text(encoding="utf-8")
text, count = re.subn(r'\(".opencode/skills/ai-brain-starter", "[^"]+",\s*"[0-9a-f]+"\)',
                      '(".opencode/skills/ai-brain-starter", %r, %r)' % (origin, commit), text)
assert count == 1, "could not point the fixture lock at the local origin"
path.write_text(text, encoding="utf-8")
PY
for run in 1 2; do
  bash "$GIT_VAULT/scripts/jobs/update-brain.sh" > "$TMP_ROOT/update-$run.txt" 2>&1 || fail "update-brain run $run exited non-zero"
done
[ "$(real_git -C "$UPD_STARTER" rev-parse HEAD)" = "$PINNED" ] \
  || fail "update-brain left the vendor clone off the commit the package pins"
[ ! -e "$UPD_STARTER/floors/two.md" ] || fail "update-brain pulled vendor content newer than the pinned commit"
if grep -Eq 'git .*(pull|merge)' "$PKG/templates/jobs/update-brain.sh"; then
  fail "update-brain.sh pulls third-party repositories on its own"
fi

# 14. --purge-clones still works after the clone moved on: a clone is owned by
#     its origin, not by a fingerprint that the first pull invalidates.
ORIGIN="$TMP_ROOT/origin"
mkdir -p "$ORIGIN"
real_git -C "$ORIGIN" init -q
printf 'v1\n' > "$ORIGIN/README.md"
real_git -C "$ORIGIN" add README.md
real_git -C "$ORIGIN" commit -q -m v1
purge_fixture() {
  local vault="$1"
  mkdir -p "$vault/.opencode/skills"
  real_git clone -q "$ORIGIN" "$vault/.opencode/skills/humanizer"
  python3 "$PKG/scripts/lib/ownership.py" "$vault/.opencode/brain-vault-install-manifest.json" init
  python3 "$PKG/scripts/lib/ownership.py" "$vault/.opencode/brain-vault-install-manifest.json" \
    record-clone ".opencode/skills/humanizer" "$ORIGIN"
}
purge_fixture "$TMP_ROOT/purge-clean"
printf 'v2\n' > "$ORIGIN/README.md"
real_git -C "$ORIGIN" commit -q -am v2
real_git -C "$TMP_ROOT/purge-clean/.opencode/skills/humanizer" pull -q --ff-only
bash "$PKG/uninstall.sh" "$TMP_ROOT/purge-clean" --purge-clones > "$TMP_ROOT/purge-clean.txt" 2>&1 \
  || fail "uninstall --purge-clones failed"
[ ! -e "$TMP_ROOT/purge-clean/.opencode/skills/humanizer" ] || fail "--purge-clones kept a pristine clone after a pull"
purge_fixture "$TMP_ROOT/purge-dirty"
printf 'local work\n' > "$TMP_ROOT/purge-dirty/.opencode/skills/humanizer/notes.md"
bash "$PKG/uninstall.sh" "$TMP_ROOT/purge-dirty" --purge-clones > "$TMP_ROOT/purge-dirty.txt" 2>&1 || true
[ -f "$TMP_ROOT/purge-dirty/.opencode/skills/humanizer/notes.md" ] || fail "--purge-clones deleted a clone with local changes"

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: audit regressions had %s failed assertions\n' "$failures" >&2
  exit 1
fi
printf 'PASS: audit regressions (jobs, scheduler backends, wiring, verify drift, dry-runs, clone ownership)\n'
