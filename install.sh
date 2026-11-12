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
#   --dry-run            valida los requisitos y muestra el plan sin tocar el vault
#   --yes, -y            aceptado por compatibilidad; el instalador no hace preguntas
#   --version            muestra la versión del paquete
#   --help, -h           muestra esta ayuda
# Requisitos: macOS, Linux o Windows nativo (Git Bash), OpenCode CLI, git, Python >= 3.9.
# En Windows hacen falta cygpath y que `opencode run --help` responda. No se exige Developer Mode.
# Idempotente: re-ejecutar es seguro; el contenido personal nunca se sobrescribe.
set -euo pipefail
unset CDPATH

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STARTER_REPO="https://github.com/mycelium-hq/ai-brain-starter"
HUMANIZER_REPO="https://github.com/adelaidasofia/humanizer.git"
LIB="$PKG/scripts/lib"
OS="$(uname -s)"
VAULT="" CONFIG="" WIRE=0 WITH_MCP=0 WITH_OBSIDIAN=0 WITH_SCHEDULE=0 DRY_RUN=0

for required in common.sh python3.sh ownership.py wire.py brain_config.py; do
  [ -f "$LIB/$required" ] || { printf '  ✗ paquete incompleto: falta scripts/lib/%s. No se modificó el vault\n' "$required" >&2; exit 1; }
done
# shellcheck source=scripts/lib/common.sh
. "$LIB/common.sh"
VERSION="$(cat "$PKG/VERSION" 2>/dev/null || echo desconocida)"
usage() { sed -n '2,/^set -/p' "$0" | sed '$d'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --config) [ $# -ge 2 ] || die "--config requiere la ruta de un brain-config.json"; CONFIG="$2"; shift 2 ;;
    --wire) WIRE=1; shift ;;
    --yes|-y) shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --version) printf 'ai-brain-opencode %s\n' "$VERSION"; exit 0 ;;
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
pick_python3 || die "falta Python >= 3.9 (python3, py -3 o python). No se modificó el vault"
if [ "$OS" = "Linux" ] && { [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; }; then
  warn "WSL2 detectado: cron no arranca solo; actívalo con 'sudo service cron start' para que --with-schedule funcione"
fi
if [ "$WITH_OBSIDIAN" = 1 ]; then
  case "$OS" in Darwin|Linux) ;; *) die "--with-obsidian soporta macOS/Linux" ;; esac
fi
if [ -n "$CONFIG" ]; then
  [ -f "$CONFIG" ] || die "--config: no existe $CONFIG"
  CONFIG_ERROR="$(brain_config "$CONFIG" validate 2>&1)" || die "--config: $CONFIG $CONFIG_ERROR"
  [ -z "$CONFIG_ERROR" ] || printf '%s\n' "$CONFIG_ERROR" >&2
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
# Apple Git's automatic identity. Check it before the vault is created or changed,
# outside the caller's cwd: another repo's local identity would not apply to the vault.
if [ "$WIRE" = 0 ]; then
  IDENT_DIR="/"
  if [ -d "$VAULT/.git" ]; then IDENT_DIR="$VAULT"; fi
  git_ident() { git -C "$IDENT_DIR" var "$1" >/dev/null 2>&1; }
  if ! git_ident GIT_AUTHOR_IDENT || ! git_ident GIT_COMMITTER_IDENT; then
    die "git no tiene identidad (user.name y user.email). Configúrala antes de continuar. No se modificó el vault"
  fi
  ok "identidad git presente"
fi

EXAMPLE="$PKG/templates/brain-config.example.json"
[ -f "$EXAMPLE" ] || die "paquete incompleto: falta templates/brain-config.example.json. No se modificó el vault"

