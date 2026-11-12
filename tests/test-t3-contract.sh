#!/usr/bin/env bash
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASH_BIN="$(command -v bash)"
# shellcheck source=lib/mocks.sh
. "$PKG/tests/lib/mocks.sh"
TMP_ROOT="$(ai_brain_test_root t3-contract)"
trap 'rm -rf "$TMP_ROOT"' EXIT

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

# Bilingual README contract (stricter than the old Spanish-only README.md check):
# - README.md (English): strict JSON under "## Configuration" + EN scoped-setup phrase
# - README.es.md (Spanish): strict JSON under "## Configuración" + ES scoped-setup phrase
if [ ! -f "$PKG/README.es.md" ]; then
  fail "README.es.md is missing (bilingual contract requires both README.md and README.es.md)"
fi
if python3 - "$PKG/README.md" >/dev/null 2>&1 <<'PY'
import json, pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r"^## Configuration\b.*?```json\s*\n(.*?)\n```", text, re.S | re.M)
if not match:
    raise SystemExit("README.md ## Configuration JSON block not found")
json.loads(match.group(1))
PY
then
  :
else
  fail "README.md configuration example does not parse as strict JSON"
fi
if python3 - "$PKG/README.es.md" >/dev/null 2>&1 <<'PY'
import json, pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r"^## Configuración\b.*?```json\s*\n(.*?)\n```", text, re.S | re.M)
if not match:
    raise SystemExit("README.es.md ## Configuración JSON block not found")
json.loads(match.group(1))
PY
then
  :
else
  fail "README.es.md configuration example does not parse as strict JSON"
fi
if ! grep -Fq 'Does not automatically detect vaults or modify OpenCode global configuration.' "$PKG/README.md"; then
  fail "README.md does not state that setup is explicit and project-scoped"
fi
if ! grep -Fq 'No detecta vaults automáticamente ni modifica la configuración global de OpenCode.' "$PKG/README.es.md"; then
  fail "README.es.md does not state that setup is explicit and project-scoped"
fi

# Both READMEs must document the starter's slash commands (the 17 wired into .opencode/commands).
EN_GROUPS=("Journal & meetings" "Vault & knowledge" "Patterns & ideas" "Content")
ES_GROUPS=("Diario y reuniones" "Vault y conocimiento" "Patrones e ideas" "Contenido")
check_readme_commands() {
  local readme="$1"; shift
  local label
  for label in "$@"; do
    if ! grep -Fq "**$label**" "$readme"; then
      fail "$readme is missing the slash-command group '$label'"
    fi
  done
  local command
  for command in daily-journal insights meeting-todos cierre diagnose setup-vault-types \
                 second-brain-mapping graphify optimize-brain patterns deconstruct evolve \
                 instinct-export instinct-import humanizer repurpose-talk nano-banana; do
    if ! grep -Fq "/$command" "$readme"; then
      fail "$readme does not document /$command"
    fi
  done
  local rows
  rows=$(grep -c '^| `/' "$readme" || true)
  if [ "$rows" -lt 17 ]; then
    fail "$readme documents only $rows slash commands (expected the 17 wired by the installer)"
  fi
}
check_readme_commands "$PKG/README.md" "${EN_GROUPS[@]}"
check_readme_commands "$PKG/README.es.md" "${ES_GROUPS[@]}"
if ! grep -Fq 'no realiza detección global' "$PKG/docs/COMPAT.md"; then
  fail "compatibility guide does not rule out global vault detection"
fi
if ! grep -Fq 'no arrancan OpenCode V2 ni comprueban que un runtime cargue los hooks' "$PKG/docs/COMPAT.md"; then
  fail "compatibility guide does not distinguish deterministic tests from live runtime checks"
fi

