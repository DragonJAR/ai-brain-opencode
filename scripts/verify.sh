#!/usr/bin/env bash
# verify.sh — verificación de salud del vault. Se instala en <vault>/scripts/verify.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [ -f "$PACKAGE_ROOT/install.sh" ] \
  && [ -f "$PACKAGE_ROOT/templates/brain-config.example.json" ] \
  && [ -f "$PACKAGE_ROOT/tests/run.sh" ]; then
  echo "== Paquete: pruebas de regresión deterministas =="
  bash "$PACKAGE_ROOT/tests/run.sh"
  exit $?
fi

VAULT="$PACKAGE_ROOT"
cd "$VAULT" || exit 1
PY3="python3"
if [ -f "$SCRIPT_DIR/lib/python3.sh" ]; then
  # shellcheck source=lib/python3.sh
  . "$SCRIPT_DIR/lib/python3.sh"
  pick_python3 || PY3="python3"
fi
OS="$(uname -s)"
WIN=0
case "$OS" in
  MINGW*|MSYS*|CYGWIN*) WIN=1 ;;
esac
PASS=0; FAIL=0
chk() { if [ "$2" = "1" ]; then printf '  ✓ %s\n' "$1"; PASS=$((PASS+1)); else printf '  ✗ %s\n' "$1"; FAIL=$((FAIL+1)); fi; }
skip() { printf '  ~ %s\n' "$1"; }

echo "== Estructura =="
starter=".opencode/skills/ai-brain-starter"
if [ -d "$starter" ] && [ ! -L "$starter" ] && [ -f "$starter/SKILL.md" ]; then
  chk "starter clonado" 1
else
  chk "starter clonado" 0
fi
if [ "$WIN" = 1 ]; then
  SK=0
  for entry in .opencode/skills/*; do
    [ -e "$entry" ] || continue
    [ "$(basename "$entry")" = "ai-brain-starter" ] && continue
    [ -d "$entry" ] && [ ! -L "$entry" ] && SK=$((SK + 1))
  done
  [ "$SK" -ge 1 ] && chk "skills copiadas ($SK)" 1 || chk "skills copiadas ($SK)" 0
else
  SK=$(find .opencode/skills -maxdepth 1 -mindepth 1 -type l 2>/dev/null | wc -l | tr -d ' ')
  [ "$SK" -ge 1 ] && chk "skills enlazadas ($SK)" 1 || chk "skills enlazadas ($SK)" 0
fi
CMD=$(find .opencode/commands -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
CMD_LABEL="comandos enlazados"; [ "$WIN" = 1 ] && CMD_LABEL="comandos copiados"
[ "$CMD" -ge 1 ] && chk "$CMD_LABEL ($CMD)" 1 || chk "$CMD_LABEL ($CMD)" 0
BAD=$(find .opencode -xtype l 2>/dev/null | wc -l | tr -d ' ')
[ "$BAD" -eq 0 ] && chk "sin symlinks rotos" 1 || chk "symlinks rotos: $BAD" 0
for d in "📓 Journals" "🏠 Home" "👤 CRM" "📝 Notes" "💼 Business" "🚀 I+D" "⚙️ Meta"; do
  [ -d "$d" ] && chk "carpeta $d" 1 || chk "carpeta $d" 0
done
CLAUDE_TARGET="AGENTS.md"
claude_ok=0
if [ "$WIN" = 1 ]; then
  if [ -f CLAUDE.md ] && [ ! -L CLAUDE.md ] && [ -f "$CLAUDE_TARGET" ] && cmp -s CLAUDE.md "$CLAUDE_TARGET"; then
    claude_ok=1
  fi
  [ "$claude_ok" = 1 ] && chk "CLAUDE.md copia de $CLAUDE_TARGET" 1 || chk "CLAUDE.md copia de $CLAUDE_TARGET" 0
else
  if [ -L CLAUDE.md ] && [ -e "$CLAUDE_TARGET" ]; then
    if $PY3 - "$CLAUDE_TARGET" <<'PY'
import os, sys
try:
    same = os.path.realpath("CLAUDE.md") == os.path.realpath(sys.argv[1])
except OSError:
    same = False
raise SystemExit(0 if same else 1)
PY
    then
      claude_ok=1
    fi
  fi
  [ "$claude_ok" = 1 ] && chk "CLAUDE.md enlazado a $CLAUDE_TARGET" 1 || chk "CLAUDE.md enlazado a $CLAUDE_TARGET" 0
fi

echo "== Contenido y config =="
[ -f AGENTS.md ] && chk "AGENTS.md presente" 1 || chk "AGENTS.md presente" 0
grep -q "Vault Map" AGENTS.md 2>/dev/null && chk "Vault Map definido" 1 || chk "Vault Map definido" 0
$PY3 -c "import json;json.load(open('⚙️ Meta/brain-config.json'))" 2>/dev/null && chk "brain-config.json válido" 1 || chk "brain-config.json válido" 0
FL=$(find "⚙️ Meta/Floors" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
[ "$FL" -ge 1 ] && chk "notas de piso ($FL)" 1 || chk "notas de piso ($FL)" 0
[ -f "⚙️ Meta/journal-config.md" ] && chk "journal-config.md presente" 1 || chk "journal-config.md presente" 0

echo "== Propiedad de la instalación =="
[ -f "scripts/lib/python3.sh" ] && chk "scripts/lib/python3.sh presente" 1 || chk "scripts/lib/python3.sh presente" 0
OWNER="scripts/lib/ownership.py"
if [ -f "$OWNER" ]; then
  if $PY3 "$OWNER" ".opencode/brain-vault-install-manifest.json" verify >/dev/null 2>&1; then
    chk "manifiesto de propiedad válido" 1
  else
    chk "manifiesto de propiedad válido" 0
  fi
else
  chk "scripts/lib/ownership.py presente ($OWNER)" 0
fi

echo "== Plugin =="
[ -f .opencode/plugins/brain-vault/index.js ] && chk "plugin instalado" 1 || chk "plugin instalado" 0
if command -v node >/dev/null; then
  node --check .opencode/plugins/brain-vault/index.js 2>/dev/null && chk "plugin sintaxis OK" 1 || chk "plugin sintaxis OK" 0
else
  skip "node no disponible: sintaxis del plugin no verificada"
fi

echo "== Git y entorno =="
[ -d .git ] && chk "repo git inicializado" 1 || chk "repo git inicializado" 0
command -v opencode >/dev/null && chk "opencode CLI presente" 1 || chk "opencode CLI presente" 0
command -v git >/dev/null && chk "git presente" 1 || chk "git presente" 0
# PY3 puede ser "py -3": la expansión sin comillas es intencional (dos palabras).
# shellcheck disable=SC2086
if $PY3 -c 'import sys' 2>/dev/null; then
  chk "python presente ($PY3)" 1
else
  chk "python presente ($PY3)" 0
fi

echo
echo "Resultado: $PASS ok, $FAIL fallos"
if [ "$FAIL" -eq 0 ]; then
  echo "Sistema sano."
  exit 0
fi
echo "Revisa los ✗ arriba." >&2
exit 1
