#!/usr/bin/env python3
"""Ownership manifest for ai-brain-opencode.

Single source of truth for the install manifest: sealing, validation, file and
tree fingerprints, the list of paths the package manages, and every
ownership-preserving change to the vault (install, uninstall, drift report).
install.sh, schedule.sh, uninstall.sh, verify.sh and wire.py all go through it.

Usage:
    python3 ownership.py <manifest-path> <action> [args...]

Actions:
    init            [version]    create the manifest or validate an existing one
    instance                     print the instance id
    install-files   <vault> (<rel> <src> <mode|->)...
                                 copy package files unless the vault owns the
                                 path differently; print how many are managed
    install-link    <vault> <rel> <target>
                                 create a relative symlink (exit 3 if preserved)
    record-file     <rel> <path> store the fingerprint of a file the installer wrote
    record-clone    <rel> <url>  record a vendor git clone by its origin
    adopt-clone     <rel> <url>  convert a legacy fingerprint record of a clone
    configure       <vault> <mcp 0|1>
                                 add the package entries to opencode.json (the deny
                                 rule for vendor skills; the MCP servers if asked);
                                 print created|updated|unchanged, exit 3 if skipped
    ensure-gitignore <vault>     create .gitignore or append the missing package lines
    owned-paths                  print the package-owned vault paths, NUL-separated
    agent-matches   <path>       exit 1 unless a launch agent still matches
    record-agent    <path> <label>
    forget-agent    <path>       drop one launch agent record
    agents-tsv                   print "<path>\t<label>" per launch agent
    cron-json                    print the owned scheduled entries as JSON
    set-cron        <json>       replace the owned scheduled entries
    clear-cron                   forget every scheduled entry
    verify                       print a JSON health summary of the manifest
    drift           <vault>      print "missing <what>" / "modified <what>" lines
    uninstall       <vault> <purge 0|1> <dry-run 0|1>
                                 remove the unchanged owned artifacts
    check-uninstall <vault>      exit 1 unless an uninstall could trust the manifest

Exit codes: 0 ok, 1 invalid/manifest error, 2 legacy manifest (fail closed),
3 an existing path was preserved instead of installed.

`cron_lines` holds the owned scheduled entries: cron lines on POSIX, schtasks
task names on Windows.
"""

import contextlib
import hashlib
import json
import os
import pathlib
import shutil
import stat
import subprocess
import sys
import time
import uuid

sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import vault_layout  # noqa: E402

MANIFEST_REL = ".opencode/brain-vault-install-manifest.json"
REQUIRED_KEYS = ("files", "symlinks", "config", "cron_lines", "launch_agents", "trees")
REQUIRED_DICTS = ("files", "symlinks", "config", "launch_agents", "trees")
# Added after the first sealed format; an older manifest simply lacks them.
OPTIONAL_KEYS = {"clones": dict, "wired": list}
PRESERVED = 3

# --- What the package manages -------------------------------------------------
# One list for install, uninstall and the drift report. A path outside it is
# never removed, whatever the manifest says.
VENDOR_CLONES = tuple(rel for rel, _url, _commit in vault_layout.VENDOR)
VENDOR_PINS = {rel: commit for rel, _url, commit in vault_layout.VENDOR}
STARTER_REL = VENDOR_CLONES[0]
MANAGED_FILES = frozenset({
    ".opencode/plugins/brain-vault/index.js",
    "CLAUDE.md",
    ".gitignore",
    "⚙️ Meta/journal-config.md",
    "scripts/verify.sh",
    "scripts/audit.py",
    "scripts/lib/ownership.py",
    "scripts/lib/python3.sh",
    "scripts/lib/common.sh",
    "scripts/lib/wire.py",
    "scripts/lib/brain_config.py",
    "scripts/lib/vault_layout.py",
    "scripts/lib/brain-config.defaults.json",
})
MANAGED_DIRS = (".opencode/plugins/brain-vault", "scripts/lib", "scripts/jobs", "scripts")
# Vendor and package content wired into the vault: symlinks on POSIX, copies on Windows.
WIRED_DIRS = (".opencode/skills", ".opencode/commands", "⚙️ Meta/scripts")
MCP_SERVERS = tuple(vault_layout.MCP_SERVERS)
MCP_RECORD_PREFIX = "opencode.json:mcp.servers."
SKILL_DENY_PREFIX = "opencode.json:permissions.skill."
CONFIG_CREATED = "opencode.json:created"
OPENCODE_SCHEMA = "https://opencode.ai/config.json"
# Lines the vault .gitignore needs: an existing file is completed, never replaced.
GITIGNORE_LINES = (
    STARTER_REL + "/",
    ".opencode/skills/humanizer/",
    MANIFEST_REL,
    ".obsidian/plugins/",
    ".obsidian/workspace.json",
    ".obsidian/workspace-mobile.json",
    ".trash/",
    ".DS_Store",
    "⚙️ Meta/logs/*.log",
    # The /ingest record is vault content (the audit's queue), not a job log; this negation must come after the line above.
    "!⚙️ Meta/logs/ingest.log",
    "⚙️ Meta/.probe-on",
)


