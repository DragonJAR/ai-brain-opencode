#!/usr/bin/env bash
# Shared fixtures for the ai-brain-opencode test suite.
# Every stub is deterministic, logs nothing outside the test root, and reads
# its platform and crontab state from environment variables the caller exports.

ai_brain_test_root() {
  mktemp -d "${TMPDIR:-/tmp}/ai-brain-$1.XXXXXX"
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

ai_brain_mock_git() {
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/git" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ -n "${MOCK_GIT_CALLS:-}" ]; then printf '%s\n' "$*" >> "$MOCK_GIT_CALLS"; fi
if [ "${1:-}" = clone ]; then
  destination="${@: -1}"
  url="${@: -2:1}"
  mkdir -p "$destination"
  if [[ "$url" == *ai-brain-starter ]]; then
    mkdir -p "$destination/.git" "$destination/skills/journal" "$destination/commands" \
      "$destination/scripts" "$destination/floors" "$destination/templates/generated"
    printf 'ref: refs/heads/main\n' > "$destination/.git/HEAD"
    printf '# Stub starter skill\n' > "$destination/SKILL.md"
    printf '# Stub journal skill\n' > "$destination/skills/journal/SKILL.md"
    printf '# Stub command\n' > "$destination/commands/brain-journal.md"
    cat > "$destination/scripts/generate_floor_stubs.py" <<'PY'
from pathlib import Path
floor = Path(__file__).resolve().parent.parent / "floors" / "stub-floor.md"
floor.write_text("# Stub floor\n", encoding="utf-8")
PY
    printf '#!/bin/sh\nexit 0\n' > "$destination/scripts/vendor-job.sh"
    cat > "$destination/templates/generated/claude-md-template.md" <<'MD'
# Stub vault instructions

## Vault Map
[FILL THIS IN]
MD
  elif [[ "$url" == *humanizer* ]]; then
    printf '# Stub humanizer\n' > "$destination/README.md"
  else
    printf 'unexpected clone URL: %s\n' "$url" >&2
    exit 91
  fi
  exit 0
fi
if [ "${1:-}" = -C ]; then
  repo="$2"
  shift 2
  case "${1:-}" in
    log) printf 'deadbeef stub vendor\n'; exit 0 ;;
    init) mkdir -p "${MOCK_VAULT:-$repo}/.git"; exit 0 ;;
    symbolic-ref) exit 0 ;;
    status) printf ' M .gitignore\n'; exit 0 ;;
    add) exit 0 ;;
    diff) exit 1 ;;
    commit) exit 0 ;;
  esac
fi
printf 'unexpected git command: %s\n' "$*" >&2
exit 92
SH
  chmod +x "$bin/git"
}
