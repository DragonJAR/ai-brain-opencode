#!/usr/bin/env bash
# schedule.sh — instala, muestra o elimina los trabajos programados del vault.
#   bash scripts/schedule.sh <ruta-del-vault>            instala (launchd en macOS, cron en Linux, schtasks en Windows)
#   bash scripts/schedule.sh <ruta-del-vault> --dry-run  muestra los trabajos sin registrarlos
#   bash scripts/schedule.sh <ruta-del-vault> --remove   elimina solo los trabajos verificados del paquete
#   bash scripts/schedule.sh <ruta-del-vault> --remove --dry-run  lista lo que --remove eliminaría, sin tocar nada
# Requisitos: macOS, Linux o Windows nativo (Git Bash, con cygpath).
set -euo pipefail
# common.sh también lo quita, pero la ruta del paquete se calcula antes de cargarlo.
unset CDPATH

VAULT="${1:-}"
MODE="${2:-install}"
if [ "$VAULT" = "--help" ] || [ "$VAULT" = "-h" ] || [ "$MODE" = "--help" ] || [ "$MODE" = "-h" ]; then
  sed -n '2,/^set -/p' "$0" | sed '$d'; exit 0
fi
[ -n "$VAULT" ] || { echo "uso: $0 <ruta-del-vault> [--dry-run|--remove [--dry-run]|--help]" >&2; exit 1; }
[ -d "$VAULT" ] || { echo "  ✗ el vault no existe: $VAULT" >&2; exit 1; }
case "$MODE" in install|--dry-run|--remove) ;; *) echo "  ✗ modo desconocido: $MODE" >&2; exit 2 ;; esac
REMOVE_DRY_RUN=0
case "$MODE ${3:-}" in
  "--remove --dry-run") REMOVE_DRY_RUN=1 ;;
  *" ") ;;
  *) echo "  ✗ argumento inesperado: $3" >&2; exit 2 ;;
esac

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
[ -f "$LIB/common.sh" ] && [ -f "$LIB/ownership.py" ] && [ -f "$LIB/brain_config.py" ] \
  || { echo "  ✗ paquete incompleto: faltan archivos en scripts/lib" >&2; exit 1; }
# shellcheck source=lib/common.sh
. "$LIB/common.sh"
pick_python3 || die "falta Python >= 3.9 (python3, py -3 o python)"

VAULT="$(cd "$VAULT" && pwd -P)"
OS="$(uname -s)"
SLUG="$(vault_slug "$VAULT")"
PREFIX="com.ai-brain.$SLUG"
J="$VAULT/scripts/jobs"
BRC="$VAULT/⚙️ Meta/brain-config.json"
MANIFEST="$VAULT/$BRAIN_MANIFEST_REL"
AGENTS_DIR="$HOME/Library/LaunchAgents"

# Fuente única de los trabajos: nombre | clave del horario | días.
# Los días usan el campo día-de-semana de cron (0 = domingo); launchd y schtasks
# se derivan de aquí, así que un trabajo nuevo es una línea nueva.
JOB_TABLE='journal-reminder|journal.time|1-5
insights-weekly|schedule.insights_time|0
daily-maintenance|schedule.maintenance_time|*
update-brain|schedule.update_time|1'

case "$OS" in
  Darwin|Linux) ;;
  MINGW*|MSYS*|CYGWIN*) ;;
  *) die "el scheduler soporta macOS, Linux y Windows nativo (Git Bash); plataforma: $OS" ;;
esac

if [ -L "$VAULT/.opencode" ]; then
  warn "el .opencode del vault es un symlink; la propiedad de los trabajos es ambigua"
  [ "$MODE" = "--remove" ] && exit 0
  exit 1
fi

owner_manifest() {
  run_python "$LIB/ownership.py" "$MANIFEST" "$@"
}

# `launchctl print` falla cuando el agente no está cargado: ese es el caso esperado.
# `bootout` solo corre después, y un fallo real de descarga queda a la vista.
bootout_loaded() {
  local label="$1" domain
  domain="gui/$(id -u)/$label"
  if launchctl print "$domain" >/dev/null 2>&1; then
    launchctl bootout "$domain" || warn "no se pudo descargar $label"
  fi
}

