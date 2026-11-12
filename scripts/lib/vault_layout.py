#!/usr/bin/env python3
"""Vault layout: the only list of vault folders and remote MCP servers.

install.sh creates FOLDERS, verify.sh checks their roots, audit.py and
ownership.py import the rest, and install --with-mcp writes MCP_SERVERS.
plugin/brain-vault/index.js keeps a copy of NOTE_TYPES (OpenCode runs it
without Python); tests/test-vault-layout-single-source.sh fails on drift.

Usage:
    python3 vault_layout.py folders|roots|mcp-names
"""

import sys

# Every folder install.sh creates (with a .gitkeep), parents before children.
FOLDERS = (
    "📓 Journals",
    "🏠 Home",
    "👤 CRM",
    "📝 Notes",
    "📝 Notes/Raw",
    "💼 Business/Engagements",
    "🚀 I+D/Herramientas",
    "🚀 I+D/Investigación",
    "⚙️ Meta/Folder Resolvers",
    "⚙️ Meta/scripts",
    "⚙️ Meta/Sessions",
    "⚙️ Meta/Decisions",
    "⚙️ Meta/Workflows",
    "⚙️ Meta/Facts",
    "⚙️ Meta/Exceptions",
    "⚙️ Meta/Floors",
    "⚙️ Meta/logs",
)

# Type the plugin stamps on a new note, by folder prefix; the first match wins.
# An empty type leaves the file untouched (Raw sources are immutable).
NOTE_TYPES = (
    ("📓 Journals/", "journal"),
    ("👤 CRM/", "person"),
    ("⚙️ Meta/Sessions/", "session"),
    ("⚙️ Meta/Decisions/", "decision"),
    ("⚙️ Meta/", "note"),
    ("🏠 Home/", "note"),
    ("📝 Notes/Raw/", ""),
    ("📝 Notes/", "note"),
    ("💼 Business/", "note"),
    ("🚀 I+D/", "note"),
)

# Where audit.py requires a `type:` and where it reports orphan notes.
TYPED_FOLDERS = (
    "📓 Journals/",
    "👤 CRM/",
    "🏠 Home/",
    "📝 Notes/",
    "💼 Business/",
    "🚀 I+D/",
    "⚙️ Meta/Sessions/",
    "⚙️ Meta/Decisions/",
)
ORPHAN_FOLDERS = (
    "📝 Notes/",
    "👤 CRM/",
    "🚀 I+D/",
    "💼 Business/",
)
RAW_PREFIX = "📝 Notes/Raw/"

# Remote MCP servers `install.sh --with-mcp` adds (opt-in; they receive the conversation).
MCP_SERVERS = {
    "granola": "https://mcp.granola.ai/mcp",
    "chatprd": "https://app.chatprd.ai/mcp",
}


def roots():
    """Top-level folders, in FOLDERS order."""
    seen = []
    for folder in FOLDERS:
        root = folder.split("/", 1)[0]
        if root not in seen:
            seen.append(root)
    return seen


def main(argv):
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", newline="\n")
        except (AttributeError, ValueError):
            pass
    lists = {"folders": FOLDERS, "roots": roots(), "mcp-names": tuple(MCP_SERVERS)}
    if len(argv) != 1 or argv[0] not in lists:
        print("uso: python3 vault_layout.py folders|roots|mcp-names", file=sys.stderr)
        return 2
    for item in lists[argv[0]]:
        print(item)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
