#!/usr/bin/env bash
# Recordatorio del diario. Notificación del sistema operativo. Lee la config por argv (M4: sin interpolar comillas).
set -euo pipefail
VAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$VAULT"
CFG="$VAULT/⚙️ Meta/brain-config.json"
NAME=$(python3 - "$CFG" <<'PY'
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("vault_name", "mi-cerebro"))
except Exception:
    print("mi-cerebro")
PY
)
TIME_=$(python3 - "$CFG" <<'PY'
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("journal", {}).get("time", "20:30"))
except Exception:
    print("20:30")
PY
)
case "$(uname -s)" in
  Darwin) osascript -e "display notification \"Hora del diario ($TIME_). Abre OpenCode en $NAME y escribe /journal\" with title \"$NAME\" sound name \"Pop\"" ;;
  Linux)  command -v notify-send >/dev/null && notify-send "$NAME" "Hora del diario ($TIME_): escribe /journal" || echo "$NAME: hora del diario ($TIME_)" ;;
  *) echo "$NAME: hora del diario ($TIME_)" ;;
esac
