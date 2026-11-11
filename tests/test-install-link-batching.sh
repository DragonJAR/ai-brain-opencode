#!/usr/bin/env bash
# python3 ownership record-links invocations must not grow linearly with N skills.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

count_record_links_for_n() {
  local n="$1" root vault bin rl_log real_py
  root="$(ai_brain_test_root "link-batch-n$n")"
  vault="$root/vault"
  bin="$root/bin"
  rl_log="$root/record-links.log"
  : > "$rl_log"
  mkdir -p "$bin" "$vault"

  MOCK_UNAME=Linux
  MOCK_GIT_CALLS="$root/git-calls.log"
  MOCK_CRONTAB_STATE="$root/crontab-state"
  MOCK_CRONTAB_CALLS="$root/crontab-calls.log"
  MOCK_CRONTAB_WRITES="$root/crontab-writes.log"
  MOCK_VAULT="$vault"
  MOCK_GIT_STARTER_SKILLS="$n"
  : > "$MOCK_GIT_CALLS"
  : > "$MOCK_CRONTAB_CALLS"
  : > "$MOCK_CRONTAB_WRITES"

  ai_brain_mock_platform "$bin"
  ai_brain_mock_crontab "$bin"
  ai_brain_mock_git "$bin"
  ai_brain_mock_opencode "$bin"

  real_py="$(command -v python3)"
  cat > "$bin/python3" <<PYWRAP
#!/bin/sh
for arg in "\$@"; do
  if [ "\$arg" = "record-links" ]; then
    printf 'record-links\n' >> "$rl_log"
  fi
done
exec "$real_py" "\$@"
PYWRAP
  chmod +x "$bin/python3"

  export MOCK_UNAME MOCK_GIT_CALLS MOCK_CRONTAB_STATE MOCK_CRONTAB_CALLS MOCK_CRONTAB_WRITES MOCK_VAULT
  export MOCK_GIT_STARTER_SKILLS
  export PATH="$bin:/usr/bin:/bin"
  export TMPDIR="$root"
  export BRAIN_STARTER_UPDATE=0
  unset BRAIN_STARTER_PIN || true

  if ! bash "$PKG/install.sh" "$vault" >"$root/install.txt" 2>&1; then
    printf 'FAIL: install failed for N=%s\n' "$n" >&2
    cat "$root/install.txt" >&2
    rm -rf "$root"
    return 1
  fi

  local count
  count="$(wc -l < "$rl_log" | tr -d ' ')"
  printf '%s' "$count"
  rm -rf "$root"
}

C5="$(count_record_links_for_n 5)"
C20="$(count_record_links_for_n 20)"

if [ -z "$C5" ] || [ -z "$C20" ]; then
  printf 'FAIL: could not measure record-links counts\n' >&2
  exit 1
fi

# With batching, flush_links runs once per phase — counts must match across N.
if [ "$C5" != "$C20" ]; then
  printf 'FAIL: record-links grew with skill count: N=5 → %s calls, N=20 → %s calls\n' "$C5" "$C20" >&2
  exit 1
fi
if [ "$C20" -ge 20 ]; then
  printf 'FAIL: record-links count %s is linear with N=20 (batching missing)\n' "$C20" >&2
  exit 1
fi

printf 'PASS: record-links batched (N=5 and N=20 both %s calls, not linear)\n' "$C20"