class ManifestError(Exception):
    exit_code = 1


class LegacyManifest(ManifestError):
    exit_code = 2


def configure_stdio():
    """UTF-8 and LF on every platform: the shell parses this output."""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", newline="\n")
        except (AttributeError, ValueError):
            pass


def warn(message):
    print("  ! " + message, file=sys.stderr)


def seal(data):
    body = {key: value for key, value in data.items() if key != "seal"}
    raw = json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def load(path):
    data = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ManifestError("el manifiesto de propiedad no pasó la validación")
    if (data.get("format") != 1 or data.get("owner") != "ai-brain-opencode"
            or not isinstance(data.get("instance"), str) or len(data["instance"]) != 32
            or data.get("seal") != seal(data)):
        raise ManifestError("el manifiesto de propiedad no pasó la validación")
    for key in REQUIRED_KEYS:
        if key not in data:
            raise ManifestError("al manifiesto de propiedad le falta " + key)
    if (not all(isinstance(data[key], dict) for key in REQUIRED_DICTS)
            or not isinstance(data["cron_lines"], list)
            or not all(isinstance(data.setdefault(key, kind()), kind) for key, kind in OPTIONAL_KEYS.items())):
        raise ManifestError("el manifiesto de propiedad tiene colecciones de registros inválidas")
    return data


def require_version(data):
    if type(data.get("cron_ownership_version")) is not int or data["cron_ownership_version"] != 2:
        raise LegacyManifest("propiedad de cron heredada o no soportada; no se migra automáticamente")


def load_current(path):
    data = load(path)
    require_version(data)
    return data


def save(path, data):
    path = pathlib.Path(path)
    data["seal"] = seal(data)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + ".tmp." + str(os.getpid()))
    try:
        with open(temp, "w", encoding="utf-8") as handle:
            handle.write(json.dumps(data, sort_keys=True, indent=2, ensure_ascii=False) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp, 0o600)
        os.replace(temp, path)
    except BaseException:
        try:
            temp.unlink()
        except FileNotFoundError:
            pass
        raise


# --- Manifest lock ---------------------------------------------------------------
# install, uninstall, schedule.sh and the update job (wire.py) all load, change
# and save the manifest; the lock keeps one writer from losing another's records.
LOCK_NAME = ".manifest.lock"
LOCK_STALE_SECONDS = 300


def _pid_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False
    return True


