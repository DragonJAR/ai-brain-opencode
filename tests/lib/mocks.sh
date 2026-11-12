#!/usr/bin/env bash
# Shared fixtures for the ai-brain-opencode test suite.
# Every stub is deterministic, logs nothing outside the test root, and reads
# its platform and crontab state from environment variables the caller exports.

ai_brain_test_root() {
  mktemp -d "${TMPDIR:-/tmp}/ai-brain-$1.XXXXXX"
}

# A scheduled job needs the vault-side libraries install.sh copies next to it.
# Usage: ai_brain_install_vault_libs <package-root> <vault>
ai_brain_install_vault_libs() {
  local pkg="$1" vault="$2"
  mkdir -p "$vault/scripts/lib" "$vault/scripts/jobs"
  cp "$pkg"/scripts/lib/*.sh "$pkg"/scripts/lib/*.py "$vault/scripts/lib/"
  cp "$pkg/templates/brain-config.example.json" "$vault/scripts/lib/brain-config.defaults.json"
}

# HH:MM -> "MM HH": cron fields are minute-then-hour, launchd hour-then-minute.
# Mirrors pm()/hm() in schedule.sh: the minute drops one leading zero.
cron_minute_hour() {
  local hhmm="$1" hour minute
  hour=${hhmm%%:*}
  minute=${hhmm#*:}
  minute=$(printf '%s\n' "$minute" | sed 's/^0//')
  printf '%s %s' "$minute" "$hour"
}

ai_brain_mock_platform() {
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/uname" <<'SH'
#!/bin/sh
printf '%s\n' "${MOCK_UNAME:-Linux}"
SH
  chmod +x "$bin/uname"
}

ai_brain_mock_crontab() {
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/crontab" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_CRONTAB_CALLS"
case "${1:-}" in
  -l)
    [ -f "$MOCK_CRONTAB_STATE" ] || { printf 'no crontab for mock user\n' >&2; exit 1; }
    cat "$MOCK_CRONTAB_STATE"
    ;;
  -r)
    # `crontab -r` borra TODO el crontab del usuario: una regresión que lo llame
    # debe fallar ruidosamente aquí, no pasar desapercibida.
    printf 'FAIL: mock crontab received -r (user crontab would be destroyed)\n' >&2
    exit 99
    ;;
  -)
    printf '%s\n' "$*" >> "$MOCK_CRONTAB_WRITES"
    cat > "$MOCK_CRONTAB_STATE"
    ;;
  *)
    printf '%s\n' "$*" >> "$MOCK_CRONTAB_WRITES"
    [ ! -f "${1:-}" ] || cat "$1" > "$MOCK_CRONTAB_STATE"
    ;;
esac
SH
  chmod +x "$bin/crontab"
}

# Windows-native helpers for Git Bash simulation (cygpath + schtasks).
# Dry-run of schedule.sh only needs cygpath; schtasks is logged if invoked.
ai_brain_mock_windows() {
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/cygpath" <<'SH'
#!/bin/sh
# Minimal cygpath -w: map a POSIX path to a fake Windows path for tests.
mode=unix
while [ $# -gt 0 ]; do
  case "$1" in
    -w|-wa|-wt) mode=win; shift ;;
    -u|-ua|-ut) mode=unix; shift ;;
    --) shift; break ;;
    -*) shift ;;
    *) break ;;
  esac
done
path="${1:-.}"
if [ "$mode" = win ]; then
  # Real cygpath -w only converts separators; it never invents extensions.
  printf 'C:\\mock%s\n' "$(printf '%s' "$path" | tr '/' '\\')"
else
  printf '%s\n' "$path"
fi
SH
  chmod +x "$bin/cygpath"
  cat > "$bin/schtasks" <<'SH'
#!/bin/sh
# Log schtasks invocations; /Query returns MOCK_SCHTASKS_STATE when set.
printf '%s\n' "$*" >> "${MOCK_SCHTASKS_CALLS:-/dev/null}"
# Git Bash rewrites "/Create" into a path unless the caller disables it.
printf '%s\n' "${MSYS_NO_PATHCONV:-unset}" >> "${MOCK_SCHTASKS_ENV:-/dev/null}"
case " $* " in
  *" /Query "*)
    [ -f "${MOCK_SCHTASKS_STATE:-}" ] && cat "${MOCK_SCHTASKS_STATE:-}"
    exit 0 ;;
esac
exit 0
SH
  chmod +x "$bin/schtasks"
}

# plutil -lint that accepts every plist and keeps a copy in MOCK_PLUTIL_CAPTURE,
# so a launchd --dry-run (which deletes its temporary plists) can be inspected.
ai_brain_mock_plutil() {
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/plutil" <<'SH'
#!/bin/sh
if [ "${1:-}" = -lint ] && [ -n "${MOCK_PLUTIL_CAPTURE:-}" ]; then cp "$2" "$MOCK_PLUTIL_CAPTURE/"; fi
exit 0
SH
  chmod +x "$bin/plutil"
}

ai_brain_mock_opencode() {
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/opencode" <<'SH'
#!/bin/sh
exit 0
SH
  chmod +x "$bin/opencode"
}

ai_brain_mock_git() {
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/git" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ -n "${MOCK_GIT_CALLS:-}" ]; then printf '%s\n' "$*" >> "$MOCK_GIT_CALLS"; fi
reply_var() {
  if [ "${MOCK_GIT_IDENTITY:-present}" = "missing" ]; then
    printf '%s\n' 'fatal: unable to auto-detect email address' >&2
    exit 128
  fi
  printf '%s\n' 'Test User <test@example.invalid> 0 +0000'
  exit 0
}
if [ "${1:-}" = clone ]; then
  destination="${@: -1}"
  url="${@: -2:1}"
  mkdir -p "$destination"
  if [[ "$url" == *ai-brain-starter ]]; then
    mkdir -p "$destination/.git" "$destination/commands" \
      "$destination/scripts" "$destination/floors" "$destination/templates/generated"
    printf 'ref: refs/heads/main\n' > "$destination/.git/HEAD"
    printf '# Stub starter skill\n' > "$destination/SKILL.md"
    n="${MOCK_GIT_STARTER_SKILLS:-}"
    if [ -n "$n" ] && [ "$n" -eq "$n" ] 2>/dev/null && [ "$n" -gt 0 ]; then
      i=1
      while [ "$i" -le "$n" ]; do
        mkdir -p "$destination/skills/skill-$i"
        printf '# skill %s\n' "$i" > "$destination/skills/skill-$i/SKILL.md"
        i=$((i + 1))
      done
    else
      mkdir -p "$destination/skills/journal"
      printf '# Stub journal skill\n' > "$destination/skills/journal/SKILL.md"
    fi
    printf '# Stub command\n' > "$destination/commands/brain-journal.md"
    cat > "$destination/scripts/generate_floor_stubs.py" <<'PY'
from pathlib import Path
floor = Path(__file__).resolve().parent.parent / "floors" / "stub-floor.md"
floor.write_text("# Stub floor\n", encoding="utf-8")
PY
    printf '#!/bin/sh\nexit 0\n' > "$destination/scripts/vendor-job.sh"
    if [ -n "${MOCK_GIT_STARTER_TEMPLATE:-}" ]; then
      cp "$MOCK_GIT_STARTER_TEMPLATE" "$destination/templates/generated/claude-md-template.md"
    else
      cat > "$destination/templates/generated/claude-md-template.md" <<'MD'
# Stub vault instructions

## Vault Map
[FILL THIS IN]
MD
    fi
  elif [[ "$url" == *humanizer* ]]; then
    printf '# Stub humanizer\n' > "$destination/README.md"
  else
    printf 'unexpected clone URL: %s\n' "$url" >&2
    exit 91
  fi
  exit 0
fi
# MOCK_GIT_REAL=<path to git>: only clone is stubbed; the vault repo is real.
if [ -n "${MOCK_GIT_REAL:-}" ]; then exec "$MOCK_GIT_REAL" "$@"; fi
if [ "${1:-}" = -C ]; then
  repo="$2"
  shift 2
  case "${1:-}" in
    log) printf 'deadbeef stub vendor\n'; exit 0 ;;
    init) mkdir -p "${MOCK_VAULT:-$repo}/.git"; exit 0 ;;
    symbolic-ref) exit 0 ;;
    status)
      # MOCK_GIT_CLEAN=1 simula un árbol limpio (ejercita el camino "sin cambios").
      [ "${MOCK_GIT_CLEAN:-0}" = 1 ] || printf ' M .gitignore\n'
      exit 0 ;;
    add) exit 0 ;;
    check-ignore) exit 1 ;;
    diff)
      [ "${MOCK_GIT_CLEAN:-0}" = 1 ] && exit 0
      case " $* " in *" --name-only "*) printf 'AGENTS.md\0'; exit 0 ;; esac
      exit 1 ;;
    commit) exit 0 ;;
    var) reply_var ;;
  esac
fi
if [ "${1:-}" = var ]; then
  reply_var
fi
printf 'unexpected git command: %s\n' "$*" >&2
exit 92
SH
  chmod +x "$bin/git"
}