# Retira un launch agent propio y sin cambios, y olvida su registro. Uno
# modificado se preserva junto con su registro.
remove_owned_agent() {
  local agent_path="$1" label="$2"
  if [ ! -e "$agent_path" ] && [ ! -L "$agent_path" ]; then
    [ "$REMOVE_DRY_RUN" = 1 ] || owner_manifest forget-agent "$agent_path"
  elif owner_manifest agent-matches "$agent_path" >/dev/null 2>&1; then
    if [ "$REMOVE_DRY_RUN" = 1 ]; then say "  ~ launch agent $agent_path"; return 0; fi
    bootout_loaded "$label"
    rm -f "$agent_path"
    owner_manifest forget-agent "$agent_path"
  else
    warn "launch agent modificado o no verificado, preservado: $agent_path"
  fi
}

# for_owned_agents <función>: llama <función> <ruta> <etiqueta> por cada launch
# agent registrado que vive donde este paquete los escribe.
for_owned_agents() {
  local callback="$1" list agent_path label
  list="$(mktemp "${TMPDIR:-/tmp}/ai-brain-agents.XXXXXX")"
  owner_manifest agents-tsv > "$list"
  while IFS=$'\t' read -r agent_path label; do
    [ -n "$agent_path" ] || continue
    case "$label" in com.ai-brain.*) ;; *) continue ;; esac
    [ "$agent_path" = "$AGENTS_DIR/$label.plist" ] || continue
    "$callback" "$agent_path" "$label"
  done < "$list"
  rm -f "$list"
}

hm() { printf '%s\n' "$1" | cut -d: -f1; }
pm() { printf '%s\n' "$1" | cut -d: -f2 | sed 's/^0//'; }

# "1-5" -> "1 2 3 4 5"; "0" -> "0"; "*" -> "" (todos los días).
expand_days() {
  local spec="$1" part day out=""
  [ "$spec" = "*" ] && return 0
  local IFS=','
  for part in $spec; do
    case "$part" in
      *-*) day="${part%-*}"; while [ "$day" -le "${part#*-}" ]; do out="$out $day"; day=$((day + 1)); done ;;
      *) out="$out $part" ;;
    esac
  done
  printf '%s' "${out# }"
}

# El plist es XML. &, <, > y las comillas no pueden entrar crudos en el texto.
xml_escape() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\\&apos;/g"
}

