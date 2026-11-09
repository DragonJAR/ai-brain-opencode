#!/usr/bin/env bash
# install.sh — instala el cerebro (ai-brain-starter adaptado a OpenCode V2).
#
# Uso:
#   bash install.sh <ruta-del-vault> [flags]
# Flags:
#   --config <archivo>   brain-config.json para sembrar (por defecto: valores incluidos)
#   --wire               solo re-ejecuta el cableado en un vault existente (ruta de actualización)
#   --with-mcp           agrega los MCP remotos granola + chatprd (opt-in: envían tu conversación cuando los usas)
#   --with-obsidian      instala los complementos de Obsidian en el vault
#   --with-schedule      instala los trabajos programados (launchd en macOS, cron en Linux)
#   --yes                no-interactivo (acepta valores por defecto)
# Idempotente: re-ejecutar es seguro; el contenido personal nunca se sobrescribe.
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STARTER_REPO="https://github.com/mycelium-hq/ai-brain-starter"
HUMANIZER_REPO="https://github.com/adelaidasofia/humanizer.git"
OS="$(uname -s)"
VAULT="" CONFIG="" WIRE=0 WITH_MCP=0 WITH_OBSIDIAN=0 WITH_SCHEDULE=0 YES=0 UNINSTALL=0

say()  { printf '%s\n' "$*"; }
ok()   { printf '  + %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }
die()  { printf '  ✗ %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --wire) WIRE=1; shift ;;
    --with-mcp) WITH_MCP=1; shift ;;
    --with-obsidian) WITH_OBSIDIAN=1; shift ;;
    --with-schedule) WITH_SCHEDULE=1; shift ;;
    --yes|-y) YES=1; shift ;;
    --help|-h) sed -n '2,14p' "$0"; exit 0 ;;
    *) if [ -z "$VAULT" ]; then VAULT="$1"; else die "argumento inesperado: $1"; fi; shift ;;
  esac
done
[ -n "$VAULT" ] || { sed -n '2,14p' "$0"; exit 1; }
mkdir -p "$VAULT"
VAULT="$(cd "$VAULT" && pwd)"
SLUG="$(basename "$VAULT" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
SLUG="${SLUG:-cerebro}"
R="$VAULT/.opencode/skills/ai-brain-starter"

echo "== 0. Preflight =="
for cmd in git python3; do command -v $cmd >/dev/null || die "falta $cmd (requerido)"; done
command -v opencode >/dev/null && ok "opencode CLI presente" || warn "opencode CLI no está en PATH (instálalo desde https://opencode.ai/docs) — el vault se instala igual"
command -v node >/dev/null && ok "node presente" || warn "node no encontrado (opcional: validación de sintaxis del plugin)"
[ "$OS" = "Darwin" ] && ok "macOS detectado (scheduler: launchd)" || { [ "$OS" = "Linux" ] && ok "Linux detectado (scheduler: cron)"; } || true
if [ "$WITH_OBSIDIAN" = 1 ] && [ "$OS" != "Darwin" ] && [ "$OS" != "Linux" ]; then die "--with-obsidian soporta macOS/Linux"; fi

echo "== 1. Carpetas canónicas del vault =="
for d in "📓 Journals" "🏠 Home" "👤 CRM" "📝 Notes" "💼 Business/Engagements" "🚀 I+D/Herramientas" "🚀 I+D/Investigación" \
         "⚙️ Meta/Folder Resolvers" "⚙️ Meta/scripts" "⚙️ Meta/Sessions" "⚙️ Meta/Decisions" "⚙️ Meta/Workflows" \
         "⚙️ Meta/Facts" "⚙️ Meta/Exceptions" "⚙️ Meta/Floors" "⚙️ Meta/logs" ".opencode/commands" ".opencode/plugins"; do
  mkdir -p "$VAULT/$d"; [ -f "$VAULT/$d/.gitkeep" ] || : > "$VAULT/$d/.gitkeep"
done
ok "estructura creada"

echo "== 2. Clonar/actualizar ai-brain-starter (fuente única) =="
if [ -f "$R/.git/HEAD" ]; then
  git -C "$R" pull --ff-only >/dev/null 2>&1 && ok "starter actualizado (ff-only)" || warn "pull falló: se usa la versión local"
else
  git clone -q --depth 1 "$STARTER_REPO" "$R" && ok "starter clonado ($(git -C "$R" log --oneline -1 | cut -c1-8))"
