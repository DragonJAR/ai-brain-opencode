#!/usr/bin/env bash
# The release gate must not be fooled: a binary file is scanned as text, a CRLF
# terms file still matches, a blank line in it does not flag every line, and the
# word "humanizer" is not a free pass (only the vendor clone URLs are exempt).
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

TMP_ROOT="$(ai_brain_test_root check-personal-data)"
trap 'rm -rf "$TMP_ROOT"' EXIT
GATE="$PKG/scripts/check-personal-data.sh"
TERM_WORD="Zyxwqv"

# gate <dir> <terms-file>: exit code of the gate, output in $TMP_ROOT/gate.txt
gate() {
  local rc=0
  BRAIN_PERSONAL_TERMS="$2" bash "$GATE" "$1" > "$TMP_ROOT/gate.txt" 2>&1 || rc=$?
  return "$rc"
}

clean_pkg() {
  rm -rf "$1"
  mkdir -p "$1"
  printf 'plain package text\nanother line\n' > "$1/README.md"
}

printf '%s\n' "$TERM_WORD" > "$TMP_ROOT/terms-lf.txt"

# 1. A binary file with an email is a leak.
P="$TMP_ROOT/pkg-binary"
clean_pkg "$P"
printf 'PNG\000\000 %s@%s \000\n' operator realmail.co > "$P/asset.bin"
if gate "$P" "$TMP_ROOT/terms-lf.txt"; then
  fail "a binary file with an email passed the gate"
fi
grep -Fq 'asset.bin' "$TMP_ROOT/gate.txt" || fail "the gate did not name the binary file: $(cat "$TMP_ROOT/gate.txt")"

# 2. A CRLF terms file still matches.
P="$TMP_ROOT/pkg-crlf"
clean_pkg "$P"
printf 'written by %s\n' "$TERM_WORD" > "$P/notes.md"
printf '%s\r\n' "$TERM_WORD" > "$TMP_ROOT/terms-crlf.txt"
if gate "$P" "$TMP_ROOT/terms-crlf.txt"; then
  fail "a CRLF terms file did not match"
fi

# 3. Blank lines and comments in the terms file do not match everything.
P="$TMP_ROOT/pkg-blank"
clean_pkg "$P"
printf '# my names\n\n%s\n\n' "$TERM_WORD" > "$TMP_ROOT/terms-blank.txt"
gate "$P" "$TMP_ROOT/terms-blank.txt" || fail "a blank line in the terms file flagged a clean package: $(head -5 "$TMP_ROOT/gate.txt")"

# 4. "humanizer" is no exemption; the vendor clone URL is.
P="$TMP_ROOT/pkg-humanizer"
clean_pkg "$P"
printf 'humanizer notes by %s\n' "$TERM_WORD" > "$P/notes.md"
if gate "$P" "$TMP_ROOT/terms-lf.txt"; then
  fail "a line with a personal term passed because it mentions humanizer"
fi
P="$TMP_ROOT/pkg-vendor-url"
clean_pkg "$P"
printf 'HUMANIZER_REPO="https://github.com/adelaidasofia/humanizer.git"\n' > "$P/install.sh"
printf 'adelaidasofia\n' > "$TMP_ROOT/terms-vendor.txt"
gate "$P" "$TMP_ROOT/terms-vendor.txt" || fail "the vendor clone URL was flagged as personal data"

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: personal data gate had %s failures\n' "$failures" >&2
  exit 1
fi
printf 'PASS: release gate scans binaries, normalizes the terms file and exempts only vendor URLs\n'
