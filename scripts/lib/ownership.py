#!/usr/bin/env python3
"""Ownership manifest for ai-brain-opencode.

Single source of truth for the install manifest: sealing, validation, file and
tree fingerprints, and the record/query actions used by install.sh,
schedule.sh and uninstall.sh.

Usage:
    python3 ownership.py <manifest-path> <action> [args...]

Actions:
    init                         create the manifest or validate an existing one
    instance                     print the instance id
    file-matches    <rel> <path> exit 1 unless <path> still matches its record
    record-file     <rel> <path> store the fingerprint of a regular file
    record-links    <rel> <dst> [<rel> <dst> ...]
                                 store several symlink records in one write
    link-matches    <rel> <target> <path>
                                 exit 1 unless the symlink record and target match
    record-link     <rel> <path> store a symlink record
    record-config   <json>       store MCP entries added to opencode.json
    record-tree     <rel> <path> store the fingerprint of a vendor clone
    agent-matches   <path>       exit 1 unless a launch agent still matches
    record-agent    <path> <label>
    agents-tsv                   print "<path>\t<label>" per launch agent
    clear-agents                 forget every launch agent record
    cron-json                    print the owned crontab lines as JSON
    set-cron        <json>       replace the owned crontab lines
    clear-cron                   forget every crontab line record
    verify                       print a JSON health summary of the manifest

Exit codes: 0 ok, 1 invalid/manifest error, 2 legacy manifest (fail closed).
"""

import hashlib
import json
import os
import pathlib
import stat
import sys
import uuid

REQUIRED_KEYS = ("files", "symlinks", "config", "cron_lines", "launch_agents", "trees")
REQUIRED_DICTS = ("files", "symlinks", "config", "launch_agents", "trees")


class ManifestError(Exception):
    exit_code = 1


class LegacyManifest(ManifestError):
    exit_code = 2


