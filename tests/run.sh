#!/usr/bin/env bash
# Runs every tests/test-*.sh and, when node is available, every tests/test-*.mjs
# (a new test file needs no registration), then the release gate.
# Every test runs even after a failure; a failed shell test is re-run under
# `bash -x` and its last trace lines are printed, so a CI log names the cause.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
TRACE_LINES="${AI_BRAIN_TRACE_LINES:-40}"

failed=()
run_test() {
  local name="$1" rc=0
  shift
  "$@" || rc=$?
  [ "$rc" -eq 0 ] && return 0
  failed+=("$name")
  printf 'FAIL: %s exited %s\n' "$name" "$rc" >&2
  return 1
}

for test_file in "$TEST_DIR"/test-*.sh; do
  run_test "${test_file##*/}" bash "$test_file" && continue
  printf -- '--- %s: last %s lines of bash -x ---\n' "${test_file##*/}" "$TRACE_LINES" >&2
  { bash -x "$test_file" 2>&1 || true; } | tail -n "$TRACE_LINES" >&2
  printf -- '--- end %s ---\n' "${test_file##*/}" >&2
done

for test_file in "$TEST_DIR"/test-*.mjs; do
  [ -f "$test_file" ] || continue
  if command -v node >/dev/null; then
    run_test "${test_file##*/}" node "$test_file" "$PKG" || true
  else
    printf 'SKIP: node no disponible; %s no ejecutado\n' "${test_file##*/}"
  fi
done

# Release gate: no personal data, no references to the private vault repo.
run_test check-personal-data.sh bash "$PKG/scripts/check-personal-data.sh" || true

if [ "${#failed[@]}" -ne 0 ]; then
  printf '\nFAIL: %s test(s) failed: %s\n' "${#failed[@]}" "${failed[*]}" >&2
  exit 1
fi