if [ "$WIRE" = 0 ] && [ "$DRY_RUN" = 0 ]; then mkdir -p "$VAULT"; fi
if [ -d "$VAULT" ]; then VAULT="$(cd "$VAULT" && pwd)"; fi
SLUG="$(vault_slug "$VAULT")"
R="$VAULT/.opencode/skills/ai-brain-starter"
MANIFEST="$VAULT/$BRAIN_MANIFEST_REL"
for rel in ".opencode" ".opencode/skills" ".opencode/skills/ai-brain-starter" \
           ".opencode/commands" ".opencode/plugins" "scripts" "scripts/jobs" "⚙️ Meta" "⚙️ Meta/scripts"; do
  [ -L "$VAULT/$rel" ] && die "ruta base es un symlink; se preservó el vault: $rel"
done
# The installer seeds these; through a symlink it would write outside the vault.
if [ "$WIRE" = 0 ]; then
  for rel in "AGENTS.md" "⚙️ Meta/brain-config.json" "⚙️ Meta/journal-config.md"; do
    [ -L "$VAULT/$rel" ] \
      && die "$rel es un symlink; el instalador no escribe a través de enlaces. Reemplázalo por un archivo normal; se preservó el vault"
  done
fi

if [ "$WIRE" = 1 ]; then
  for rel in ".opencode/skills" ".opencode/commands" ".opencode/plugins" "scripts" "scripts/jobs" "⚙️ Meta" "⚙️ Meta/scripts"; do
    [ -d "$VAULT/$rel" ] || die "--wire requiere la estructura existente; falta $rel"
  done
  [ -f "$MANIFEST" ] || die "--wire requiere un manifiesto de propiedad existente; no se creó ni migró"
  [ -f "$R/SKILL.md" ] && [ -d "$R/skills" ] && [ -d "$R/commands" ] && [ -d "$R/scripts" ] \
    || die "--wire requiere un starter existente y válido en $R"
  [ -f "$VAULT/AGENTS.md" ] || die "--wire requiere AGENTS.md existente; no se regenera el vault"
  [ -f "$VAULT/⚙️ Meta/brain-config.json" ] || die "--wire requiere ⚙️ Meta/brain-config.json existente"
  brain_config "$VAULT/⚙️ Meta/brain-config.json" validate >/dev/null 2>&1 \
    || die "--wire requiere una configuración JSON válida"
fi

owner_manifest() {
  run_python "$LIB/ownership.py" "$MANIFEST" "$@"
}

if [ "$DRY_RUN" = 1 ]; then
  echo "== Plan (--dry-run: no se modificó nada) =="
  if [ "$WIRE" = 1 ]; then
    ok "re-cablearía skills, comandos y scripts del starter en $VAULT"
  else
    ok "crearía o actualizaría el vault en $VAULT"
    if [ -f "$R/.git/HEAD" ]; then ok "usaría el starter ya clonado"; else ok "clonaría $STARTER_REPO"; fi
    if [ -f "$VAULT/AGENTS.md" ]; then ok "preservaría AGENTS.md"; else ok "generaría AGENTS.md"; fi
    if [ -n "$CONFIG" ]; then ok "sembraría brain-config.json desde $CONFIG"; fi
  fi
  ok "instalaría el plugin, los comandos, los trabajos y las bibliotecas del paquete ($VERSION)"
  if [ "$WITH_MCP" = 1 ]; then ok "agregaría los MCP remotos a opencode.json"; fi
  if [ "$WITH_OBSIDIAN" = 1 ]; then ok "instalaría los complementos de Obsidian"; fi
  if [ "$WITH_SCHEDULE" = 1 ]; then ok "programaría los trabajos (míralos con: bash scripts/schedule.sh <vault> --dry-run)"; fi
  exit 0
fi

if [ "$WIRE" = 0 ]; then mkdir -p "$(dirname "$MANIFEST")"; fi
owner_manifest init "$VERSION" || die "el registro de propiedad existe pero no es válido; se preservó el vault"

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

# Toda escritura con propiedad pasa por ownership.py: copia solo lo que el vault
# no posee de otra forma, registra la huella y avisa de lo que preserva.
# install_files (<ruta-en-vault> <origen> <modo|->)...  deja en MANAGED cuántos gestionó.
MANAGED=0
install_files() {
  MANAGED="$(owner_manifest install-files "$VAULT" "$@")" || die "no se pudieron instalar los archivos del paquete"
}

