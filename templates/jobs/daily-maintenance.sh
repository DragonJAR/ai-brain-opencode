#!/usr/bin/env bash
# Mantenimiento diario: índice del diario + snapshot git de lo nuevo.
set -euo pipefail
VAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$VAULT"
mkdir -p "$VAULT/⚙️ Meta/logs"
LOG="$VAULT/⚙️ Meta/logs/maintenance.log"

if [ -f "$VAULT/scripts/lib/python3.sh" ]; then
  # shellcheck source=/dev/null
  . "$VAULT/scripts/lib/python3.sh"
  require_python3 || { echo "$(date '+%F %T') sin Python 3 válido (python3, py -3, python)" >> "$LOG"; exit 1; }
else
  PY3="python3"   # vault instalado antes de que existiera la lib
fi

if [ -f "⚙️ Meta/scripts/build-journal-index.py" ]; then
  if ! $PY3 "⚙️ Meta/scripts/build-journal-index.py" --vault-root . >> "$LOG" 2>&1; then
    echo "$(date '+%F %T') falló build-journal-index" >> "$LOG"
    echo "falló build-journal-index" >&2
    exit 1
  fi
else
  echo "$(date '+%F %T') build-journal-index.py ausente; omitido" >> "$LOG"
fi

if [ -d ".git" ]; then
  paths_to_add=()
  for p in "📓 Journals" "⚙️ Meta/Sessions" "⚙️ Meta/Decisions" "⚙️ Meta/journal-index.json"; do
    [ -e "$p" ] && paths_to_add+=("$p")
  done
  if [ ${#paths_to_add[@]} -gt 0 ]; then
    if ! git add "${paths_to_add[@]}" >> "$LOG" 2>&1; then
      echo "$(date '+%F %T') falló git add" >> "$LOG"
      echo "falló git add" >&2
      exit 1
    fi
  fi
  if ! git diff --cached --quiet 2>/dev/null; then
    if ! git commit -q -m "chore: snapshot diario del vault" >> "$LOG" 2>&1; then
      echo "$(date '+%F %T') falló git commit" >> "$LOG"
      echo "falló git commit" >&2
      exit 1
    fi
    echo "$(date '+%F %T') snapshot" >> "$LOG"
  fi
else
  echo "$(date '+%F %T') sin repositorio git; omitido snapshot" >> "$LOG"
fi
