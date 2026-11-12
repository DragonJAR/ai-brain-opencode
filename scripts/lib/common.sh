#!/usr/bin/env bash
# Utilidades de shell compartidas por install, uninstall, schedule y los
# trabajos programados. Se instala en <vault>/scripts/lib/ junto a python3.sh.
# El llamador hace: . scripts/lib/common.sh

# Con CDPATH, `cd dir` imprime la ruta y "$(cd dir && pwd)" devuelve dos líneas.
unset CDPATH
BRAIN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=python3.sh
. "$BRAIN_LIB_DIR/python3.sh"

# shellcheck disable=SC2034  # la usan los scripts que cargan esta biblioteca
BRAIN_MANIFEST_REL=".opencode/brain-vault-install-manifest.json"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  + %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die()  { printf '  ✗ %s\n' "$*" >&2; exit 1; }

# usage: la ayuda de un script de entrada es su comentario de cabecera (de la línea 2
# hasta antes de `set -`). -h/--help la imprime y sale con 0.
usage() { sed -n '2,/^set -/p' "$0" | sed '$d'; }
# usage_error <mensaje>: invocación inválida (flag desconocida, argumento de más o de menos); sale con 2.
usage_error() { printf '  ✗ %s (usa --help)\n' "$*" >&2; exit 2; }

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

# git_commit_paths <mensaje> <ruta...>: confirma en el repo del cwd solo esas
# rutas, borrados incluidos. Omite (y nombra en stderr) las que el .gitignore
# excluye, porque `git add` aborta con ellas. Sin firma, editor ni prompts: corre
# sin nadie delante. Sale con 0 también si no hay nada que confirmar.
git_commit_paths() {
  local message="$1" p
  local paths=()
  shift
  for p in "$@"; do
    if [ -e "$p" ] || [ -L "$p" ]; then
      if git check-ignore -q -- "$p" 2>/dev/null; then
        printf 'snapshot: %s está en .gitignore; omitida\n' "$p" >&2
        continue
      fi
    elif [ -z "$(git ls-files -- "$p" 2>/dev/null)" ]; then
      continue
    fi
    paths+=("$p")
  done
  [ "${#paths[@]}" -gt 0 ] || return 0
  export GIT_LITERAL_PATHSPECS=1 GIT_TERMINAL_PROMPT=0
  git add -A -- "${paths[@]}" < /dev/null || return 1
  # El pathspec limita el commit a estas rutas: lo que el usuario tenga en el
  # index por su cuenta no entra.
  git diff --cached --quiet -- "${paths[@]}" 2>/dev/null && return 0
  git -c commit.gpgsign=false commit -q -m "$message" -- "${paths[@]}" < /dev/null
}

# --- Trabajos programados ------------------------------------------------------
# job_log_file <vault> <trabajo>: el único nombre de log de un trabajo. Lo usan
# job_init y cada backend del scheduler, así la rotación cubre toda la salida.
job_log_file() { printf '%s/⚙️ Meta/logs/%s.log' "$1" "$2"; }

# job_init: fija VAULT, LOG y PY3, toma el candado y rota el log. El nombre del
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
  JOB_LOCK="$VAULT/⚙️ Meta/logs/.$name.lock"
  if ! job_lock "$JOB_LOCK"; then
    pid="$(cat "$JOB_LOCK/pid" 2>/dev/null || true)"
    job_log "otra ejecución en curso (pid ${pid:-?}); omitido"
    exit 0
  fi
  trap 'rm -rf "$JOB_LOCK"' EXIT
  # Solo quien tiene el candado rota: otra ejecución puede estar escribiendo.
  if [ -f "$LOG" ]; then
    size="$(wc -c < "$LOG" | tr -d ' ')"
    if [ "${size:-0}" -gt "$JOB_LOG_MAX_BYTES" ]; then mv -f "$LOG" "${LOG%.log}.1.log"; fi
  fi
  require_python3 2>/dev/null || job_fail "sin Python 3 válido (python3, py -3, python)"
}

