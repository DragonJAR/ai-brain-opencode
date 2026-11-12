#!/usr/bin/env python3
"""Wire the vendor starter into the vault: skills, commands and scripts.

One pass, one manifest read and one write. install.sh and the scheduled update
job both use it, so a starter update is wired exactly as it was installed.
Relative symlinks on POSIX, copies on Windows.

Usage:
    python3 wire.py <vault> [--mode link|copy] [--only skills,commands,scripts]

Entries the starter dropped are pruned while the vault still owns them
unchanged. Anything the vault owns differently is preserved and reported.
"""

import os
import pathlib
import shutil
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import ownership  # noqa: E402

# name -> (starter subdir, vault dir, link target prefix, kind, suffixes, noun, linked, copied)
SECTIONS = {
    "skills": ("skills", ".opencode/skills", "ai-brain-starter/skills/", "dir", (),
               "skills", "enlazadas", "copiadas"),
    "commands": ("commands", ".opencode/commands", "../skills/ai-brain-starter/commands/", "file", (".md",),
                 "comandos", "enlazados", "copiados"),
    "scripts": ("scripts", "⚙️ Meta/scripts", "../../.opencode/skills/ai-brain-starter/scripts/", "file",
                (".py", ".sh"), "scripts", "enlazados", "copiados"),
}
RESERVED = {pathlib.PurePosixPath(rel).name for rel in ownership.VENDOR_CLONES}


def default_mode():
    return "copy" if os.name == "nt" or sys.platform in ("cygwin", "msys") else "link"


def vendor_entries(source, kind, suffixes):
    if not source.is_dir():
        return []
    entries = []
    for item in sorted(source.iterdir(), key=lambda entry: entry.name):
        if kind == "dir":
            if item.is_dir() and item.name not in RESERVED:
                entries.append(item)
        elif item.is_file() and item.name.endswith(suffixes):
            entries.append(item)
    return entries


def prune(data, vault, vault_dir, wanted):
    """Drop owned entries the starter no longer ships, while still unchanged.

    Symlinks in a wired directory are always vendor wiring. Copies share those
    directories with package files, so only the ones listed in `wired` count.
    """
    pruned = 0

    def stale(rels):
        return [rel for rel in list(rels)
                if str(pathlib.PurePosixPath(rel).parent) == vault_dir
                and pathlib.PurePosixPath(rel).name not in wanted]

    def drop(records, rel, unchanged, remove):
        try:
            target = ownership.safe_target(vault, rel)
            if target.exists() or target.is_symlink():
                if not unchanged(target):
                    return 0
                remove(target)
                removed = 1
            else:
                removed = 0
        except (OSError, ownership.ManifestError):
            return 0
        del records[rel]
        if rel in data["wired"]:
            data["wired"].remove(rel)
        return removed

    for rel in stale(data["symlinks"]):
        expected = data["symlinks"][rel]
        pruned += drop(data["symlinks"], rel,
                       lambda target: target.is_symlink() and os.readlink(target) == expected,
                       lambda target: target.unlink())
    for rel in stale(data["wired"]):
        if rel in data["files"]:
            expected = data["files"][rel]
            pruned += drop(data["files"], rel,
                           lambda target: not target.is_symlink() and target.is_file()
                           and ownership.file_info(target) == expected,
                           lambda target: target.unlink())
        elif rel in data["trees"]:
            expected = data["trees"][rel]
            pruned += drop(data["trees"], rel,
                           lambda target: not target.is_symlink() and target.is_dir()
                           and ownership.tree_hash(target) == expected,
                           shutil.rmtree)
        else:
            data["wired"].remove(rel)
    return pruned


def wire(data, vault, mode, names):
    starter = pathlib.Path(vault).joinpath(*pathlib.PurePosixPath(ownership.STARTER_REL).parts)
    if not (starter / "SKILL.md").is_file():
        raise ownership.ManifestError("no hay un starter válido en " + str(starter))
    for name in names:
        subdir, vault_dir, target_prefix, kind, suffixes, noun, linked, copied = SECTIONS[name]
        entries = vendor_entries(starter / subdir, kind, suffixes)
        managed = 0
        for entry in entries:
            rel = vault_dir + "/" + entry.name
            if mode == "link":
                reason = ownership.put_link(data, vault, rel, target_prefix + entry.name)
            else:
                put = ownership.put_tree if kind == "dir" else ownership.put_file
                reason = put(data, vault, rel, entry)
                if reason is None and rel not in data["wired"]:
                    data["wired"].append(rel)
            if reason is None:
                managed += 1
            else:
                ownership.warn(reason)
        pruned = prune(data, vault, vault_dir, {entry.name for entry in entries})
        print("  + %d %s %s" % (managed, noun, linked if mode == "link" else copied))
        if pruned:
            print("  - %d %s que el starter ya no trae, retirados" % (pruned, noun))


def main(argv):
    ownership.configure_stdio()
    mode, names, positional = default_mode(), list(SECTIONS), []
    index = 0
    while index < len(argv):
        if argv[index] in ("--mode", "--only") and index + 1 < len(argv):
            if argv[index] == "--mode":
                mode = argv[index + 1]
            else:
                names = [name for name in argv[index + 1].split(",") if name]
            index += 2
        else:
            positional.append(argv[index])
            index += 1
    if len(positional) != 1 or mode not in ("link", "copy") or any(name not in SECTIONS for name in names):
        print("uso: python3 wire.py <vault> [--mode link|copy] [--only skills,commands,scripts]", file=sys.stderr)
        return 1
    vault = pathlib.Path(positional[0])
    manifest = vault.joinpath(*pathlib.PurePosixPath(ownership.MANIFEST_REL).parts)
    try:
        if manifest.is_symlink() or (vault / ".opencode").is_symlink():
            raise ownership.ManifestError("el manifiesto de propiedad es un symlink; no se sigue")
        with ownership.manifest_lock(manifest):
            data = ownership.load_current(manifest)
            try:
                wire(data, vault, mode, names)
            finally:
                ownership.save(manifest, data)
    except ownership.ManifestError as error:
        print("fallo: " + str(error), file=sys.stderr)
        return error.exit_code
    except (OSError, ValueError, TypeError, AttributeError) as error:
        print("fallo: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