# Package-mode verify must invoke the adjacent test runner and propagate its status.
VERIFY_FIXTURE="$TMP_ROOT/verify-package"
mkdir -p "$VERIFY_FIXTURE/scripts" "$VERIFY_FIXTURE/tests" "$VERIFY_FIXTURE/templates"
cp "$PKG/scripts/verify.sh" "$VERIFY_FIXTURE/scripts/verify.sh"
: > "$VERIFY_FIXTURE/install.sh"
: > "$VERIFY_FIXTURE/templates/brain-config.example.json"
cat > "$VERIFY_FIXTURE/tests/run.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' invoked > "$VERIFY_MARKER"
exit "$VERIFY_EXIT"
SH
VERIFY_MARKER="$TMP_ROOT/verify-runner.marker"
if VERIFY_MARKER="$VERIFY_MARKER" VERIFY_EXIT=23 "$BASH_BIN" "$VERIFY_FIXTURE/scripts/verify.sh" > "$TMP_ROOT/package-verify.txt" 2>&1; then
  verify_status=0
else
  verify_status=$?
fi
if [ "$verify_status" -ne 23 ]; then
  fail "package verifier did not propagate the regression runner exit status (got $verify_status)"
fi
if [ ! -f "$VERIFY_MARKER" ]; then
  fail "package verifier did not invoke the package regression runner"
fi

# Build a temporary vault and local source stubs; install tests never use a real vault.
VAULT="$TMP_ROOT/vault"
MOCK_STARTER="$VAULT/.opencode/skills/ai-brain-starter"
MOCK_CRONTAB_STATE="$TMP_ROOT/crontab-state"
MOCK_CRONTAB_CALLS="$TMP_ROOT/crontab-calls.log"
MOCK_CRONTAB_WRITES="$TMP_ROOT/crontab-writes.log"
MOCK_GIT_CALLS="$TMP_ROOT/git-calls.log"
mkdir -p "$TMP_ROOT/bin" "$VAULT"
MOCK_UNAME=Linux

ai_brain_mock_platform "$TMP_ROOT/bin"
ai_brain_mock_crontab "$TMP_ROOT/bin"
ai_brain_mock_git "$TMP_ROOT/bin"
ai_brain_mock_opencode "$TMP_ROOT/bin"

export MOCK_UNAME MOCK_CRONTAB_STATE MOCK_CRONTAB_CALLS MOCK_CRONTAB_WRITES MOCK_GIT_CALLS
export PATH="$TMP_ROOT/bin:$PATH"
export BRAIN_STARTER_UPDATE=0
unset BRAIN_STARTER_PIN || true

if ! MOCK_VAULT="$VAULT" "$BASH_BIN" "$PKG/install.sh" "$VAULT" > "$TMP_ROOT/install.txt" 2>&1; then
  fail "initial fixture installation failed; see isolated install output"
  cat "$TMP_ROOT/install.txt" >&2
else
  # Simulate user edits and a starter update without touching files outside this fixture.
  printf 'user-owned AGENTS content\n' > "$VAULT/AGENTS.md"
  python3 - "$VAULT/⚙️ Meta/brain-config.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["user_note"] = "preserve this value"
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
  cp "$VAULT/AGENTS.md" "$TMP_ROOT/agents.snapshot"
  cp "$VAULT/⚙️ Meta/brain-config.json" "$TMP_ROOT/brain-config.snapshot"
  printf 'user-owned scheduled job\n' > "$VAULT/scripts/jobs/journal-reminder.sh"
  cp "$VAULT/scripts/jobs/journal-reminder.sh" "$TMP_ROOT/job.snapshot"
  rm -rf "$VAULT/📓 Journals"
  rm -f "$VAULT/⚙️ Meta/journal-config.md"
  mkdir -p "$MOCK_STARTER/skills/new-skill" "$MOCK_STARTER/commands"
  printf '# Added skill after starter update\n' > "$MOCK_STARTER/skills/new-skill/SKILL.md"
  printf '# Added command after starter update\n' > "$MOCK_STARTER/commands/new-command.md"
  cp "$MOCK_GIT_CALLS" "$TMP_ROOT/git-before-wire.log"

  if ! MOCK_VAULT="$VAULT" "$BASH_BIN" "$PKG/install.sh" "$VAULT" --wire --with-schedule > "$TMP_ROOT/wire.txt" 2>&1; then
    fail "--wire failed for the existing isolated vault"
    cat "$TMP_ROOT/wire.txt" >&2
  fi
  if [ ! -L "$VAULT/.opencode/skills/new-skill" ] || [ ! -f "$VAULT/.opencode/skills/new-skill/SKILL.md" ]; then
    fail "--wire did not link the skill added by the updated starter"
  fi
  if [ ! -L "$VAULT/.opencode/commands/new-command.md" ] || [ ! -f "$VAULT/.opencode/commands/new-command.md" ]; then
    fail "--wire did not link the command added by the updated starter"
  fi
  if [ -e "$VAULT/📓 Journals" ] || [ -e "$VAULT/⚙️ Meta/journal-config.md" ]; then
    fail "--wire re-scaffolded a removed vault directory or config file"
  fi
  if ! cmp -s "$VAULT/AGENTS.md" "$TMP_ROOT/agents.snapshot"; then
    fail "--wire overwrote user-owned AGENTS.md content"
  fi
  if ! cmp -s "$VAULT/⚙️ Meta/brain-config.json" "$TMP_ROOT/brain-config.snapshot"; then
    fail "--wire overwrote user-owned brain configuration"
  fi
  if ! cmp -s "$VAULT/scripts/jobs/journal-reminder.sh" "$TMP_ROOT/job.snapshot"; then
    fail "--wire overwrote a user-modified scheduled job"
  fi
  if ! cmp -s "$MOCK_GIT_CALLS" "$TMP_ROOT/git-before-wire.log"; then
    fail "--wire invoked git clone or changed the vault git state"
  fi
  if [ ! -s "$MOCK_CRONTAB_WRITES" ]; then
    fail "--wire --with-schedule did not reconcile through the crontab stub"
  fi
