#!/usr/bin/env bash
# install.sh — instala el cerebro personal (ai-brain-starter adaptado a OpenCode V2).
#
# Uso:
#   bash install.sh <ruta-del-vault> [flags]
# Flags:
#   --config <archivo>   brain-config.json para sembrar (por defecto: templates/brain-config.example.json)
#   --wire               solo re-cablea un vault existente (ruta de actualización)
#   --with-mcp           agrega los MCP remotos granola + chatprd (opt-in: envían tu conversación cuando los usas)
#   --with-obsidian      instala los complementos de Obsidian en el vault
#   --with-schedule      instala los trabajos programados (launchd en macOS, cron en Linux, schtasks en Windows)
#   --yes, -y            aceptado por compatibilidad; el instalador no hace preguntas
#   --help, -h           muestra esta ayuda
# Requisitos: macOS, Linux o Windows nativo (Git Bash), OpenCode CLI, git, Python >= 3.9.
# En Windows hacen falta cygpath y que `opencode run --help` responda. No se exige Developer Mode.
# Idempotente: re-ejecutar es seguro; el contenido personal nunca se sobrescribe.
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STARTER_REPO="https://github.com/mycelium-hq/ai-brain-starter"
HUMANIZER_REPO="https://github.com/adelaidasofia/humanizer.git"
OS="$(uname -s)"
VAULT="" CONFIG="" WIRE=0 WITH_MCP=0 WITH_OBSIDIAN=0 WITH_SCHEDULE=0

ok()   { printf '  + %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }
die()  { printf '  ✗ %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,/^set -/p' "$0" | sed '$d'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --config) [ $# -ge 2 ] || die "--config requiere la ruta de un brain-config.json"; CONFIG="$2"; shift 2 ;;
    --wire) WIRE=1; shift ;;
    --yes|-y) shift ;;
    --with-mcp) WITH_MCP=1; shift ;;
    --with-obsidian) WITH_OBSIDIAN=1; shift ;;
    --with-schedule) WITH_SCHEDULE=1; shift ;;
    --help|-h) usage; exit 0 ;;
    -*) die "flag desconocida: $1 (usa --help)";;
    *) if [ -z "$VAULT" ]; then VAULT="$1"; else die "argumento inesperado: $1"; fi; shift ;;
  esac
done
[ -n "$VAULT" ] || { usage >&2; exit 1; }
if [ "$WIRE" = 1 ]; then
  [ -d "$VAULT" ] || die "--wire requiere la ruta de un vault existente"
  if [ -n "$CONFIG" ] || [ "$WITH_MCP" = 1 ] || [ "$WITH_OBSIDIAN" = 1 ]; then
    die "--wire solo admite --with-schedule; no aplica configuración ni instala complementos"
  fi
fi

echo "== 0. Preflight =="
WIN=0
WIRE_MODE="link"
case "$OS" in
  Darwin) ok "macOS detectado (scheduler: launchd)" ;;
  Linux)  ok "Linux detectado (scheduler: cron)" ;;
  MINGW*|MSYS*|CYGWIN*)
    WIN=1
    WIRE_MODE=copy
    ok "Windows nativo detectado (scheduler: schtasks; cableado: copia)"
    ;;
  *) die "plataforma no soportada ($OS): se requiere macOS, Linux o Windows nativo (Git Bash). No se modificó el vault" ;;
esac
# shellcheck source=scripts/lib/python3.sh
. "$PKG/scripts/lib/python3.sh"
pick_python3 || die "falta Python >= 3.9 (python3, py -3 o python). No se modificó el vault"
# En Windows el nombre `python3` del resto del script usa el intérprete elegido.
# En POSIX no se define la función: los tests y el PATH siguen viendo el binario.
if [ "$WIN" = 1 ]; then
  python3() {
    case "$PY3" in
      python3) command python3 "$@" ;;
      python) command python "$@" ;;
      "py -3") py -3 "$@" ;;
      *) # PY3 es un solo token aquí.
        command $PY3 "$@" ;;
    esac
  }
fi
if [ "$OS" = "Linux" ] && { [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; }; then
  warn "WSL2 detectado: cron no arranca solo; actívalo con 'sudo service cron start' para que --with-schedule funcione"
fi
if [ "$WITH_OBSIDIAN" = 1 ]; then
  case "$OS" in Darwin|Linux) ;; *) die "--with-obsidian soporta macOS/Linux" ;; esac
fi
if [ -n "$CONFIG" ]; then
  [ -f "$CONFIG" ] || die "--config: no existe $CONFIG"
  CONFIG_ERROR="$(python3 - "$CONFIG" 2>&1 <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as error:
    raise SystemExit("no es JSON válido: " + str(error))
if not isinstance(data, dict):
    raise SystemExit("debe ser un objeto JSON (clave/valor)")
PY
)" || die "--config: $CONFIG $CONFIG_ERROR"
  ok "config válida: $CONFIG"
