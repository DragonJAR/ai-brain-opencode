#!/usr/bin/env bash
# Revisión semanal headless. Solo corre si hay entradas de diario.
set -euo pipefail
LIB="$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
[ -f "$LIB" ] || { echo "falta scripts/lib/common.sh; re-ejecuta install.sh sobre este vault" >&2; exit 1; }
# shellcheck source=/dev/null
. "$LIB"
job_init

COUNT=$( { find "📓 Journals" -name '*.md' -not -name '.gitkeep' 2>/dev/null || true; } | wc -l | tr -d ' ')
if [ "$COUNT" -lt 1 ]; then job_log "sin entradas; omitido"; exit 0; fi
job_log "/insights con ${COUNT} entradas"
command -v opencode >/dev/null || job_fail "opencode no disponible"

# La fecha del informe sigue la zona horaria del vault, no la del host.
DATE_TAG="$(brain_config "$CFG" today 2>> "$LOG")" || DATE_TAG="$(date '+%Y-%m-%d')"
TIMEOUT_SECONDS=900
TASK="revisión semanal de mis entradas de diario. Guarda el informe en 📝 Notes/insights-${DATE_TAG}.md y no hagas preguntas."

# Sin nadie delante, sin --auto `opencode run` rechaza todo permiso y no puede
# guardar el informe. Los flags salen de la ayuda de la CLI instalada: v2 no
# tiene --command y manda el mensaje como texto, así que "/insights" no correría
# el comando; se nombra la skill que ese comando invoca.
RUN_HELP="$(opencode run --help 2>&1 < /dev/null || true)"
case "$RUN_HELP" in *--auto*) ;; *) job_fail "opencode run no admite --auto; actualiza OpenCode" ;; esac
ARGS=(run --auto)
case "$RUN_HELP" in *--archived*) ARGS+=(--archived) ;; esac
case "$RUN_HELP" in
  *--command*) ARGS+=(--command insights "$TASK") ;;
  *) ARGS+=("Usa la skill \`insights\` para la $TASK") ;;
esac
run_with_timeout "$TIMEOUT_SECONDS" opencode "${ARGS[@]}" < /dev/null \
  >> "$LOG" 2>&1 || job_fail "opencode run falló o superó ${TIMEOUT_SECONDS} s"
