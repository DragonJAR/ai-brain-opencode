#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"

bash "$TEST_DIR/test-scheduler-dry-run.sh"
bash "$TEST_DIR/test-uninstall-ownership.sh"
bash "$TEST_DIR/test-t3-contract.sh"

if command -v node >/dev/null; then
  node "$TEST_DIR/test-plugin-contract.mjs" "$PKG"
else
  printf 'SKIP: node no disponible; contrato del plugin no ejecutado\n'
fi
