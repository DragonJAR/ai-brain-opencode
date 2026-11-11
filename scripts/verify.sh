#!/usr/bin/env bash
# verify.sh — verificación de salud del vault. Se instala en <vault>/scripts/verify.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [ -f "$PACKAGE_ROOT/install.sh" ] \
  && [ -f "$PACKAGE_ROOT/templates/brain-config.example.json" ] \
  && [ -f "$PACKAGE_ROOT/tests/run.sh" ]; then
  echo "== Package checkout: deterministic regression tests =="
  bash "$PACKAGE_ROOT/tests/run.sh"
  exit $?
fi

VAULT="$PACKAGE_ROOT"
cd "$VAULT"
PASS=0; FAIL=0
chk() { if [ "$2" = "1" ]; then printf '  ✓ %s\n' "$1"; PASS=$((PASS+1)); else printf '  ✗ %s\n' "$1"; FAIL=$((FAIL+1)); fi; }
skip() { printf '  ~ %s\n' "$1"; }

echo "== Estructura =="
[ -d ".opencode/skills/ai-brain-starter" ] && chk "starter clonado" 1 || chk "starter clonado" 0
SK=$(find .opencode/skills -maxdepth 1 -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
[ "$SK" -ge 2 ] && chk "skills enlazadas ($SK)" 1 || chk "skills enlazadas ($SK)" 0
CMD=$(find .opencode/commands -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
[ "$CMD" -ge 1 ] && chk "comandos enlazados ($CMD)" 1 || chk "comandos enlazados ($CMD)" 0
BAD=$(find .opencode -xtype l 2>/dev/null | wc -l | tr -d ' ')
[ "$BAD" -eq 0 ] && chk "sin symlinks rotos" 1 || chk "symlinks rotos: $BAD" 0
for d in "📓 Journals" "🏠 Home" "👤 CRM" "📝 Notes" "💼 Business" "🚀 I+D" "⚙️ Meta"; do
  [ -d "$d" ] && chk "carpeta $d" 1 || chk "carpeta $d" 0
done
[ -L CLAUDE.md ] && chk "CLAUDE.md enlazado a AGENTS.md" 1 || chk "CLAUDE.md enlazado a AGENTS.md" 0

echo "== Contenido y config =="
[ -f AGENTS.md ] && chk "AGENTS.md presente" 1 || chk "AGENTS.md presente" 0
grep -q "Vault Map" AGENTS.md 2>/dev/null && chk "Vault Map definido" 1 || chk "Vault Map definido" 0
python3 -c "import json;json.load(open('⚙️ Meta/brain-config.json'))" 2>/dev/null && chk "brain-config.json válido" 1 || chk "brain-config.json válido" 0
FL=$(find "⚙️ Meta/Floors" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
[ "$FL" -ge 1 ] && chk "notas de piso ($FL)" 1 || chk "notas de piso ($FL)" 0
[ -f "⚙️ Meta/journal-config.md" ] && chk "journal-config.md presente" 1 || chk "journal-config.md presente" 0

echo "== Propiedad de la instalación =="
OWNER="scripts/lib/ownership.py"
if [ -f "$OWNER" ]; then
  if python3 "$OWNER" ".opencode/brain-vault-install-manifest.json" verify >/dev/null 2>&1; then
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
command -v python3 >/dev/null && chk "python3 presente" 1 || chk "python3 presente" 0

echo
echo "Resultado: $PASS ok, $FAIL fallos"
if [ "$FAIL" -eq 0 ]; then
  echo "Sistema sano."
  exit 0
fi
echo "Revisa los ✗ arriba." >&2
exit 1
