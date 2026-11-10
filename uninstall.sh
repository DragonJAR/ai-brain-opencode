#!/usr/bin/env bash
# uninstall.sh — removes only unchanged artifacts recorded by this package.
#   bash uninstall.sh <vault-path> [--purge-clones]
set -euo pipefail

VAULT="${1:-}"
PURGE=0
[ "${2:-}" = "--purge-clones" ] && PURGE=1
[ -n "$VAULT" ] || { echo "usage: bash uninstall.sh <vault-path> [--purge-clones]" >&2; exit 1; }
[ -d "$VAULT" ] || { echo "vault does not exist: $VAULT" >&2; exit 1; }
VAULT="$(cd "$VAULT" && pwd)"
PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$VAULT/.opencode/brain-vault-install-manifest.json"

echo "== Removing verified scheduled jobs =="
bash "$PKG/scripts/schedule.sh" "$VAULT" --remove || {
  echo "  ! schedule cleanup failed; remaining package artifacts were preserved" >&2
  exit 1
}

echo "== Removing unchanged package-owned artifacts =="
python3 - "$VAULT" "$MANIFEST" "$PURGE" <<'PY'
import hashlib, json, os, pathlib, shutil, stat, sys

vault = pathlib.Path(sys.argv[1])
manifest = pathlib.Path(sys.argv[2])
purge = sys.argv[3] == "1"

def seal(data):
    body = {key: value for key, value in data.items() if key != "seal"}
    raw = json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()

def file_info(path):
    st = path.stat()
    return {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "mode": stat.S_IMODE(st.st_mode), "nlink": st.st_nlink}

def relative(value):
    path = pathlib.PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or str(path) != value:
        raise ValueError("manifest contains a non-relative path")
    return path

def vault_target(value):
    rel = relative(value)
    target = vault
    for part in rel.parts[:-1]:
        target = target / part
        if target.is_symlink():
            raise ValueError("manifest target traverses a symlinked directory")
    return vault.joinpath(*rel.parts)

def managed_file(value):
    return (value in {".opencode/plugins/brain-vault/index.js", "scripts/verify.sh"}
            or (value.startswith("scripts/jobs/") and value.endswith(".sh")))

def managed_link(value):
    path = relative(value)
    if value == "CLAUDE.md": return True
    if path.parts[:2] == (".opencode", "skills") and len(path.parts) == 3: return True
    if path.parts[:2] == (".opencode", "commands") and len(path.parts) == 3: return True
    return path.parts[:2] == ("⚙️ Meta", "scripts") and len(path.parts) == 3

def tree_hash(root):
    digest = hashlib.sha256()
    root_stat = root.lstat()
    digest.update(b"ROOT\0" + str(stat.S_IFMT(root_stat.st_mode)).encode() + b":"
                  + str(stat.S_IMODE(root_stat.st_mode)).encode() + b":"
                  + str(root_stat.st_nlink).encode() + b"\0")
    for base, dirs, files in os.walk(root, followlinks=False):
        dirs.sort(); files.sort()
        base_path = pathlib.Path(base)
        for name in list(dirs):
            item = base_path / name
            rel = item.relative_to(root).as_posix()
            item_stat = item.lstat()
            metadata = (str(stat.S_IFMT(item_stat.st_mode)) + ":"
                        + str(stat.S_IMODE(item_stat.st_mode)) + ":"
                        + str(item_stat.st_nlink)).encode()
            if stat.S_ISLNK(item_stat.st_mode):
                digest.update(b"L\0" + rel.encode() + b"\0" + metadata + b"\0" + os.readlink(item).encode() + b"\0")
                dirs.remove(name)
            elif stat.S_ISDIR(item_stat.st_mode):
                digest.update(b"D\0" + rel.encode() + b"\0" + metadata + b"\0")
            else:
                digest.update(b"E\0" + rel.encode() + b"\0" + metadata + b"\0")
                dirs.remove(name)
        for name in files:
            item = base_path / name
            rel = item.relative_to(root).as_posix()
            item_stat = item.lstat()
            metadata = (str(stat.S_IFMT(item_stat.st_mode)) + ":"
                        + str(stat.S_IMODE(item_stat.st_mode)) + ":"
                        + str(item_stat.st_nlink)).encode()
            if stat.S_ISLNK(item_stat.st_mode):
                digest.update(b"L\0" + rel.encode() + b"\0" + metadata + b"\0" + os.readlink(item).encode() + b"\0")
            elif stat.S_ISREG(item_stat.st_mode):
                digest.update(b"F\0" + rel.encode() + b"\0" + metadata + b"\0")
                digest.update(hashlib.sha256(item.read_bytes()).digest())
            else:
                digest.update(b"E\0" + rel.encode() + b"\0" + metadata + b"\0")
    return digest.hexdigest()

