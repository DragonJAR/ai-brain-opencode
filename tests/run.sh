#!/usr/bin/env bash
# Runs every tests/test-*.sh (a new test file needs no registration), the plugin
# contract when node is available, and the release gate.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"

for test_file in "$TEST_DIR"/test-*.sh; do
  bash "$test_file"
done

if command -v node >/dev/null; then
  node "$TEST_DIR/test-plugin-contract.mjs" "$PKG"
else
  printf 'SKIP: node no disponible; contrato del plugin no ejecutado\n'
fi

# Release gate: no personal data, no references to the private vault repo.
bash "$PKG/scripts/check-personal-data.sh"
