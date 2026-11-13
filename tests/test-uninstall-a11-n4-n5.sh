#!/usr/bin/env bash
# Uninstall leaves no empty scripts/; flow messages are Spanish.
# scripts/ replaced by symlink → exit ≠ 0, manifest preserved.
# --purge-clones accepted in any position; --bogus rejected.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

TMP_ROOT="$(ai_brain_test_root uninstall-guards)"
trap 'rm -rf "$TMP_ROOT"' EXIT

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

setup_install_env() {
  local root="$1"
  mkdir -p "$root/bin" "$root/vault"
  MOCK_UNAME=Linux
  MOCK_GIT_CALLS="$root/git-calls.log"
  MOCK_CRONTAB_STATE="$root/crontab-state"
  MOCK_CRONTAB_CALLS="$root/crontab-calls.log"
  MOCK_CRONTAB_WRITES="$root/crontab-writes.log"
  MOCK_VAULT="$root/vault"
  : > "$MOCK_GIT_CALLS"
  : > "$MOCK_CRONTAB_CALLS"
  : > "$MOCK_CRONTAB_WRITES"
  : > "$MOCK_CRONTAB_STATE"
  ai_brain_mock_platform "$root/bin"
  ai_brain_mock_crontab "$root/bin"
  ai_brain_mock_git "$root/bin"
  ai_brain_mock_opencode "$root/bin"
  export MOCK_UNAME MOCK_GIT_CALLS MOCK_CRONTAB_STATE MOCK_CRONTAB_CALLS MOCK_CRONTAB_WRITES MOCK_VAULT
  export PATH="$root/bin:$PATH"
  export TMPDIR="$root"
  unset BRAIN_STARTER_PIN || true
}

# --- Flag parser -------------------------------------------------------------
FLAG_ROOT="$TMP_ROOT/flags"
setup_install_env "$FLAG_ROOT"
VAULT_FLAG="$FLAG_ROOT/vault"
mkdir -p "$VAULT_FLAG"

set +e
bash "$PKG/uninstall.sh" --bogus "$VAULT_FLAG" >"$FLAG_ROOT/bogus-out.txt" 2>"$FLAG_ROOT/bogus-err.txt"
bogus_rc=$?
bash "$PKG/uninstall.sh" "$VAULT_FLAG" --bogus >"$FLAG_ROOT/bogus2-out.txt" 2>"$FLAG_ROOT/bogus2-err.txt"
bogus2_rc=$?
set -e
if [ "$bogus_rc" -eq 0 ] || [ "$bogus2_rc" -eq 0 ]; then
  fail "uninstall --bogus exited 0"
fi
if ! grep -q 'flag desconocida' "$FLAG_ROOT/bogus-err.txt" "$FLAG_ROOT/bogus-out.txt" \
  "$FLAG_ROOT/bogus2-err.txt" "$FLAG_ROOT/bogus2-out.txt" 2>/dev/null; then
  fail "missing flag desconocida for --bogus"
fi

# --purge-clones accepted before and after vault (needs a real install first)
if ! bash "$PKG/install.sh" "$VAULT_FLAG" >"$FLAG_ROOT/install.txt" 2>&1; then
  fail "flag-parser fixture install failed"
  cat "$FLAG_ROOT/install.txt" >&2
else
  MANIFEST_FLAG="$VAULT_FLAG/.opencode/brain-vault-install-manifest.json"
  [ -f "$MANIFEST_FLAG" ] || fail "install did not create ownership manifest"

  # Flag before vault path
  VAULT_FLAG_B="$FLAG_ROOT/vault-b"
  mkdir -p "$VAULT_FLAG_B"
  MOCK_VAULT="$VAULT_FLAG_B"
  if ! bash "$PKG/install.sh" "$VAULT_FLAG_B" >"$FLAG_ROOT/install-b.txt" 2>&1; then
    fail "second fixture install failed"
  else
    set +e
    bash "$PKG/uninstall.sh" --purge-clones "$VAULT_FLAG_B" >"$FLAG_ROOT/purge-before.txt" 2>"$FLAG_ROOT/purge-before.err"
    purge_before_rc=$?
    set -e
    if [ "$purge_before_rc" -ne 0 ]; then
      fail "--purge-clones before vault rejected (rc=$purge_before_rc)"
      cat "$FLAG_ROOT/purge-before.txt" "$FLAG_ROOT/purge-before.err" >&2
    fi
  fi

  # Flag after vault path
  set +e
  bash "$PKG/uninstall.sh" "$VAULT_FLAG" --purge-clones >"$FLAG_ROOT/purge-after.txt" 2>"$FLAG_ROOT/purge-after.err"
  purge_after_rc=$?
  set -e
  if [ "$purge_after_rc" -ne 0 ]; then
    fail "--purge-clones after vault rejected (rc=$purge_after_rc)"
    cat "$FLAG_ROOT/purge-after.txt" "$FLAG_ROOT/purge-after.err" >&2
  fi
fi

# --- No empty scripts/; Spanish messages -------------------------------------
ES_ROOT="$TMP_ROOT/spanish-empty"
setup_install_env "$ES_ROOT"
VAULT_ES="$ES_ROOT/vault"
mkdir -p "$VAULT_ES"
if ! bash "$PKG/install.sh" "$VAULT_ES" >"$ES_ROOT/install.txt" 2>&1; then
  fail "spanish/empty-scripts fixture install failed"
  cat "$ES_ROOT/install.txt" >&2