fi

# The base commit must stage the managed artifacts and the empty structure.
if ! grep -Eq 'add -- .*\.opencode' "$MOCK_GIT_CALLS"; then
  fail "installer did not stage managed artifacts in the base commit"
fi
if ! grep -Eq 'add -- .*(📓 Journals|⚙️ Meta)/\.gitkeep' "$MOCK_GIT_CALLS"; then
  fail "base commit did not stage the empty vault structure"
fi
if ! grep -Fq 'commit -q -m chore: bootstrap ai-brain OpenCode vault' "$MOCK_GIT_CALLS"; then
  fail "installer did not create the base commit"
fi

# Native Windows (MINGW*) is a supported backend: WIRE_MODE=copy (zero package symlinks).
# Truly unsupported platforms (e.g. FreeBSD) still abort before mutation.
ai_brain_mock_windows "$TMP_ROOT/bin"
MOCK_SCHTASKS_CALLS="$TMP_ROOT/schtasks-calls.log"
: > "$MOCK_SCHTASKS_CALLS"
export MOCK_SCHTASKS_CALLS

UNSUPPORTED_VAULT="$TMP_ROOT/freebsd-vault"
mkdir -p "$UNSUPPORTED_VAULT"
printf 'keep\n' > "$UNSUPPORTED_VAULT/keep.txt"
if MOCK_UNAME=FreeBSD "$BASH_BIN" "$PKG/install.sh" "$UNSUPPORTED_VAULT" > "$TMP_ROOT/freebsd.txt" 2>&1; then
  fail "installer accepted an unsupported platform (FreeBSD)"
fi
if ! grep -Eqi 'plataforma no soportada|no soportad' "$TMP_ROOT/freebsd.txt"; then
  fail "unsupported-platform rejection did not name the failure"
fi
if [ ! -f "$UNSUPPORTED_VAULT/keep.txt" ] || [ -e "$UNSUPPORTED_VAULT/.opencode" ]; then
  fail "unsupported-platform rejection modified the target"
fi

WINDOWS_VAULT="$TMP_ROOT/windows-vault"
mkdir -p "$WINDOWS_VAULT"
# opencode must answer `opencode run --help` on the Windows preflight path.
ai_brain_mock_opencode "$TMP_ROOT/bin"
if ! MOCK_UNAME=MINGW64_NT-10.0 MOCK_VAULT="$WINDOWS_VAULT" \
  "$BASH_BIN" "$PKG/install.sh" "$WINDOWS_VAULT" > "$TMP_ROOT/windows.txt" 2>&1; then
  fail "installer rejected native Windows (MINGW); see isolated install output"
  cat "$TMP_ROOT/windows.txt" >&2
