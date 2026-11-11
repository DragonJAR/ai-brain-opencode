#!/usr/bin/env bash
# schedule.sh — instala, muestra o elimina los trabajos programados del vault.
#   bash scripts/schedule.sh <ruta-del-vault>            instala (launchd en macOS, cron en Linux)
#   bash scripts/schedule.sh <ruta-del-vault> --dry-run  muestra los trabajos sin registrarlos
#   bash scripts/schedule.sh <ruta-del-vault> --remove   elimina solo los trabajos verificados del paquete
# Requisitos: macOS o Linux (en Windows usa WSL2 con cron activo).
set -euo pipefail

VAULT="${1:-}"
MODE="${2:-install}"
if [ "$VAULT" = "--help" ] || [ "$VAULT" = "-h" ] || [ "$MODE" = "--help" ] || [ "$MODE" = "-h" ]; then
  sed -n '2,/^set -/p' "$0" | sed '$d'; exit 0
fi
[ -n "$VAULT" ] || { echo "uso: $0 <ruta-del-vault> [--dry-run|--remove|--help]" >&2; exit 1; }
[ -d "$VAULT" ] || { echo "  ✗ el vault no existe: $VAULT" >&2; exit 1; }
case "$MODE" in install|--dry-run|--remove) ;; *) echo "  ✗ modo desconocido: $MODE" >&2; exit 2 ;; esac
VAULT="$(cd "$VAULT" && pwd)"
OS="$(uname -s)"
SLUG="$(basename "$VAULT" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')"
SLUG="${SLUG:-cerebro}"
PREFIX="com.ai-brain.$SLUG"
J="$VAULT/scripts/jobs"
BRC="$VAULT/⚙️ Meta/brain-config.json"
MANIFEST="$VAULT/.opencode/brain-vault-install-manifest.json"
OWNERSHIP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/ownership.py"

say() { printf '%s\n' "$*"; }
ok() { printf '  + %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die() { printf '  ✗ %s\n' "$*" >&2; exit 1; }

[ -f "$OWNERSHIP" ] || die "paquete incompleto: falta scripts/lib/ownership.py"

case "$OS" in
  Darwin|Linux) ;;
  *)
    die "el scheduler soporta macOS y Linux; en Windows usa WSL2 con cron activo" ;;
esac

if [ -L "$VAULT/.opencode" ]; then
  warn "el .opencode del vault es un symlink; la propiedad de los trabajos es ambigua"
  [ "$MODE" = "--remove" ] && exit 0
  exit 1
fi

owner_manifest() {
  python3 "$OWNERSHIP" "$MANIFEST" "$@"
}

cron_value() {
  python3 - "$BRC" "$1" "$2" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
default = sys.argv[3]
if not path.is_file():
    print(default); sys.exit(0)
try:
    cur = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    print(default); sys.exit(0)
for key in sys.argv[2].split("."):
    if not isinstance(cur, dict) or key not in cur:
        print(default); sys.exit(0)
    cur = cur[key]
print(cur)
PY
}

# A schedule value must be HH:MM; anything else falls back to the documented default.
config_time() {
  local value="$1" default="$2" label="$3"
  if printf '%s' "$value" | grep -Eq '^([01]?[0-9]|2[0-3]):[0-5][0-9]$'; then
    printf '%s' "$value"
  else
    warn "$label inválida en brain-config.json ('$value'); se usa $default"
    printf '%s' "$default"
  fi
}

hm() { printf '%s\n' "$1" | cut -d: -f1; }
pm() { printf '%s\n' "$1" | cut -d: -f2 | sed 's/^0//'; }

write_cron_lines() {
  local marker="$1"
  printf '%s %s * * 1-5 /bin/bash "%s/journal-reminder.sh" %s\n' "$(hm "$JT")" "$(pm "$JT")" "$J" "$marker"
  printf '%s %s * * 0 /bin/bash "%s/insights-weekly.sh" %s\n' "$(hm "$ITIME")" "$(pm "$ITIME")" "$J" "$marker"
  printf '%s %s * * * /bin/bash "%s/daily-maintenance.sh" %s\n' "$(hm "$MTIME")" "$(pm "$MTIME")" "$J" "$marker"
  printf '%s %s * * 1 /bin/bash "%s/update-brain.sh" %s\n' "$(hm "$UTIME")" "$(pm "$UTIME")" "$J" "$marker"
}

