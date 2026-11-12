#!/usr/bin/env bash
# Revisión semanal headless. Solo corre si hay entradas de diario.
set -euo pipefail
VAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$VAULT"
mkdir -p "$VAULT/⚙️ Meta/logs"
LOG="$VAULT/⚙️ Meta/logs/insights-weekly.log"
COUNT=$( { find "📓 Journals" -name '*.md' -not -name '.gitkeep' 2>/dev/null || true; } | wc -l | tr -d ' ')
if [ "$COUNT" -lt 1 ]; then echo "$(date '+%F %T') sin entradas; omitido" >> "$LOG"; exit 0; fi
echo "$(date '+%F %T') /insights con ${COUNT} entradas" >> "$LOG"
command -v opencode >/dev/null || {
  echo "$(date '+%F %T') opencode no disponible" >> "$LOG"
  echo "opencode no disponible" >&2
  exit 1
}
# GNU timeout no existe en macOS stock: perl -alarm es el fallback portable.
RUN_CMD=(opencode run)
if command -v timeout >/dev/null; then
  RUN_CMD=(timeout 900 opencode run)
elif command -v perl >/dev/null; then
  RUN_CMD=(perl -e 'alarm shift; exec @ARGV' 900 opencode run)
else
  echo "$(date '+%F %T') aviso: sin timeout ni perl; la corrida no tiene límite" >> "$LOG"
fi
# La fecha del informe sigue la zona horaria del vault, no la del host.
DATE_TAG="$(date '+%Y-%m-%d')"
CFG="$VAULT/⚙️ Meta/brain-config.json"
if [ -n "${PY3:-}" ] || { [ -f "$VAULT/scripts/lib/python3.sh" ] && . "$VAULT/scripts/lib/python3.sh" && pick_python3; }; then
  if [ -f "$CFG" ]; then
    DATE_TAG=$($PY3 - "$CFG" <<'PY'
import json, sys
try:
    cfg = json.load(open(sys.argv[1], encoding="utf-8"))
    tz = cfg.get("timezone") if isinstance(cfg, dict) else None
    if not isinstance(tz, str) or not tz:
        raise SystemExit(1)
    from datetime import datetime, timezone as tz_module
    from zoneinfo import ZoneInfo
    print(datetime.now(ZoneInfo(tz)).strftime("%Y-%m-%d"))
except Exception:
    raise SystemExit(1)
PY
) || DATE_TAG="$(date '+%Y-%m-%d')"
  fi
fi
"${RUN_CMD[@]}" "Ejecuta /insights: revisión semanal de mis entradas de diario. Guarda el informe en 📝 Notes/insights-${DATE_TAG}.md y no hagas preguntas." >> "$LOG" 2>&1