fi
if ! grep -Fq 'Windows nativo detectado' "$TMP_ROOT/windows.txt"; then
  fail "Windows install did not announce native Windows / copy wiring"
fi
# Package wiring must be copies: no symlinks under the vault root.
if [ -n "$(find "$WINDOWS_VAULT" -type l 2>/dev/null | head -n 1)" ]; then
  fail "Windows install created symlinks (expected WIRE_MODE=copy with zero symlinks)"
  find "$WINDOWS_VAULT" -type l >&2 || true
fi
if [ ! -d "$WINDOWS_VAULT/.opencode/skills" ] \
  || [ -z "$(find "$WINDOWS_VAULT/.opencode/skills" -maxdepth 1 -mindepth 1 -type d ! -name ai-brain-starter 2>/dev/null | head -n 1)" ]; then
  fail "Windows install did not materialize skill copies under .opencode/skills"
fi
if [ ! -f "$WINDOWS_VAULT/.opencode/commands/brain-journal.md" ] \
  && [ -z "$(ls -1 "$WINDOWS_VAULT/.opencode/commands" 2>/dev/null | head -n 1)" ]; then
  fail "Windows install did not materialize command copies"
fi
if [ ! -f "$WINDOWS_VAULT/AGENTS.md" ] || [ -L "$WINDOWS_VAULT/CLAUDE.md" ]; then
  fail "Windows install did not leave AGENTS.md / CLAUDE.md as regular copy content"
fi

# schtasks dry-run: cygpath+schtasks mocks; printed /ST times match package defaults.
mkdir -p "$WINDOWS_VAULT/scripts/jobs" "$WINDOWS_VAULT/⚙️ Meta"
for j in journal-reminder insights-weekly daily-maintenance update-brain; do
  [ -f "$WINDOWS_VAULT/scripts/jobs/$j.sh" ] || { printf '#!/bin/sh\n' > "$WINDOWS_VAULT/scripts/jobs/$j.sh"; chmod +x "$WINDOWS_VAULT/scripts/jobs/$j.sh"; }
done
if ! MOCK_UNAME=MINGW64_NT-10.0 \
  "$BASH_BIN" "$PKG/scripts/schedule.sh" "$WINDOWS_VAULT" --dry-run \
  > "$TMP_ROOT/windows-sched.txt" 2>"$TMP_ROOT/windows-sched.err"; then
  fail "Windows schedule --dry-run failed"
  cat "$TMP_ROOT/windows-sched.txt" "$TMP_ROOT/windows-sched.err" >&2
fi
for st in '20:30' '21:00' '03:30' '08:00'; do
  if ! grep -Fq "/ST $st" "$TMP_ROOT/windows-sched.txt"; then
    fail "Windows schedule dry-run missing /ST $st"
    cat "$TMP_ROOT/windows-sched.txt" >&2
  fi
done
if ! grep -Fq 'schtasks /Create' "$TMP_ROOT/windows-sched.txt"; then
  fail "Windows schedule dry-run did not print schtasks /Create lines"
fi
# Windows schtasks contract: one ai-brain-run.cmd wrapper; /TR is wrapper path + job name.
if ! grep -Fq 'ai-brain-run.cmd' "$TMP_ROOT/windows-sched.txt"; then
  fail "Windows schedule dry-run /TR missing ai-brain-run.cmd wrapper"
  cat "$TMP_ROOT/windows-sched.txt" >&2
fi
if [ "$(grep -c $'\b' "$TMP_ROOT/windows-sched.txt" || true)" != 0 ]; then
  fail "Windows schedule dry-run lines contain backspace (0x08) bytes"
  cat "$TMP_ROOT/windows-sched.txt" >&2
fi
# Non-dry-run creates the wrapper; body must invoke bash "%~dp0%JOB%.sh".
if ! MOCK_UNAME=MINGW64_NT-10.0 \
  "$BASH_BIN" "$PKG/scripts/schedule.sh" "$WINDOWS_VAULT" \
  > "$TMP_ROOT/windows-sched-apply.txt" 2>"$TMP_ROOT/windows-sched-apply.err"; then
  fail "Windows schedule apply failed (needed to materialize ai-brain-run.cmd)"
  cat "$TMP_ROOT/windows-sched-apply.txt" "$TMP_ROOT/windows-sched-apply.err" >&2