reconcile_crontab() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json, pathlib, sys
current_path, generated_path, output_path = map(pathlib.Path, sys.argv[1:4])
previous = json.loads(sys.argv[4])
current = current_path.read_text(encoding="utf-8").splitlines(keepends=True)
for old in previous:
    for index, line in enumerate(current):
        if line.rstrip("\r\n") == old:
            current.pop(index)
            break
owned = []
for line in generated_path.read_text(encoding="utf-8").splitlines(keepends=True):
    value = line.rstrip("\r\n")
    if not any(existing.rstrip("\r\n") == value for existing in current):
        current.append(line)
        owned.append(value)
output_path.write_text("".join(current), encoding="utf-8")
print(json.dumps(owned, ensure_ascii=False, separators=(",", ":")))
PY
}

read_crontab() {
  local output="$1" errors rc
  errors="$(mktemp "${TMPDIR:-/tmp}/ai-brain-crontab-error.XXXXXX")"
  if crontab -l > "$output" 2> "$errors"; then
    rm -f "$errors"
    return 0
  else
    rc=$?
  fi
  if grep -qi 'no crontab for' "$errors"; then
    : > "$output"
    rm -f "$errors"
    return 0
  fi
  cat "$errors" >&2
  rm -f "$errors"
  return "$rc"
}

if [ "$MODE" = "--remove" ]; then
  if CRON_JSON="$(owner_manifest cron-json 2>/dev/null)"; then
    :
  else
    manifest_status=$?
    if [ "$manifest_status" -eq 2 ]; then
      warn "la propiedad de cron es ambigua (formato anterior); se preservaron los trabajos y el manifiesto"
      exit 1
    fi
    warn "manifiesto de propiedad ausente o inválido; se preservaron los artefactos programados"
    exit 0
  fi
  if [ "$OS" = "Darwin" ]; then
    AGENT_LIST="$(mktemp "${TMPDIR:-/tmp}/ai-brain-agents.XXXXXX")"
    trap 'rm -f "$AGENT_LIST"' EXIT
    owner_manifest agents-tsv > "$AGENT_LIST"
    while IFS=$'\t' read -r agent_path label; do
      [ -n "$agent_path" ] || continue
      case "$label" in "$PREFIX".*) ;; *) continue ;; esac
      [ "$agent_path" = "$HOME/Library/LaunchAgents/$label.plist" ] || continue
      if owner_manifest agent-matches "$agent_path" >/dev/null 2>&1; then
        launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
        rm -f "$agent_path"
      else
        warn "launch agent modificado o no verificado, preservado: $agent_path"
      fi
    done < "$AGENT_LIST"
    owner_manifest clear-agents
  elif [ "$CRON_JSON" != "[]" ]; then
    CURRENT="$(mktemp "${TMPDIR:-/tmp}/ai-brain-cron-current.XXXXXX")"
    GENERATED="$(mktemp "${TMPDIR:-/tmp}/ai-brain-cron-empty.XXXXXX")"
    UPDATED="$(mktemp "${TMPDIR:-/tmp}/ai-brain-cron-updated.XXXXXX")"
    trap 'rm -f "$CURRENT" "$GENERATED" "$UPDATED"' EXIT
    read_crontab "$CURRENT" || { warn "no se pudo leer el crontab; se preservaron los registros de propiedad"; exit 1; }
    OWNED="$(reconcile_crontab "$CURRENT" "$GENERATED" "$UPDATED" "$CRON_JSON")"
    if ! cmp -s "$CURRENT" "$UPDATED"; then crontab "$UPDATED"; fi
    owner_manifest clear-cron
  else
    say "No hay entradas de cron verificadas del paquete para eliminar."
  fi
  exit 0
fi

JT="$(config_time "$(cron_value 'journal.time' '20:30')" '20:30' 'journal.time')"
ITIME="$(config_time "$(cron_value 'schedule.insights_time' '21:00')" '21:00' 'schedule.insights_time')"
MTIME="$(config_time "$(cron_value 'schedule.maintenance_time' '03:30')" '03:30' 'schedule.maintenance_time')"
UTIME="$(config_time "$(cron_value 'schedule.update_time' '08:00')" '08:00' 'schedule.update_time')"

