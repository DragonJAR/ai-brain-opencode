#!/usr/bin/env bash
# Recordatorio del diario. Notificación del sistema operativo. Lee la config del vault.
set -euo pipefail
VAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$VAULT"
CFG="$VAULT/⚙️ Meta/brain-config.json"
NAME=$(python3 -c "import json;print(json.load(open('$CFG')).get('vault_name','mi-cerebro'))" 2>/dev/null || echo "mi-cerebro")
TIME_=$(python3 -c "import json;print(json.load(open('$CFG')).get('journal',{}).get('time','20:30'))" 2>/dev/null || echo "20:30")
case "$(uname -s)" in
  Darwin) osascript -e "display notification \"Hora del diario ($TIME_). Abre OpenCode en $NAME y escribe /journal\" with title \"$NAME\" sound name \"Pop\"" ;;
  Linux)  command -v notify-send >/dev/null && notify-send "$NAME" "Hora del diario ($TIME_): escribe /journal" || echo "$NAME: hora del diario ($TIME_)" ;;
  *) echo "$NAME: hora del diario ($TIME_)" ;;
esac
