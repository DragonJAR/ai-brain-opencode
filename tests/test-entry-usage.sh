#!/usr/bin/env bash
# Every entry script shares usage()/usage_error() from scripts/lib/common.sh:
# -h/--help prints the header on stdout and exits 0; an unknown flag exits 2
# with the message on stderr and nothing on stdout.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

TMP_ROOT="$(ai_brain_test_root entry-usage)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# verify.sh inside the package runs the whole suite; a vault copy keeps this test from recursing.
VAULT="$TMP_ROOT/vault"
ai_brain_install_vault_libs "$PKG" "$VAULT"
cp "$PKG/scripts/verify.sh" "$VAULT/scripts/verify.sh"

for script in "$PKG/install.sh" "$PKG/uninstall.sh" "$PKG/scripts/schedule.sh" \
              "$PKG/scripts/check-personal-data.sh" "$VAULT/scripts/verify.sh"; do
  name="${script##*/}"
  for flag in --help -h; do
    rc=0
    bash "$script" "$flag" > "$TMP_ROOT/out" 2> "$TMP_ROOT/err" || rc=$?
    [ "$rc" = 0 ] || fail "$name $flag exited $rc"
    grep -q "$name" "$TMP_ROOT/out" || fail "$name $flag did not print its usage on stdout"
    [ ! -s "$TMP_ROOT/err" ] || fail "$name $flag wrote to stderr: $(head -2 "$TMP_ROOT/err")"
  done
  rc=0
  bash "$script" --bogus > "$TMP_ROOT/out" 2> "$TMP_ROOT/err" || rc=$?
  [ "$rc" = 2 ] || fail "$name --bogus exited $rc, expected 2"
  grep -q -- '--bogus' "$TMP_ROOT/err" || fail "$name --bogus did not name the flag on stderr"
  [ ! -s "$TMP_ROOT/out" ] || fail "$name --bogus wrote to stdout: $(head -2 "$TMP_ROOT/out")"
done

# One definition: no entry script keeps its own usage().
for script in install.sh uninstall.sh scripts/schedule.sh scripts/verify.sh scripts/check-personal-data.sh; do
  if grep -Eq '^[[:space:]]*usage\(\)' "$PKG/$script" || grep -q "sed -n '2,/\^set -/p'" "$PKG/$script"; then
    fail "$script defines its own usage instead of common.sh's"
  fi
done

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: entry script usage had %s failures\n' "$failures" >&2
  exit 1
fi
printf 'PASS: entry scripts share usage(): --help exits 0, unknown flags exit 2\n'
