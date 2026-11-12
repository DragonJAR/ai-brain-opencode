#!/usr/bin/env bash
# Recordatorio del diario. Notificación del sistema operativo.
set -euo pipefail
LIB="$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
[ -f "$LIB" ] || { echo "falta scripts/lib/common.sh; re-ejecuta install.sh sobre este vault" >&2; exit 1; }
# shellcheck source=/dev/null
. "$LIB"
job_init

INFO="$(brain_config "$CFG" get vault_name journal.time 2>> "$LOG")" || job_fail "no se pudo leer brain-config.json"
NAME=$(printf '%s\n' "$INFO" | sed -n '1p')
TIME_=$(printf '%s\n' "$INFO" | sed -n '2p')
MESSAGE="Hora del diario ($TIME_). Abre OpenCode en $NAME y escribe /daily-journal"

# La notificación es cosmética: sin sesión gráfica no llega, y eso no es un
# fallo del trabajo. Queda anotado en el log.
case "$(uname -s)" in
  Darwin)
    osascript - "$NAME" "$MESSAGE" <<'APPLESCRIPT' >/dev/null 2>&1 || job_log "osascript no pudo notificar"
on run argv
    display notification (item 2 of argv) with title (item 1 of argv) sound name "Pop"
end run
APPLESCRIPT
    ;;
  Linux)
    # cron no hereda la sesión de escritorio: sin el bus del usuario notify-send no llega.
    if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "/run/user/$(id -u)/bus" ]; then
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
      export DBUS_SESSION_BUS_ADDRESS
    fi
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "$NAME" "$MESSAGE" >/dev/null 2>&1 || job_log "notify-send no pudo notificar"
    else
      job_log "notify-send no disponible"
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    # Toast nativo. Título y mensaje viajan por el entorno, no dentro del script.
    BRAIN_NOTIFY_TITLE="$NAME" BRAIN_NOTIFY_MESSAGE="$MESSAGE" powershell.exe -NoProfile -NonInteractive -Command '
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
$text = $xml.GetElementsByTagName("text")
$text.Item(0).AppendChild($xml.CreateTextNode($env:BRAIN_NOTIFY_TITLE)) | Out-Null
$text.Item(1).AppendChild($xml.CreateTextNode($env:BRAIN_NOTIFY_MESSAGE)) | Out-Null
$app = "{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
' >/dev/null 2>&1 || job_log "powershell no pudo notificar"
    ;;
esac
job_log "$MESSAGE"
echo "$NAME: $MESSAGE"
