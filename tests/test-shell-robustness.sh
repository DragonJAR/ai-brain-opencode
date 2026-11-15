#!/usr/bin/env bash
# Shell robustness of the entry scripts: an exported CDPATH, an empty array on
# bash 3.2, the git identity probe of the vault (not of the caller's cwd repo),
# no writes through symlinked config/seed files, and verify.sh counting what it
# claims (vendor wiring only, every wired directory scanned for broken links).
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

TMP_ROOT="$(ai_brain_test_root shell-robustness)"
trap 'rm -rf "$TMP_ROOT"' EXIT
BIN="$TMP_ROOT/bin"
ai_brain_mock_platform "$BIN"
ai_brain_mock_git "$BIN"
ai_brain_mock_opencode "$BIN"
ai_brain_mock_windows "$BIN"
MOCK_GIT_CALLS="$TMP_ROOT/git-calls.log"
: > "$MOCK_GIT_CALLS"
export MOCK_UNAME=Linux MOCK_GIT_CALLS
export PATH="$BIN:/usr/bin:/bin" TMPDIR="$TMP_ROOT"
unset BRAIN_STARTER_PIN CDPATH || true

install_vault() {
  local vault="$1"
  shift
  MOCK_VAULT="$vault" bash "$PKG/install.sh" "$vault" "$@" > "$TMP_ROOT/install-${vault##*/}.txt" 2>&1
}

# 1. CDPATH makes `cd dir` print the directory, so "$(cd dir && pwd)" got two lines.
PARENT="$(dirname "$PKG")"
NAME="$(basename "$PKG")"
(cd "$PARENT" && CDPATH="$PARENT" bash "$NAME/install.sh" --version) > "$TMP_ROOT/cdpath-install.txt" 2>&1 \
  || fail "install.sh --version failed with CDPATH set: $(cat "$TMP_ROOT/cdpath-install.txt")"
(cd "$PARENT" && CDPATH="$PARENT" bash "$NAME/uninstall.sh" --help) > "$TMP_ROOT/cdpath-uninstall.txt" 2>&1 \
  || fail "uninstall.sh --help failed with CDPATH set: $(cat "$TMP_ROOT/cdpath-uninstall.txt")"

V="$TMP_ROOT/vault"
install_vault "$V" || fail "fixture install failed"
(cd "$TMP_ROOT" && CDPATH="$TMP_ROOT" bash vault/scripts/verify.sh) > "$TMP_ROOT/cdpath-verify.txt" 2>&1 || true
grep -Fq '✓ starter clonado' "$TMP_ROOT/cdpath-verify.txt" || fail "verify.sh broke with CDPATH set"

# 2. The identity probe never runs in the caller's cwd (another repo's identity).
if grep -Eq '^var ' "$MOCK_GIT_CALLS"; then
  fail "the git identity was probed in the caller's working directory"
fi

