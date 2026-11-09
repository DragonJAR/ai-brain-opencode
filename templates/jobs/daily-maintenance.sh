#!/usr/bin/env bash
# Mantenimiento diario: índice del diario + snapshot git de lo nuevo.
set -euo pipefail
VAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$VAULT"
LOG="$VAULT/⚙️ Meta/logs/maintenance.log"
if [ -f "⚙️ Meta/scripts/build-journal-index.py" ]; then
  python3 "⚙️ Meta/scripts/build-journal-index.py" --vault-root . >> "$LOG" 2>&1 || true
fi
git add "📓 Journals" "⚙️ Meta/Sessions" "⚙️ Meta/Decisions" "⚙️ Meta/journal-index.json" 2>/dev/null || true
if ! git diff --cached --quiet 2>/dev/null; then
  git commit -q -m "chore: snapshot diario del vault" && echo "$(date '+%F %T') snapshot" >> "$LOG"
fi
