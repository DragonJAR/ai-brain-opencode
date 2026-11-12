#!/usr/bin/env bash
# Every vault folder a product file names must exist in scripts/lib/vault_layout.py.
# The list itself lives only there; the other files mention single folders in
# paths and prose, and this test reads each mention so a renamed or mistyped
# folder cannot survive anywhere. It also keeps the plugin's default
# snapshot_paths equal to the package example.
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$PKG" <<'PY'
import json, pathlib, re, sys
sys.dont_write_bytecode = True
pkg = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(pkg / "scripts" / "lib"))
import vault_layout as layout

roots = list(layout.roots())
folders = set(layout.FOLDERS)
# A folder plus its ancestors: "💼 Business" is valid because "💼 Business/Engagements" is.
known = set()
for folder in folders:
    parts = folder.split("/")
    for depth in range(1, len(parts) + 1):
        known.add("/".join(parts[:depth]))

files = [pkg / "install.sh", pkg / "uninstall.sh", pkg / "plugin/brain-vault/index.js",
         pkg / "templates/brain-config.example.json", pkg / "templates/agents-opencode-appendix.md"]
for pattern in ("scripts/*.sh", "scripts/*.py", "scripts/lib/*.sh", "scripts/lib/*.py",
                "templates/jobs/*.sh", "templates/commands/*.md"):
    files += sorted(pkg.glob(pattern))
files = [f for f in files if f.name != "vault_layout.py"]

root_re = "|".join(re.escape(root) for root in roots)
# <root>, optionally followed by /<Segment>. A segment that is a file name, a
# placeholder or a shell variable is not a folder and is left alone.
mention = re.compile(r"(%s)(?:/([^/\s`\"'|)\]<>$*,;:]+))?" % root_re)
problems, checked = [], 0
for path in files:
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        for match in mention.finditer(line):
            root, segment = match.group(1), match.group(2)
            checked += 1
            if not segment:
                continue
            tail = line[match.end():match.end() + 1]
            is_file_or_template = "." in segment or segment.endswith("-") or tail in ("$", "<", "*")
            if is_file_or_template or not segment[0].isupper() and not segment[0].islower():
                continue
            candidate = root + "/" + segment
            # Longest folder name wins: "⚙️ Meta/Folder Resolvers" has a space in it.
            rest = line[match.start():]
            if any(rest.startswith(folder) for folder in known if folder.startswith(candidate)):
                continue
            if candidate not in known:
                problems.append("%s:%d names %r, which vault_layout.FOLDERS does not have"
                                % (path.relative_to(pkg), number, candidate))
assert checked > 40, "the scan found too few folder mentions (%d): the pattern is broken" % checked
if problems:
    raise SystemExit("\n".join(problems))

# The plugin's default snapshot_paths mirror the package example, and both stay inside the layout.
example = json.loads((pkg / "templates/brain-config.example.json").read_text(encoding="utf-8"))["snapshot_paths"]
plugin = (pkg / "plugin/brain-vault/index.js").read_text(encoding="utf-8")
found = re.search(r"snapshot_paths:\s*(\[[^\]]*\])", plugin)
assert found and json.loads(found.group(1)) == example, "plugin snapshot_paths drifted from the example"
for entry in example:
    assert entry.split("/")[0] in roots, "snapshot_paths entry outside the vault layout: " + entry
print("PASS: %d folder mentions in %d product files all exist in vault_layout.py" % (checked, len(files)))
PY