# launchd y cron arrancan los trabajos con un PATH mínimo, sin opencode ni el
# Python del usuario. Se conserva el PATH de quien programa, saneado.
schedule_path() {
  local out="" dir
  local IFS=':'
  set -f
  for dir in $PATH /usr/local/bin /usr/bin /bin /usr/sbin /sbin; do
    case "$dir" in /*) ;; *) continue ;; esac
    case "$dir" in *"'"*|*'"'*|*%*|*'&'*|*'<'*|*'>'*|*'\'*|*$'\n'*) continue ;; esac
    [ -d "$dir" ] || continue
    case ":$out:" in *":$dir:"*) continue ;; esac
    out="${out:+$out:}$dir"
  done
  set +f
  printf '%s' "$out"
}

# cron_quote <texto>: el texto literal para el sh de cron. Entre comillas simples
# ($, ` y espacios no se interpretan) y con `%` escapado: cron lo vuelve salto de
# línea y quita la barra de `\%` antes de pasar la línea a sh.
cron_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed -e "s/'/'\\\\''/g" -e 's/%/\\%/g')"
}

# Cron lee minuto y luego hora.
write_cron_lines() {
  local marker="$1" index=0
  while [ "$index" -lt "${#JOB_NAMES[@]}" ]; do
    printf "%s %s * * %s PATH='%s' /bin/bash %s >> %s 2>&1 %s\n" \
      "$(pm "${JOB_TIMES[$index]}")" "$(hm "${JOB_TIMES[$index]}")" "${JOB_DAYS[$index]}" \
      "$SCHEDULE_PATH" "$(cron_quote "$J/${JOB_NAMES[$index]}.sh")" \
      "$(cron_quote "$(job_log_file "$VAULT" "${JOB_NAMES[$index]}")")" "$marker"
    index=$((index + 1))
  done
}

reconcile_crontab() {
  run_python - "$1" "$2" "$3" "$4" <<'PY'
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
# write_text only accepts a newline argument from Python 3.10; open() keeps 3.9 working.
with open(output_path, "w", encoding="utf-8", newline="") as handle:
    handle.write("".join(current))
sys.stdout.reconfigure(encoding="utf-8", newline="\n")
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

# --- Windows (schtasks) --------------------------------------------------------

# Git Bash convierte en rutas los argumentos que empiezan por "/" (/Create,
# /TN...). schtasks necesita recibirlos tal cual.
schtasks_native() {
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' schtasks "$@"
}

# Nombres de las tareas existentes, uno por línea.
windows_task_names() {
  local csv rc=0
  # A un archivo y no a $(...): la salida puede ser UTF-16 (bytes NUL).
  csv="$(mktemp "${TMPDIR:-/tmp}/ai-brain-schtasks.XXXXXX")"
  schtasks_native /Query /FO CSV /NH > "$csv" 2>/dev/null || { rm -f "$csv"; return 1; }
  # El CSV de schtasks es citado: los nombres de tarea pueden contener comas. Su
  # codificación depende de la consola (UTF-8, la página de códigos OEM o ANSI, o
  # UTF-16): se prueba cada una sin reemplazar bytes en silencio.
  run_python - "$csv" <<'PY' || rc=$?
import codecs, csv, io, sys

data = open(sys.argv[1], "rb").read()
encodings = []
if data.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE)):
    encodings.append("utf-16")
encodings.append("utf-8-sig")
try:
    import ctypes
    kernel32 = ctypes.windll.kernel32
    for page in (kernel32.GetConsoleOutputCP(), kernel32.GetOEMCP(), kernel32.GetACP()):
        if page:
            encodings.append("cp%d" % page)
except (AttributeError, OSError):
    pass
encodings += ["cp1252", "latin-1"]
for encoding in encodings:
    try:
        text = data.decode(encoding)
        break
    except (LookupError, UnicodeDecodeError):
        continue
sys.stdout.reconfigure(encoding="utf-8", newline="\n")
for row in csv.reader(io.StringIO(text)):
    if row and row[0].strip():
        print(row[0].strip().lstrip("\\"))
PY
  rm -f "$csv"
  return "$rc"
}

json_lines() {
  printf '%s\n' "$1" | run_python -c 'import json, sys
sys.stdout.reconfigure(encoding="utf-8", newline="\n")
for name in json.load(sys.stdin):
    print(name)'
}

lines_json() {
  run_python -c 'import json, sys
sys.stdout.reconfigure(encoding="utf-8", newline="\n")
print(json.dumps([line for line in sys.stdin.read().splitlines() if line], ensure_ascii=False))'
}

sch_st() {
  local h m
  h="${1%%:*}"
  m="${1#*:}"
  printf '%02d:%02d' "$((10#$h))" "$((10#$m))"
}

# "1 2 3 4 5" -> "MON,TUE,WED,THU,FRI"
windows_days() {
  local names="SUN MON TUE WED THU FRI SAT" day out="" name
  for day in $1; do
    # shellcheck disable=SC2086
    set -- $names
    shift "$day"
    name="$1"
    out="${out:+$out,}$name"
  done
  printf '%s' "$out"
}

write_windows_runner() {
  local dest="$1" git_root
  # El bash que programa es el de Git for Windows: su wrapper bin\bash.exe va
  # primero. `where bash` queda al final: en muchos equipos resuelve antes al
  # lanzador de WSL (System32\bash.exe), que no puede correr estos trabajos.
  git_root="$(cygpath -w / 2>/dev/null || true)"
  git_root="${git_root%\\}"
  # La línea bash "%~dp0%JOB%.sh" queda: es el contrato que afirma el test.
  printf '%s\r\n' \
    '@echo off' \
    'set "JOB=%~1"' \
    'if "%JOB%"=="" exit /b 2' \
    "set \"BRAIN_BASH=${git_root}\\bin\\bash.exe\"" \
    'if exist "%BRAIN_BASH%" goto :run_known' \
    'if exist "%ProgramFiles%\Git\bin\bash.exe" goto :run_pf' \
    'if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" goto :run_x86' \
    'if exist "%LocalAppData%\Programs\Git\bin\bash.exe" goto :run_local' \
    'if exist "%ProgramFiles%\Git\usr\bin\bash.exe" goto :run_usr' \
    'where bash >nul 2>&1 && goto :run_path' \
    'echo No se encontro bash. Instala Git for Windows o agregalo al PATH. 1>&2' \
    'exit /b 127' \
    ':run_known' \
    '"%BRAIN_BASH%" "%~dp0%JOB%.sh"' \
    'exit /b %ERRORLEVEL%' \
    ':run_pf' \
    '"%ProgramFiles%\Git\bin\bash.exe" "%~dp0%JOB%.sh"' \
    'exit /b %ERRORLEVEL%' \
    ':run_x86' \
    '"%ProgramFiles(x86)%\Git\bin\bash.exe" "%~dp0%JOB%.sh"' \
    'exit /b %ERRORLEVEL%' \
    ':run_local' \
    '"%LocalAppData%\Programs\Git\bin\bash.exe" "%~dp0%JOB%.sh"' \
    'exit /b %ERRORLEVEL%' \
    ':run_usr' \
    '"%ProgramFiles%\Git\usr\bin\bash.exe" "%~dp0%JOB%.sh"' \
    'exit /b %ERRORLEVEL%' \
    ':run_path' \
    'bash "%~dp0%JOB%.sh"' \
    'exit /b %ERRORLEVEL%' \
    > "$dest"
}

windows_schedule() {
  local runner="$J/ai-brain-run.cmd" win_runner index=0 tn days sc when existing previous staged wanted=""
  command -v cygpath >/dev/null 2>&1 || die "falta cygpath (lo requiere schtasks)"
  win_runner="$(cygpath -w "$runner")"
  if [ "$MODE" != "--dry-run" ]; then
    command -v schtasks >/dev/null 2>&1 || die "falta schtasks"
    owner_manifest init || die "manifiesto de propiedad inválido; no se cambió la programación"
    staged="$(mktemp "${TMPDIR:-/tmp}/ai-brain-run.XXXXXX")"
    write_windows_runner "$staged"
    owner_manifest install-files "$VAULT" "scripts/jobs/ai-brain-run.cmd" "$staged" - >/dev/null \
      || { rm -f "$staged"; die "no se pudo instalar scripts/jobs/ai-brain-run.cmd"; }
    rm -f "$staged"
    existing="$(windows_task_names)" || die "no se pudo listar las tareas programadas; no se cambió la programación"
    previous="$(json_lines "$(owner_manifest cron-json)")"
    # Una tarea con el mismo nombre que no es de este vault (otro vault con el
    # mismo nombre de carpeta) no se pisa: /Create /F la reemplazaría.
    while [ "$index" -lt "${#JOB_NAMES[@]}" ]; do
      tn="ai-brain ${SLUG} ${JOB_NAMES[$index]}"
      if printf '%s\n' "$existing" | grep -qxF "$tn" && ! printf '%s\n' "$previous" | grep -qxF "$tn"; then
        warn "ya existe una tarea ajena llamada '$tn' (¿otro vault con el mismo nombre de carpeta?); se preservó"
        SCHEDULE_FAILED=1
      else
        wanted="${wanted}${tn}"$'\n'
      fi
      index=$((index + 1))
    done
    # Los nombres se registran ANTES de crear: una falla a medias nunca deja
    # tareas instaladas sin dueño.
    owner_manifest set-cron "$(printf '%s' "$wanted" | lines_json)" \
      || die "no se pudo registrar la propiedad de las tareas; no se cambió la programación"
  fi
  index=0
  while [ "$index" -lt "${#JOB_NAMES[@]}" ]; do
    tn="ai-brain ${SLUG} ${JOB_NAMES[$index]}"
    days="$(windows_days "$(expand_days "${JOB_DAYS[$index]}")")"
    when="$(sch_st "${JOB_TIMES[$index]}")"
    sc=WEEKLY
    [ -n "$days" ] || sc=DAILY
    set -- /Create /F /TN "$tn" /SC "$sc" ${days:+/D "$days"} /ST "$when" /TR "\"$win_runner\" ${JOB_NAMES[$index]}"
    if [ "$MODE" = "--dry-run" ]; then
      printf 'schtasks /Create /F /TN "%s" /SC %s%s /ST %s /TR "%s" %s\n' \
        "$tn" "$sc" "${days:+ /D $days}" "$when" "$win_runner" "${JOB_NAMES[$index]}"
    elif ! printf '%s' "$wanted" | grep -qxF "$tn"; then
      :
    elif schtasks_native "$@"; then
      ok "$tn"
    else
      warn "no se pudo crear la tarea $tn"
      SCHEDULE_FAILED=1
    fi
    index=$((index + 1))
  done
}

windows_remove() {
  local owned_json="$1" names owned name removed=0
  command -v schtasks >/dev/null 2>&1 || die "falta schtasks"
  names="$(windows_task_names)" || die "no se pudo listar las tareas programadas"
  owned="$(json_lines "$owned_json")"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    printf '%s\n' "$names" | grep -qxF "$name" || continue
    if [ "$REMOVE_DRY_RUN" = 1 ]; then say "  ~ tarea $name"; removed=$((removed + 1)); continue; fi
    schtasks_native /Delete /F /TN "$name" || die "no se pudo borrar la tarea $name"
    ok "tarea eliminada: $name"
    removed=$((removed + 1))
  done <<EOF
$owned
EOF
  while IFS= read -r name; do
    case "$name" in
      "ai-brain "*) printf '%s\n' "$owned" | grep -qxF "$name" || warn "tarea ajena preservada: $name" ;;
    esac
  done <<EOF
$names
EOF
  [ "$REMOVE_DRY_RUN" = 1 ] || owner_manifest clear-cron
  [ "$removed" -gt 0 ] || say "No hay tareas de Windows registradas del paquete para eliminar."
}

# --- Eliminación -----------------------------------------------------------------

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
  if is_windows; then
    windows_remove "$CRON_JSON"
  elif [ "$OS" = "Darwin" ]; then
    for_owned_agents remove_owned_agent
  elif [ "$CRON_JSON" != "[]" ]; then
    CURRENT="$(mktemp "${TMPDIR:-/tmp}/ai-brain-cron-current.XXXXXX")"
    GENERATED="$(mktemp "${TMPDIR:-/tmp}/ai-brain-cron-empty.XXXXXX")"
    UPDATED="$(mktemp "${TMPDIR:-/tmp}/ai-brain-cron-updated.XXXXXX")"
    trap 'rm -f "$CURRENT" "$GENERATED" "$UPDATED"' EXIT
    read_crontab "$CURRENT" || { warn "no se pudo leer el crontab; se preservaron los registros de propiedad"; exit 1; }
    reconcile_crontab "$CURRENT" "$GENERATED" "$UPDATED" "$CRON_JSON" >/dev/null
    if [ "$REMOVE_DRY_RUN" = 1 ]; then
      diff "$CURRENT" "$UPDATED" | sed -n 's/^< /  ~ cron /p' || true
      exit 0
    fi
    if ! cmp -s "$CURRENT" "$UPDATED"; then crontab "$UPDATED"; fi
    owner_manifest clear-cron
  else
    say "No hay entradas de cron verificadas del paquete para eliminar."
  fi
  exit 0
fi

# --- Instalación y dry-run -------------------------------------------------------

JOB_NAMES=() JOB_KEYS=() JOB_DAYS=() JOB_TIMES=()
while IFS='|' read -r job_name job_key job_days; do
  JOB_NAMES+=("$job_name")
  JOB_KEYS+=("$job_key")
  JOB_DAYS+=("$job_days")
done <<EOF
$JOB_TABLE
EOF
# Una sola lectura de la config: valida HH:MM y cae al valor por defecto con aviso.
TIMES="$(brain_config "$BRC" get "${JOB_KEYS[@]}")" || die "no se pudieron resolver los horarios de los trabajos"
while IFS= read -r job_time; do JOB_TIMES+=("$job_time"); done <<EOF
$TIMES
EOF
[ "${#JOB_TIMES[@]}" -eq "${#JOB_NAMES[@]}" ] || die "no se pudieron resolver los horarios de los trabajos"

SCHEDULE_FAILED=0
SCHEDULE_PATH="$(schedule_path)"

if is_windows; then
  windows_schedule
  [ "$SCHEDULE_FAILED" = 0 ] || die "no se pudieron crear todas las tareas de Windows; revisa la salida de schtasks"
  exit 0
fi

if [ "$MODE" = "--dry-run" ] && [ "$OS" != "Darwin" ]; then
  write_cron_lines "# ai-brain $SLUG owner=<dry-run>"
  exit 0
fi

if [ "$MODE" != "--dry-run" ]; then
  owner_manifest init || die "manifiesto de propiedad inválido; no se cambió la programación"
fi

if [ "$OS" = "Darwin" ]; then
  launchd_calendar() {
    local time="$1" days="$2" day entry="" count=0
    for day in ${days:-all}; do
      entry="$entry<dict><key>Hour</key><integer>$((10#$(hm "$time")))</integer><key>Minute</key><integer>$((10#$(printf '%s' "$time" | cut -d: -f2)))</integer>"
      [ "$day" = all ] || entry="$entry<key>Weekday</key><integer>$day</integer>"
      entry="$entry</dict>"
      count=$((count + 1))
    done
    if [ "$count" -gt 1 ]; then entry="<array>$entry</array>"; fi
    printf '<key>StartCalendarInterval</key>%s' "$entry"
  }

  install_agent() {
    local job="$1" time="$2" days="$3" label="$PREFIX.$1" plist
    if [ "$MODE" = "--dry-run" ]; then
      plist="$(mktemp "${TMPDIR:-/tmp}/ai-brain-${label}.XXXXXX")"
    else
      plist="$AGENTS_DIR/$label.plist"
      if [ -L "$plist" ]; then warn "launch agent symlink preservado: $plist"; return 1; fi
      if [ -e "$plist" ] && ! owner_manifest agent-matches "$plist" >/dev/null 2>&1; then
        warn "launch agent ajeno o modificado, preservado: $plist (¿otro vault con el mismo nombre de carpeta?)"
        return 1
      fi
      mkdir -p "$AGENTS_DIR"
    fi
    cat > "$plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$(xml_escape "$label")</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$(xml_escape "$J/$job.sh")</string></array>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>$(xml_escape "$SCHEDULE_PATH")</string></dict>
$(launchd_calendar "$time" "$(expand_days "$days")")
<key>StandardOutPath</key><string>$(xml_escape "$(job_log_file "$VAULT" "$job")")</string>
<key>StandardErrorPath</key><string>$(xml_escape "$(job_log_file "$VAULT" "$job")")</string>
</dict></plist>
PL
    if ! plutil -lint "$plist" >/dev/null 2>&1; then
      warn "plist inválido: $label"
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
      return 1
    fi
    bootout_loaded "$label"
    if bootstrap_agent "$plist" "$label"; then ok "$label"; else warn "$label (falló el bootstrap)"; return 1; fi
  }

  # Justo después de un bootout, launchd puede seguir descargando el agente y
  # bootstrap falla ("Input/output error", "already in progress"): unos pocos
  # reintentos breves, no un bucle.
  bootstrap_agent() {
    local plist="$1" label="$2" attempt=1
    while ! launchctl bootstrap "gui/$(id -u)" "$plist"; do
      [ "$attempt" -lt 3 ] || return 1
      attempt=$((attempt + 1))
      sleep 1
      bootout_loaded "$label"
    done
  }

  # TCC: un launch agent no puede leer Documentos, Escritorio, Descargas ni iCloud
  # Drive sin permiso explícito, y el trabajo fallaría en silencio cada noche.
  tcc_folder=""
  for home in "$HOME" "$(cd "$HOME" 2>/dev/null && pwd -P || printf '%s' "$HOME")"; do
    for dir in Documents Desktop Downloads "Library/Mobile Documents"; do
      case "$VAULT/" in "$home/$dir/"*) tcc_folder="$home/$dir" ;; esac
    done
  done
  if [ -n "$tcc_folder" ]; then
    warn "el vault está en una carpeta protegida de macOS ($tcc_folder): launchd no puede leerla y los trabajos fallarían."
    warn "Mueve el vault fuera de Documentos, Escritorio, Descargas e iCloud Drive, o da Acceso total al disco a /bin/bash en Ajustes del Sistema > Privacidad y seguridad."
  fi

  # Un agente propio cuyo trabajo ya no está en la tabla (renombrado o retirado)
  # se va: de lo contrario seguiría disparando un script que no existe.
  retire_stale_agent() {
    local agent_path="$1" label="$2" index=0
    while [ "$index" -lt "${#JOB_NAMES[@]}" ]; do
      [ "$label" = "$PREFIX.${JOB_NAMES[$index]}" ] && return 0
      index=$((index + 1))
    done
    remove_owned_agent "$agent_path" "$label"
  }
  [ "$MODE" = "--dry-run" ] || for_owned_agents retire_stale_agent

  index=0
  while [ "$index" -lt "${#JOB_NAMES[@]}" ]; do
    install_agent "${JOB_NAMES[$index]}" "${JOB_TIMES[$index]}" "${JOB_DAYS[$index]}" || SCHEDULE_FAILED=1
    index=$((index + 1))
  done
  [ "$SCHEDULE_FAILED" = 0 ] || die "no se pudieron instalar todos los launch agents; revisa los avisos"
else
  MARK="# ai-brain $SLUG owner=$(owner_manifest instance)"
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
    ok "${#JOB_NAMES[@]} entradas de cron propias ($MARK)"
  else
    ok "las entradas de cron propias ya están al día"
  fi
fi
