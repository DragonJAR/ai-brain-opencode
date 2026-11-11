#!/usr/bin/env bash
# install.sh --bogus must exit non-zero with "flag desconocida" and create no vault.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

TMP_ROOT="$(ai_brain_test_root install-flag)"
trap 'rm -rf "$TMP_ROOT"' EXIT

VAULT="$TMP_ROOT/should-not-exist"
mkdir -p "$TMP_ROOT/bin"
ai_brain_mock_platform "$TMP_ROOT/bin"
ai_brain_mock_opencode "$TMP_ROOT/bin"
export PATH="$TMP_ROOT/bin:$PATH"
export MOCK_UNAME=Linux

SCRATCH_CWD="$TMP_ROOT/scratch"
mkdir -p "$SCRATCH_CWD"
set +e
( cd "$SCRATCH_CWD" && bash "$PKG/install.sh" --bogus ) >"$TMP_ROOT/out.txt" 2>"$TMP_ROOT/err.txt"
rc=$?
set -e

if [ "$rc" -eq 0 ]; then
  printf 'FAIL: install.sh --bogus exited 0\n' >&2
  exit 1
fi
if ! grep -q 'flag desconocida' "$TMP_ROOT/err.txt" "$TMP_ROOT/out.txt" 2>/dev/null; then
  printf 'FAIL: missing "flag desconocida" message\n' >&2
  cat "$TMP_ROOT/out.txt" "$TMP_ROOT/err.txt" >&2
  exit 1
fi
if [ -e "$VAULT" ] || [ -d "$TMP_ROOT/should-not-exist" ]; then
  printf 'FAIL: --bogus created a vault path\n' >&2
  exit 1
fi
# Also ensure a positional vault path is not created when the unknown flag is first.
if [ -e "$PKG/--bogus" ] || [ -e "$SCRATCH_CWD/--bogus" ]; then
  printf 'FAIL: treated --bogus as a vault path on disk\n' >&2
  exit 1
fi

printf 'PASS: install.sh --bogus rejected without creating a vault\n'
