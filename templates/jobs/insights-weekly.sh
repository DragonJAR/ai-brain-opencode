#!/usr/bin/env bash
# Revisión semanal headless. Solo corre si hay entradas de diario.
set -euo pipefail
VAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$VAULT"
LOG="$VAULT/⚙️ Meta/logs/insights-weekly.log"
COUNT=$(find "📓 Journals" -name '*.md' -not -name '.gitkeep' 2>/dev/null | wc -l | tr -d ' ')
if [ "$COUNT" -lt 1 ]; then echo "$(date '+%F %T') sin entradas; omitido" >> "$LOG"; exit 0; fi
echo "$(date '+%F %T') /insights con ${COUNT} entradas" >> "$LOG"
command -v opencode >/dev/null || { echo "$(date '+%F %T') opencode no disponible" >> "$LOG"; exit 0; }
opencode run "Ejecuta /insights: revisión semanal de mis entradas de diario. Guarda el informe en 📝 Notes/ y no hagas preguntas." >> "$LOG" 2>&1
