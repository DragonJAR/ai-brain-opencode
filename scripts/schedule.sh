#!/usr/bin/env bash
# schedule.sh — instala los trabajos programados del vault.
#   bash scripts/schedule.sh <vault-path>            instala (launchd en macOS, cron en Linux)
#   bash scripts/schedule.sh <vault-path> --dry-run  genera los plists sin registrarlos
#   bash scripts/schedule.sh <vault-path> --remove   desinstala
# Horarios leídos de ⚙️ Meta/brain-config.json (schedule.*). Labels: com.ai-brain.<slug>.*
set -euo pipefail
VAULT="${1:-}"; MODE="${2:-install}"
[ -n "$VAULT" ] || { echo "uso: $0 <vault-path> [--dry-run|--remove]" >&2; exit 1; }
[ -d "$VAULT" ] || { echo "no existe el vault: $VAULT" >&2; exit 1; }
VAULT="$(cd "$VAULT" && pwd)"
SLUG="$(basename "$VAULT" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')"
SLUG="${SLUG:-cerebro}"
PREFIX="com.ai-brain.$SLUG"
J="$VAULT/scripts/jobs"
BRC="$VAULT/⚙️ Meta/brain-config.json"
get() { python3 - "$BRC" "$1" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
path, default = sys.argv[2], sys.argv[3]
cur = d
for k in path.split("."):
    if not isinstance(cur, dict) or k not in cur:
        print(default); sys.exit()
    cur = cur[k]
print(cur)
PY
}
JT="$(get 'journal.time' '20:30')"; ITIME="$(get 'schedule.insights_time' '21:00')"
MTIME="$(get 'schedule.maintenance_time' '03:30')"; UTIME="$(get 'schedule.update_time' '08:00')"
hm() { echo "$1" | cut -d: -f1; }
pm() { echo "$1" | cut -d: -f2 | sed 's/^0//'; }

print_cron_jobs() {
  local marker="$1"
  printf '%s %s * * 1-5 /bin/bash "%s/journal-reminder.sh" %s\n' "$(hm "$JT")" "$(pm "$JT")" "$J" "$marker"
  printf '%s %s * * 0 /bin/bash "%s/insights-weekly.sh" %s\n' "$(hm "$ITIME")" "$(pm "$ITIME")" "$J" "$marker"
  printf '%s %s * * * /bin/bash "%s/daily-maintenance.sh" %s\n' "$(hm "$MTIME")" "$(pm "$MTIME")" "$J" "$marker"
  printf '%s %s * * 1 /bin/bash "%s/update-brain.sh" %s\n' "$(hm "$UTIME")" "$(pm "$UTIME")" "$J" "$marker"
}

if [ "$MODE" = "--dry-run" ] && [ "$(uname -s)" != "Darwin" ]; then
  MARK="# ai-brain $SLUG"
  echo "$MARK"
  print_cron_jobs "$MARK"
  exit 0
fi

if [ "$MODE" = "--remove" ]; then
  if [ "$(uname -s)" = "Darwin" ]; then
    for j in journal-reminder insights-weekly daily-maintenance update-brain-weekly; do
      launchctl bootout "gui/$(id -u)/$PREFIX.$j" 2>/dev/null || true
      rm -f "$HOME/Library/LaunchAgents/$PREFIX.$j.plist"
    done
  else
    crontab -l 2>/dev/null | grep -v "# ai-brain $SLUG" | crontab - 2>/dev/null || true
  fi
  echo "Desinstalado: $PREFIX.*"
  exit 0
fi

if [ "$(uname -s)" = "Darwin" ]; then
  mkdir -p "$HOME/Library/LaunchAgents"
  mk() { # $1 job, $2 label, $3 interval-xml
    local job="$1" label="$2" cal="$3"
    cat > "$HOME/Library/LaunchAgents/$label.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$J/$job.sh</string></array>
$cal
<key>StandardOutPath</key><string>$VAULT/⚙️ Meta/logs/$job.log</string>
<key>StandardErrorPath</key><string>$VAULT/⚙️ Meta/logs/$job.log</string>
</dict></plist>
PL
    if [ "$MODE" = "--dry-run" ]; then echo "  (dry-run) $label"; plutil -lint "$HOME/Library/LaunchAgents/$label.plist" >/dev/null 2>&1 && echo "    plist válido" || echo "    ✗ plist inválido"; rm -f "$HOME/Library/LaunchAgents/$label.plist"; return 0; fi
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$label.plist" && echo "  + $label" || echo "  ! $label (bootstrap falló)"
  }
  # A3: StartCalendarInterval como ARRAY (varias horas no caben como claves repetidas)
  CAL_J="<key>StartCalendarInterval</key><array>$(for wd in 1 2 3 4 5; do printf '<dict><key>Hour</key><integer>%s</integer><key>Minute</key><integer>%s</integer><key>Weekday</key><integer>%s</integer></dict>' "$(hm "$JT")" "$(pm "$JT")" "$wd"; done)</array>"
  CAL_I="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$ITIME")</integer><key>Minute</key><integer>$(pm "$ITIME")</integer><key>Weekday</key><integer>0</integer></dict>"
  CAL_M="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$MTIME")</integer><key>Minute</key><integer>$(pm "$MTIME")</integer></dict>"
  CAL_U="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$UTIME")</integer><key>Minute</key><integer>$(pm "$UTIME")</integer><key>Weekday</key><integer>1</integer></dict>"
  mk journal-reminder    "$PREFIX.journal-reminder"    "$CAL_J"
  mk insights-weekly     "$PREFIX.insights-weekly"     "$CAL_I"
  mk daily-maintenance   "$PREFIX.daily-maintenance"   "$CAL_M"
  mk update-brain-weekly "$PREFIX.update-brain-weekly" "$CAL_U"
else
  MARK="# ai-brain $SLUG"
  crontab -l 2>/dev/null | grep -v "$MARK" > /tmp/ai-brain-cron.$$ || true
  { echo "$MARK"
    print_cron_jobs "$MARK"
  } >> /tmp/ai-brain-cron.$$
  crontab /tmp/ai-brain-cron.$$ && rm -f /tmp/ai-brain-cron.$$ && echo "  + 4 entradas crontab ($MARK)"
fi