def _lock_is_stale(lock):
    try:
        pid = int((lock / "pid").read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        pid = None
    # On Windows os.kill(pid, 0) terminates the process: only the age counts there.
    if pid is not None and os.name != "nt":
        return not _pid_alive(pid)
    try:
        return time.time() - lock.stat().st_mtime > LOCK_STALE_SECONDS
    except OSError:
        return False


@contextlib.contextmanager
def manifest_lock(manifest):
    lock = pathlib.Path(manifest).parent / LOCK_NAME
    if not lock.parent.is_dir() or lock.parent.is_symlink():
        yield
        return
    deadline = time.monotonic() + float(os.environ.get("BRAIN_MANIFEST_LOCK_TIMEOUT", "60"))
    while True:
        try:
            os.mkdir(lock)
            break
        except FileExistsError:
            if _lock_is_stale(lock):
                stale = lock.with_name(LOCK_NAME + ".stale." + str(os.getpid()))
                try:
                    os.rename(lock, stale)
                    shutil.rmtree(stale, ignore_errors=True)
                except OSError:
                    pass
                continue
            if time.monotonic() >= deadline:
                raise ManifestError("el manifiesto de propiedad está en uso por otro proceso; si ninguno "
                                    "lo usa, borra " + str(lock))
            time.sleep(0.1)
    try:
        (lock / "pid").write_text(str(os.getpid()), encoding="utf-8")
        yield
    finally:
        shutil.rmtree(lock, ignore_errors=True)


def relative(value):
    path = pathlib.PurePosixPath(value)
    if (path.is_absolute() or ".." in path.parts or str(path) != value
            or "\\" in value or ":" in value):
        raise ManifestError("las rutas de propiedad deben ser relativas al vault, sin '..', absolutas, "
                            "barras invertidas ni unidades")
    return value


def safe_target(vault, value):
    """Vault path for a record; refuses to walk through a symlinked directory."""
    parts = pathlib.PurePosixPath(relative(value)).parts
    current = pathlib.Path(vault)
    for part in parts[:-1]:
        current = current / part
        if current.is_symlink():
            raise ManifestError("la ruta atraviesa un directorio que es un symlink")
    target = pathlib.Path(vault).joinpath(*parts)
    # A Windows junction is not a symlink to is_symlink(); resolve() follows it.
    try:
        target.parent.resolve().relative_to(pathlib.Path(vault).resolve())
    except ValueError:
        raise ManifestError("la ruta sale del vault")
    return target


def is_wired(value):
    return str(pathlib.PurePosixPath(value).parent) in WIRED_DIRS


def is_managed_file(value):
    return (value in MANAGED_FILES or is_wired(value)
            or (value.startswith("scripts/jobs/") and value.endswith((".sh", ".cmd"))))


def is_managed_link(value):
    return value == "CLAUDE.md" or is_wired(value)


def file_info(path):
    target = pathlib.Path(path)
    if target.is_symlink() or not target.is_file():
        raise ManifestError("el archivo propio no es un archivo regular")
    st = target.stat()
    return {
        "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
        "mode": stat.S_IMODE(st.st_mode),
        "nlink": st.st_nlink,
    }


def _entry_metadata(item_stat):
    return (str(stat.S_IFMT(item_stat.st_mode)) + ":" + str(stat.S_IMODE(item_stat.st_mode)) + ":"
            + str(item_stat.st_nlink)).encode()


def tree_hash(path):
    root = pathlib.Path(path)
    digest = hashlib.sha256()
    digest.update(b"ROOT\0" + _entry_metadata(root.lstat()) + b"\0")
    for base, dirs, files in os.walk(root, followlinks=False):
        dirs.sort()
        files.sort()
        base_path = pathlib.Path(base)
        for name, listed_as_dir in [(name, True) for name in list(dirs)] + [(name, False) for name in files]:
            item = base_path / name
            rel = item.relative_to(root).as_posix().encode()
            item_stat = item.lstat()
            metadata = _entry_metadata(item_stat)
            if stat.S_ISLNK(item_stat.st_mode):
                digest.update(b"L\0" + rel + b"\0" + metadata + b"\0" + os.readlink(item).encode() + b"\0")
            elif listed_as_dir and stat.S_ISDIR(item_stat.st_mode):
                digest.update(b"D\0" + rel + b"\0" + metadata + b"\0")
                continue
            elif not listed_as_dir and stat.S_ISREG(item_stat.st_mode):
                digest.update(b"F\0" + rel + b"\0" + metadata + b"\0")
                digest.update(hashlib.sha256(item.read_bytes()).digest())
            else:
                digest.update(b"E\0" + rel + b"\0" + metadata + b"\0")
            if listed_as_dir:
                dirs.remove(name)
    return digest.hexdigest()


def new_manifest():
    data = {
        "format": 1,
        "owner": "ai-brain-opencode",
        "instance": uuid.uuid4().hex,
        "cron_ownership_version": 2,
        "cron_lines": [],
    }
    for key in REQUIRED_DICTS:
        data[key] = {}
    for key, kind in OPTIONAL_KEYS.items():
        data[key] = kind()
    return data


def summary(data):
    result = {"valid": True, "instance": data["instance"]}
    for key in REQUIRED_KEYS + tuple(OPTIONAL_KEYS):
        result[key] = len(data[key])
    return result


# --- Ownership-preserving installs --------------------------------------------
# Each put_* returns None when the path is now managed, or the reason it was
# preserved. Nothing the vault owns differently is ever overwritten.

def put_file(data, vault, rel, src, mode=None, transform=None):
    """`transform` (bytes -> bytes) adapts the content; the record is the written file's hash."""
    src = pathlib.Path(src)
    if not src.is_file():
        raise ManifestError("falta " + str(src) + " en el paquete; instalación abortada sin cambios posteriores")
    try:
        dst = safe_target(vault, rel)
    except ManifestError:
        return "directorio padre symlink preservado: " + rel
    if dst.is_symlink():
        return "symlink existente preservado: " + rel
    if dst.exists():
        try:
            owned = data["files"].get(rel) == file_info(dst)
        except ManifestError:
            owned = False
        if not owned:
            return "archivo existente no administrado preservado: " + rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    content = src.read_bytes() if transform is None else transform(src.read_bytes())
    if not dst.exists() or dst.read_bytes() != content:
        if transform is None:
            shutil.copy(src, dst)
        else:
            dst.write_bytes(content)
    if mode is not None:
        os.chmod(dst, mode)
    data["files"][rel] = file_info(dst)
    return None


def put_link(data, vault, rel, target):
    try:
        dst = safe_target(vault, rel)
    except ManifestError:
        return "directorio padre symlink preservado: " + rel
    if dst.is_symlink() or dst.exists():
        if dst.is_symlink() and data["symlinks"].get(rel) == target and os.readlink(dst) == target:
            return None
        return "ruta existente preservada: " + rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    os.symlink(target, dst)
    data["symlinks"][rel] = target
    return None


def put_tree(data, vault, rel, src):
    try:
        dst = safe_target(vault, rel)
    except ManifestError:
        return "directorio padre symlink preservado: " + rel
    if dst.is_symlink():
        return "symlink existente preservado: " + rel
    if dst.exists():
        if not dst.is_dir() or data["trees"].get(rel) != tree_hash(dst):
            return "árbol existente no administrado preservado: " + rel
        shutil.rmtree(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(src, dst, symlinks=True)
    data["trees"][rel] = tree_hash(dst)
    return None


def ensure_gitignore(data, vault):
    """Create .gitignore, or append the package lines an existing one lacks."""
    target = safe_target(vault, ".gitignore")
    if target.is_symlink() or (target.exists() and not target.is_file()):
        return "symlink o ruta no regular preservada: .gitignore"
    if not target.exists():
        target.write_text("\n".join(GITIGNORE_LINES) + "\n", encoding="utf-8")
        data["files"][".gitignore"] = file_info(target)
        print("  + .gitignore")
        return None
    text = target.read_text(encoding="utf-8")
    present = {line.strip() for line in text.splitlines()}
    missing = [line for line in GITIGNORE_LINES if line not in present]
    if not missing:
        return None
    try:
        owned = data["files"].get(".gitignore") == file_info(target)
    except ManifestError:
        owned = False
    prefix = "" if not text or text.endswith("\n") else "\n"
    with open(target, "a", encoding="utf-8") as handle:
        handle.write(prefix + "\n".join(missing) + "\n")
    if owned:
        data["files"][".gitignore"] = file_info(target)
    print("  + .gitignore completado (%d líneas del paquete)" % len(missing))
    return None


def owned_paths(data):
    """Paths the package wrote into the vault; vendor clones are not among them."""
    paths = set(data["files"]) | set(data["symlinks"]) | set(data["trees"])
    return sorted(rel for rel in paths if rel not in VENDOR_CLONES)


# --- Vendor clones --------------------------------------------------------------
# A clone moves with every pinned commit, so it is owned by its origin, not by its
# bytes. It is pristine when deleting it loses nothing: a clean tree, HEAD on the
# pinned commit or on a remote ref, and no local branch ahead of the remote.

def clone_is_pristine(path, origin, pinned=None):
    def git(*args):
        result = subprocess.run(["git", "-C", str(path)] + list(args), stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, universal_newlines=True)
        return result.stdout.strip() if result.returncode == 0 else None
    if path.is_symlink() or not path.is_dir() or not (path / ".git").exists():
        return False
    try:
        if git("config", "--get", "remote.origin.url") != origin or git("status", "--porcelain") != "":
            return False
        head = git("rev-parse", "HEAD")
        head_published = head is not None and (
            head == pinned or git("rev-list", "-n", "1", "HEAD", "--not", "--remotes") == "")
        return head_published and git("rev-list", "-n", "1", "--branches", "--not", "--remotes") == ""
    except OSError:
        return False


# --- Drift report ---------------------------------------------------------------

def _file_matches(expected):
    def matches(target):
        try:
            return file_info(target) == expected
        except ManifestError:
            return False
    return matches


def drift(data, vault):
    """Differences between the manifest and the machine, as (kind, what) pairs."""
    findings = []

    def check(rel, noun, matches):
        try:
            target = safe_target(vault, rel)
            if not target.exists() and not target.is_symlink():
                findings.append(("missing", noun + " " + rel))
            elif not matches(target):
                findings.append(("modified", noun + " " + rel))
        except (OSError, ManifestError):
            findings.append(("modified", noun + " " + rel))

    for rel, expected in data["files"].items():
        check(rel, "archivo", _file_matches(expected))
    for rel, expected in data["symlinks"].items():
        check(rel, "enlace", lambda target, expected=expected: target.is_symlink() and os.readlink(target) == expected)
    for rel, expected in data["trees"].items():
        if rel not in VENDOR_CLONES:
            check(rel, "árbol", lambda target, expected=expected: target.is_dir() and tree_hash(target) == expected)
    for rel in data["clones"]:
        check(rel, "clon", lambda target: (target / ".git").exists())
    for agent_path, entry in data["launch_agents"].items():
        if not os.path.lexists(agent_path):
            findings.append(("missing", "launch agent " + agent_path))
        elif not _file_matches(entry.get("file"))(agent_path):
            findings.append(("modified", "launch agent " + agent_path))
    # cron_lines are schtasks names on Windows and stay empty on macOS.
    if data["cron_lines"] and sys.platform.startswith("linux") and shutil.which("crontab"):
        try:
            listing = subprocess.run(["crontab", "-l"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                     universal_newlines=True)
        except OSError:
            listing = None
        if listing is not None and listing.returncode == 0:
            current = set(listing.stdout.splitlines())
            findings.extend(("missing", "entrada de cron " + line)
                            for line in data["cron_lines"] if line not in current)
    return findings


# --- opencode.json ---------------------------------------------------------------
# The package adds two kinds of entries and records each one, so the uninstall
# removes exactly what it added and nothing the user wrote or changed.

class ConfigSkipped(Exception):
    """opencode.json was left alone; str() is the reason for the user."""


def skill_deny_rule(skill_id):
    return {"action": "skill", "resource": skill_id, "effect": "deny"}


def read_opencode_config(vault):
    """(path, config or None if absent). Raises ConfigSkipped when it must not be touched."""
    path = pathlib.Path(vault) / "opencode.json"
    jsonc = pathlib.Path(vault) / "opencode.jsonc"
    if path.is_symlink():
        raise ConfigSkipped("opencode.json es un symlink; se preservó sin modificarlo")
    if jsonc.exists() or jsonc.is_symlink():
        raise ConfigSkipped("existe opencode.jsonc: no se crea una segunda configuración")
    if not path.exists():
        return path, None
    if not path.is_file() or path.stat().st_nlink != 1:
        raise ConfigSkipped("opencode.json no es un archivo regular o tiene varios enlaces duros")
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
    except ValueError:
        raise ConfigSkipped("opencode.json no es JSON estricto (¿comentarios o comas finales?)")
    if not isinstance(config, dict):
        raise ConfigSkipped("la raíz de opencode.json no es un objeto")
    return path, config


def configure(data, vault, with_mcp):
    """Add the package entries to opencode.json; returns created|updated|unchanged."""
    path, config = read_opencode_config(vault)
    created = config is None
    if created:
        config = {"$schema": OPENCODE_SCHEMA}
    changed = False
    rules = config.get("permissions", [])
    if not isinstance(rules, list):
        raise ConfigSkipped("`permissions` de opencode.json no es una lista")
    for skill_id in vault_layout.DENIED_SKILLS:
        rule = skill_deny_rule(skill_id)
        if rule not in rules:
            rules.append(rule)
            config["permissions"] = rules
            data["config"][SKILL_DENY_PREFIX + skill_id] = rule
            changed = True
    if with_mcp:
        mcp = config.get("mcp", {})
        servers = mcp.get("servers", {}) if isinstance(mcp, dict) else None
        if not isinstance(servers, dict):
            raise ConfigSkipped("`mcp.servers` de opencode.json no es un objeto")
        for name, url in vault_layout.MCP_SERVERS.items():
            if name not in servers:
                servers[name] = {"type": "remote", "url": url}
                mcp["servers"] = servers
                config["mcp"] = mcp
                data["config"][MCP_RECORD_PREFIX + name] = servers[name]
                changed = True
    if not changed:
        return "unchanged"
    if created:
        data["config"][CONFIG_CREATED] = True
    path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return "created" if created else "updated"


def unconfigure(data, vault, dry_run, gone):
    """Remove the recorded entries that are still exactly as the package wrote them."""
    try:
        path, config = read_opencode_config(vault)
    except ConfigSkipped:
        print("  ! no se pudo verificar opencode.json; configuración preservada")
        return
    if config is None:
        return
    try:
        mcp = config.get("mcp", {})
        servers = mcp.get("servers", {}) if isinstance(mcp, dict) else {}
        rules = config.get("permissions", [])
        if not isinstance(servers, dict) or not isinstance(rules, list):
            raise ValueError("unexpected shape")
        changed = False
        for record, expected in data["config"].items():
            if record.startswith(MCP_RECORD_PREFIX) and record[len(MCP_RECORD_PREFIX):] in MCP_SERVERS:
                name = record[len(MCP_RECORD_PREFIX):]
                if servers.get(name) == expected:
                    del servers[name]
                    changed = True
                    print("  " + gone + " entrada MCP sin cambios " + name)
                elif name in servers:
                    print("  ! entrada MCP modificada, preservada: " + name)
            elif record.startswith(SKILL_DENY_PREFIX) and expected in rules:
                rules.remove(expected)
                changed = True
                print("  " + gone + " regla que oculta el skill " + record[len(SKILL_DENY_PREFIX):])
        if not changed or dry_run:
            return
        if isinstance(mcp, dict) and not servers:
            mcp.pop("servers", None)
        if not mcp:
            config.pop("mcp", None)
        if not rules:
            config.pop("permissions", None)
        # A file the package created and that holds nothing else goes with it.
        if data["config"].get(CONFIG_CREATED) is True and config == {"$schema": OPENCODE_SCHEMA}:
            path.unlink()
        else:
            path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    except (OSError, ValueError, TypeError, AttributeError):
        print("  ! no se pudo verificar opencode.json; configuración preservada")


# --- Uninstall ------------------------------------------------------------------

def load_for_uninstall(manifest, vault):
    """The manifest an uninstall may trust, or ManifestError: nothing is provable without it."""
    try:
        if (vault / ".opencode").is_symlink() or manifest.is_symlink() or not manifest.is_file():
            raise ManifestError("el manifiesto de propiedad no está o no es un archivo regular")
        return load_current(manifest)
    except (OSError, ValueError, TypeError, AttributeError) as error:
        raise ManifestError(str(error))


def uninstall(manifest, vault, purge, dry_run):
    vault = pathlib.Path(vault)
    manifest = pathlib.Path(manifest)
    try:
        data = load_for_uninstall(manifest, vault)
    except ManifestError as error:
        print("  ✗ propiedad no demostrable; no se eliminó nada: " + str(error))
        return 1

    failures = []
    gone = "~" if dry_run else "-"

    def refuse(value, error):
        failures.append(str(value))
        print("  ✗ " + str(value) + ": " + str(error))

    def guard(value):
        try:
            safe_target(vault, value)
        except (OSError, ValueError, ManifestError) as error:
            refuse(value, error)

    for value in list(data["files"]) + list(data["symlinks"]):
        if is_managed_file(value) or is_managed_link(value):
            guard(value)
    for value in list(data["trees"]) + list(data["clones"]) + list(MANAGED_DIRS):
        guard(value)
    if failures:
        print("  ✗ desinstalación rechazada; el manifiesto se preservó")
        return 1

    for value, expected in data["symlinks"].items():
        try:
            if not is_managed_link(value):
                continue
            target = safe_target(vault, value)
            if target.is_symlink() and os.readlink(target) == expected:
                if not dry_run:
                    target.unlink()
                print("  " + gone + " enlace " + value)
        except (OSError, ValueError, ManifestError) as error:
            refuse(value, error)

    def remove_file(value, expected):
        try:
            target = safe_target(vault, value)
            if target.is_file() and not target.is_symlink() and file_info(target) == expected:
                if not dry_run:
                    target.unlink()
                print("  " + gone + " archivo " + value)
            elif target.exists() or target.is_symlink():
                print("  ! archivo modificado o no verificado, preservado: " + value)
        except (OSError, ValueError, ManifestError) as error:
            refuse(value, error)

    # .gitignore hides the vendor clones: it goes last, and only if none remains.
    for value, expected in data["files"].items():
        if is_managed_file(value) and value != ".gitignore":
            remove_file(value, expected)

    unconfigure(data, vault, dry_run, gone)

    def remove_tree(value, noun, unchanged):
        try:
            target = safe_target(vault, value)
            if unchanged(target):
                if not dry_run:
                    shutil.rmtree(target)
                print("  " + gone + " " + noun + " sin cambios " + value)
            elif target.exists() or target.is_symlink():
                print("  ! " + noun + " modificado o no verificado, preservado: " + value)
        except (OSError, ValueError, ManifestError) as error:
            refuse(value, error)

    # Copy-mode wiring trees are package artifacts: they go in a normal uninstall.
    # The vendor clones stay unless --purge-clones (they are re-usable caches).
    for value, expected in data["trees"].items():
        is_clone = value in VENDOR_CLONES
        if is_clone and (not purge or value in data["clones"]):
            continue
        remove_tree(value, "clon del vendor" if is_clone else "árbol copiado",
                    lambda target, expected=expected: (target.is_dir() and not target.is_symlink()
                                                       and tree_hash(target) == expected))
    if purge:
        for value, origin in data["clones"].items():
            if value in VENDOR_CLONES:
                remove_tree(value, "clon del vendor",
                            lambda target, origin=origin, value=value:
                                clone_is_pristine(target, origin, VENDOR_PINS.get(value)))

    if ".gitignore" in data["files"]:
        remaining = [rel for rel in VENDOR_CLONES
                     if os.path.lexists(str(vault.joinpath(*pathlib.PurePosixPath(rel).parts)))]
        if remaining:
            print("  ! .gitignore preservado: quedan clones del vendor (" + ", ".join(remaining) + ")")
        else:
            remove_file(".gitignore", data["files"][".gitignore"])

    if not dry_run:
        for value in MANAGED_DIRS:
            try:
                target = safe_target(vault, value)
                if not target.is_symlink() and target.is_dir():
                    target.rmdir()
            except ManifestError as error:
                refuse(value, error)
            except (OSError, ValueError):
                pass

    if failures:
        print("  ✗ desinstalación incompleta; el manifiesto se preservó")
        return 1
    if dry_run:
        print("  ~ manifiesto de propiedad")
        print("  (dry-run) no se eliminó nada")
        return 0
    manifest.unlink()
    print("  - manifiesto de propiedad")
    return 0


# --- CLI ------------------------------------------------------------------------

def dispatch(path, action, argv):
    if action == "init":
        version = argv[0] if argv else None
        if path.exists() or path.is_symlink():
            if path.is_symlink():
                raise ManifestError("el manifiesto de propiedad es un symlink; no se sigue")
            data = load_current(path)
            if version is None or data.get("package_version") == version:
                return 0
        else:
            data = new_manifest()
        if version is not None:
            data["package_version"] = version
        save(path, data)
        return 0

    if action == "uninstall":
        return uninstall(path, argv[0], argv[1] == "1", argv[2] == "1")
    if action == "check-uninstall":
        load_for_uninstall(path, pathlib.Path(argv[0]))
        return 0

    data = load(path)

    if action == "instance":
        print(data["instance"])
        return 0

    require_version(data)

    if action == "verify":
        print(json.dumps(summary(data), sort_keys=True, separators=(",", ":")))
    elif action == "drift":
        for kind, what in drift(data, argv[0]):
            print(kind + " " + what)
    elif action == "install-files":
        vault, entries = argv[0], argv[1:]
        if len(entries) % 3 != 0:
            raise ManifestError("install-files espera tríos <ruta> <origen> <modo|->")
        managed = 0
        try:
            for rel, src, mode in zip(entries[0::3], entries[1::3], entries[2::3]):
                reason = put_file(data, vault, relative(rel), src, None if mode == "-" else int(mode, 8))
                if reason is None:
                    managed += 1
                else:
                    warn(reason)
        finally:
            save(path, data)
        print(managed)
    elif action == "ensure-gitignore":
        reason = ensure_gitignore(data, argv[0])
        if reason is not None:
            warn(reason)
            return PRESERVED
        save(path, data)
    elif action == "owned-paths":
        for rel in owned_paths(data):
            sys.stdout.write(rel + "\0")
    elif action == "install-link":
        reason = put_link(data, argv[0], relative(argv[1]), argv[2])
        if reason is not None:
            warn(reason)
            return PRESERVED
        save(path, data)
    elif action == "record-file":
        data["files"][relative(argv[0])] = file_info(argv[1])
        save(path, data)
    elif action == "record-clone":
        data["clones"][relative(argv[0])] = argv[1]
        data["trees"].pop(argv[0], None)
        save(path, data)
    elif action == "adopt-clone":
        # Only a clone this install created (it has a legacy fingerprint record).
        if argv[0] in data["trees"]:
            data["clones"][relative(argv[0])] = argv[1]
            del data["trees"][argv[0]]
            save(path, data)
    elif action == "configure":
        try:
            status = configure(data, argv[0], argv[1] == "1")
        except ConfigSkipped as skipped:
            warn(str(skipped))
            return PRESERVED
        if status != "unchanged":
            save(path, data)
        print(status)
    elif action == "agent-matches":
        entry = data["launch_agents"].get(argv[0])
        if entry is None or not _file_matches(entry.get("file"))(argv[0]):
            return 1
    elif action == "record-agent":
        data["launch_agents"][argv[0]] = {"label": argv[1], "file": file_info(argv[0])}
        save(path, data)
    elif action == "forget-agent":
        if data["launch_agents"].pop(argv[0], None) is not None:
            save(path, data)
    elif action == "agents-tsv":
        for agent_path, entry in data["launch_agents"].items():
            print(agent_path + "\t" + entry["label"])
    elif action == "cron-json":
        print(json.dumps(data["cron_lines"], ensure_ascii=False, separators=(",", ":")))
    elif action == "set-cron":
        value = json.loads(argv[0])
        if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
            raise ManifestError("set-cron expects a JSON array of strings")
        data["cron_lines"] = value
        save(path, data)
    elif action == "clear-cron":
        data["cron_lines"] = []
        save(path, data)
    else:
        raise ManifestError("acción de propiedad desconocida: " + action)
    return 0


def main(argv):
    configure_stdio()
    if len(argv) < 2:
        print("uso: python3 ownership.py <manifiesto> <acción> [args...]", file=sys.stderr)
        return 1
    path = pathlib.Path(argv[0])
    action = argv[1]
    try:
        with manifest_lock(path):
            return dispatch(path, action, argv[2:])
    except LegacyManifest as error:
        if action == "cron-json":
            print("propiedad de cron heredada o no soportada; no se confían las entradas programadas", file=sys.stderr)
        else:
            print("fallo: " + str(error), file=sys.stderr)
        return error.exit_code
    except ManifestError as error:
        print("fallo: " + str(error), file=sys.stderr)
        return error.exit_code
    except (OSError, ValueError, TypeError, AttributeError, IndexError, json.JSONDecodeError) as error:
        print("fallo: " + str(error), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("fallo: interrumpido", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