# Un candado sin pid es de una ejecución que aún no lo escribió, salvo que sea
# más viejo que esto (la ejecución murió entre mkdir y la escritura del pid).
JOB_LOCK_STALE_MINUTES=10

# job_lock_stale <candado>: 0 si su dueño ya no corre.
job_lock_stale() {
  local pid
  pid="$(cat "$1/pid" 2>/dev/null || true)"
  case "$pid" in
    ''|*[!0-9]*) [ -n "$(find "$1" -maxdepth 0 -mmin +"$JOB_LOCK_STALE_MINUTES" 2>/dev/null)" ] ;;
    *) ! kill -0 "$pid" 2>/dev/null ;;
  esac
}

# job_lock <candado>: 0 si lo toma, 1 si otra ejecución viva lo tiene. mkdir es
# atómico; quitar un candado viejo no lo es, así que solo quien tiene <candado>.reap
# lo quita y vuelve a crearlo antes de soltarlo.
job_lock() {
  local lock="$1" reap="$1.reap" tries=0
  while [ "$tries" -lt 20 ]; do
    tries=$((tries + 1))
    if mkdir "$lock" 2>/dev/null; then
      job_lock_write_pid "$lock"
      return 0
    fi
    [ -d "$lock" ] || continue
    job_lock_stale "$lock" || return 1
    if mkdir "$reap" 2>/dev/null; then
      if job_lock_stale "$lock"; then rm -rf "$lock"; fi
      if mkdir "$lock" 2>/dev/null; then
        job_lock_write_pid "$lock"
        rmdir "$reap"
        return 0
      fi
      rmdir "$reap"
      return 1
    fi
    if job_lock_stale "$reap"; then rm -rf "$reap"; else sleep 1; fi
  done
  return 1
}

job_lock_write_pid() {
  printf '%s\n' "$$" > "$1/pid.$$" && mv -f "$1/pid.$$" "$1/pid"
}

# run_with_timeout <segundos> <comando...>: sale con 124 si se agota el tiempo y
# mata todo el árbol del comando, no solo el hijo directo (opencode lanza su
# propio servidor). POSIX: el hijo encabeza un grupo de procesos nuevo y se manda
# TERM y luego KILL al grupo. Git Bash: `taskkill /T /F` sobre el PID de Windows.
# Python y no `timeout`: no existe en macOS y en Windows es otro programa.
run_with_timeout() {
  local seconds="$1" mode=group
  shift
  if is_windows; then mode=tree; fi
  run_python -c 'import os, shutil, signal, subprocess, sys
mode, seconds, argv = sys.argv[1], float(sys.argv[2]), sys.argv[3:]
argv[0] = shutil.which(argv[0]) or argv[0]
child = subprocess.Popen(argv, start_new_session=(mode == "group"))

def kill_tree():
    if mode == "group":
        for sig, grace in ((signal.SIGTERM, 5), (signal.SIGKILL, 0)):
            try:
                os.killpg(child.pid, sig)
            except OSError:
                break
            try:
                child.wait(timeout=grace)
            except subprocess.TimeoutExpired:
                pass
        return
    # An MSYS Python sees MSYS pids; taskkill needs the Windows one.
    pid = child.pid
    try:
        with open("/proc/%d/winpid" % pid) as f:
            pid = int(f.read())
    except (OSError, ValueError):
        pass
    env = dict(os.environ, MSYS_NO_PATHCONV="1", MSYS2_ARG_CONV_EXCL="*")
    try:
        subprocess.call(["taskkill", "/T", "/F", "/PID", str(pid)], env=env,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass
    child.kill()

def on_signal(signum, frame):
    kill_tree()
    raise SystemExit(128 + signum)

signal.signal(signal.SIGTERM, on_signal)
try:
    raise SystemExit(child.wait(timeout=seconds))
except subprocess.TimeoutExpired:
    kill_tree()
    child.wait()
    raise SystemExit(124)' "$mode" "$seconds" "$@"
}
