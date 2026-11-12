#!/usr/bin/env bash
# verify.sh — verificación de salud del vault. Se instala en <vault>/scripts/verify.sh
#   bash scripts/verify.sh      revisa el vault que lo contiene (en el paquete: corre las pruebas)
#   -h, --help                  muestra esta ayuda
set -uo pipefail
unset CDPATH
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Sin bibliotecas (vault dañado) la verificación igual corre y reporta lo que falta.
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
  # shellcheck source=lib/common.sh
  . "$SCRIPT_DIR/lib/common.sh"
elif [ -f "$SCRIPT_DIR/lib/python3.sh" ]; then
  # shellcheck source=lib/python3.sh
  . "$SCRIPT_DIR/lib/python3.sh"
fi
if [ $# -gt 0 ]; then
  command -v usage_error >/dev/null \
    || { printf '  ✗ falta scripts/lib/common.sh; re-ejecuta install.sh --wire sobre este vault\n' >&2; exit 1; }
  case "$1" in
    --help|-h) usage; exit 0 ;;
    -*) usage_error "flag desconocida: $1" ;;
    *) usage_error "argumento inesperado: $1" ;;
  esac
fi
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
if command -v pick_python3 >/dev/null; then pick_python3 || PY3="python3"; fi
OS="$(uname -s)"
WIN=0
case "$OS" in
  MINGW*|MSYS*|CYGWIN*) WIN=1 ;;
esac
PASS=0; FAIL=0
chk() { if [ "$2" = "1" ]; then printf '  ✓ %s\n' "$1"; PASS=$((PASS+1)); else printf '  ✗ %s\n' "$1"; FAIL=$((FAIL+1)); fi; }
skip() { printf '  ~ %s\n' "$1"; }
# check <etiqueta> <comando...>: ✓ si el comando sale con 0.
check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then chk "$label" 1; else chk "$label" 0; fi
}

# wired_count <dir del starter> <dir del vault> <d|f>: entradas del starter cableadas en
# el vault (symlink en POSIX, copia en Windows). Los comandos del paquete y los clones
# del vendor (ai-brain-starter, humanizer) no cuentan como cableado.
wired_count() {
  local src="$1" dst="$2" kind="$3" entry name count=0
  for entry in "$src"/*; do
    name="${entry##*/}"
    if [ "$kind" = d ]; then
      [ -d "$entry" ] || continue
      case "$name" in ai-brain-starter|humanizer) continue ;; esac
    else
      [ -f "$entry" ] || continue
      case "$name" in *.md) ;; *) continue ;; esac
    fi
    if [ "$WIN" = 1 ]; then
      if [ -e "$dst/$name" ] && [ ! -L "$dst/$name" ]; then count=$((count + 1)); fi
    elif [ -L "$dst/$name" ]; then
      count=$((count + 1))
    fi
  done
  printf '%s' "$count"
}

echo "== Estructura =="
starter=".opencode/skills/ai-brain-starter"
if [ -d "$starter" ] && [ ! -L "$starter" ] && [ -f "$starter/SKILL.md" ]; then
  chk "starter clonado" 1
else
  chk "starter clonado" 0
fi
WIRED_LABEL="enlazad"
if [ "$WIN" = 1 ]; then WIRED_LABEL="copiad"; fi
SK="$(wired_count "$starter/skills" .opencode/skills d)"
check "skills ${WIRED_LABEL}as ($SK)" [ "$SK" -ge 1 ]
CMD="$(wired_count "$starter/commands" .opencode/commands f)"
check "comandos ${WIRED_LABEL}os ($CMD)" [ "$CMD" -ge 1 ]
# `find -xtype` es solo de GNU: en macOS fallaba en silencio y este chequeo pasaba siempre.
BAD=$(find .opencode "⚙️ Meta/scripts" CLAUDE.md -type l ! -exec test -e {} \; -print 2>/dev/null | wc -l | tr -d ' ')
if [ "$BAD" -eq 0 ]; then chk "sin symlinks rotos" 1; else chk "symlinks rotos: $BAD" 0; fi
ROOTS=()
# shellcheck disable=SC2086  # PY3 puede ser "py -3"
if [ -f scripts/lib/vault_layout.py ]; then
  while IFS= read -r d; do ROOTS+=("$d"); done < <($PY3 scripts/lib/vault_layout.py roots 2>/dev/null | tr -d '\r')
