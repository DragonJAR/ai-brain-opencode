#!/usr/bin/env bash
# check-personal-data.sh — el paquete no debe llevar datos del operador.
#
# 1) Estructural (siempre): rutas home absolutas, correos, tokens.
# 2) Nombres propios: lista local en una de estas rutas (nunca dentro del paquete):
#      $BRAIN_PERSONAL_TERMS  |  ~/.config/ai-brain/personal-terms.txt
set -uo pipefail
PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -n "${1:-}" ] && PKG="$1"
BAD=0

echo "== Chequeo estructural =="
STRUCT=$(cd "$PKG" && grep -rnE "/Users/[A-Za-z0-9._-]+|/(home|Users)/[a-z0-9._-]+/|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}" . --exclude-dir=.git --exclude-dir=.codegraph --exclude-dir=node_modules --exclude=check-personal-data.sh 2>/dev/null || true)
if [ -z "$STRUCT" ]; then echo "  ✓ sin rutas personales, correos ni tokens"; else echo "  ✗ filtraciones:"; echo "$STRUCT" | head -20; BAD=1; fi

echo "== Chequeo de nombres propios =="
TERMS_FILE="${BRAIN_PERSONAL_TERMS:-$HOME/.config/ai-brain/personal-terms.txt}"
if [ -f "$TERMS_FILE" ]; then
  HITS=$(cd "$PKG" && grep -rniE -f "$TERMS_FILE" . --exclude-dir=.git --exclude-dir=.codegraph --exclude-dir=node_modules --exclude=check-personal-data.sh --exclude=LICENSE 2>/dev/null | grep -viE "mycelium-hq/ai-brain-starter|humanizer" || true)  # LICENSE se excluye: atribución del autor, no dato del operador
  if [ -z "$HITS" ]; then echo "  ✓ sin coincidencias ($TERMS_FILE)"; else echo "  ✗ coincidencias:"; echo "$HITS" | head -20; BAD=1; fi
else
  echo "  ~ sin lista de términos ($TERMS_FILE) — chequeo de nombres omitido"
fi

[ "$BAD" -eq 0 ] && { echo; echo "✓ Paquete limpio"; exit 0; } || { echo; echo "✗ Revisa lo anterior"; exit 1; }
