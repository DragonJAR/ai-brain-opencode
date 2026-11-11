#!/usr/bin/env bash
# uninstall.sh — elimina solo los artefactos sin cambios registrados por este paquete.
#   bash uninstall.sh <ruta-del-vault> [--purge-clones]
#   --purge-clones  además borra los clones vendorizados (ai-brain-starter, humanizer)
#   -h, --help      muestra esta ayuda
set -euo pipefail

warn() { printf '  ! %s\n' "$*"; }
die()  { printf '  ✗ %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,/^set -/p' "$0" | sed '$d'; }

VAULT=""
PURGE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --purge-clones) PURGE=1; shift ;;
    -*) die "flag desconocida: $1 (usa --help)" ;;
    *)
      if [ -n "$VAULT" ]; then
        die "argumento inesperado: $1"
      fi
      VAULT="$1"
      shift
      ;;
  esac
done
[ -n "$VAULT" ] || { usage >&2; exit 1; }
[ -d "$VAULT" ] || die "el vault no existe: $VAULT"
VAULT="$(cd "$VAULT" && pwd)"
PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$VAULT/.opencode/brain-vault-install-manifest.json"

for rel in "scripts" "scripts/jobs" ".opencode" ".opencode/skills" ".opencode/plugins"; do
  if [ -L "$VAULT/$rel" ]; then
    die "$rel/ es un symlink; desinstalación rechazada y manifiesto preservado"
  fi
done

echo "== Eliminando trabajos programados verificados =="
bash "$PKG/scripts/schedule.sh" "$VAULT" --remove || {
  die "falló la limpieza de la programación; se preservaron los artefactos restantes"
}

echo "== Eliminando artefactos del paquete sin cambios =="
[ -f "$PKG/scripts/lib/ownership.py" ] || die "paquete incompleto: falta scripts/lib/ownership.py"
python3 - "$VAULT" "$MANIFEST" "$PURGE" "$PKG/scripts/lib" <<'PY'
import json, os, pathlib, shutil, sys

sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[4])
import ownership

vault = pathlib.Path(sys.argv[1])
manifest = pathlib.Path(sys.argv[2])
purge = sys.argv[3] == "1"

def file_info(path):
    return ownership.file_info(str(path))

def relative(value):
    return pathlib.PurePosixPath(ownership.relative(value))

def vault_target(value):
    rel = relative(value)
    target = vault
    for part in rel.parts[:-1]:
        target = target / part
        if target.is_symlink():
            raise ownership.ManifestError("la ruta atraviesa un directorio que es un symlink")
    return vault.joinpath(*rel.parts)

def managed_file(value):
    return (value in {".opencode/plugins/brain-vault/index.js", "scripts/verify.sh", "scripts/lib/ownership.py", "scripts/lib/python3.sh", "CLAUDE.md"}
            or (value.startswith("scripts/jobs/") and value.endswith((".sh", ".cmd"))))

def managed_link(value):
    path = relative(value)
    if value == "CLAUDE.md": return True
    if path.parts[:2] == (".opencode", "skills") and len(path.parts) == 3: return True
    if path.parts[:2] == (".opencode", "commands") and len(path.parts) == 3: return True
    return path.parts[:2] == ("⚙️ Meta", "scripts") and len(path.parts) == 3

def tree_hash(root):
    return ownership.tree_hash(root)

try:
    if (vault / ".opencode").is_symlink() or manifest.is_symlink() or not manifest.is_file():
        raise ownership.ManifestError("el manifiesto de propiedad no está o no es un archivo regular")
    data = ownership.load(manifest)
    ownership.require_version(data)
except (OSError, ValueError, TypeError, ownership.ManifestError) as error:
    print("  ! propiedad ambigua; se preservaron los artefactos del vault: " + str(error))
    sys.exit(0)

failures = []

def refuse(value, error):
    failures.append(str(value))
    print("  ✗ " + str(value) + ": " + str(error))

def guard(value):
    try:
        vault_target(value)
    except (OSError, ValueError, ownership.ManifestError) as error:
        refuse(value, error)