try:
    if (vault / ".opencode").is_symlink() or manifest.is_symlink() or not manifest.is_file():
        raise ValueError("ownership manifest absent or not a regular file")
    data = json.loads(manifest.read_text(encoding="utf-8"))
    if (data.get("format") != 1 or data.get("owner") != "ai-brain-opencode"
            or not isinstance(data.get("instance"), str) or len(data["instance"]) != 32
            or data.get("seal") != seal(data)):
        raise ValueError("ownership manifest failed validation")
    for key in ("files", "symlinks", "config", "cron_lines", "launch_agents", "trees"):
        if key not in data:
            raise ValueError("ownership manifest is missing " + key)
    if (not all(isinstance(data[key], dict) for key in ("files", "symlinks", "config", "launch_agents", "trees"))
            or not isinstance(data["cron_lines"], list)):
        raise ValueError("ownership manifest has invalid record collections")
except (OSError, ValueError, TypeError, json.JSONDecodeError) as error:
    print("  ! ownership is ambiguous; vault artifacts preserved: " + str(error))
    sys.exit(0)

for value, expected in data["symlinks"].items():
    try:
        if not managed_link(value):
            continue
        target = vault_target(value)
        if target.is_symlink() and os.readlink(target) == expected:
            target.unlink()
            print("  - symlink " + value)
    except (OSError, ValueError):
        pass

for value, expected in data["files"].items():
    try:
        if not managed_file(value):
            continue
        target = vault_target(value)
        if target.is_file() and not target.is_symlink() and file_info(target) == expected:
            target.unlink()
            print("  - file " + value)
        elif target.exists() or target.is_symlink():
            print("  ! modified or unverified file preserved: " + value)
    except (OSError, ValueError):
        pass

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
                print("  - unchanged MCP entry " + name)
            elif name in servers:
                print("  ! modified MCP entry preserved: " + name)
        if config_changed:
            mcp = config.get("mcp", {})
            if not servers:
                mcp.pop("servers", None)
            if not mcp:
                config.pop("mcp", None)
            config_path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    except (OSError, ValueError, TypeError, AttributeError):
        print("  ! opencode.json could not be verified; configuration preserved")

if purge:
    for value, expected in data["trees"].items():
        try:
            if value not in {".opencode/skills/ai-brain-starter", ".opencode/skills/humanizer"}:
                continue
            target = vault_target(value)
            if target.is_dir() and not target.is_symlink() and tree_hash(target) == expected:
                shutil.rmtree(target)
                print("  - unchanged vendor clone " + value)
            elif target.exists() or target.is_symlink():
                print("  ! modified or unverified clone preserved: " + value)
        except (OSError, ValueError):
            pass

for value in (".opencode/plugins/brain-vault", "scripts/jobs"):
    try:
        target = vault_target(value)
        if not target.is_symlink() and target.is_dir():
            target.rmdir()
    except (OSError, ValueError):
        pass

manifest.unlink()
print("  - ownership manifest")
PY

echo
echo "Done. Unowned, modified, and ambiguous content was preserved."
