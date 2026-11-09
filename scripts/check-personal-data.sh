#!/usr/bin/env bash
# check-personal-data.sh — verifica que el paquete no lleve datos del operador.
#
# 1) Chequeo estructural (siempre): rutas home absolutas, correos, tokens, nombres de archivo típicos.
# 2) Chequeo de nombres propios: lee una lista local `.personal-terms.txt` (NO se distribuye; está en
#    .gitignore). Si no existe, se avisa y se omite ese chequeo.
#
# Uso: bash scripts/check-personal-data.sh [directorio]
set -uo pipefail
PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -n "${1:-}" ] && PKG="$1"
BAD=0

echo "== Chequeo estructural =="
STRUCT=$(grep -rnE "/Users/[A-Za-z0-9._-]+|/(home|Users)/[a-z0-9._-]+/|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}" "$PKG" --exclude-dir=.git --exclude=check-personal-data.sh 2>/dev/null | grep -v "$PKG/" || true)
if [ -z "$STRUCT" ]; then echo "  ✓ sin rutas personales, correos ni tokens"; else echo "  ✗ filtraciones:"; echo "$STRUCT" | head -20; BAD=1; fi

echo "== Chequeo de nombres propios =="
TERMS_FILE="$PKG/.personal-terms.txt"
if [ -f "$TERMS_FILE" ]; then
  HITS=$(grep -rniE -f "$TERMS_FILE" "$PKG" --exclude-dir=.git --exclude=check-personal-data.sh --exclude=.personal-terms.txt --exclude=LICENSE 2>/dev/null || true)
  if [ -z "$HITS" ]; then echo "  ✓ sin coincidencias con la lista local"; else echo "  ✗ coincidencias:"; echo "$HITS" | head -20; BAD=1; fi
else
  echo "  ~ lista local .personal-terms.txt ausente — este chequeo se omitió"
  echo "    (crea ese archivo con los términos a filtrar y vuelve a correr; no se distribuye)"
fi

echo "== Atribución esperada =="
echo "  (las URLs del upstream y la línea de copyright del autor son correctas y no son datos del operador)"

[ "$BAD" -eq 0 ] && { echo; echo "✓ Paquete limpio"; exit 0; } || { echo; echo "✗ Revisa lo anterior"; exit 1; }