fi
WIN_RUNNER_CMD="$WINDOWS_VAULT/scripts/jobs/ai-brain-run.cmd"
if [ ! -f "$WIN_RUNNER_CMD" ]; then
  fail "Windows schedule did not create scripts/jobs/ai-brain-run.cmd"
fi
if ! grep -Fq 'bash "%~dp0%JOB%.sh"' "$WIN_RUNNER_CMD"; then
  fail "ai-brain-run.cmd does not invoke bash with %~dp0%JOB%.sh"
  cat "$WIN_RUNNER_CMD" >&2
fi

# schtasks apply must record the task names in the manifest (ownership), and
# --remove deletes exactly those — a foreign "ai-brain ..." task stays untouched.
if ! python3 - "$WINDOWS_VAULT/.opencode/brain-vault-install-manifest.json" <<'PY'
import json, pathlib, sys
names = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))["cron_lines"]
expected = {"ai-brain windows-vault journal-reminder", "ai-brain windows-vault insights-weekly",
            "ai-brain windows-vault daily-maintenance", "ai-brain windows-vault update-brain"}
assert set(names) == expected, "manifest did not record the schtasks task names: %r" % (names,)
PY
then
  fail "Windows schedule apply did not record owned schtasks task names"
fi
: > "$MOCK_SCHTASKS_CALLS"
MOCK_SCHTASKS_STATE="$TMP_ROOT/schtasks-state"
export MOCK_SCHTASKS_STATE
{
  printf '"\\ai-brain windows-vault journal-reminder","2026-01-01 20:30:00"\n'
  printf '"ai-brain windows-vault insights-weekly","2026-01-01 21:00:00"\n'
  printf '"\\ai-brain windows-vault daily-maintenance","2026-01-01 03:30:00"\n'
  printf '"ai-brain windows-vault update-brain","2026-01-01 08:00:00"\n'
  printf '"\\ai-brain other-vault foreign-job","2026-01-01 09:00:00"\n'
} > "$MOCK_SCHTASKS_STATE"
if ! MOCK_UNAME=MINGW64_NT-10.0 \
  "$BASH_BIN" "$PKG/scripts/schedule.sh" "$WINDOWS_VAULT" --remove \
  > "$TMP_ROOT/windows-sched-remove.txt" 2>&1; then
  fail "Windows schedule --remove failed"
  cat "$TMP_ROOT/windows-sched-remove.txt" >&2
fi
for owned_name in journal-reminder insights-weekly daily-maintenance update-brain; do
  if ! grep -Fq "/Delete /F /TN ai-brain windows-vault $owned_name" "$MOCK_SCHTASKS_CALLS"; then
    fail "Windows --remove did not delete the owned task $owned_name"
  fi
done
if grep -Fq "/Delete /F /TN ai-brain other-vault foreign-job" "$MOCK_SCHTASKS_CALLS"; then
  fail "Windows --remove deleted a foreign ai-brain task"
fi
if ! grep -Fq 'tarea ajena preservada: ai-brain other-vault foreign-job' "$TMP_ROOT/windows-sched-remove.txt"; then
  fail "Windows --remove did not report the preserved foreign task"
fi

# Owned copy trees must re-sync with the starter (the Windows --wire path).
printf '\nresync-marker\n' >> "$WINDOWS_VAULT/.opencode/skills/ai-brain-starter/skills/journal/SKILL.md"
if ! MOCK_UNAME=MINGW64_NT-10.0 MOCK_VAULT="$WINDOWS_VAULT" \
  "$BASH_BIN" "$PKG/install.sh" "$WINDOWS_VAULT" > "$TMP_ROOT/windows-resync.txt" 2>&1; then
  fail "Windows re-install failed"
  cat "$TMP_ROOT/windows-resync.txt" >&2
