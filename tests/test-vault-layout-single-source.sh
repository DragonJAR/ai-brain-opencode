#!/usr/bin/env bash
# scripts/lib/vault_layout.py is the only list of vault folders and remote MCP
# servers. install.sh creates exactly its folders, verify.sh checks its roots,
# audit.py and ownership.py import it, --with-mcp writes exactly its servers,
# and the plugin's FOLDER_TYPES (a JS copy: the plugin cannot import Python)
# must equal its NOTE_TYPES.
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

TMP_ROOT="$(ai_brain_test_root vault-layout)"
trap 'rm -rf "$TMP_ROOT"' EXIT
LAYOUT="$PKG/scripts/lib/vault_layout.py"

if [ ! -f "$LAYOUT" ]; then
  fail "scripts/lib/vault_layout.py does not exist"
  printf 'FAIL: vault layout single source had %s failures\n' "$failures" >&2
  exit 1
fi

# 1. Python consumers use the module's objects, not their own copies.
python3 - "$PKG/scripts" <<'PY' || fail "a Python consumer keeps its own folder or MCP list"
import sys
sys.dont_write_bytecode = True
sys.path[:0] = [sys.argv[1] + "/lib", sys.argv[1]]
import audit, ownership, vault_layout as layout
assert audit.TYPED_FOLDERS is layout.TYPED_FOLDERS, "audit.TYPED_FOLDERS"
assert audit.CONTENT_FOLDERS_FOR_ORPHANS is layout.ORPHAN_FOLDERS, "audit.CONTENT_FOLDERS_FOR_ORPHANS"
assert audit.RAW_PREFIX == layout.RAW_PREFIX, "audit.RAW_PREFIX"
assert tuple(ownership.MCP_SERVERS) == tuple(layout.MCP_SERVERS), "ownership.MCP_SERVERS"
for prefix in layout.TYPED_FOLDERS + layout.ORPHAN_FOLDERS + tuple(p for p, _ in layout.NOTE_TYPES):
    assert prefix.endswith("/") and any((f + "/").startswith(prefix) for f in layout.FOLDERS), \
        "prefix outside FOLDERS: " + prefix
PY

# 1b. The Vault Map written into AGENTS.md describes exactly the canonical roots.
python3 - "$PKG/scripts/lib" "$PKG/install.sh" <<'PY' || fail "the Vault Map in install.sh drifted from vault_layout roots"
import pathlib, re, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import vault_layout as layout
text = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
block = re.search(r'vault_map = """(.*?)"""', text, re.S).group(1)
described = re.findall(r"^- (.+?)/ — ", block, re.M)
assert described == list(layout.roots()), "Vault Map: %s\nroots: %s" % (described, list(layout.roots()))
PY

# 2. The plugin's JS copy equals NOTE_TYPES, order included (first match wins).
if command -v node >/dev/null; then
  python3 -c 'import json, sys; sys.path.insert(0, sys.argv[1]); import vault_layout as l; print(json.dumps(l.NOTE_TYPES, ensure_ascii=False))' \
    "$PKG/scripts/lib" > "$TMP_ROOT/py-types.json"
  node - "$PKG/plugin/brain-vault/index.js" "$TMP_ROOT/js-types.json" <<'JS' || fail "could not read FOLDER_TYPES from the plugin"
const { readFileSync, writeFileSync } = require("node:fs")
const src = readFileSync(process.argv[2], "utf8")
const start = src.indexOf("const FOLDER_TYPES = ")
const end = src.indexOf("].map(", start)
if (start < 0 || end < 0) process.exit(1)
const types = Function("return (" + src.slice(start + "const FOLDER_TYPES = ".length, end + 1) + ")")()
writeFileSync(process.argv[3], JSON.stringify(types))
JS
  python3 - "$TMP_ROOT/py-types.json" "$TMP_ROOT/js-types.json" <<'PY' || fail "plugin FOLDER_TYPES drifted from vault_layout.NOTE_TYPES"
import json, sys
py, js = (json.load(open(path, encoding="utf-8")) for path in sys.argv[1:])
if py != js:
    raise SystemExit("python=%s\njs=%s" % (py, js))
PY
else
  printf 'SKIP: node no disponible; anti-drift del plugin omitido\n'
fi

# 3. A fresh install creates exactly the canonical folders and the canonical MCP servers.
BIN="$TMP_ROOT/bin"
ai_brain_mock_platform "$BIN"
ai_brain_mock_git "$BIN"
ai_brain_mock_opencode "$BIN"
V="$TMP_ROOT/vault"
if ! MOCK_UNAME=Linux MOCK_GIT_CLEAN=1 MOCK_VAULT="$V" BRAIN_STARTER_UPDATE=0 PATH="$BIN:/usr/bin:/bin" TMPDIR="$TMP_ROOT" \
     bash "$PKG/install.sh" "$V" --with-mcp > "$TMP_ROOT/install.out" 2>&1; then
  fail "install failed: $(tail -3 "$TMP_ROOT/install.out")"
fi
python3 - "$PKG/scripts/lib" "$V" <<'PY' || fail "install did not create exactly the canonical folders and MCP servers"
import json, os, pathlib, sys
sys.path.insert(0, sys.argv[1])
import vault_layout as layout
vault = pathlib.Path(sys.argv[2])
made = sorted(str(p.parent.relative_to(vault).as_posix()) for p in vault.rglob(".gitkeep")
              if not p.parent.relative_to(vault).as_posix().startswith(".opencode/"))
if made != sorted(layout.FOLDERS):
    raise SystemExit("created=%s\ncanonical=%s" % (made, sorted(layout.FOLDERS)))
servers = json.loads((vault / "opencode.json").read_text(encoding="utf-8"))["mcp"]["servers"]
expected = {name: {"type": "remote", "url": url} for name, url in layout.MCP_SERVERS.items()}
if servers != expected:
    raise SystemExit("servers=%s" % servers)
PY

# 4. verify.sh checks one folder per canonical root; the help names every MCP server.
mkdir -p "$TMP_ROOT/vbin"
ai_brain_mock_opencode "$TMP_ROOT/vbin"
(cd "$V" && PATH="$TMP_ROOT/vbin:/usr/bin:/bin:$PATH" bash scripts/verify.sh > "$TMP_ROOT/verify.out" 2>&1) || true
roots="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import vault_layout as l; print("\n".join(l.roots()))' "$PKG/scripts/lib")"
checked="$(sed -n 's/^  [✓✗] carpeta //p' "$TMP_ROOT/verify.out")"
[ "$checked" = "$roots" ] || fail "verify.sh folders differ from the canonical roots: $(printf '%s' "$checked" | tr '\n' '|')"
for name in $(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import vault_layout as l; print(" ".join(l.MCP_SERVERS))' "$PKG/scripts/lib"); do
  bash "$PKG/install.sh" --help | grep -q "$name" || fail "install.sh --help does not name the MCP server $name"
done

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: vault layout single source had %s failures\n' "$failures" >&2
  exit 1
fi
printf 'PASS: vault folders and MCP servers come from scripts/lib/vault_layout.py\n'
