#!/usr/bin/env bash
# schedule.sh — instala los trabajos programados del vault.
# macOS: launchd (plist). Linux: crontab. Idempotente.
set -euo pipefail
DRY=0
[ "${2:-}" = "--dry-run" ] && DRY=1
VAULT="$(cd "$1" && pwd)"
SLUG="$(basename "$VAULT" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
SLUG="${SLUG:-cerebro}"
PREFIX="com.ai-brain.$SLUG"
LA="$HOME/Library/LaunchAgents"
J="$VAULT/scripts/jobs"
cfg() { python3 -c "import json;d=json.load(open('$VAULT/⚙️ Meta/brain-config.json'));print($1)" 2>/dev/null; }
JT="$(cfg "d.get('journal',{}).get('time','20:30')")"
JDAY="$(cfg "d.get('schedule',{}).get('insights_day','Sunday')")"
JTIME="$(cfg "d.get('schedule',{}).get('insights_time','21:00')")"
MTIME="$(cfg "d.get('schedule',{}).get('maintenance_time','03:30')")"
UDAY="$(cfg "d.get('schedule',{}).get('update_day','Monday')")"
UTIME="$(cfg "d.get('schedule',{}).get('update_time','08:00')")"
hm() { echo "$1" | cut -d: -f1; }
pm() { echo "$1" | cut -d: -f2 | sed 's/^0//'; }

if [ "$(uname -s)" = "Darwin" ]; then
  mkdir -p "$LA"
  mk() { # $1 job  $2 label  $3 calendar-xml
    local job="$1" label="$2" cal="$3"
    cat > "$LA/$label.plist" <<PL
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
    if [ "$DRY" = 1 ]; then
      cp "$LA/$label.plist" "/tmp/$label.plist.dry" 2>/dev/null || true
      rm -f "$LA/$label.plist"
      echo "  (dry-run) $label"
      return 0
    fi
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$LA/$label.plist" 2>/dev/null && echo "  + $label" || echo "  ! $label (revisa: launchctl bootstrap)"
  }
  CAL_J="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$JT")</integer><key>Minute</key><integer>$(pm "$JT")</integer><key>Weekday</key><integer>1</integer></dict><key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$JT")</integer><key>Minute</key><integer>$(pm "$JT")</integer><key>Weekday</key><integer>2</integer></dict><key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$JT")</integer><key>Minute</key><integer>$(pm "$JT")</integer><key>Weekday</key><integer>3</integer></dict><key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$JT")</integer><key>Minute</key><integer>$(pm "$JT")</integer><key>Weekday</key><integer>4</integer></dict><key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$JT")</integer><key>Minute</key><integer>$(pm "$JT")</integer><key>Weekday</key><integer>5</integer></dict>"
  CAL_I="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$JTIME")</integer><key>Minute</key><integer>$(pm "$JTIME")</integer><key>Weekday</key><integer>0</integer></dict>"
  CAL_M="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$MTIME")</integer><key>Minute</key><integer>$(pm "$MTIME")</integer></dict>"
  CAL_U="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$UTIME")</integer><key>Minute</key><integer>$(pm "$UTIME")</integer><key>Weekday</key><integer>1</integer></dict>"
  mk journal-reminder   "$PREFIX.journal-reminder"   "$CAL_J"
  mk insights-weekly   "$PREFIX.insights-weekly"   "$CAL_I"
  mk daily-maintenance  "$PREFIX.daily-maintenance" "$CAL_M"
  mk update-brain-weekly "$PREFIX.update-brain-weekly" "$CAL_U"
  echo "  (desinstalar: bash scripts/schedule.sh --remove \"$VAULT\")"
else
  L=$(cfg "d.get('journal',{}).get('time','20:30')")
  crontab -l 2>/dev/null | grep -v "# ai-brain" > /tmp/ai-brain-cron.$$ || true
  { echo "# ai-brain $SLUG"
    echo "$(hm "$L") $(pm "$L") * * 1-5 /bin/bash $J/journal-reminder.sh # ai-brain"
    echo "$(hm "$JTIME") $(pm "$JTIME") * * 0 /bin/bash $J/insights-weekly.sh # ai-brain"
    echo "$(hm "$MTIME") $(pm "$MTIME") * * * /bin/bash $J/daily-maintenance.sh # ai-brain"
    echo "$(hm "$UTIME") $(pm "$UTIME") * * 1 /bin/bash $J/update-brain.sh # ai-brain"
  } >> /tmp/ai-brain-cron.$$
  crontab /tmp/ai-brain-cron.$$ && rm -f /tmp/ai-brain-cron.$$ && echo "  + 4 entradas crontab instaladas"
fi