# install_link <ruta-en-vault> <destino-relativo>
install_link() {
  local rc=0
  owner_manifest install-link "$VAULT" "$1" "$2" || rc=$?
  case "$rc" in 0|3) ;; *) die "no se pudo enlazar $1" ;; esac
}

wire_vendor() {
  run_python "$LIB/wire.py" "$VAULT" --mode "$WIRE_MODE" --only "$1" || die "no se pudo cablear el starter ($1)"
}

echo "== 1. Carpetas canónicas del vault =="
# Paths this run wrote outside the manifest; only they (and the manifest's) enter the base commit.
BASE_PATHS=()
if [ "$WIRE" = 0 ]; then
  for d in "📓 Journals" "🏠 Home" "👤 CRM" "📝 Notes" "📝 Notes/Raw" "💼 Business/Engagements" "🚀 I+D/Herramientas" "🚀 I+D/Investigación" \
           "⚙️ Meta/Folder Resolvers" "⚙️ Meta/scripts" "⚙️ Meta/Sessions" "⚙️ Meta/Decisions" "⚙️ Meta/Workflows" \
           "⚙️ Meta/Facts" "⚙️ Meta/Exceptions" "⚙️ Meta/Floors" "⚙️ Meta/logs" ".opencode/commands" ".opencode/plugins"; do
    if ! ensure_vault_dir "$d"; then
      warn "directorio symlink o ruta incompatible preservada: $d"
      continue
    fi
    if [ -L "$VAULT/$d/.gitkeep" ]; then
      warn "symlink .gitkeep preservado: $d/.gitkeep"
      continue
    elif [ ! -f "$VAULT/$d/.gitkeep" ]; then
      : > "$VAULT/$d/.gitkeep"
    fi
    BASE_PATHS+=("$d/.gitkeep")
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
    if git -C "$R" pull --ff-only >/dev/null 2>&1; then ok "starter actualizado (ff-only)"; else warn "pull falló: se usa la versión local"; fi
  else
    ok "starter presente (actualiza con BRAIN_STARTER_UPDATE=1)"
  fi
