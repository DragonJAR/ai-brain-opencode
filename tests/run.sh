#!/usr/bin/env bash
# Runs every tests/test-*.sh and, when node is available, every tests/test-*.mjs
# (a new test file needs no registration), then the release gate.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"

for test_file in "$TEST_DIR"/test-*.sh; do
  bash "$test_file"
done

for test_file in "$TEST_DIR"/test-*.mjs; do
  [ -f "$test_file" ] || continue
  if command -v node >/dev/null; then
    node "$test_file" "$PKG"
  else
    printf 'SKIP: node no disponible; %s no ejecutado\n' "${test_file##*/}"
  fi
done

# Release gate: no personal data, no references to the private vault repo.
bash "$PKG/scripts/check-personal-data.sh"
