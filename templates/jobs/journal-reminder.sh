#!/usr/bin/env bash
# Recordatorio del diario. Notificación del sistema operativo.
set -euo pipefail
VAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$VAULT"
CFG="$VAULT/⚙️ Meta/brain-config.json"
mkdir -p "$VAULT/⚙️ Meta/logs"
LOG="$VAULT/⚙️ Meta/logs/journal-reminder.log"

if [ -f "$VAULT/scripts/lib/python3.sh" ]; then
  # shellcheck source=/dev/null
  . "$VAULT/scripts/lib/python3.sh"
  require_python3 || { echo "$(date '+%F %T') sin Python 3 válido (python3, py -3, python)" >> "$LOG"; exit 1; }
else
  PY3="python3"   # vault instalado antes de que existiera la lib
fi

INFO=$($PY3 - "$CFG" <<'PY'
import json, sys
try:
    cfg = json.load(open(sys.argv[1], encoding="utf-8"))
    if not isinstance(cfg, dict):
        cfg = {}
except Exception:
    cfg = {}
journal = cfg.get("journal")
time = journal.get("time") if isinstance(journal, dict) else None
print(str(cfg.get("vault_name") or "mi-cerebro"))
print(time if isinstance(time, str) and time else "20:30")
PY
)
NAME=$(printf '%s\n' "$INFO" | sed -n '1p')
TIME_=$(printf '%s\n' "$INFO" | sed -n '2p')
MESSAGE="Hora del diario ($TIME_). Abre OpenCode en $NAME y escribe /journal"
case "$(uname -s)" in
  Darwin)
    # Notificación cosmética: el fallo de osascript es aceptable (ej. sin sesión gráfica) y no debe abortar el trabajo
    osascript - "$NAME" "$MESSAGE" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
    display notification (item 2 of argv) with title (item 1 of argv) sound name "Pop"
end run
APPLESCRIPT
    ;;
  Linux)
    if command -v notify-send >/dev/null; then notify-send "$NAME" "$MESSAGE"; else echo "$NAME: $MESSAGE"; fi
    ;;
  *) echo "$NAME: $MESSAGE" ;;
esac