# 3. No package job templates: an empty array must not be unbound on bash 3.2.
COPY="$TMP_ROOT/pkg-nojobs"
mkdir -p "$COPY"
(cd "$PKG" && tar cf - --exclude ./.git --exclude ./odd --exclude ./.atl .) | (cd "$COPY" && tar xf -)
rm -f "$COPY"/templates/jobs/*.sh
E="$TMP_ROOT/vault-nojobs"
if ! MOCK_VAULT="$E" MOCK_GIT_CLEAN=1 /bin/bash "$COPY/install.sh" "$E" > "$TMP_ROOT/nojobs.txt" 2>&1; then
  fail "install without job templates failed on /bin/bash: $(grep -m1 -E 'unbound|✗' "$TMP_ROOT/nojobs.txt")"
fi

if ai_brain_need_symlinks "install rechaza brain-config.json y AGENTS.md como symlink"; then
  # 4. A symlinked brain-config.json or a dangling AGENTS.md link is refused before any change.
  printf '{"language":"en"}\n' > "$TMP_ROOT/cfg.json"
  S="$TMP_ROOT/vault-symlink-config"
  mkdir -p "$S/⚙️ Meta"
  printf '{"outside": true}\n' > "$TMP_ROOT/outside.json"
  ln -s "$TMP_ROOT/outside.json" "$S/⚙️ Meta/brain-config.json"
  if install_vault "$S" --config "$TMP_ROOT/cfg.json"; then
    fail "install wrote through a symlinked brain-config.json"
  fi
  grep -Fq '"outside": true' "$TMP_ROOT/outside.json" || fail "install overwrote the symlink target of brain-config.json"
  grep -Fq 'symlink' "$TMP_ROOT/install-vault-symlink-config.txt" || fail "the symlinked brain-config.json refusal was not explained"
  [ ! -e "$S/.opencode" ] || fail "install changed the vault before refusing the symlinked brain-config.json"
  A="$TMP_ROOT/vault-dangling-agents"
  mkdir -p "$A"
  ln -s "$TMP_ROOT/agents-outside.md" "$A/AGENTS.md"
  install_vault "$A" && fail "install accepted a dangling AGENTS.md symlink"
  [ ! -e "$TMP_ROOT/agents-outside.md" ] || fail "install wrote AGENTS.md through a dangling symlink"
fi

# 5. verify.sh: package commands do not stand in for the vendor wiring.
rm "$V/.opencode/commands/brain-journal.md"
bash "$V/scripts/verify.sh" > "$TMP_ROOT/verify-cmd.txt" 2>&1 || true
# Starter commands are copies on every platform now (rewritten for OpenCode), hence "copiados".
grep -Fq '✗ comandos copiados' "$TMP_ROOT/verify-cmd.txt" \
  || fail "verify counted package commands as vendor wiring: $(grep -F 'comandos' "$TMP_ROOT/verify-cmd.txt")"

# 6. verify.sh: a broken link in ⚙️ Meta/scripts is reported.
rm "$V/.opencode/skills/ai-brain-starter/scripts/vendor-job.sh"
bash "$V/scripts/verify.sh" > "$TMP_ROOT/verify-links.txt" 2>&1 || true
grep -Fq '✗ symlinks rotos' "$TMP_ROOT/verify-links.txt" \
  || fail "verify missed a broken link in ⚙️ Meta/scripts"

# 7. verify.sh on Windows: the humanizer clone is not a copied starter skill.
W="$TMP_ROOT/vault-win"
MOCK_UNAME=MINGW64_NT-10.0 install_vault "$W" || fail "Windows fixture install failed"
rm -rf "$W/.opencode/skills/journal"
MOCK_UNAME=MINGW64_NT-10.0 bash "$W/scripts/verify.sh" > "$TMP_ROOT/verify-win.txt" 2>&1 || true
grep -Fq '✗ skills copiadas' "$TMP_ROOT/verify-win.txt" \
  || fail "verify counted the humanizer clone as a copied skill: $(grep -F 'skills' "$TMP_ROOT/verify-win.txt")"

# 8. run_with_timeout returns 2 if called with fewer than 2 arguments.
bash -c ". '$PKG/scripts/lib/common.sh' && run_with_timeout 1" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" = 2 ] || fail "run_with_timeout without command returned $rc (expected 2)"

# 9. run_python lazily initializes pick_python3 when PY3 is unset.
bash -c "unset PY3; . '$PKG/scripts/lib/common.sh'; run_python -c 'import sys; sys.exit(0)'" >/dev/null 2>&1 \
  || fail "run_python failed when PY3 was unset before invocation"

# 10. brain_config.py seed/list/get require argument with clear error message.
cfg_err="$(python3 "$PKG/scripts/lib/brain_config.py" "$TMP_ROOT/dummy.json" seed 2>&1 || true)"
echo "$cfg_err" | grep -Fq 'seed requiere el nombre del vault' \
  || fail "brain_config seed without vault name did not emit clear message (got: $cfg_err)"
cfg_err="$(python3 "$PKG/scripts/lib/brain_config.py" "$TMP_ROOT/dummy.json" list 2>&1 || true)"
echo "$cfg_err" | grep -Fq 'list requiere una clave' \
  || fail "brain_config list without key did not emit clear message (got: $cfg_err)"
cfg_err="$(python3 "$PKG/scripts/lib/brain_config.py" "$TMP_ROOT/dummy.json" get 2>&1 || true)"
echo "$cfg_err" | grep -Fq 'get requiere al menos una clave' \
  || fail "brain_config get without key did not emit clear message (got: $cfg_err)"

# 11. wire.py rejects empty --only flag.
wire_err="$(python3 "$PKG/scripts/lib/wire.py" "$TMP_ROOT/dummy-vault" --only "" 2>&1 || true)"
echo "$wire_err" | grep -Fq 'uso: python3 wire.py' \
  || fail "wire.py accepted empty --only without usage error (got: $wire_err)"

# 12. run_with_timeout terminates child tree and exits 130 on SIGINT.
sig_rc="$(python3 -c '
import os, signal, subprocess, time
p = subprocess.Popen(["bash", "-c", ". \"'"$PKG"'/scripts/lib/common.sh\"; run_with_timeout 10 sleep 30"], preexec_fn=os.setsid)
time.sleep(0.3)
os.killpg(p.pid, signal.SIGINT)
raise SystemExit(p.wait())
' 2>/dev/null || echo $?)"
[ "$sig_rc" = 130 ] || fail "run_with_timeout on SIGINT exited with $sig_rc (expected 130)"

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: shell robustness had %s failures\n' "$failures" >&2
  exit 1
fi
printf 'PASS: CDPATH, empty arrays on bash 3.2, identity probe, symlinked config refused, verify counts\n'
