#!/usr/bin/env bash
# Ownership seal/validate/fingerprint logic must live only in ownership.py.
# Shell scripts may call the library; they must not reimplement sha256/st_mode/hashlib.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"

OWNERSHIP="$PKG/scripts/lib/ownership.py"
[ -f "$OWNERSHIP" ] || { printf 'FAIL: missing %s\n' "$OWNERSHIP" >&2; exit 1; }

# Canonical implementation must still own the fingerprint primitives.
if ! grep -Eq 'hashlib\.sha256' "$OWNERSHIP"; then
  printf 'FAIL: scripts/lib/ownership.py no longer defines fingerprint primitives\n' >&2
  exit 1
fi

SHELL_SCRIPTS=(
  "$PKG/install.sh"
  "$PKG/uninstall.sh"
  "$PKG/scripts/schedule.sh"
  "$PKG/scripts/verify.sh"
  "$PKG/scripts/check-personal-data.sh"
)
for job in "$PKG"/templates/jobs/*.sh; do
  [ -f "$job" ] || continue
  SHELL_SCRIPTS+=("$job")
done

drift=0
for script in "${SHELL_SCRIPTS[@]}"; do
  [ -f "$script" ] || continue
  # Flag reimplementation markers outside comments that merely mention ownership.py:
  # python primitives, and any shell-side hashing tool (openssl/shasum/cksum/md5sum).
  if grep -nE 'sha256|st_mode|hashlib\.sha|file_info\s*=|openssl dgst|shasum|cksum|md5sum' "$script" \
    | grep -Ev 'ownership\.py|^\s*#' >/dev/null 2>&1; then
    printf 'FAIL: ownership logic reimplemented in shell: %s\n' "${script#$PKG/}" >&2
    grep -nE 'sha256|st_mode|hashlib\.sha|file_info\s*=|openssl dgst|shasum|cksum|md5sum' "$script" >&2 || true
    drift=1
  fi
done

if [ "$drift" -ne 0 ]; then
  exit 1
fi

printf 'PASS: ownership seal/validate/fingerprint stays in ownership.py (no shell reimplementation)\n'