fi
[ -f "$R/SKILL.md" ] || die "el clon no tiene SKILL.md — revisa $R"

echo "== 3. Cablear skills y comandos (symlinks relativos, sin copias) =="
for d in "$R"/skills/*/; do
  n="$(basename "$d")"; [ "$n" = "ai-brain-starter" ] && continue
  l="$VAULT/.opencode/skills/$n"
  if [ ! -e "$l" ]; then ln -s "ai-brain-starter/skills/$n" "$l"; fi
done
ok "$(find "$VAULT/.opencode/skills" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ') skills enlazadas"
mkdir -p "$VAULT/.opencode/commands"
for f in "$R"/commands/*.md; do
  n="$(basename "$f")"; l="$VAULT/.opencode/commands/$n"
  [ -e "$l" ] || ln -s "../skills/ai-brain-starter/commands/$n" "$l"
done
ok "$(ls -1 "$VAULT/.opencode/commands" | wc -l | tr -d ' ') comandos enlazados"

echo "== 4. humanizer (MIT, lo usa la regla de humanización) =="
H="$VAULT/.opencode/skills/humanizer"
if [ ! -e "$H" ]; then git clone -q --depth 1 "$HUMANIZER_REPO" "$H" && ok "humanizer clonado" || warn "humanizer falló (opcional)"; else ok "humanizer presente"; fi

echo "== 5. Pisos emocionales (generados desde el framework High-Rise del vendor) =="
python3 "$R/scripts/generate_floor_stubs.py" >/dev/null 2>&1 && ok "stubs generados en el clon" || warn "generador de pisos falló"
if [ -d "$R/floors" ]; then
  cp "$R/floors/"*.md "$VAULT/⚙️ Meta/Floors/" 2>/dev/null && ok "$(ls -1 "$VAULT/⚙️ Meta/Floors" | wc -l | tr -d ' ') notas de piso"
fi

echo "== 6. Configuración del diario (plantilla del vendor, sin sobrescribir) =="
if [ ! -f "$VAULT/⚙️ Meta/journal-config.md" ] && [ -f "$R/templates/journal-config.md" ]; then
  cp "$R/templates/journal-config.md" "$VAULT/⚙️ Meta/journal-config.md" && ok "journal-config.md creado"
else
  ok "journal-config.md presente"
fi

echo "== 7. brain-config.json (valores del cerebro; el plugin lo lee) =="
BRC="$VAULT/⚙️ Meta/brain-config.json"
if [ -n "$CONFIG" ]; then
  [ -f "$CONFIG" ] || die "no existe --config: $CONFIG"
  cp "$CONFIG" "$BRC" && ok "config sembrada desde $CONFIG"
elif [ ! -f "$BRC" ]; then
  cp "$PKG/templates/brain-config.example.json" "$BRC"
  python3 - "$BRC" "$SLUG" <<'PZ'
import json, os, pathlib, re, sys
p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text())
tz = ""
try:
    link = os.readlink("/etc/localtime")
    m = re.search(r"zoneinfo/(.+)$", link)
    if m: tz = m.group(1)
except Exception:
    pass
d["timezone"] = tz or "UTC"
d["vault_name"] = sys.argv[2]
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
print("  + config por defecto creada (zona horaria detectada: " + d["timezone"] + ")")
PZ
else
  ok "brain-config.json presente"
fi

echo "== 8. AGENTS.md (template del vendor + adaptación OpenCode) =="
if [ -f "$VAULT/AGENTS.md" ]; then
  ok "AGENTS.md existe — preservado (nunca se sobrescribe contenido personal)"
else
  python3 - "$R/templates/generated/claude-md-template.md" "$PKG/templates/agents-opencode-appendix.md" "$BRC" "$VAULT/AGENTS.md" <<'PYGEN'
import json, pathlib, re, sys
tpl = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
app = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
cfg = json.load(open(sys.argv[3], encoding="utf-8"))
out = pathlib.Path(sys.argv[4])
src = tpl.replace("~/.claude/skills/humanizer", ".opencode/skills/humanizer")
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
    "{{LANGUAGE}}": cfg.get("language", "es"),
    "{{JOURNAL_TIME}}": cfg.get("journal", {}).get("time", "20:30"),
    "{{TIMEZONE}}": cfg.get("timezone", "UTC"),
    "{{HABITS}}": ", ".join(cfg.get("habits", [])) or "ninguno",
    "{{ACCOUNTABILITY}}": ", ".join(cfg.get("accountability", [])) or "a definir en la entrevista",
    "{{VAULT_NAME}}": cfg.get("vault_name", "mi-cerebro"),
}.items():
    app = app.replace(k, str(v))
header = ("<!-- Generado por install.sh desde el template de ai-brain-starter + adaptación OpenCode. "
          "Completa las secciones personales con la entrevista de setup. -->\n\n")
out.write_text(header + src.rstrip() + "\n\n" + app + "\n", encoding="utf-8")
PYGEN
  [ -f "$VAULT/AGENTS.md" ] && ok "AGENTS.md generado (plantilla + adaptación OpenCode)" || die "fallo generando AGENTS.md"
fi
[ -L "$VAULT/CLAUDE.md" ] || { [ -e "$VAULT/CLAUDE.md" ] || ln -s AGENTS.md "$VAULT/CLAUDE.md" && ok "CLAUDE.md -> AGENTS.md"; }

echo "== 9. Plugin brain-vault (hooks OpenCode) =="
mkdir -p "$VAULT/.opencode/plugins/brain-vault"
cp "$PKG/plugin/brain-vault/index.js" "$VAULT/.opencode/plugins/brain-vault/index.js"
ok "plugin instalado (lee ⚙️ Meta/brain-config.json)"

echo "== 10. Trabajos programados (scripts data-driven) =="
mkdir -p "$VAULT/scripts/jobs"
cp "$PKG"/templates/jobs/*.sh "$VAULT/scripts/jobs/" 2>/dev/null || true
cp "$PKG/scripts/verify.sh" "$VAULT/scripts/verify.sh" 2>/dev/null || true
chmod +x "$VAULT/scripts/verify.sh" 2>/dev/null || true
chmod +x "$VAULT"/scripts/jobs/*.sh 2>/dev/null || true
ok "$(ls -1 "$VAULT/scripts/jobs" | wc -l | tr -d ' ') trabajos copiados"

echo "== 11. Git del vault (respaldo local) =="
if [ ! -d "$VAULT/.git" ]; then git -C "$VAULT" init -q -b main && ok "git init (main)"; fi
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
if [ -z "$(git -C "$VAULT" status --porcelain)" ]; then ok "sin cambios por confirmar"
else git -C "$VAULT" add AGENTS.md CLAUDE.md .gitignore .opencode scripts "📓 Journals" "🏠 Home" "👤 CRM" "📝 Notes" "💼 Business" "🚀 I+D" "⚙️ Meta" && git -C "$VAULT" commit -q -m "chore: bootstrap ai-brain OpenCode vault" && ok "commit base"; fi

if [ "$WITH_MCP" = 1 ]; then
  echo "== 12. MCP remotos (opt-in) =="
  python3 - "$VAULT/opencode.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text()) if p.exists() else {}
servers = d.setdefault("mcp", {}).setdefault("servers", {})
for name, url in {"granola": "https://mcp.granola.ai/mcp", "chatprd": "https://app.chatprd.ai/mcp"}.items():
    servers.setdefault(name, {"type": "remote", "url": url})
p.write_text(json.dumps(d, indent=2) + "\n", encoding="utf-8")
print("  + granola y chatprd configurados (autenticación: /mcps en OpenCode)")
PY
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
if not cp.exists():
    cp.write_text(json.dumps(list(PLUGINS), indent=2) + "\n", encoding="utf-8")
    print("  + community-plugins.json (aprueba complementos al abrir Obsidian la primera vez)")
PY
fi

if [ "$WITH_SCHEDULE" = 1 ]; then
  echo "== 14. Trabajos programados =="
  bash "$PKG/scripts/schedule.sh" "$VAULT"
fi

echo
echo "━━━ Instalación completa ━━━"
echo "  vault: $VAULT"
echo "  Siguientes pasos:"
echo "   1. Reinicia OpenCode o ejecuta /reload para que cargue el plugin."
echo "   2. Edita AGENTS.md (sección Me / Current Focus) o corre la entrevista de setup."
echo "   3. Esta noche: /journal — la primera entrada activa el sistema."
echo "   4. Verificación: bash $VAULT/scripts/verify.sh"
