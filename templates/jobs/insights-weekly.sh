#!/usr/bin/env bash
# Revisión semanal headless. Solo corre si hay entradas de diario.
set -euo pipefail
LIB="$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
[ -f "$LIB" ] || { echo "falta scripts/lib/common.sh; re-ejecuta install.sh sobre este vault" >&2; exit 1; }
# shellcheck source=/dev/null
. "$LIB"
job_init insights-weekly

COUNT=$( { find "📓 Journals" -name '*.md' -not -name '.gitkeep' 2>/dev/null || true; } | wc -l | tr -d ' ')
if [ "$COUNT" -lt 1 ]; then job_log "sin entradas; omitido"; exit 0; fi
job_log "/insights con ${COUNT} entradas"
command -v opencode >/dev/null || job_fail "opencode no disponible"

# La fecha del informe sigue la zona horaria del vault, no la del host.
DATE_TAG="$(brain_config "$CFG" today 2>> "$LOG")" || DATE_TAG="$(date '+%Y-%m-%d')"
TIMEOUT_SECONDS=900
run_with_timeout "$TIMEOUT_SECONDS" opencode run \
  "Ejecuta /insights: revisión semanal de mis entradas de diario. Guarda el informe en 📝 Notes/insights-${DATE_TAG}.md y no hagas preguntas." \
  >> "$LOG" 2>&1 || job_fail "opencode run falló o superó ${TIMEOUT_SECONDS} s"