fi
if ! grep -Fq 'resync-marker' "$WINDOWS_VAULT/.opencode/skills/journal/SKILL.md"; then
  fail "Windows re-install did not refresh the owned copied skill tree"
fi

# A vault health check with failures must exit non-zero.
BROKEN_VAULT="$TMP_ROOT/broken-vault"
mkdir -p "$BROKEN_VAULT/scripts"
cp "$PKG/scripts/verify.sh" "$BROKEN_VAULT/scripts/verify.sh"
if "$BASH_BIN" "$BROKEN_VAULT/scripts/verify.sh" > "$TMP_ROOT/broken-verify.txt" 2>&1; then
  fail "vault verifier exited 0 for a broken vault"
fi
if ! grep -Fq 'fallos' "$TMP_ROOT/broken-verify.txt"; then
  fail "vault verifier did not report the failure count"
fi

# The missing-OpenCode preflight must leave an existing target byte-for-byte unchanged.
NO_OPENCODE_BIN="$TMP_ROOT/no-opencode-bin"
MISSING_VAULT="$TMP_ROOT/no-opencode-vault"
mkdir -p "$NO_OPENCODE_BIN" "$MISSING_VAULT"
printf 'existing user data\n' > "$MISSING_VAULT/keep.txt"
for command_name in dirname mkdir basename tr sed python3 node find wc ln readlink cp chmod ls cat grep date head tail rm cut sort; do
  if resolved="$(command -v "$command_name")"; then
    ln -s "$resolved" "$NO_OPENCODE_BIN/$command_name"
  fi
done
ln -s "$TMP_ROOT/bin/uname" "$NO_OPENCODE_BIN/uname"
ln -s "$TMP_ROOT/bin/git" "$NO_OPENCODE_BIN/git"
find "$MISSING_VAULT" -mindepth 1 -print | sort > "$TMP_ROOT/no-opencode-before.txt"
if PATH="$NO_OPENCODE_BIN" MOCK_VAULT="$MISSING_VAULT" "$BASH_BIN" "$PKG/install.sh" "$MISSING_VAULT" > "$TMP_ROOT/no-opencode.txt" 2>&1; then
  fail "installer succeeded without the required OpenCode CLI"
fi
if ! grep -Fq 'OpenCode CLI' "$TMP_ROOT/no-opencode.txt" || ! grep -Fq 'No se modificó el vault' "$TMP_ROOT/no-opencode.txt"; then
  fail "missing-OpenCode error did not explain the prerequisite and no-mutation guarantee"
fi
find "$MISSING_VAULT" -mindepth 1 -print | sort > "$TMP_ROOT/no-opencode-after.txt"
if ! cmp -s "$TMP_ROOT/no-opencode-before.txt" "$TMP_ROOT/no-opencode-after.txt"; then
  fail "installer mutated the vault before reporting missing OpenCode"
fi

# CLAUDE.md must resolve to AGENTS.md. Any other symlink, a regular file, or absence fails.
check_claude() {
  local name="$1"
  local mode="$2"
  local root="$TMP_ROOT/claude-$name"
  mkdir -p "$root/scripts"
  cp "$PKG/scripts/verify.sh" "$root/scripts/verify.sh"
  printf 'agents body\n' > "$root/AGENTS.md"
  case "$mode" in
    good) ln -s AGENTS.md "$root/CLAUDE.md" ;;
    wrong)
      printf 'other\n' > "$TMP_ROOT/other-claude.md"
      ln -s "$TMP_ROOT/other-claude.md" "$root/CLAUDE.md"
      ;;
    file) printf 'regular\n' > "$root/CLAUDE.md" ;;
    absent) ;;
  esac
  set +e
  "$BASH_BIN" "$root/scripts/verify.sh" > "$TMP_ROOT/claude-$name.txt" 2>&1
  local status=$?
  set -e
  printf '%s\n' "$status" > "$TMP_ROOT/claude-$name.exit"
}

check_claude good good
if ! grep -Fq '✓ CLAUDE.md enlazado a AGENTS.md' "$TMP_ROOT/claude-good.txt"; then
  fail "verifier rejected a CLAUDE.md symlink whose real target is AGENTS.md"