fi
command -v git >/dev/null || die "falta git (requerido)"
if [ "$WIN" = 1 ]; then
  command -v bash >/dev/null || die "falta bash (Git Bash). No se modificó el vault"
  command -v cygpath >/dev/null || die "falta cygpath (lo requiere el scheduler de Windows). No se modificó el vault"
  case "$VAULT" in
    /mnt|/mnt/*) die "ruta bajo /mnt/ (interop de WSL). Usa una ruta nativa de Git Bash. No se modificó el vault" ;;
  esac
  command -v opencode >/dev/null || die "falta OpenCode CLI (requerido); instálalo antes de continuar. No se modificó el vault"
  opencode run --help >/dev/null 2>&1 || die "opencode no responde a 'opencode run --help'. No se modificó el vault"
  ok "opencode run --help responde"
else
  command -v opencode >/dev/null || die "falta OpenCode CLI (requerido); instálalo antes de continuar. No se modificó el vault"
  ok "opencode CLI presente"
fi
if command -v node >/dev/null; then ok "node presente"; else warn "node no encontrado (opcional: validación de sintaxis del plugin)"; fi
if [ "$WITH_SCHEDULE" = 1 ] && [ "$OS" = "Linux" ]; then
  command -v crontab >/dev/null || die "falta crontab (lo requiere --with-schedule en Linux); instala cron o ejecuta sin --with-schedule. No se modificó el vault"
fi
# git commit needs an author. `git var` matches what commit will resolve, including
# Apple Git's automatic identity. Check it before the vault is created or changed.
if [ "$WIRE" = 0 ]; then
  if [ -d "$VAULT/.git" ]; then
    git_ident() { git -C "$VAULT" var "$1" >/dev/null 2>&1; }
  else
    git_ident() { git var "$1" >/dev/null 2>&1; }
  fi
  if ! git_ident GIT_AUTHOR_IDENT || ! git_ident GIT_COMMITTER_IDENT; then
    die "git no tiene identidad (user.name y user.email). Configúrala antes de continuar. No se modificó el vault"
  fi
  ok "identidad git presente"
fi

EXAMPLE="$PKG/templates/brain-config.example.json"
[ -f "$EXAMPLE" ] || die "paquete incompleto: falta templates/brain-config.example.json. No se modificó el vault"

if [ "$WIRE" = 0 ]; then mkdir -p "$VAULT"; fi
VAULT="$(cd "$VAULT" && pwd)"
SLUG="$(basename "$VAULT" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')"
SLUG="${SLUG:-cerebro}"
R="$VAULT/.opencode/skills/ai-brain-starter"
MANIFEST="$VAULT/.opencode/brain-vault-install-manifest.json"
STARTER_CREATED=0
HUMANIZER_CREATED=0
for rel in ".opencode" ".opencode/skills" ".opencode/skills/ai-brain-starter" \
           ".opencode/commands" ".opencode/plugins" "scripts" "scripts/jobs" "⚙️ Meta" "⚙️ Meta/scripts"; do
  [ -L "$VAULT/$rel" ] && die "ruta base es un symlink; se preservó el vault: $rel"
done

if [ "$WIRE" = 1 ]; then
  for rel in ".opencode/skills" ".opencode/commands" ".opencode/plugins" "scripts" "scripts/jobs" "⚙️ Meta" "⚙️ Meta/scripts"; do
    [ -d "$VAULT/$rel" ] || die "--wire requiere la estructura existente; falta $rel"
  done
  [ -f "$MANIFEST" ] || die "--wire requiere un manifiesto de propiedad existente; no se creó ni migró"
  [ -f "$R/SKILL.md" ] && [ -d "$R/skills" ] && [ -d "$R/commands" ] && [ -d "$R/scripts" ] \
    || die "--wire requiere un starter existente y válido en $R"
  [ -f "$VAULT/AGENTS.md" ] || die "--wire requiere AGENTS.md existente; no se regenera el vault"
  [ -f "$VAULT/⚙️ Meta/brain-config.json" ] || die "--wire requiere ⚙️ Meta/brain-config.json existente"
  python3 -c "import json,sys;json.load(open(sys.argv[1]))" "$VAULT/⚙️ Meta/brain-config.json" 2>/dev/null \
    || die "--wire requiere una configuración JSON válida"
fi

OWNERSHIP="$PKG/scripts/lib/ownership.py"

[ -f "$OWNERSHIP" ] || die "paquete incompleto: falta scripts/lib/ownership.py"

owner_manifest() {
  python3 "$OWNERSHIP" "$MANIFEST" "$@"
}

if [ "$WIRE" = 0 ]; then mkdir -p "$(dirname "$MANIFEST")"; fi
owner_manifest init || die "el registro de propiedad existe pero no es válido; se preservó el vault"

safe_parent() {
  local destination="$1" rel parent current part
  local -a parts=()
  case "$destination" in "$VAULT"/*) rel="${destination#"$VAULT"/}" ;; *) return 1 ;; esac
  parent="${rel%/*}"
  current="$VAULT"
  IFS='/' read -r -a parts <<< "$parent"
  for part in "${parts[@]}"; do
    current="$current/$part"
    [ -L "$current" ] && return 1
  done
  return 0
}

ensure_vault_dir() {
  local rel="$1" current="$VAULT" part
  local -a parts=()
  IFS='/' read -r -a parts <<< "$rel"
  for part in "${parts[@]}"; do
    current="$current/$part"
    if [ -L "$current" ] || { [ -e "$current" ] && [ ! -d "$current" ]; }; then
      return 1
    fi
    [ -d "$current" ] || mkdir "$current" || return 1
  done
  return 0
}

managed_copy() {
  local src="$1" dst="$2" rel="$3" mode="${4:-}"
  MANAGED_COPY_RESULT=0
  [ -f "$src" ] || die "falta $src en el paquete; instalación abortada sin cambios posteriores"
  if ! safe_parent "$dst"; then
    warn "directorio padre symlink preservado: $rel"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ]; then
    warn "symlink existente preservado: $rel"
    return 0
  fi
  if [ -e "$dst" ]; then
    if ! owner_manifest file-matches "$rel" "$dst" >/dev/null 2>&1; then
      warn "archivo existente no administrado preservado: $rel"
      return 0
    fi
  fi
  cp "$src" "$dst"
  if [ -n "$mode" ]; then chmod "$mode" "$dst"; fi
  owner_manifest record-file "$rel" "$dst" || die "no se pudo registrar la propiedad de $rel"
  MANAGED_COPY_RESULT=1
}

# Symlink records are batched: one manifest write per phase instead of one per link.
PENDING_LINKS=()
flush_links() {
  [ "${#PENDING_LINKS[@]}" -eq 0 ] && return 0
  owner_manifest record-links "${PENDING_LINKS[@]}" || die "no se pudo registrar la propiedad de los symlinks"
  PENDING_LINKS=()
}

managed_link() {
  local target="$1" dst="$2" rel="$3"
  if ! safe_parent "$dst"; then
    warn "directorio padre symlink preservado: $rel"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ -L "$dst" ] && owner_manifest link-matches "$rel" "$target" "$dst" >/dev/null 2>&1; then
      return 0
    fi
    warn "ruta existente preservada: $rel"
    return 0
  fi
  ln -s "$target" "$dst"
  PENDING_LINKS+=("$rel" "$dst")
}

managed_copy_tree() {
  local src="$1" dst="$2" rel="$3"
  src="${src%/}"
  if ! safe_parent "$dst"; then
    warn "directorio padre symlink preservado: $rel"
    return 0
  fi
  if [ -L "$dst" ]; then
    warn "symlink existente preservado: $rel"
    return 0
  fi
  if [ -e "$dst" ]; then
    if ! owner_manifest tree-matches "$rel" "$dst" >/dev/null 2>&1; then
      warn "árbol existente no administrado preservado: $rel"
      return 0
    fi
    rm -rf "$dst"
  fi
  mkdir -p "$(dirname "$dst")"
  cp -R "$src" "$dst"
  owner_manifest record-tree "$rel" "$dst" || die "no se pudo registrar la propiedad de $rel"
}

wire_file() {
  local src="$1" dst="$2" rel="$3" link_target="$4" mode="${5:-}"
  if [ "$WIRE_MODE" = "copy" ]; then
    managed_copy "$src" "$dst" "$rel" "$mode"
  else
    managed_link "$link_target" "$dst" "$rel"
  fi
}

wire_tree() {
  local src="$1" dst="$2" rel="$3" link_target="$4"
  if [ "$WIRE_MODE" = "copy" ]; then
    managed_copy_tree "$src" "$dst" "$rel"
  else
    managed_link "$link_target" "$dst" "$rel"
  fi
}

echo "== 1. Carpetas canónicas del vault =="
if [ "$WIRE" = 0 ]; then
  for d in "📓 Journals" "🏠 Home" "👤 CRM" "📝 Notes" "💼 Business/Engagements" "🚀 I+D/Herramientas" "🚀 I+D/Investigación" \
           "⚙️ Meta/Folder Resolvers" "⚙️ Meta/scripts" "⚙️ Meta/Sessions" "⚙️ Meta/Decisions" "⚙️ Meta/Workflows" \
           "⚙️ Meta/Facts" "⚙️ Meta/Exceptions" "⚙️ Meta/Floors" "⚙️ Meta/logs" ".opencode/commands" ".opencode/plugins"; do
    if ! ensure_vault_dir "$d"; then
      warn "directorio symlink o ruta incompatible preservada: $d"
      continue
    fi
    if [ -L "$VAULT/$d/.gitkeep" ]; then
      warn "symlink .gitkeep preservado: $d/.gitkeep"
    elif [ ! -f "$VAULT/$d/.gitkeep" ]; then
      : > "$VAULT/$d/.gitkeep"
    fi
  done
  ok "estructura creada"
else
  ok "estructura existente preservada (--wire)"
fi

echo "== 2. Clonar/actualizar ai-brain-starter (fuente única) =="
if [ "$WIRE" = 1 ]; then
  ok "starter existente; --wire no clona ni actualiza"
elif [ -f "$R/.git/HEAD" ]; then
  if [ "${BRAIN_STARTER_UPDATE:-}" = "1" ]; then
    git -C "$R" pull --ff-only >/dev/null 2>&1 && ok "starter actualizado (ff-only)" || warn "pull falló: se usa la versión local"
  else
    ok "starter presente (actualiza con BRAIN_STARTER_UPDATE=1)"
  fi
else
  git clone -q --depth 1 "$STARTER_REPO" "$R" || die "no se pudo clonar $STARTER_REPO"
  STARTER_CREATED=1
  if [ -n "${BRAIN_STARTER_PIN:-}" ]; then
    if git -C "$R" fetch -q --depth 1 origin "$BRAIN_STARTER_PIN" 2>/dev/null \
       && git -C "$R" checkout -q "$BRAIN_STARTER_PIN" 2>/dev/null; then
      ok "starter en el SHA fijado ($BRAIN_STARTER_PIN)"
    else
      die "no se pudo fijar BRAIN_STARTER_PIN=$BRAIN_STARTER_PIN (SHA inexistente o red); borra $R y reintenta"
    fi
  else
    ok "starter clonado ($(git -C "$R" log --oneline -1 | cut -c1-8))"
  fi
fi
[ -f "$R/SKILL.md" ] || die "el clon no tiene SKILL.md — revisa $R"

if [ "$WIRE_MODE" = "copy" ]; then
  echo "== 3. Cablear skills y comandos (copias, sin symlinks) =="
else
  echo "== 3. Cablear skills y comandos (symlinks relativos, sin copias) =="
fi
for d in "$R"/skills/*/; do
  n="$(basename "$d")"; [ "$n" = "ai-brain-starter" ] && continue
  l="$VAULT/.opencode/skills/$n"
  wire_tree "$d" "$l" ".opencode/skills/$n" "ai-brain-starter/skills/$n"
