#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$TEST_DIR/test-scheduler-dry-run.sh"
bash "$TEST_DIR/test-uninstall-ownership.sh"
