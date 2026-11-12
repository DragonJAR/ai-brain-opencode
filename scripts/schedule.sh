#!/usr/bin/env bash
# schedule.sh — instala, muestra o elimina los trabajos programados del vault.
#   bash scripts/schedule.sh <ruta-del-vault>            instala (launchd en macOS, cron en Linux, schtasks en Windows)
#   bash scripts/schedule.sh <ruta-del-vault> --dry-run  muestra los trabajos sin registrarlos
#   bash scripts/schedule.sh <ruta-del-vault> --remove   elimina solo los trabajos verificados del paquete
# Requisitos: macOS, Linux o Windows nativo (Git Bash, con cygpath).
set -euo pipefail

VAULT="${1:-}"
MODE="${2:-install}"
if [ "$VAULT" = "--help" ] || [ "$VAULT" = "-h" ] || [ "$MODE" = "--help" ] || [ "$MODE" = "-h" ]; then
  sed -n '2,/^set -/p' "$0" | sed '$d'; exit 0
fi
[ -n "$VAULT" ] || { echo "uso: $0 <ruta-del-vault> [--dry-run|--remove|--help]" >&2; exit 1; }
[ -d "$VAULT" ] || { echo "  ✗ el vault no existe: $VAULT" >&2; exit 1; }
case "$MODE" in install|--dry-run|--remove) ;; *) echo "  ✗ modo desconocido: $MODE" >&2; exit 2 ;; esac
VAULT="$(cd "$VAULT" && pwd -P)"
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

# `launchctl print` falla cuando el agente no está cargado: ese es el caso esperado.
# `bootout` solo corre después, y un fallo real de descarga queda a la vista.
bootout_loaded() {
  local label="$1" domain
  domain="gui/$(id -u)/$label"
  if launchctl print "$domain" >/dev/null 2>&1; then
    launchctl bootout "$domain" || warn "no se pudo descargar $label"
  fi
}

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/python3.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/python3.sh"
pick_python3 || die "falta Python >= 3.9 (python3, py -3 o python)"
EXAMPLE="$PKG/templates/brain-config.example.json"
[ -f "$OWNERSHIP" ] || die "paquete incompleto: falta scripts/lib/ownership.py"
[ -f "$EXAMPLE" ] || die "paquete incompleto: falta templates/brain-config.example.json"

package_default() {
  $PY3 - "$EXAMPLE" "$1" <<'PY'
import json, pathlib, sys
path, dotted = sys.argv[1], sys.argv[2]
try:
    cur = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
except Exception as error:
    sys.stderr.write("json inválido: %s\n" % error)
    raise SystemExit(1)
for key in dotted.split("."):
    if not isinstance(cur, dict) or key not in cur:
        sys.stderr.write("falta %s\n" % dotted)
        raise SystemExit(1)
    cur = cur[key]
if not isinstance(cur, str) or not cur.strip():
    sys.stderr.write("falta %s\n" % dotted)
    raise SystemExit(1)
sys.stdout.write(cur.strip())
PY
}

default_or_die() {
  local key value
  key="$1"
  if ! value="$(package_default "$key")"; then
    die "paquete incompleto: templates/brain-config.example.json no declara $key"
  fi
  printf '%s' "$value" | grep -Eq '^([01]?[0-9]|2[0-3]):[0-5][0-9]$' \
    || die "paquete incompleto: $key en templates/brain-config.example.json no es HH:MM"
  printf '%s' "$value"
}

WIN=0
case "$OS" in
  Darwin|Linux) ;;
  MINGW*|MSYS*|CYGWIN*) WIN=1 ;;
  *)
    die "el scheduler soporta macOS, Linux y Windows nativo (Git Bash); plataforma: $OS" ;;
esac

if [ -L "$VAULT/.opencode" ]; then
  warn "el .opencode del vault es un symlink; la propiedad de los trabajos es ambigua"
  [ "$MODE" = "--remove" ] && exit 0
  exit 1
fi

owner_manifest() {
  $PY3 "$OWNERSHIP" "$MANIFEST" "$@"
}

cron_value() {
  $PY3 - "$BRC" "$1" "$2" <<'PY'
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

# El plist es XML. &, <, > y las comillas no pueden entrar crudos en el texto.
xml_escape() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\\&apos;/g"
}