fi
check "lista de carpetas del vault (scripts/lib/vault_layout.py)" [ "${#ROOTS[@]}" -gt 0 ]
for d in ${ROOTS[@]+"${ROOTS[@]}"}; do
  check "carpeta $d" [ -d "$d" ]
done
CLAUDE_TARGET="AGENTS.md"
claude_ok=0
if [ "$WIN" = 1 ]; then
  if [ -f CLAUDE.md ] && [ ! -L CLAUDE.md ] && [ -f "$CLAUDE_TARGET" ] && cmp -s CLAUDE.md "$CLAUDE_TARGET"; then
    claude_ok=1
  fi
  check "CLAUDE.md copia de $CLAUDE_TARGET" [ "$claude_ok" = 1 ]
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
  check "CLAUDE.md enlazado a $CLAUDE_TARGET" [ "$claude_ok" = 1 ]
fi

echo "== Contenido y config =="
check "AGENTS.md presente" [ -f AGENTS.md ]
check "Vault Map definido" grep -q "Vault Map" AGENTS.md
# shellcheck disable=SC2086  # PY3 puede ser "py -3"
if [ -f "scripts/lib/brain_config.py" ] && CONFIG_NOTES="$($PY3 scripts/lib/brain_config.py "⚙️ Meta/brain-config.json" validate 2>&1)"; then
  chk "brain-config.json válido" 1
  # Un valor con forma inválida no rompe nada (se usa el valor por defecto), pero conviene verlo.
  if [ -n "$CONFIG_NOTES" ]; then printf '%s\n' "$CONFIG_NOTES" | sed 's/^  ! /  ~ /'; fi
else
  chk "brain-config.json válido" 0
fi
FL=$(find "⚙️ Meta/Floors" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
check "notas de piso ($FL)" [ "$FL" -ge 1 ]
check "journal-config.md presente" [ -f "⚙️ Meta/journal-config.md" ]

echo "== Propiedad de la instalación =="
for lib in python3.sh common.sh ownership.py wire.py brain_config.py vault_layout.py brain-config.defaults.json; do
  check "scripts/lib/$lib presente" [ -f "scripts/lib/$lib" ]
done
OWNER="scripts/lib/ownership.py"
MANIFEST=".opencode/brain-vault-install-manifest.json"
# shellcheck disable=SC2086
if [ -f "$OWNER" ] && $PY3 "$OWNER" "$MANIFEST" verify >/dev/null 2>&1; then
  chk "manifiesto de propiedad válido" 1
  # Deriva entre el manifiesto y el disco. Lo que falta es un fallo; lo que el
  # usuario modificó es suyo y solo se informa (la desinstalación lo preservará).
  DRIFT="$($PY3 "$OWNER" "$MANIFEST" drift "$VAULT" 2>/dev/null)"
  MISSING="$(printf '%s\n' "$DRIFT" | grep -c '^missing ' || true)"
  if [ "$MISSING" -eq 0 ]; then chk "artefactos registrados presentes" 1; else chk "artefactos registrados ausentes: $MISSING" 0; fi
  printf '%s\n' "$DRIFT" | sed -n 's/^missing /  ✗ falta: /p; s/^modified /  ~ modificado por ti: /p'
else
  chk "manifiesto de propiedad válido" 0
fi

echo "== Plugin =="
check "plugin instalado" [ -f .opencode/plugins/brain-vault/index.js ]
if command -v node >/dev/null; then
  check "plugin sintaxis OK" node --check .opencode/plugins/brain-vault/index.js
else
  skip "node no disponible: sintaxis del plugin no verificada"
fi

echo "== Git y entorno =="
check "repo git inicializado" [ -d .git ]
check "opencode CLI presente" command -v opencode
check "git presente" command -v git
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