fi
check_claude wrong wrong
if ! grep -Fq '✗ CLAUDE.md enlazado a AGENTS.md' "$TMP_ROOT/claude-wrong.txt"; then
  fail "verifier accepted a CLAUDE.md symlink that does not resolve to AGENTS.md"
fi
if [ "$(cat "$TMP_ROOT/claude-wrong.exit")" -eq 0 ]; then
  fail "verifier exited 0 when CLAUDE.md pointed elsewhere"
fi
check_claude absent absent
if ! grep -Fq '✗ CLAUDE.md enlazado a AGENTS.md' "$TMP_ROOT/claude-absent.txt"; then
  fail "verifier accepted a vault without CLAUDE.md"
fi
if [ "$(cat "$TMP_ROOT/claude-absent.exit")" -eq 0 ]; then
  fail "verifier exited 0 when CLAUDE.md was absent"
fi
check_claude regular file
if ! grep -Fq '✗ CLAUDE.md enlazado a AGENTS.md' "$TMP_ROOT/claude-regular.txt"; then
  fail "verifier accepted a regular CLAUDE.md file"
fi
if [ "$(cat "$TMP_ROOT/claude-regular.exit")" -eq 0 ]; then
  fail "verifier exited 0 when CLAUDE.md was a regular file"
fi

# insights-weekly must fail visibly when opencode is missing, and run when it is present.
INSIGHTS_VAULT="$TMP_ROOT/insights-vault"
INSIGHTS_BIN="$TMP_ROOT/insights-bin"
mkdir -p "$INSIGHTS_VAULT/scripts/jobs" "$INSIGHTS_VAULT/📓 Journals" "$INSIGHTS_BIN"
ai_brain_install_vault_libs "$PKG" "$INSIGHTS_VAULT"
cp "$PKG/templates/jobs/insights-weekly.sh" "$INSIGHTS_VAULT/scripts/jobs/insights-weekly.sh"
printf '# entrada\n' > "$INSIGHTS_VAULT/📓 Journals/hoy.md"
set +e
PATH="$INSIGHTS_BIN:/usr/bin:/bin" "$BASH_BIN" "$INSIGHTS_VAULT/scripts/jobs/insights-weekly.sh" > "$TMP_ROOT/insights-miss.out" 2> "$TMP_ROOT/insights-miss.err"
insights_miss=$?
set -e
if [ "$insights_miss" -eq 0 ]; then
  fail "insights-weekly exited 0 when opencode was absent"
fi
if ! grep -Fq 'opencode no disponible' "$TMP_ROOT/insights-miss.err"; then
  fail "insights-weekly did not write the missing-opencode error to stderr"
fi
cat > "$INSIGHTS_BIN/opencode" <<'SH'
#!/bin/sh
printf '%s\n' "$*"
exit 0
SH
chmod +x "$INSIGHTS_BIN/opencode"
if ! PATH="$INSIGHTS_BIN:/usr/bin:/bin" "$BASH_BIN" "$INSIGHTS_VAULT/scripts/jobs/insights-weekly.sh" > "$TMP_ROOT/insights-ok.out" 2> "$TMP_ROOT/insights-ok.err"; then
  fail "insights-weekly failed when opencode was on PATH"
fi
EMPTY_VAULT="$TMP_ROOT/insights-empty"
mkdir -p "$EMPTY_VAULT/scripts/jobs" "$EMPTY_VAULT/📓 Journals"
ai_brain_install_vault_libs "$PKG" "$EMPTY_VAULT"
cp "$PKG/templates/jobs/insights-weekly.sh" "$EMPTY_VAULT/scripts/jobs/insights-weekly.sh"
if ! PATH="$INSIGHTS_BIN:/usr/bin:/bin" "$BASH_BIN" "$EMPTY_VAULT/scripts/jobs/insights-weekly.sh" > "$TMP_ROOT/insights-empty.out" 2> "$TMP_ROOT/insights-empty.err"; then
  fail "insights-weekly failed when there were no journal entries"
fi