# Cron reads minute then hour. hm() is HH and pm() is MM; launchd uses them in the other order.
write_cron_lines() {
  local marker="$1"
  printf '%s %s * * 1-5 /bin/bash "%s/journal-reminder.sh" %s\n' "$(pm "$JT")" "$(hm "$JT")" "$J" "$marker"
  printf '%s %s * * 0 /bin/bash "%s/insights-weekly.sh" %s\n' "$(pm "$ITIME")" "$(hm "$ITIME")" "$J" "$marker"
  printf '%s %s * * * /bin/bash "%s/daily-maintenance.sh" %s\n' "$(pm "$MTIME")" "$(hm "$MTIME")" "$J" "$marker"
  printf '%s %s * * 1 /bin/bash "%s/update-brain.sh" %s\n' "$(pm "$UTIME")" "$(hm "$UTIME")" "$J" "$marker"
}

reconcile_crontab() {
  $PY3 - "$1" "$2" "$3" "$4" <<'PY'
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

sch_st() {
  local h m
  h="${1%%:*}"
  m="${1#*:}"
  printf '%02d:%02d' "$((10#$h))" "$((10#$m))"
}

write_windows_runner() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  # where bash, y si no está en PATH las rutas del instalador de Git for Windows.
  # La línea bash "%~dp0%JOB%.sh" queda: es el contrato que afirma el test.
  printf '%s\r\n' \
    '@echo off' \
    'set "JOB=%~1"' \
    'if "%JOB%"=="" exit /b 2' \
    'where bash >nul 2>&1 && goto :run_path' \
    'if exist "%ProgramFiles%\Git\bin\bash.exe" goto :run_pf' \
    'if exist "%ProgramFiles%\Git\usr\bin\bash.exe" goto :run_usr' \
    'if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" goto :run_x86' \
    'if exist "%LocalAppData%\Programs\Git\bin\bash.exe" goto :run_local' \
    'echo No se encontro bash. Instala Git for Windows o agregalo al PATH. 1>&2' \
    'exit /b 127' \
    ':run_path' \
    'bash "%~dp0%JOB%.sh"' \
    'exit /b %ERRORLEVEL%' \
    ':run_pf' \
    '"%ProgramFiles%\Git\bin\bash.exe" "%~dp0%JOB%.sh"' \
    'exit /b %ERRORLEVEL%' \
    ':run_usr' \
    '"%ProgramFiles%\Git\usr\bin\bash.exe" "%~dp0%JOB%.sh"' \
    'exit /b %ERRORLEVEL%' \
    ':run_x86' \
    '"%ProgramFiles(x86)%\Git\bin\bash.exe" "%~dp0%JOB%.sh"' \
    'exit /b %ERRORLEVEL%' \
    ':run_local' \
    '"%LocalAppData%\Programs\Git\bin\bash.exe" "%~dp0%JOB%.sh"' \
    'exit /b %ERRORLEVEL%' \
    > "$dest"
}

# Tareas propias: los nombres se registran en el manifiesto (cron_lines) ANTES
# de crearlas, para que --remove borre solo lo verificado con la misma garantía
# que en POSIX.
TASK_FAILED=0

windows_task() {
  local job="$1" sc="$2" days="$3" when="$4" tn tr
  tn="ai-brain ${SLUG} ${job}"
  tr="\"${WIN_RUNNER}\" ${job}"
  if [ "$MODE" = "--dry-run" ]; then
    if [ -n "$days" ]; then
      printf 'schtasks /Create /F /TN "%s" /SC %s /D %s /ST %s /TR %s\n' "$tn" "$sc" "$days" "$when" "$tr"
    else
      printf 'schtasks /Create /F /TN "%s" /SC %s /ST %s /TR %s\n' "$tn" "$sc" "$when" "$tr"
    fi
    return 0
  fi
  local created=0
  if [ -n "$days" ]; then
    schtasks /Create /F /TN "$tn" /SC "$sc" /D "$days" /ST "$when" /TR "$tr" && created=1
  else
    schtasks /Create /F /TN "$tn" /SC "$sc" /ST "$when" /TR "$tr" && created=1
  fi
  if [ "$created" = 1 ]; then
    ok "$tn"
  else
    warn "no se pudo crear la tarea $tn"
    TASK_FAILED=1
  fi
}