def seal(data):
    body = {key: value for key, value in data.items() if key != "seal"}
    raw = json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def load(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    if (data.get("format") != 1 or data.get("owner") != "ai-brain-opencode"
            or not isinstance(data.get("instance"), str) or len(data["instance"]) != 32
            or data.get("seal") != seal(data)):
        raise ManifestError("ownership manifest failed validation")
    for key in REQUIRED_KEYS:
        if key not in data:
            raise ManifestError("ownership manifest is missing " + key)
    if (not all(isinstance(data[key], dict) for key in REQUIRED_DICTS)
            or not isinstance(data["cron_lines"], list)):
        raise ManifestError("ownership manifest has invalid record collections")
    return data


def require_version(data):
    if type(data.get("cron_ownership_version")) is not int or data["cron_ownership_version"] != 2:
        raise LegacyManifest("legacy or unsupported cron ownership; refusing automatic migration")


def save(path, data):
    data["seal"] = seal(data)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + ".tmp." + str(os.getpid()))
    temp.write_text(json.dumps(data, sort_keys=True, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.chmod(temp, 0o600)
    os.replace(temp, path)


def relative(value):
    path = pathlib.PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or str(path) != value:
        raise ManifestError("ownership paths must be normalized vault-relative paths")
    return value


def file_info(path):
    target = pathlib.Path(path)
    if target.is_symlink() or not target.is_file():
        raise ManifestError("owned file is not a regular file")
    st = target.stat()
    return {
        "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
        "mode": stat.S_IMODE(st.st_mode),
        "nlink": st.st_nlink,
    }


def tree_hash(path):
    root = pathlib.Path(path)
    digest = hashlib.sha256()
    root_stat = root.lstat()
    digest.update(b"ROOT\0" + str(stat.S_IFMT(root_stat.st_mode)).encode() + b":"
                  + str(stat.S_IMODE(root_stat.st_mode)).encode() + b":"
                  + str(root_stat.st_nlink).encode() + b"\0")
    for base, dirs, files in os.walk(root, followlinks=False):
        dirs.sort()
        files.sort()
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


def new_manifest():
    return {
        "format": 1,
        "owner": "ai-brain-opencode",
        "instance": uuid.uuid4().hex,
        "cron_ownership_version": 2,
        "files": {},
        "symlinks": {},
        "config": {},
        "cron_lines": [],
        "launch_agents": {},
        "trees": {},
    }


def summary(data):
    return {
        "valid": True,
        "instance": data["instance"],
        "files": len(data["files"]),
        "symlinks": len(data["symlinks"]),
        "config": len(data["config"]),
        "cron_lines": len(data["cron_lines"]),
        "launch_agents": len(data["launch_agents"]),
        "trees": len(data["trees"]),
    }


def dispatch(path, action, argv):
    if action == "init":
        if path.exists() or path.is_symlink():
            if path.is_symlink():
                raise ManifestError("ownership manifest is a symlink; refusing to follow it")
            require_version(load(path))
        else:
            save(path, new_manifest())
        return 0

    data = load(path)

    if action == "instance":
        print(data["instance"])
        return 0

    require_version(data)

    if action == "verify":
        print(json.dumps(summary(data), sort_keys=True, separators=(",", ":")))
    elif action == "file-matches":
        if data["files"].get(relative(argv[0])) != file_info(argv[1]):
            return 1
    elif action == "record-file":
        data["files"][relative(argv[0])] = file_info(argv[1])
        save(path, data)
    elif action == "record-links":
        if len(argv) % 2 != 0:
            raise ManifestError("record-links expects <rel> <dst> pairs")
        for rel, dst in zip(argv[0::2], argv[1::2]):
            data["symlinks"][relative(rel)] = os.readlink(dst)
        save(path, data)
    elif action == "link-matches":
        record, target, actual = relative(argv[0]), argv[1], argv[2]
        if data["symlinks"].get(record) != target or not pathlib.Path(actual).is_symlink():
            return 1
        if os.readlink(actual) != target:
            return 1
    elif action == "record-link":
        data["symlinks"][relative(argv[0])] = os.readlink(argv[1])
        save(path, data)
    elif action == "record-config":
        for name, value in json.loads(argv[0]).items():
            data["config"]["opencode.json:mcp.servers." + name] = value
        save(path, data)
    elif action == "record-tree":
        data["trees"][relative(argv[0])] = tree_hash(argv[1])
        save(path, data)
    elif action == "agent-matches":
        entry = data["launch_agents"].get(argv[0])
        if entry is None or not pathlib.Path(argv[0]).is_file() or pathlib.Path(argv[0]).is_symlink():
            return 1
        if entry.get("file") != file_info(argv[0]):
            return 1
    elif action == "record-agent":
        data["launch_agents"][argv[0]] = {"label": argv[1], "file": file_info(argv[0])}
        save(path, data)
    elif action == "agents-tsv":
        for agent_path, entry in data["launch_agents"].items():
            print(agent_path + "\t" + entry["label"])
    elif action == "clear-agents":
        data["launch_agents"] = {}
        save(path, data)
    elif action == "cron-json":
        print(json.dumps(data["cron_lines"], ensure_ascii=False, separators=(",", ":")))
    elif action == "set-cron":
        data["cron_lines"] = json.loads(argv[0])
        save(path, data)
    elif action == "clear-cron":
        data["cron_lines"] = []
        save(path, data)
    else:
        raise ManifestError("unknown ownership action: " + action)
    return 0


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        return 1
    path = pathlib.Path(argv[0])
    action = argv[1]
    try:
        return dispatch(path, action, argv[2:])
    except LegacyManifest as error:
        if action == "cron-json":
            print("legacy or unsupported cron ownership; refusing to trust scheduled entries", file=sys.stderr)
        else:
            print("error: " + str(error), file=sys.stderr)
        return error.exit_code
    except ManifestError as error:
        print("error: " + str(error), file=sys.stderr)
        return error.exit_code
    except (OSError, ValueError, TypeError, AttributeError, json.JSONDecodeError) as error:
        print("error: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
