#!/usr/bin/env bash
# Python 3.9 is the documented minimum (and the one macOS ships). Constructs
# added in 3.10+ must not appear in package Python, standalone or embedded in
# shell heredocs; each one has already broken a real run once.
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PKG"

failures=0
check() {
  local label="$1" pattern="$2" hits
  hits="$(grep -nE "$pattern" install.sh uninstall.sh scripts/*.sh scripts/*.py scripts/lib/*.py \
    templates/jobs/*.sh 2>/dev/null | grep -v '# py39-ok' || true)"
  if [ -n "$hits" ]; then
    printf 'FAIL: %s\n%s\n' "$label" "$hits" >&2
    failures=$((failures + 1))
  fi
}

check 'Path.write_text(newline=) needs Python 3.10' 'write_text\([^)]*newline='
check 'PEP 604 "X | None" annotation needs Python 3.10' '(->|:)[[:space:]]*[A-Za-z_][A-Za-z_.]*(\[[^]]*\])?[[:space:]]*\|[[:space:]]*None'
check 'match/case statement needs Python 3.10' '^[[:space:]]*match[[:space:]]+[^=]+:[[:space:]]*$'
check 'zip(strict=) needs Python 3.10' 'zip\([^)]*strict='

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: %s Python 3.10+ constructs in package code\n' "$failures" >&2
  exit 1
fi
printf 'PASS: package Python stays compatible with 3.9\n'