else
  git clone -q --depth 1 "$STARTER_REPO" "$R" || die "no se pudo clonar $STARTER_REPO"
  owner_manifest record-clone ".opencode/skills/ai-brain-starter" "$STARTER_REPO" || die "no se pudo registrar el clon del starter"
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
wire_vendor skills,commands
PKG_COMMANDS=()
for f in "$PKG"/templates/commands/*.md; do
  [ -f "$f" ] || continue
  PKG_COMMANDS+=(".opencode/commands/$(basename "$f")" "$f" 0644)
done
if [ "${#PKG_COMMANDS[@]}" -gt 0 ]; then
  install_files "${PKG_COMMANDS[@]}"
  ok "$MANAGED comandos del paquete"
fi

echo "== 3b. Scripts del vendor que los skills invocan (⚙️ Meta/scripts) =="
wire_vendor scripts

echo "== 4. humanizer (MIT, lo usa la regla de humanización) =="
H="$VAULT/.opencode/skills/humanizer"
if [ "$WIRE" = 1 ]; then
  ok "humanizer preservado (--wire no instala dependencias)"
elif [ ! -e "$H" ] && [ ! -L "$H" ]; then
  if git clone -q --depth 1 "$HUMANIZER_REPO" "$H"; then
    owner_manifest record-clone ".opencode/skills/humanizer" "$HUMANIZER_REPO" || warn "no se pudo registrar el clon de humanizer"
    ok "humanizer clonado"
  else
    warn "humanizer falló (opcional)"
  fi
else
  ok "humanizer presente"
fi

echo "== 5. Pisos emocionales (generados desde el framework High-Rise del vendor) =="
if [ "$WIRE" = 0 ]; then
  if run_python "$R/scripts/generate_floor_stubs.py" >/dev/null 2>&1; then ok "stubs generados en el clon"; else warn "generador de pisos falló"; fi
  # Un clon registrado por huella (instalaciones anteriores) pasa a registrarse
  # por su origen: la huella deja de coincidir en el primer pull.
  owner_manifest adopt-clone ".opencode/skills/ai-brain-starter" "$STARTER_REPO" || warn "no se pudo migrar el registro del starter"
  owner_manifest adopt-clone ".opencode/skills/humanizer" "$HUMANIZER_REPO" || warn "no se pudo migrar el registro de humanizer"
  if [ -d "$R/floors" ]; then
    floors_copied="$(copy_new_floors "$R/floors" "$VAULT/⚙️ Meta/Floors")" || warn "no se pudieron copiar todas las notas de piso"
    ok "$(find "$VAULT/⚙️ Meta/Floors" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ') notas de piso (${floors_copied:-0} nuevas)"
  fi
else
  ok "pisos y datos personales preservados (--wire)"
fi

echo "== 6. Configuración del diario (plantilla del vendor, sin sobrescribir) =="
if [ "$WIRE" = 1 ]; then
  ok "journal-config.md preservado (--wire)"
elif [ ! -f "$VAULT/⚙️ Meta/journal-config.md" ] && [ -f "$R/templates/journal-config.md" ]; then
  cp "$R/templates/journal-config.md" "$VAULT/⚙️ Meta/journal-config.md" || die "no se pudo crear ⚙️ Meta/journal-config.md"
  ok "journal-config.md creado"
  owner_manifest record-file "⚙️ Meta/journal-config.md" "$VAULT/⚙️ Meta/journal-config.md" \
    || warn "no se pudo registrar ⚙️ Meta/journal-config.md"
else
  ok "journal-config.md presente"
fi

echo "== 7. brain-config.json (valores del cerebro; el plugin lo lee) =="
BRC="$VAULT/⚙️ Meta/brain-config.json"
if [ "$WIRE" = 1 ]; then
  ok "brain-config.json preservado (--wire)"
elif [ -n "$CONFIG" ]; then
  if [ -f "$BRC" ]; then
    cp "$BRC" "$BRC.bak.$(date +%Y%m%d-%H%M%S)" || die "no se pudo respaldar la config previa; no se sembró --config"
    warn "backup de la config previa"
  fi
  cp "$CONFIG" "$BRC" || die "no se pudo sembrar la config desde $CONFIG"
  ok "config sembrada desde $CONFIG"
  BASE_PATHS+=("⚙️ Meta/brain-config.json")
elif [ ! -f "$BRC" ]; then
  brain_config "$BRC" seed "$SLUG" || die "no se pudo sembrar brain-config.json desde templates/brain-config.example.json"
  BASE_PATHS+=("⚙️ Meta/brain-config.json")
else
  ok "brain-config.json presente"
fi

echo "== 8. AGENTS.md (template del vendor + adaptación OpenCode) =="
if [ "$WIRE" = 1 ]; then
  ok "AGENTS.md preservado (--wire)"
elif [ -f "$VAULT/AGENTS.md" ]; then
  ok "AGENTS.md existe — preservado (nunca se sobrescribe contenido personal)"
else
  run_python - "$R/templates/generated/claude-md-template.md" "$PKG/templates/agents-opencode-appendix.md" "$BRC" "$VAULT/AGENTS.md" "$LIB" <<'PYGEN' || die "fallo generando AGENTS.md"
import pathlib, re, sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[5])
import brain_config
tpl = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
app = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
try:
    cfg, _ = brain_config.effective(sys.argv[3])
except brain_config.ConfigError as error:
    raise SystemExit(str(error))
out = pathlib.Path(sys.argv[4])
missing = []

def adapt(pattern, replacement, text, what):
    """The vendor template changes upstream: a lost anchor must be visible."""
    result, count = re.subn(pattern, lambda match: replacement, text, flags=re.S)
    if not count:
        missing.append(what)
    return result

src = tpl.replace("~/.claude/skills/humanizer", ".opencode/skills/humanizer")
src = src.replace("~/.claude/skills/ai-brain-starter", ".opencode/skills/ai-brain-starter")
src = adapt(r"8\. \*\*Your brain lives in the vault.*?(?=\n\n9\. )",
    "8. **Tu cerebro vive en el vault — nunca solo en la memoria del agente.** Todo lo que valga entre sesiones termina como archivo de este vault (nota, decisión, regla). Test: \"¿otra máquina, otra herramienta, el próximo mes — sigue aquí?\"",
    src, "regla 8 (el cerebro vive en el vault)")
src = adapt(r"1\. Start: Read this file and.*?(?=\n2\. )",
    "1. Start: lee este archivo y la sesión más reciente en `⚙️ Meta/Sessions/`.",
    src, "paso de inicio de sesión")
src = adapt(r"\n2\. \*\*Run the daily AI brain setup update check\*\*.*?(?=\n3\. )", "", src, "chequeo diario de actualización")
src = adapt(r"\n3\. During: ", "\n2. During: ", src, "paso 'During' del protocolo de sesión")
src = adapt(r"\n4\. End: The \*\*session close cascade\*\*.*?(?=\n\n## )",
    "\n3. End: cierra con una señal de cierre (\"chao\", \"eso es todo\", \"good night\"...). El plugin brain-vault la detecta e inyecta el cascade: guarda la sesión en ⚙️ Meta/Sessions/, registra decisiones en ⚙️ Meta/Decisions/ y compromete solo las rutas tocadas.",
    src, "paso de cierre de sesión")
src = adapt(r"## Session close — configuration \(optional\).*?\Z", "", src, "sección de configuración del cierre")
if "## Session start — daily update check" in src:
    src = adapt(r"## Session start — daily update check.*?(?=\n## |\Z)", "", src, "sección del chequeo diario")
vault_map = """Carpetas del vault (adaptación OpenCode). Los nombres van en inglés a propósito: los skills del sistema tienen rutas fijas y traducirlos genera carpetas duplicadas.

- 📓 Journals/ — entradas del diario. Crea el skill `daily-journal`.
- 🏠 Home/ — About Me.md y contexto personal.
- 👤 CRM/ — personas. Un archivo por persona.
- 📝 Notes/ — notas sueltas, artículos, imports.
- 💼 Business/ — trabajo y negocio; Engagements/ = una carpeta por cliente.
- 🚀 I+D/ — investigación y desarrollo (Herramientas/, Investigación/).
- ⚙️ Meta/ — maquinaria: Folder Resolvers/, Floors/, Sessions/, Decisions/, logs/.

Antes de crear cualquier cosa: revisa este mapa y ⚙️ Meta/Folder Resolvers/."""
src = adapt(r"## Vault Map\n\[FILL THIS IN.*?\]", "## Vault Map\n" + vault_map, src, "Vault Map")
journal, schedule = cfg["journal"], cfg["schedule"]
for k, v in {
    "{{LANGUAGE}}": cfg["language"],
    "{{JOURNAL_TIME}}": journal["time"],
    "{{TIMEZONE}}": cfg["timezone"],
    "{{HABITS}}": ", ".join(cfg["habits"]) or "ninguno",
    "{{ACCOUNTABILITY}}": ", ".join(cfg["accountability"]) or "a definir en la entrevista",
    "{{VAULT_NAME}}": cfg["vault_name"],
    "{{INSIGHTS_TIME}}": schedule["insights_time"],
    "{{MAINTENANCE_TIME}}": schedule["maintenance_time"],
    "{{UPDATE_TIME}}": schedule["update_time"],
}.items():
    app = app.replace(k, v)
header = ("<!-- Generado por install.sh desde el template de ai-brain-starter + adaptación OpenCode. "
          "Completa las secciones personales con la entrevista de setup. -->\n\n")
out.write_text(header + src.rstrip() + "\n\n" + app + "\n", encoding="utf-8")
for what in missing:
    print("  ! la plantilla del vendor cambió: no se encontró '" + what + "'; revisa esa parte de AGENTS.md", file=sys.stderr)
PYGEN
  [ -f "$VAULT/AGENTS.md" ] || die "fallo generando AGENTS.md"
  BASE_PATHS+=("AGENTS.md")
  ok "AGENTS.md generado (plantilla + adaptación OpenCode)"
fi
if [ "$WIRE_MODE" = "copy" ]; then
  install_files "CLAUDE.md" "$VAULT/AGENTS.md" -
else
  install_link "CLAUDE.md" "AGENTS.md"
fi

echo "== 9. Plugin brain-vault (hooks OpenCode) =="
install_files ".opencode/plugins/brain-vault/index.js" "$PKG/plugin/brain-vault/index.js" -
if command -v node >/dev/null; then
  node --check "$VAULT/.opencode/plugins/brain-vault/index.js" \
    || die "el plugin instalado tiene un error de sintaxis: .opencode/plugins/brain-vault/index.js"
  ok "plugin instalado (sintaxis validada)"
else
  ok "plugin instalado (lee ⚙️ Meta/brain-config.json)"
fi

echo "== 10. Trabajos programados (scripts data-driven) =="
PKG_JOBS=()
for f in "$PKG"/templates/jobs/*.sh; do
  [ -f "$f" ] || continue
  PKG_JOBS+=("scripts/jobs/$(basename "$f")" "$f" 0755)
done
if [ "${#PKG_JOBS[@]}" -gt 0 ]; then
  install_files "${PKG_JOBS[@]}"
  ok "$MANAGED trabajos gestionados"
fi
# Lo que el vault necesita para verificarse y correr sus trabajos sin el checkout
# del paquete. La lista de rutas gestionadas vive en ownership.py (MANAGED_FILES).
install_files \
  "scripts/verify.sh" "$PKG/scripts/verify.sh" 0755 \
  "scripts/audit.py" "$PKG/scripts/audit.py" 0755 \
  "scripts/lib/ownership.py" "$LIB/ownership.py" 0644 \
  "scripts/lib/python3.sh" "$LIB/python3.sh" 0644 \
  "scripts/lib/common.sh" "$LIB/common.sh" 0644 \
  "scripts/lib/wire.py" "$LIB/wire.py" 0644 \
  "scripts/lib/brain_config.py" "$LIB/brain_config.py" 0644 \
  "scripts/lib/brain-config.defaults.json" "$EXAMPLE" 0644
ok "$MANAGED utilidades del vault (verify, audit, bibliotecas)"

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
  # Las líneas viven en ownership.py (GITIGNORE_LINES); un .gitignore existente solo se completa.
  rc=0
  owner_manifest ensure-gitignore "$VAULT" || rc=$?
  case "$rc" in 0|3) ;; *) warn "no se pudo completar .gitignore" ;; esac
fi

if [ "$WITH_MCP" = 1 ]; then
  echo "== 12. MCP remotos (opt-in) =="
  # El vault ya está instalado: un fallo aquí se avisa y se omite, nunca aborta.
  if [ -L "$VAULT/opencode.json" ]; then
    warn "opencode.json es un symlink; se preservó sin modificarlo"
  elif [ -e "$VAULT/opencode.jsonc" ] || [ -L "$VAULT/opencode.jsonc" ]; then
    warn "existe opencode.jsonc: se omitió la configuración MCP para no crear una segunda configuración; agrega a mano granola y chatprd"
  else
    OPENCODE_EXISTED=0
    if [ -e "$VAULT/opencode.json" ]; then OPENCODE_EXISTED=1; fi
    if ! MCP_ADDED="$(run_python - "$VAULT/opencode.json" 2>&1 <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
if p.exists() and (p.is_symlink() or not p.is_file() or p.stat().st_nlink != 1):
    raise SystemExit("refusing to modify a symlinked, non-regular, or hard-linked opencode.json")
try:
    d = json.loads(p.read_text(encoding="utf-8")) if p.exists() else {"$schema": "https://opencode.ai/config.json"}
except ValueError:
    raise SystemExit("opencode.json no es JSON estricto (¿comentarios o comas finales?); agrega a mano granola y chatprd")
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
      warn "se omitió la configuración MCP: $MCP_ADDED"
    else
      if [ "$MCP_ADDED" != "{}" ] && ! owner_manifest record-config "$MCP_ADDED"; then
        warn "no se pudo registrar la configuración MCP; la desinstalación no quitará granola ni chatprd"
      fi
      if [ "$OPENCODE_EXISTED" = 0 ] && [ -f "$VAULT/opencode.json" ]; then BASE_PATHS+=("opencode.json"); fi
      ok "MCP remotos configurados sin sobrescribir entradas existentes"
    fi
  fi
fi

if [ "$WITH_OBSIDIAN" = 1 ]; then
  echo "== 13. Obsidian: complementos comunitarios =="
  run_python - "$VAULT" <<'PY'
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

SCHEDULE_FAILED=0
if [ "$WITH_SCHEDULE" = 1 ]; then
  echo "== 14. Trabajos programados =="
  bash "$PKG/scripts/schedule.sh" "$VAULT" || SCHEDULE_FAILED=1
fi

echo "== 15. Commit base del vault =="
if [ "$WIRE" = 1 ]; then
  ok "estado Git preservado (--wire)"
elif [ ! -d "$VAULT/.git" ]; then
  warn "sin repositorio Git; commit base omitido"
elif [ -z "$(git -C "$VAULT" status --porcelain)" ]; then
  ok "sin cambios por confirmar"
else
  # Solo lo que el paquete posee (manifiesto) y lo que esta ejecución creó: la
  # configuración, los agentes y el contenido del usuario nunca entran.
  CANDIDATES=()
  while IFS= read -r -d '' path; do CANDIDATES+=("$path"); done < <(owner_manifest owned-paths)
  CANDIDATES+=(${BASE_PATHS[@]+"${BASE_PATHS[@]}"})
  # `git add` aborta con una ruta ignorada: lo que el .gitignore del usuario excluye se respeta.
  IGNORED=$'\n'
  if [ "${#CANDIDATES[@]}" -gt 0 ]; then
    IGNORED="$IGNORED$(printf '%s\0' "${CANDIDATES[@]}" \
      | git -C "$VAULT" check-ignore -z --stdin 2>/dev/null | tr '\0' '\n' || true)"$'\n'
  fi
  GIT_ADD=()
  for path in ${CANDIDATES[@]+"${CANDIDATES[@]}"}; do
    [ -e "$VAULT/$path" ] || [ -L "$VAULT/$path" ] || continue
    case "$IGNORED" in *$'\n'"$path"$'\n'*) continue ;; esac
    GIT_ADD+=("$path")
  done
  STAGED=()
  if [ "${#GIT_ADD[@]}" -gt 0 ]; then
    GIT_LITERAL_PATHSPECS=1 git -C "$VAULT" add -- "${GIT_ADD[@]}"
    while IFS= read -r -d '' path; do STAGED+=("$path"); done \
      < <(GIT_LITERAL_PATHSPECS=1 git -C "$VAULT" diff --cached --name-only -z -- "${GIT_ADD[@]}")
  fi
  if [ "${#STAGED[@]}" -eq 0 ]; then
    ok "sin cambios por confirmar"
  else
    # El pathspec limita el commit a estas rutas: lo que el usuario ya tuviera
    # en el index de un vault existente no entra en el commit base.
    GIT_LITERAL_PATHSPECS=1 git -C "$VAULT" commit -q -m "chore: bootstrap ai-brain OpenCode vault" -- "${STAGED[@]}"
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
  echo "   3. Esta noche: /daily-journal — la primera entrada activa el sistema."
  echo "   4. Verificación: bash $VAULT/scripts/verify.sh"
fi
if [ "$SCHEDULE_FAILED" = 1 ]; then
  die "el vault quedó instalado, pero la programación de trabajos falló; revisa los avisos y repite con: bash $PKG/scripts/schedule.sh \"$VAULT\""
fi
