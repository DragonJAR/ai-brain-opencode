#!/usr/bin/env bash
# verify.sh — verificación de salud del vault. Se instala en <vault>/scripts/verify.sh
set -uo pipefail
VAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$VAULT"
PASS=0; FAIL=0
chk() { if [ "$2" = "1" ]; then printf '  ✓ %s\n' "$1"; PASS=$((PASS+1)); else printf '  ✗ %s\n' "$1"; FAIL=$((FAIL+1)); fi; }

echo "== Estructura =="
[ -d ".opencode/skills/ai-brain-starter" ] && chk "starter clonado" 1 || chk "starter clonado" 0
SK=$(find .opencode/skills -maxdepth 1 -mindepth 1 2>/dev/null | wc -l | tr -d ' ')
[ "$SK" -ge 20 ] && chk "skills enlazadas ($SK)" 1 || chk "skills enlazadas ($SK)" 0
CMD=$(find .opencode/commands -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
[ "$CMD" -ge 10 ] && chk "comandos enlazados ($CMD)" 1 || chk "comandos enlazados ($CMD)" 0
BAD=$(find .opencode -xtype l 2>/dev/null | wc -l | tr -d ' ')
[ "$BAD" -eq 0 ] && chk "sin symlinks rotos" 1 || chk "symlinks rotos: $BAD" 0
for d in "📓 Journals" "🏠 Home" "👤 CRM" "📝 Notes" "💼 Business" "🚀 I+D" "⚙️ Meta"; do
  [ -d "$d" ] && chk "carpeta $d" 1 || chk "carpeta $d" 0
done

echo "== Contenido y config =="
[ -f AGENTS.md ] && chk "AGENTS.md presente" 1 || chk "AGENTS.md presente" 0
grep -q "Vault Map" AGENTS.md 2>/dev/null && chk "Vault Map definido" 1 || chk "Vault Map definido" 0
python3 -c "import json;json.load(open('⚙️ Meta/brain-config.json'))" 2>/dev/null && chk "brain-config.json válido" 1 || chk "brain-config.json válido" 0
FL=$(ls -1 "⚙️ Meta/Floors" 2>/dev/null | wc -l | tr -d ' ')
[ "$FL" -ge 30 ] && chk "pisos emocionales ($FL)" 1 || chk "pisos emocionales ($FL)" 0
[ -f "⚙️ Meta/journal-config.md" ] && chk "journal-config.md presente" 1 || chk "journal-config.md presente" 0

echo "== Plugin =="
[ -f .opencode/plugins/brain-vault/index.js ] && chk "plugin instalado" 1 || chk "plugin instalado" 0
command -v node >/dev/null && { node --check .opencode/plugins/brain-vault/index.js 2>/dev/null && chk "plugin sintaxis OK" 1 || chk "plugin sintaxis OK" 0; }

echo "== Git y entorno =="
[ -d .git ] && chk "repo git inicializado" 1 || chk "repo git inicializado" 0
command -v opencode >/dev/null && chk "opencode CLI presente" 1 || chk "opencode CLI presente" 0
command -v git >/dev/null && chk "git presente" 1 || chk "git presente" 0
command -v python3 >/dev/null && chk "python3 presente" 1 || chk "python3 presente" 0

echo
echo "Resultado: $PASS ok, $FAIL fallos"
[ "$FAIL" -eq 0 ] && echo "Sistema sano." || echo "Revisa los ✗ arriba."
