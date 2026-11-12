#!/usr/bin/env bash
# Utilidades de shell compartidas por install, uninstall, schedule y los
# trabajos programados. Se instala en <vault>/scripts/lib/ junto a python3.sh.
# El llamador hace: . scripts/lib/common.sh

BRAIN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=python3.sh
. "$BRAIN_LIB_DIR/python3.sh"

# shellcheck disable=SC2034  # la usan los scripts que cargan esta biblioteca
BRAIN_MANIFEST_REL=".opencode/brain-vault-install-manifest.json"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  + %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die()  { printf '  ✗ %s\n' "$*" >&2; exit 1; }

is_windows() {
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; *) return 1 ;; esac
}

# Nombre corto del vault para etiquetas de scheduler y vault_name por defecto.
vault_slug() {
  local slug
  slug="$(basename "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')"
  printf '%s' "${slug:-cerebro}"
}

# run_python <args>: el intérprete elegido por pick_python3. PY3 puede ser
# "py -3" (dos palabras), por eso se expande sin comillas y solo aquí.
run_python() {
  # shellcheck disable=SC2086
  $PY3 "$@"
}

# brain_config <config> <acción> [args]: lector único de brain-config.json.
brain_config() {
  run_python "$BRAIN_LIB_DIR/brain_config.py" "$@"
}

# copy_new_floors <origen> <destino>: copia solo los pisos que faltan; nunca
# pisa una nota editada. Imprime cuántos copió.
copy_new_floors() {
  local src="$1" dst="$2" floor copied=0
  mkdir -p "$dst"
  for floor in "$src"/*.md; do
    [ -f "$floor" ] || continue
    [ -e "$dst/${floor##*/}" ] && continue
    cp "$floor" "$dst/${floor##*/}" || return 1
    copied=$((copied + 1))
  done
  printf '%s' "$copied"
}

# --- Trabajos programados ------------------------------------------------------
# job_log_file <vault> <trabajo>: el único nombre de log de un trabajo. Lo usan
# job_init y cada backend del scheduler, así la rotación cubre toda la salida.
job_log_file() { printf '%s/⚙️ Meta/logs/%s.log' "$1" "$2"; }

# job_init: fija VAULT, LOG y PY3, rota el log y toma el candado. El nombre del
# trabajo es el del script que lo llama (scripts/jobs/<trabajo>.sh). Un trabajo
# que ya está corriendo no se solapa: el segundo sale con 0.
JOB_LOG_MAX_BYTES=1048576

job_log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

job_fail() {
  job_log "$*"
  printf '%s\n' "$*" >&2
  exit 1
}

job_init() {
  local name="${BASH_SOURCE[1]##*/}" size pid
  name="${name%.sh}"
  VAULT="$(cd "$BRAIN_LIB_DIR/../.." && pwd -P)"
  cd "$VAULT" || exit 1
  # shellcheck disable=SC2034
  CFG="$VAULT/⚙️ Meta/brain-config.json"
  mkdir -p "$VAULT/⚙️ Meta/logs"
  LOG="$(job_log_file "$VAULT" "$name")"
  if [ -f "$LOG" ]; then
    size="$(wc -c < "$LOG" | tr -d ' ')"
    if [ "${size:-0}" -gt "$JOB_LOG_MAX_BYTES" ]; then mv -f "$LOG" "${LOG%.log}.1.log"; fi
  fi
  require_python3 2>/dev/null || job_fail "sin Python 3 válido (python3, py -3, python)"
  JOB_LOCK="$VAULT/⚙️ Meta/logs/.$name.lock"
  if ! mkdir "$JOB_LOCK" 2>/dev/null; then
    pid="$(cat "$JOB_LOCK/pid" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      job_log "otra ejecución en curso (pid $pid); omitido"
      exit 0
    fi
    rm -rf "$JOB_LOCK"
    mkdir "$JOB_LOCK" || job_fail "no se pudo tomar el candado $JOB_LOCK"
  fi
  printf '%s\n' "$$" > "$JOB_LOCK/pid"
  trap 'rm -rf "$JOB_LOCK"' EXIT
}

# run_with_timeout <segundos> <comando...>: sale con 124 si se agota el tiempo.
# Python y no `timeout`: no existe en macOS y en Windows es otro programa.
run_with_timeout() {
  local seconds="$1"
  shift
  run_python -c 'import shutil, subprocess, sys
argv = sys.argv[2:]
argv[0] = shutil.which(argv[0]) or argv[0]
try:
    raise SystemExit(subprocess.run(argv, timeout=float(sys.argv[1])).returncode)
except subprocess.TimeoutExpired:
    raise SystemExit(124)' "$seconds" "$@"
}