else
  # Keep a user file under scripts/ so the tree is not solely package-owned empties.
  mkdir -p "$VAULT_ES/scripts"
  printf 'user keep\n' > "$VAULT_ES/scripts/user-keep.txt"

  set +e
  bash "$PKG/uninstall.sh" "$VAULT_ES" >"$ES_ROOT/uninstall.txt" 2>"$ES_ROOT/uninstall.err"
  es_rc=$?
  set -e
  cat "$ES_ROOT/uninstall.txt" "$ES_ROOT/uninstall.err" >"$ES_ROOT/uninstall.all"

  if [ "$es_rc" -ne 0 ]; then
    fail "uninstall exited $es_rc"
    cat "$ES_ROOT/uninstall.all" >&2
  fi

  # Spanish flow markers (not English leftovers).
  if ! grep -Fq 'Eliminando' "$ES_ROOT/uninstall.all"; then
    fail "uninstall output missing Spanish section headers"
  fi
  if ! grep -Fq 'Listo. El contenido sin propiedad, modificado o ambiguo se preservó.' "$ES_ROOT/uninstall.all"; then
    fail "uninstall missing Spanish completion message"
  fi
  if grep -Eiq 'ownership manifest absent|removing scheduled|Done\.|preserved artifacts' "$ES_ROOT/uninstall.all"; then
    fail "uninstall emitted English flow messages"
  fi

  if [ -d "$VAULT_ES/scripts" ]; then
    # Directory may remain for user content, but must not be empty.
    if [ -z "$(find "$VAULT_ES/scripts" -mindepth 1 -print -quit)" ]; then
      fail "left an empty scripts/ directory"
    fi
    if [ ! -f "$VAULT_ES/scripts/user-keep.txt" ]; then
      fail "removed user file under scripts/"
    fi
  fi
fi

# --- scripts/ symlink refuse: exit ≠ 0, manifest preserved, owned file intact -
# Minimal sealed vault + scripts/ → symlink; expect exit≠0, byte-identical
# manifest, owned.sh intact, and the verified refusal strings.
if ai_brain_need_symlinks "uninstall rechaza scripts/ reemplazado por un symlink"; then
  SYMLINK_ROOT="$TMP_ROOT/symlink-refuse"
  # schedule --remove needs a mocked Linux crontab so uninstall reaches the Python guard.
  setup_install_env "$SYMLINK_ROOT"
  V="$SYMLINK_ROOT/vault"
  mkdir -p "$V/scripts/jobs" "$V/.opencode"
  printf '#!/usr/bin/env bash\necho owned\n' > "$V/scripts/jobs/owned.sh"
  chmod 755 "$V/scripts/jobs/owned.sh"

  python3 - "$V" <<'PY'
import hashlib, json, pathlib, stat, sys
vault = pathlib.Path(sys.argv[1]); target = vault/"scripts/jobs/owned.sh"; st = target.stat()
data = {"format": 1, "owner": "ai-brain-opencode", "instance": "a"*32, "cron_ownership_version": 2,
        "files": {"scripts/jobs/owned.sh": {"sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                                            "mode": stat.S_IMODE(st.st_mode), "nlink": st.st_nlink}},
        "symlinks": {}, "config": {}, "cron_lines": [], "launch_agents": {}, "trees": {}}
body = {k: v for k, v in data.items() if k != "seal"}
data["seal"] = hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
(vault/".opencode/brain-vault-install-manifest.json").write_text(
    json.dumps(data, sort_keys=True, indent=2, ensure_ascii=False)+"\n", encoding="utf-8")
PY

  MANIFEST_SYMLINK="$V/.opencode/brain-vault-install-manifest.json"
  cp "$MANIFEST_SYMLINK" "$SYMLINK_ROOT/mf.before"
  mv "$V/scripts" "$SYMLINK_ROOT/moved-scripts"
  ln -s "$SYMLINK_ROOT/moved-scripts" "$V/scripts"

  set +e
  bash "$PKG/uninstall.sh" "$V" >"$SYMLINK_ROOT/uninstall.txt" 2>"$SYMLINK_ROOT/uninstall.err"
  symlink_rc=$?
  set -e
  cat "$SYMLINK_ROOT/uninstall.txt" "$SYMLINK_ROOT/uninstall.err" >"$SYMLINK_ROOT/uninstall.all"

  if [ "$symlink_rc" -eq 0 ]; then
    fail "uninstall exited 0 despite scripts/ symlink"
  fi
  if [ ! -f "$MANIFEST_SYMLINK" ] || ! cmp -s "$MANIFEST_SYMLINK" "$SYMLINK_ROOT/mf.before"; then
    fail "manifest not byte-identical after symlink refusal"
  fi
  if [ ! -f "$SYMLINK_ROOT/moved-scripts/jobs/owned.sh" ]; then
    fail "owned.sh was removed through the scripts/ symlink"
  fi
  # Refusal must mention symlink and state that uninstall was rejected / manifest preserved.
  # Live product may phrase the guard as either the path-traversal form or the
  # shorter "scripts/ es un symlink; …" form verified against this tree.
  if ! grep -Eq 'symlink' "$SYMLINK_ROOT/uninstall.all"; then
    fail "missing symlink mention in refusal"
    cat "$SYMLINK_ROOT/uninstall.all" >&2
  fi
  if ! grep -Fq 'desinstalación rechazada' "$SYMLINK_ROOT/uninstall.all" \
    || ! grep -Eq 'manifiesto preserv' "$SYMLINK_ROOT/uninstall.all"; then
    fail "missing desinstalación rechazada / manifiesto preservado"
    cat "$SYMLINK_ROOT/uninstall.all" >&2
  fi
fi

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: uninstall guards had %s failed assertions\n' "$failures" >&2
  exit 1
fi
printf 'PASS: uninstall leaves no empty scripts/ (Spanish); refuses scripts/ symlink; accepts purge/rejects bogus\n'
