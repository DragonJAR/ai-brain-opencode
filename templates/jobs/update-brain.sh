#!/usr/bin/env bash
# Actualiza el starter y humanizer (ff-only) y regenera los pisos.
set -euo pipefail
VAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$VAULT"
LOG="$VAULT/⚙️ Meta/logs/update.log"
R="$VAULT/.opencode/skills/ai-brain-starter"
H="$VAULT/.opencode/skills/humanizer"
if [ -d "$R/.git" ]; then git -C "$R" pull --ff-only >> "$LOG" 2>&1 || echo "$(date '+%F %T') pull starter falló" >> "$LOG"; fi
if [ -d "$H/.git" ]; then git -C "$H" pull --ff-only >> "$LOG" 2>&1 || echo "$(date '+%F %T') pull humanizer falló" >> "$LOG"; fi
if [ -f "$R/scripts/generate_floor_stubs.py" ]; then
  python3 "$R/scripts/generate_floor_stubs.py" >> "$LOG" 2>&1 || true
  cp "$R/floors/"*.md "$VAULT/⚙️ Meta/Floors/" 2>/dev/null || true
fi