# Missing git identity must stop before any vault mutation. The successful install above is the with-identity case.
NO_IDENT_NEW="$TMP_ROOT/no-ident-new"
if MOCK_GIT_IDENTITY=missing MOCK_VAULT="$NO_IDENT_NEW" "$BASH_BIN" "$PKG/install.sh" "$NO_IDENT_NEW" > "$TMP_ROOT/no-ident-new.txt" 2>&1; then
  fail "installer succeeded without git identity"
fi
if [ -e "$NO_IDENT_NEW" ]; then
  fail "missing git identity created a new vault"
fi
if ! grep -Fq 'No se modificó el vault' "$TMP_ROOT/no-ident-new.txt" || ! grep -Fq 'identidad' "$TMP_ROOT/no-ident-new.txt"; then
  fail "missing git identity error did not name the prerequisite and the no-mutation guarantee"
fi
NO_IDENT_OLD="$TMP_ROOT/no-ident-existing"
mkdir -p "$NO_IDENT_OLD"
printf 'keep\n' > "$NO_IDENT_OLD/keep.txt"
find "$NO_IDENT_OLD" -print | sort > "$TMP_ROOT/no-ident-existing-before.txt"
if MOCK_GIT_IDENTITY=missing "$BASH_BIN" "$PKG/install.sh" "$NO_IDENT_OLD" > "$TMP_ROOT/no-ident-existing.txt" 2>&1; then
  fail "installer succeeded on an existing vault without git identity"
fi
find "$NO_IDENT_OLD" -print | sort > "$TMP_ROOT/no-ident-existing-after.txt"
if ! cmp -s "$TMP_ROOT/no-ident-existing-before.txt" "$TMP_ROOT/no-ident-existing-after.txt"; then
  fail "missing git identity mutated an existing vault"
fi
if ! grep -Fq 'No se modificó el vault' "$TMP_ROOT/no-ident-existing.txt" || ! grep -Fq 'identidad' "$TMP_ROOT/no-ident-existing.txt"; then
  fail "existing vault without git identity did not name the prerequisite and the no-mutation guarantee"
fi

# An existing Git repository uses that repo's identity, not only the global one.
NO_IDENT_REPO="$TMP_ROOT/no-ident-repo"
mkdir -p "$NO_IDENT_REPO/.git"
printf 'keep\n' > "$NO_IDENT_REPO/keep.txt"
find "$NO_IDENT_REPO" -print | sort > "$TMP_ROOT/no-ident-repo-before.txt"
if MOCK_GIT_IDENTITY=missing "$BASH_BIN" "$PKG/install.sh" "$NO_IDENT_REPO" > "$TMP_ROOT/no-ident-repo.txt" 2>&1; then
  fail "installer succeeded on an existing git vault without identity"
fi
find "$NO_IDENT_REPO" -print | sort > "$TMP_ROOT/no-ident-repo-after.txt"
if ! cmp -s "$TMP_ROOT/no-ident-repo-before.txt" "$TMP_ROOT/no-ident-repo-after.txt"; then
  fail "missing git identity mutated an existing git vault"
fi
if ! grep -Fq 'identidad' "$TMP_ROOT/no-ident-repo.txt"; then
  fail "existing git vault without identity did not report the missing identity"
fi

IDENT_REPO="$TMP_ROOT/ident-repo"
mkdir -p "$IDENT_REPO/.git"
printf 'keep\n' > "$IDENT_REPO/keep.txt"
if ! MOCK_VAULT="$IDENT_REPO" "$BASH_BIN" "$PKG/install.sh" "$IDENT_REPO" > "$TMP_ROOT/ident-repo.txt" 2>&1; then
  fail "installer rejected an existing git vault that already has identity"
  cat "$TMP_ROOT/ident-repo.txt" >&2
fi
if ! grep -Fq 'identidad git presente' "$TMP_ROOT/ident-repo.txt" || ! grep -Fq 'commit base' "$TMP_ROOT/ident-repo.txt"; then
  fail "existing git vault with identity did not pass preflight and commit"
fi

if [ "$failures" -gt 0 ]; then
  printf 'FAIL: installer and verification contract had %s failed assertions\n' "$failures" >&2
  exit 1
fi

printf 'PASS: wire, OpenCode preflight, strict JSON, and package verifier contracts\n'