if [ "$MODE" = "--dry-run" ] && [ "$OS" != "Darwin" ]; then
  write_cron_lines "# ai-brain $SLUG owner=<dry-run>"
  exit 0
fi

if [ "$MODE" = "--dry-run" ]; then
  INSTANCE="dry-run"
else
  owner_manifest init || { echo "  ✗ manifiesto de propiedad inválido; no se cambió la programación" >&2; exit 1; }
  INSTANCE="$(owner_manifest instance)"
fi

if [ "$OS" = "Darwin" ]; then
  mk() {
    local job="$1" label="$2" cal="$3" plist=""
    if [ "$MODE" = "--dry-run" ]; then
      plist="$(mktemp "${TMPDIR:-/tmp}/ai-brain-${label}.XXXXXX")"
    else
      plist="$HOME/Library/LaunchAgents/$label.plist"
      if [ -L "$plist" ]; then warn "launch agent symlink preservado: $plist"; return 0; fi
      if [ -e "$plist" ] && ! owner_manifest agent-matches "$plist" >/dev/null 2>&1; then
        warn "launch agent sin propiedad o modificado, preservado: $plist"
        return 0
      fi
      mkdir -p "$HOME/Library/LaunchAgents"
    fi
    cat > "$plist" <<PL
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
    if [ "$MODE" = "--dry-run" ]; then
      echo "  (dry-run) $label"
      plutil -lint "$plist" >/dev/null 2>&1 && echo "    plist válido" || echo "    ! plist inválido"
      rm -f "$plist"
      return 0
    fi
    owner_manifest record-agent "$plist" "$label" || { warn "no se pudo registrar el launch agent: $plist"; return 0; }
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$plist" && ok "$label" || echo "  ! $label (falló el bootstrap)"
  }
  CAL_J="<key>StartCalendarInterval</key><array>$(for wd in 1 2 3 4 5; do printf '<dict><key>Hour</key><integer>%s</integer><key>Minute</key><integer>%s</integer><key>Weekday</key><integer>%s</integer></dict>' "$(hm "$JT")" "$(pm "$JT")" "$wd"; done)</array>"
  CAL_I="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$ITIME")</integer><key>Minute</key><integer>$(pm "$ITIME")</integer><key>Weekday</key><integer>0</integer></dict>"
  CAL_M="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$MTIME")</integer><key>Minute</key><integer>$(pm "$MTIME")</integer></dict>"
  CAL_U="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$UTIME")</integer><key>Minute</key><integer>$(pm "$UTIME")</integer><key>Weekday</key><integer>1</integer></dict>"
  mk journal-reminder "$PREFIX.journal-reminder" "$CAL_J"
  mk insights-weekly "$PREFIX.insights-weekly" "$CAL_I"
  mk daily-maintenance "$PREFIX.daily-maintenance" "$CAL_M"
  mk update-brain-weekly "$PREFIX.update-brain-weekly" "$CAL_U"
else
  MARK="# ai-brain $SLUG owner=$INSTANCE"
  GENERATED="$(mktemp "${TMPDIR:-/tmp}/ai-brain-cron-new.XXXXXX")"
  CURRENT="$(mktemp "${TMPDIR:-/tmp}/ai-brain-cron-current.XXXXXX")"
  UPDATED="$(mktemp "${TMPDIR:-/tmp}/ai-brain-cron-updated.XXXXXX")"
  trap 'rm -f "$GENERATED" "$CURRENT" "$UPDATED"' EXIT
  write_cron_lines "$MARK" > "$GENERATED"
  read_crontab "$CURRENT" || { warn "no se pudo leer el crontab; no se cambió la programación"; exit 1; }
  PREVIOUS="$(owner_manifest cron-json)"
  OWNED="$(reconcile_crontab "$CURRENT" "$GENERATED" "$UPDATED" "$PREVIOUS")"
  if ! cmp -s "$CURRENT" "$UPDATED"; then
    crontab "$UPDATED"
    ok "4 entradas de cron propias ($MARK)"
  else
    ok "las entradas de cron propias ya están al día"
  fi
  owner_manifest set-cron "$OWNED"
fi