vendor_clones = {".opencode/skills/ai-brain-starter", ".opencode/skills/humanizer"}
for value in list(data["files"]) + list(data["symlinks"]) + list(data["trees"]):
    if managed_file(value) or managed_link(value) or value in data["trees"]:
        guard(value)
for value in (".opencode/plugins/brain-vault", "scripts/lib", "scripts/jobs", "scripts"):
    guard(value)
if failures:
    print("  ✗ desinstalación rechazada; el manifiesto se preservó")
    sys.exit(1)

for value, expected in data["symlinks"].items():
    try:
        if not managed_link(value):
            continue
        target = vault_target(value)
        if target.is_symlink() and os.readlink(target) == expected:
            target.unlink()
            print("  - enlace " + value)
    except (OSError, ValueError, ownership.ManifestError) as error:
        refuse(value, error)

for value, expected in data["files"].items():
    try:
        if not managed_file(value):
            continue
        target = vault_target(value)
        if target.is_file() and not target.is_symlink() and file_info(target) == expected:
            target.unlink()
            print("  - archivo " + value)
        elif target.exists() or target.is_symlink():
            print("  ! archivo modificado o no verificado, preservado: " + value)
    except (OSError, ValueError, ownership.ManifestError) as error:
        refuse(value, error)

config_path = vault / "opencode.json"
config_changed = False
if not config_path.is_symlink() and config_path.is_file():
    try:
        if config_path.stat().st_nlink != 1:
            raise ValueError("opencode.json has multiple hard links")
        config = json.loads(config_path.read_text(encoding="utf-8"))
        if not isinstance(config, dict):
            raise ValueError("opencode.json root is not an object")
        mcp = config.get("mcp", {})
        if not isinstance(mcp, dict):
            raise ValueError("mcp configuration is not an object")
        servers = mcp.get("servers", {})
        if not isinstance(servers, dict):
            raise ValueError("mcp.servers is not an object")
        for record, expected in data["config"].items():
            if not record.startswith("opencode.json:mcp.servers."):
                continue
            name = record.removeprefix("opencode.json:mcp.servers.")
            if name not in {"granola", "chatprd"}:
                continue
            if servers.get(name) == expected:
                del servers[name]
                config_changed = True
                print("  - entrada MCP sin cambios " + name)
            elif name in servers:
                print("  ! entrada MCP modificada, preservada: " + name)
        if config_changed:
            mcp = config.get("mcp", {})
            if not servers:
                mcp.pop("servers", None)
            if not mcp:
                config.pop("mcp", None)
            config_path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    except (OSError, ValueError, TypeError, AttributeError):
        print("  ! no se pudo verificar opencode.json; configuración preservada")

# Copy-mode wiring trees are package artifacts: they go in a normal uninstall.
# The two vendor clones stay unless --purge-clones (they are re-usable caches).
for value, expected in data["trees"].items():
    try:
        if value in vendor_clones and not purge:
            continue
        target = vault_target(value)
        noun = "clon del vendor" if value in vendor_clones else "árbol copiado"
        if target.is_dir() and not target.is_symlink() and tree_hash(target) == expected:
            shutil.rmtree(target)
            print("  - " + noun + " sin cambios " + value)
        elif target.exists() or target.is_symlink():
            print("  ! " + noun + " modificado o no verificado, preservado: " + value)
    except (OSError, ValueError, ownership.ManifestError) as error:
        refuse(value, error)

for value in (".opencode/plugins/brain-vault", "scripts/lib", "scripts/jobs", "scripts"):
    try:
        target = vault_target(value)
        if not target.is_symlink() and target.is_dir():
            target.rmdir()
    except ownership.ManifestError as error:
        refuse(value, error)
    except (OSError, ValueError):
        pass

if failures:
    print("  ✗ desinstalación incompleta; el manifiesto se preservó")
    sys.exit(1)
manifest.unlink()
print("  - manifiesto de propiedad")
PY

echo
echo "Listo. El contenido sin propiedad, modificado o ambiguo se preservó."
