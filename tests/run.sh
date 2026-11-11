#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"

bash "$TEST_DIR/test-scheduler-dry-run.sh"
bash "$TEST_DIR/test-uninstall-ownership.sh"
bash "$TEST_DIR/test-defaults-single-source.sh"
bash "$TEST_DIR/test-ownership-dry-shell.sh"
bash "$TEST_DIR/test-install-link-batching.sh"
bash "$TEST_DIR/test-agents-schedule-appendix.sh"
bash "$TEST_DIR/test-update-brain-floor-preserve.sh"
bash "$TEST_DIR/test-journal-reminder-once.sh"
bash "$TEST_DIR/test-install-unknown-flag.sh"
bash "$TEST_DIR/test-uninstall-a11-n4-n5.sh"
bash "$TEST_DIR/test-uninstall-managed-copies.sh"
bash "$TEST_DIR/test-t3-contract.sh"

if command -v node >/dev/null; then
  node "$TEST_DIR/test-plugin-contract.mjs" "$PKG"
else
  printf 'SKIP: node no disponible; contrato del plugin no ejecutado\n'
fi

# Release gate: no personal data, no references to the private vault repo.
bash "$PKG/scripts/check-personal-data.sh"