done
flush_links
if [ "$WIRE_MODE" = "copy" ]; then
  ok "$(find "$VAULT/.opencode/skills" -maxdepth 1 -mindepth 1 -type d ! -name ai-brain-starter ! -name humanizer | wc -l | tr -d ' ') skills copiadas"
else
  ok "$(find "$VAULT/.opencode/skills" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ') skills enlazadas"
fi
mkdir -p "$VAULT/.opencode/commands"
for f in "$R"/commands/*.md; do
  n="$(basename "$f")"; l="$VAULT/.opencode/commands/$n"
  wire_file "$f" "$l" ".opencode/commands/$n" "../skills/ai-brain-starter/commands/$n"
done
flush_links
if [ "$WIRE_MODE" = "copy" ]; then
  ok "$(find "$VAULT/.opencode/commands" -maxdepth 1 -mindepth 1 -type f | wc -l | tr -d ' ') comandos copiados"
else
  ok "$(ls -1 "$VAULT/.opencode/commands" | wc -l | tr -d ' ') comandos enlazados"
fi

echo "== 3b. Scripts del vendor que los skills invocan (symlinks a ⚙️ Meta/scripts) =="
mkdir -p "$VAULT/⚙️ Meta/scripts"
n_scripts=0
for f in "$R"/scripts/*.py "$R"/scripts/*.sh; do
  [ -f "$f" ] || continue
  n="$(basename "$f")"; l="$VAULT/⚙️ Meta/scripts/$n"
  wire_file "$f" "$l" "⚙️ Meta/scripts/$n" "../../.opencode/skills/ai-brain-starter/scripts/$n"
  if [ "$WIRE_MODE" = "copy" ]; then
    [ -f "$l" ] && [ ! -L "$l" ] && n_scripts=$((n_scripts+1))
  else
    [ -L "$l" ] && [ "$(readlink "$l")" = "../../.opencode/skills/ai-brain-starter/scripts/$n" ] && n_scripts=$((n_scripts+1))
  fi
done
flush_links
if [ "$WIRE_MODE" = "copy" ]; then
  ok "$n_scripts scripts copiados (build-journal-index, journal-preflight, drift-detection...)"
else
  ok "$n_scripts scripts enlazados (build-journal-index, journal-preflight, drift-detection...)"
fi

echo "== 4. humanizer (MIT, lo usa la regla de humanización) =="
H="$VAULT/.opencode/skills/humanizer"
if [ "$WIRE" = 1 ]; then
  ok "humanizer preservado (--wire no instala dependencias)"
elif [ ! -e "$H" ] && [ ! -L "$H" ]; then
  if git clone -q --depth 1 "$HUMANIZER_REPO" "$H"; then HUMANIZER_CREATED=1; ok "humanizer clonado"; else warn "humanizer falló (opcional)"; fi
else
  ok "humanizer presente"
fi

echo "== 5. Pisos emocionales (generados desde el framework High-Rise del vendor) =="
if [ "$WIRE" = 0 ]; then
  python3 "$R/scripts/generate_floor_stubs.py" >/dev/null 2>&1 && ok "stubs generados en el clon" || warn "generador de pisos falló"
  if [ "$STARTER_CREATED" = 1 ]; then owner_manifest record-tree ".opencode/skills/ai-brain-starter" "$R" || warn "no se pudo registrar el clon del starter"; fi
  if [ "$HUMANIZER_CREATED" = 1 ]; then owner_manifest record-tree ".opencode/skills/humanizer" "$H" || warn "no se pudo registrar el clon de humanizer"; fi
  if [ -d "$R/floors" ]; then
    cp -n "$R/floors/"*.md "$VAULT/⚙️ Meta/Floors/" 2>/dev/null && ok "$(ls -1 "$VAULT/⚙️ Meta/Floors" | wc -l | tr -d ' ') notas de piso"
  fi
else
  ok "pisos y datos personales preservados (--wire)"
fi

echo "== 6. Configuración del diario (plantilla del vendor, sin sobrescribir) =="
if [ "$WIRE" = 1 ]; then
  ok "journal-config.md preservado (--wire)"
elif [ ! -f "$VAULT/⚙️ Meta/journal-config.md" ] && [ -f "$R/templates/journal-config.md" ]; then
  cp "$R/templates/journal-config.md" "$VAULT/⚙️ Meta/journal-config.md" && ok "journal-config.md creado"
else
  ok "journal-config.md presente"
fi

echo "== 7. brain-config.json (valores del cerebro; el plugin lo lee) =="
BRC="$VAULT/⚙️ Meta/brain-config.json"
if [ "$WIRE" = 1 ]; then
  ok "brain-config.json preservado (--wire)"
elif [ -n "$CONFIG" ]; then
  [ -f "$CONFIG" ] || die "no existe --config: $CONFIG"
  if [ -f "$BRC" ]; then cp "$BRC" "$BRC.bak.$(date +%Y%m%d-%H%M%S)" && warn "backup de la config previa"; fi
  cp "$CONFIG" "$BRC" && ok "config sembrada desde $CONFIG"
elif [ ! -f "$BRC" ]; then
  cp "$EXAMPLE" "$BRC"
  python3 - "$BRC" "$SLUG" <<'PZ' || die "no se pudo sembrar brain-config.json desde templates/brain-config.example.json"
import json, os, pathlib, re, sys
p = pathlib.Path(sys.argv[1])
try:
    d = json.loads(p.read_text(encoding="utf-8"))
except Exception as error:
    raise SystemExit("no es JSON válido: " + str(error))
if not isinstance(d, dict):
    raise SystemExit("debe ser un objeto JSON")
tz = ""
detected = False
try:
    link = os.readlink("/etc/localtime")
    m = re.search(r"zoneinfo/(.+)$", link)
    if m: tz = m.group(1); detected = True
except Exception:
    pass
fallback_tz = d.get("timezone")
if not tz:
    if not isinstance(fallback_tz, str) or not fallback_tz.strip():
        raise SystemExit("no declara timezone")
    tz = fallback_tz.strip()
d["timezone"] = tz
d["vault_name"] = sys.argv[2]
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
if detected:
    print("  + config por defecto creada (zona horaria detectada: " + tz + ")")
else:
    print("  ! config por defecto creada (zona horaria NO detectada; se usa " + tz + ") — ajústala en ⚙️ Meta/brain-config.json")
PZ
else
  ok "brain-config.json presente"
fi

echo "== 8. AGENTS.md (template del vendor + adaptación OpenCode) =="
if [ "$WIRE" = 1 ]; then
  ok "AGENTS.md preservado (--wire)"
elif [ -f "$VAULT/AGENTS.md" ]; then
  ok "AGENTS.md existe — preservado (nunca se sobrescribe contenido personal)"
else
  python3 - "$R/templates/generated/claude-md-template.md" "$PKG/templates/agents-opencode-appendix.md" "$BRC" "$VAULT/AGENTS.md" "$EXAMPLE" <<'PYGEN' || die "fallo generando AGENTS.md"
import json, pathlib, re, sys
tpl = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
app = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
cfg = json.load(open(sys.argv[3], encoding="utf-8"))
example = json.load(open(sys.argv[5], encoding="utf-8"))
if not isinstance(cfg, dict):
    cfg = {}
out = pathlib.Path(sys.argv[4])

def section(name):
    value = cfg.get(name)
    return value if isinstance(value, dict) else {}

def text(value, default):
    return value.strip() if isinstance(value, str) and value.strip() else default

def from_example(path):
    cur = example
    for key in path.split("."):
        if not isinstance(cur, dict) or key not in cur:
            raise SystemExit("paquete incompleto: templates/brain-config.example.json no declara " + path)
        cur = cur[key]
    if not isinstance(cur, str) or not cur.strip():
        raise SystemExit("paquete incompleto: templates/brain-config.example.json no declara " + path)
    return cur.strip()

def words(value):
    if not isinstance(value, list):
        return ""
    return ", ".join(item.strip() for item in value if isinstance(item, str) and item.strip())

journal, schedule = section("journal"), section("schedule")
src = tpl.replace("~/.claude/skills/humanizer", ".opencode/skills/humanizer")
src = src.replace("~/.claude/skills/ai-brain-starter", ".opencode/skills/ai-brain-starter")
src = re.sub(r"8\. \*\*Your brain lives in the vault.*?(?=\n\n9\. )",
    "8. **Tu cerebro vive en el vault — nunca solo en la memoria del agente.** Todo lo que valga entre sesiones termina como archivo de este vault (nota, decisión, regla). Test: \"¿otra máquina, otra herramienta, el próximo mes — sigue aquí?\"", src, flags=re.S)
src = re.sub(r"2\. \*\*Run the daily AI brain setup update check\*\*.*?(?=\n3\. )", "", src, flags=re.S)
src = re.sub(r"4\. End: The \*\*session close cascade\*\*.*?(?=\n\n## )",
    "4. End: cierra con una señal de cierre (\"chao\", \"eso es todo\", \"good night\"...). El plugin brain-vault la detecta e inyecta el cascade: guarda la sesión en ⚙️ Meta/Sessions/, registra decisiones en ⚙️ Meta/Decisions/ y compromete solo las rutas tocadas.", src, flags=re.S)
src = re.sub(r"## Session close — configuration \(optional\).*?\Z", "", src, flags=re.S)
src = re.sub(r"## Session start — daily update check.*?(?=\n## )", "", src, flags=re.S)
vault_map = """Carpetas del vault (adaptación OpenCode). Los nombres van en inglés a propósito: los skills del sistema tienen rutas fijas y traducirlos genera carpetas duplicadas.

- 📓 Journals/ — entradas del diario. Crea el skill `daily-journal`.
- 🏠 Home/ — About Me.md y contexto personal.
- 👤 CRM/ — personas. Un archivo por persona.
- 📝 Notes/ — notas sueltas, artículos, imports.
- 💼 Business/ — trabajo y negocio; Engagements/ = una carpeta por cliente.
- 🚀 I+D/ — investigación y desarrollo (Herramientas/, Investigación/).
- ⚙️ Meta/ — maquinaria: Folder Resolvers/, Floors/, Sessions/, Decisions/, logs/.

Antes de crear cualquier cosa: revisa este mapa y ⚙️ Meta/Folder Resolvers/."""
src = re.sub(r"## Vault Map\n\[FILL THIS IN.*?\]", "## Vault Map\n" + vault_map, src, flags=re.S)
for k, v in {
    "{{LANGUAGE}}": text(cfg.get("language"), from_example("language")),
    "{{JOURNAL_TIME}}": text(journal.get("time"), from_example("journal.time")),
    "{{TIMEZONE}}": text(cfg.get("timezone"), from_example("timezone")),
    "{{HABITS}}": words(cfg.get("habits")) or "ninguno",
    "{{ACCOUNTABILITY}}": words(cfg.get("accountability")) or "a definir en la entrevista",
    "{{VAULT_NAME}}": text(cfg.get("vault_name"), from_example("vault_name")),
    "{{INSIGHTS_TIME}}": text(schedule.get("insights_time"), from_example("schedule.insights_time")),
    "{{MAINTENANCE_TIME}}": text(schedule.get("maintenance_time"), from_example("schedule.maintenance_time")),
    "{{UPDATE_TIME}}": text(schedule.get("update_time"), from_example("schedule.update_time")),
}.items():
    app = app.replace(k, v)
header = ("<!-- Generado por install.sh desde el template de ai-brain-starter + adaptación OpenCode. "
          "Completa las secciones personales con la entrevista de setup. -->\n\n")
out.write_text(header + src.rstrip() + "\n\n" + app + "\n", encoding="utf-8")
PYGEN
  [ -f "$VAULT/AGENTS.md" ] && ok "AGENTS.md generado (plantilla + adaptación OpenCode)" || die "fallo generando AGENTS.md"
fi
if [ "$WIRE_MODE" = "copy" ]; then
  wire_file "$VAULT/AGENTS.md" "$VAULT/CLAUDE.md" "CLAUDE.md" "AGENTS.md"
else
  managed_link "AGENTS.md" "$VAULT/CLAUDE.md" "CLAUDE.md"
fi
flush_links

echo "== 9. Plugin brain-vault (hooks OpenCode) =="
managed_copy "$PKG/plugin/brain-vault/index.js" "$VAULT/.opencode/plugins/brain-vault/index.js" ".opencode/plugins/brain-vault/index.js"
if command -v node >/dev/null; then
  node --check "$VAULT/.opencode/plugins/brain-vault/index.js" && ok "plugin instalado (sintaxis validada)" || die "el plugin instalado tiene un error de sintaxis: .opencode/plugins/brain-vault/index.js"
else
  ok "plugin instalado (lee ⚙️ Meta/brain-config.json)"
fi

echo "== 10. Trabajos programados (scripts data-driven) =="
mkdir -p "$VAULT/scripts/jobs"
n_jobs=0
for f in "$PKG"/templates/jobs/*.sh; do
  [ -f "$f" ] || continue
  n="$(basename "$f")"
  managed_copy "$f" "$VAULT/scripts/jobs/$n" "scripts/jobs/$n" 0755
  [ "$MANAGED_COPY_RESULT" = 1 ] && n_jobs=$((n_jobs+1))
done
managed_copy "$PKG/scripts/verify.sh" "$VAULT/scripts/verify.sh" "scripts/verify.sh" 0755
managed_copy "$PKG/scripts/lib/ownership.py" "$VAULT/scripts/lib/ownership.py" "scripts/lib/ownership.py" 0644
managed_copy "$PKG/scripts/lib/python3.sh" "$VAULT/scripts/lib/python3.sh" "scripts/lib/python3.sh" 0644
ok "$n_jobs trabajos gestionados"

echo "== 11. Git del vault (respaldo local) =="
if [ "$WIRE" = 1 ]; then
  ok "estado Git preservado (--wire)"
else
  if [ ! -d "$VAULT/.git" ]; then
    if ! git -C "$VAULT" init -q -b main 2>/dev/null; then
      git -C "$VAULT" init -q && git -C "$VAULT" symbolic-ref HEAD refs/heads/main \
        || die "no se pudo inicializar el repositorio Git del vault"
    fi
    ok "git init (main)"
  fi
  if [ ! -f "$VAULT/.gitignore" ]; then
    cat > "$VAULT/.gitignore" <<'GI'
.opencode/skills/ai-brain-starter/
.opencode/skills/humanizer/
.obsidian/plugins/
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.trash/
.DS_Store
⚙️ Meta/logs/*.log
⚙️ Meta/.probe-on
GI
    ok ".gitignore"
  fi
fi

if [ "$WITH_MCP" = 1 ]; then
  echo "== 12. MCP remotos (opt-in) =="
  if [ -L "$VAULT/opencode.json" ]; then
    warn "opencode.json es un symlink; se preservó sin modificarlo"
  else
    if ! MCP_ADDED="$(python3 - "$VAULT/opencode.json" 2>&1 <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
if p.exists() and (p.is_symlink() or not p.is_file() or p.stat().st_nlink != 1):
    raise SystemExit("refusing to modify a symlinked, non-regular, or hard-linked opencode.json")
d = json.loads(p.read_text()) if p.exists() else {"$schema": "https://opencode.ai/config.json"}
if not isinstance(d, dict):
    raise SystemExit("refusing to modify opencode.json with a non-object root")
servers = d.setdefault("mcp", {}).setdefault("servers", {})
if not isinstance(servers, dict):
    raise SystemExit("refusing to modify a non-object mcp.servers configuration")
added = {}
for name, url in {"granola": "https://mcp.granola.ai/mcp", "chatprd": "https://app.chatprd.ai/mcp"}.items():
    if name not in servers:
        servers[name] = {"type": "remote", "url": url}
        added[name] = servers[name]
if added:
    p.write_text(json.dumps(d, indent=2) + "\n", encoding="utf-8")
print(json.dumps(added, separators=(",", ":"), ensure_ascii=False))
PY
    )"; then
      die "no se pudo configurar MCP en opencode.json: $MCP_ADDED"
    fi
    [ "$MCP_ADDED" = "{}" ] || owner_manifest record-config "$MCP_ADDED" || die "no se pudo registrar la configuración MCP"
    ok "MCP remotos configurados sin sobrescribir entradas existentes"
  fi
fi

if [ "$WITH_OBSIDIAN" = 1 ]; then
  echo "== 13. Obsidian: complementos comunitarios =="
  python3 - "$VAULT" <<'PY'
import io, json, shutil, sys, urllib.request, zipfile
from pathlib import Path
PLG = Path(sys.argv[1]) / ".obsidian" / "plugins"; PLG.mkdir(parents=True, exist_ok=True)
PLUGINS = {
    "dataview": "blacksmithgu/obsidian-dataview",
    "templater-obsidian": "SilentVoid13/Templater",
    "obsidian-tasks-plugin": "obsidian-tasks-group/obsidian-tasks",
    "obsidian-local-rest-api": "coddingtonbear/obsidian-local-rest-api",
    "custom-sort": "SebastianMC/obsidian-custom-sort",
}
for pid, repo in PLUGINS.items():
    t = PLG / pid
    if (t / "main.js").exists() and (t / "manifest.json").exists():
        print(f"  + {pid} ya instalado"); continue
    try:
        req = urllib.request.Request(f"https://api.github.com/repos/{repo}/releases/latest", headers={"Accept": "application/vnd.github+json"})
        rel = json.load(urllib.request.urlopen(req, timeout=30))
        z = next((a for a in rel.get("assets", []) if a["name"].endswith(".zip")), None)
        t.mkdir(parents=True, exist_ok=True)
        if z:
            buf = io.BytesIO(urllib.request.urlopen(z["browser_download_url"], timeout=60).read())
            with zipfile.ZipFile(buf) as zf:
                for n in zf.namelist():
                    if n.endswith(("main.js", "manifest.json", "styles.css")):
                        with zf.open(n) as s, open(t / Path(n).name, "wb") as dd: shutil.copyfileobj(s, dd)
            print(f"  + {pid} instalado (zip)")
        else:
            got = False
            for fn in ("main.js", "manifest.json", "styles.css"):
                a = next((a for a in rel.get("assets", []) if a["name"] == fn), None)
                if a:
                    with urllib.request.urlopen(a["browser_download_url"], timeout=60) as r:
                        (t / fn).write_bytes(r.read())
                    got = True
            print(f"  + {pid} instalado (assets sueltos)" if got else f"  ! {pid}: sin assets usables")
    except Exception as e:
        print(f"  ! {pid}: {e}")
cp = Path(sys.argv[1]) / ".obsidian" / "community-plugins.json"
installed = [pid for pid in PLUGINS if ((Path(sys.argv[1]) / ".obsidian" / "plugins" / pid / "main.js").exists() and (Path(sys.argv[1]) / ".obsidian" / "plugins" / pid / "manifest.json").exists())]
if installed and not cp.exists():
    cp.write_text(json.dumps(installed, indent=2) + "\n", encoding="utf-8")
    print(f"  + community-plugins.json con {len(installed)} complementos (aprueba al abrir Obsidian la primera vez)")
elif not installed:
    print("  ! ningún complemento instalado — no se escribe community-plugins.json")
PY
fi

if [ "$WITH_SCHEDULE" = 1 ]; then
  echo "== 14. Trabajos programados =="
  bash "$PKG/scripts/schedule.sh" "$VAULT"
fi

echo "== 15. Commit base del vault =="
if [ "$WIRE" = 1 ]; then
  ok "estado Git preservado (--wire)"
elif [ ! -d "$VAULT/.git" ]; then
  warn "sin repositorio Git; commit base omitido"
elif [ -z "$(git -C "$VAULT" status --porcelain)" ]; then
  ok "sin cambios por confirmar"
else
  # Solo maquinaria del paquete y la estructura vacía: el contenido personal nunca entra.
  GIT_ADD=()
  for path in AGENTS.md CLAUDE.md .gitignore .opencode scripts opencode.json \
              "⚙️ Meta/scripts" "⚙️ Meta/Floors" "⚙️ Meta/brain-config.json" "⚙️ Meta/journal-config.md"; do
    [ -e "$VAULT/$path" ] || [ -L "$VAULT/$path" ] || continue
    GIT_ADD+=("$path")
  done
  for d in "📓 Journals" "🏠 Home" "👤 CRM" "📝 Notes" "💼 Business" "🚀 I+D" "⚙️ Meta"; do
    [ -d "$VAULT/$d" ] || continue
    while IFS= read -r keep; do GIT_ADD+=("${keep#"$VAULT"/}"); done < <(find "$VAULT/$d" -name .gitkeep -print)
  done
  git -C "$VAULT" add -- "${GIT_ADD[@]}"
  if git -C "$VAULT" diff --cached --quiet; then
    ok "sin cambios por confirmar"
  else
    git -C "$VAULT" commit -q -m "chore: bootstrap ai-brain OpenCode vault"
    ok "commit base"
  fi
fi

echo
if [ "$WIRE" = 1 ]; then
  echo "━━━ Re-cableado completo ━━━"
else
  echo "━━━ Instalación completa ━━━"
fi
echo "  vault: $VAULT"
echo "  Siguientes pasos:"
if [ "$WIRE" = 1 ]; then
  echo "   1. Reinicia OpenCode o ejecuta /reload para que cargue el plugin."
  echo "   2. Verificación del vault: bash $VAULT/scripts/verify.sh"
else
  echo "   1. Reinicia OpenCode o ejecuta /reload para que cargue el plugin."
  echo "   2. Edita AGENTS.md (sección Me / Current Focus) o corre la entrevista de setup."
  echo "   3. Esta noche: /journal — la primera entrada activa el sistema."
  echo "   4. Verificación: bash $VAULT/scripts/verify.sh"
fi