windows_schedule() {
  local runner="$J/ai-brain-run.cmd"
  command -v cygpath >/dev/null 2>&1 || die "falta cygpath (lo requiere schtasks)"
  WIN_RUNNER="$(cygpath -w "$runner")"
  if [ "$MODE" != "--dry-run" ]; then
    command -v schtasks >/dev/null 2>&1 || die "falta schtasks"
    write_windows_runner "$runner"
    owner_manifest init || die "manifiesto de propiedad inválido; no se cambió la programación"
    owner_manifest record-file "scripts/jobs/ai-brain-run.cmd" "$runner" \
      || warn "no se pudo registrar scripts/jobs/ai-brain-run.cmd"
    # Los nombres son deterministas: se registran ANTES de crear para que una
    # falla a medias nunca deje tareas instaladas sin dueño.
    owner_manifest set-cron "[\"ai-brain ${SLUG} journal-reminder\", \"ai-brain ${SLUG} insights-weekly\", \"ai-brain ${SLUG} daily-maintenance\", \"ai-brain ${SLUG} update-brain\"]" \
      || die "no se pudo registrar la propiedad de las tareas; bórralas a mano con schtasks /Delete"
  fi
  windows_task journal-reminder WEEKLY "MON,TUE,WED,THU,FRI" "$(sch_st "$JT")"
  windows_task insights-weekly WEEKLY "SUN" "$(sch_st "$ITIME")"
  windows_task daily-maintenance DAILY "" "$(sch_st "$MTIME")"
  windows_task update-brain WEEKLY "MON" "$(sch_st "$UTIME")"
  if [ "$MODE" != "--dry-run" ] && [ "$TASK_FAILED" != 0 ]; then
    die "no se pudieron crear todas las tareas de Windows; revisa el output de schtasks"
  fi
}

windows_schtasks_remove() {
  local owned_json="$1" csv name bare names owned removed
  command -v schtasks >/dev/null 2>&1 || die "falta schtasks"
  csv="$(schtasks /Query /FO CSV /NH 2>/dev/null)" || die "no se pudo listar las tareas programadas"
  names="$(mktemp "${TMPDIR:-/tmp}/ai-brain-schtasks-names.XXXXXX")"
  owned="$(mktemp "${TMPDIR:-/tmp}/ai-brain-schtasks-owned.XXXXXX")"
  printf '%s\n' "$owned_json" | $PY3 -c 'import json, sys
for name in json.load(sys.stdin):
    print(name)' > "$owned"
  # El CSV de schtasks es citado: los nombres de tarea pueden contener comas.
  printf '%s\n' "$csv" | $PY3 -c 'import csv, io, sys
for row in csv.reader(io.StringIO(sys.stdin.read())):
    if row and row[0].strip():
        print(row[0].strip().lstrip("\\"))
' > "$names"
  removed=0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    grep -qxF "$name" "$names" || continue
    if ! schtasks /Delete /F /TN "$name"; then
      warn "no se pudo borrar la tarea $name"
      rm -f "$names" "$owned"
      exit 1
    fi
    ok "tarea eliminada: $name"
    removed=$((removed + 1))
  done < "$owned"
  while IFS= read -r bare; do
    [ -n "$bare" ] || continue
    case "$bare" in
      "ai-brain "*)
        grep -qxF "$bare" "$owned" || warn "tarea ajena preservada: $bare"
        ;;
    esac
  done < "$names"
  rm -f "$names" "$owned"
  owner_manifest clear-cron
  [ "$removed" -gt 0 ] || say "No hay tareas de Windows registradas del paquete para eliminar."
}

if [ "$MODE" = "--remove" ]; then
  if CRON_JSON="$(owner_manifest cron-json 2>/dev/null)"; then
    :
  else
    manifest_status=$?
    if [ "$manifest_status" -eq 2 ]; then
      warn "la propiedad de los trabajos es ambigua (formato anterior); se preservaron los trabajos y el manifiesto"
      exit 1
    fi
    warn "manifiesto de propiedad ausente o inválido; se preservaron los artefactos programados"
    exit 0
  fi
  if [ "$WIN" = 1 ]; then
    windows_schtasks_remove "$CRON_JSON"
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
        bootout_loaded "$label"
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

