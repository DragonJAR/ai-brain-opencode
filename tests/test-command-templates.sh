#!/usr/bin/env bash
# Package slash commands must open with OpenCode frontmatter carrying a
# description: without it the command loads but shows up blank in the list.
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failures=0
for f in "$PKG"/templates/commands/*.md; do
  name="$(basename "$f")"
  if [ "$(head -n 1 "$f")" != "---" ]; then
    printf 'FAIL: %s does not start with frontmatter\n' "$name" >&2
    failures=$((failures + 1))
    continue
  fi
  # Quoted: an unquoted value containing ": " is invalid YAML.
  if ! awk 'NR > 1 && /^---$/ { exit } NR > 1 && /^description: "[^"]+"$/ { found = 1 } END { exit !found }' "$f"; then
    printf 'FAIL: %s frontmatter has no quoted description\n' "$name" >&2
    failures=$((failures + 1))
  fi
done

# OpenCode v2 `opencode run` sends its message as plain text, so a slash command
# there never runs; no template or doc may tell the user otherwise.
SLASH_RUN="$(grep -RInE "opencode run( --?[A-Za-z-]+)* [\"']/" "$PKG/templates" "$PKG/docs" "$PKG"/README*.md || true)"
if [ -n "$SLASH_RUN" ]; then
  printf 'FAIL: a template or doc tells the user to run a slash command with opencode run:\n%s\n' "$SLASH_RUN" >&2
  failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: %s package command template or doc problems\n' "$failures" >&2
  exit 1
fi
printf 'PASS: package slash commands declare an OpenCode description; no doc runs one through opencode run\n'