JT_DEFAULT="$(default_or_die journal.time)" || exit 1
IT_DEFAULT="$(default_or_die schedule.insights_time)" || exit 1
MT_DEFAULT="$(default_or_die schedule.maintenance_time)" || exit 1
UT_DEFAULT="$(default_or_die schedule.update_time)" || exit 1
JT="$(config_time "$(cron_value 'journal.time' "$JT_DEFAULT")" "$JT_DEFAULT" 'journal.time')"
ITIME="$(config_time "$(cron_value 'schedule.insights_time' "$IT_DEFAULT")" "$IT_DEFAULT" 'schedule.insights_time')"
MTIME="$(config_time "$(cron_value 'schedule.maintenance_time' "$MT_DEFAULT")" "$MT_DEFAULT" 'schedule.maintenance_time')"
UTIME="$(config_time "$(cron_value 'schedule.update_time' "$UT_DEFAULT")" "$UT_DEFAULT" 'schedule.update_time')"

if [ "$WIN" = 1 ]; then
  windows_schedule
  exit 0
fi

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
    local xml_label xml_program xml_log
    xml_label="$(xml_escape "$label")"
    xml_program="$(xml_escape "$J/$job.sh")"
    xml_log="$(xml_escape "$VAULT/⚙️ Meta/logs/$job.log")"
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
<key>Label</key><string>$xml_label</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$xml_program</string></array>
$cal
<key>StandardOutPath</key><string>$xml_log</string>
<key>StandardErrorPath</key><string>$xml_log</string>
</dict></plist>
PL
    if ! plutil -lint "$plist" >/dev/null 2>&1; then
      echo "  ✗ plist inválido: $label" >&2
      rm -f "$plist"
      return 1
    fi
    if [ "$MODE" = "--dry-run" ]; then
      echo "  (dry-run) $label"
      echo "    plist válido"
      rm -f "$plist"
      return 0
    fi
    if ! owner_manifest record-agent "$plist" "$label"; then
      rm -f "$plist"   # sin registro no hay dueño: mejor no dejar el huérfano
      warn "no se pudo registrar el launch agent: $plist"
      return 0
    fi
    bootout_loaded "$label"
    launchctl bootstrap "gui/$(id -u)" "$plist" && ok "$label" || echo "  ! $label (falló el bootstrap)"
  }
  CAL_J="<key>StartCalendarInterval</key><array>$(for wd in 1 2 3 4 5; do printf '<dict><key>Hour</key><integer>%s</integer><key>Minute</key><integer>%s</integer><key>Weekday</key><integer>%s</integer></dict>' "$(hm "$JT")" "$(pm "$JT")" "$wd"; done)</array>"
  CAL_I="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$ITIME")</integer><key>Minute</key><integer>$(pm "$ITIME")</integer><key>Weekday</key><integer>0</integer></dict>"
  CAL_M="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$MTIME")</integer><key>Minute</key><integer>$(pm "$MTIME")</integer></dict>"
  CAL_U="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$UTIME")</integer><key>Minute</key><integer>$(pm "$UTIME")</integer><key>Weekday</key><integer>1</integer></dict>"
  mk journal-reminder "$PREFIX.journal-reminder" "$CAL_J" || warn "launch agent omitido: $PREFIX.journal-reminder"
  mk insights-weekly "$PREFIX.insights-weekly" "$CAL_I" || warn "launch agent omitido: $PREFIX.insights-weekly"
  mk daily-maintenance "$PREFIX.daily-maintenance" "$CAL_M" || warn "launch agent omitido: $PREFIX.daily-maintenance"
  mk update-brain-weekly "$PREFIX.update-brain-weekly" "$CAL_U" || warn "launch agent omitido: $PREFIX.update-brain-weekly"
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
  # La propiedad se registra ANTES de aplicar: si el registro fallara después,
  # las líneas nuevas quedarían instaladas pero sin dueño (--remove no las vería).
  owner_manifest set-cron "$OWNED" \
    || { warn "no se pudo registrar la propiedad de las líneas; no se cambió el crontab"; exit 1; }
  if ! cmp -s "$CURRENT" "$UPDATED"; then
    crontab "$UPDATED"
    ok "4 entradas de cron propias ($MARK)"
  else
    ok "las entradas de cron propias ya están al día"
  fi
fi
