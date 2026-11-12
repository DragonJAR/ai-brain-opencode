#!/usr/bin/env bash
# check-personal-data.sh — el paquete no debe llevar datos del operador.
#
# 1) Estructural (siempre): rutas home absolutas, correos, tokens.
# 2) Nombres propios: lista local en una de estas rutas (nunca dentro del paquete):
#      $BRAIN_PERSONAL_TERMS  |  ~/.config/ai-brain/personal-terms.txt
#
# grep devuelve 0 si hay coincidencias, 1 si no hay, y >=2 si no pudo correr.
# Un código >=2 es un error: el paquete no se declara limpio.
#
# No se escanean directorios que no se distribuyen: .atl/, odd/, __pycache__/.
# Los correos de ejemplo (example.com/org/net y *.invalid) no son datos del operador.
# La atribución publicada de README.md y README.es.md no entra en los nombres propios.
# Los binarios se leen como texto (grep -a): un correo dentro de un PNG también es una fuga.
set -uo pipefail
PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -n "${1:-}" ] && PKG="$1"
BAD=0
STRUCT_RE="/(home|Users)/[A-Za-z0-9._-]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}"

# Lo que no se distribuye o es el propio detector: una sola lista para los tres chequeos.
EXCLUDES=(--exclude-dir=.git --exclude-dir=.codegraph --exclude-dir=node_modules
          --exclude-dir=.atl --exclude-dir=odd --exclude-dir=__pycache__
          --exclude=check-personal-data.sh)

die() { printf '  ✗ %s\n' "$*" >&2; exit 1; }
[ -d "$PKG" ] || die "no existe el directorio a revisar: $PKG"

# Corre grep dentro de $PKG. El stderr solo se muestra si el código es >= 2.
grep_in_pkg() {
  local err rc
  err="$(mktemp "${TMPDIR:-/tmp}/ai-brain-grep.XXXXXX")" || return 2
  if ! cd "$PKG"; then
    rm -f "$err"
    printf '  ✗ no se puede entrar a %s\n' "$PKG" >&2
    return 2
  fi
  # Bash no guarda bytes NUL en variables: se quitan aquí, no en cada llamador.
  grep -a "$@" 2>"$err" | tr -d '\000'
  rc=${PIPESTATUS[0]}
  if [ "$rc" -ge 2 ]; then
    cat "$err" >&2
  fi
  rm -f "$err"
  return "$rc"
}

# Quita correos reservados y vuelve a aplicar el patrón estructural.
# example.com, example.org, example.net (y subdominios) y *.invalid no son fugas.
keep_structural() {
  local line scrubbed
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    scrubbed="$(printf '%s\n' "$line" | sed -E \
      -e 's/[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+\.)*example\.(com|org|net)//g' \
      -e 's/[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+\.)*[A-Za-z0-9-]+\.invalid//g')"
    if printf '%s\n' "$scrubbed" | grep -qE "$STRUCT_RE"; then
      printf '%s\n' "$line"
    fi
  done
}

# La atribución del README (badge, clone publicado y crédito) es intencional.
readme_attribution() {
  case "$1" in
    ./README.md:*|./README.es.md:*|README.md:*|README.es.md:*) ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$1" | grep -qE 'badge/author-|github\.com/DragonJAR/ai-brain-opencode|cd ai-brain-opencode|dragonjar\.org'
}

echo "== Chequeo estructural =="
STRUCT="$(grep_in_pkg -rnE "$STRUCT_RE" . \
"${EXCLUDES[@]}")"
rc=$?
if [ "$rc" -ge 2 ]; then
  die "el chequeo estructural no pudo correr (grep salió $rc)"
fi
if [ "$rc" -eq 0 ]; then
  STRUCT="$(printf '%s\n' "$STRUCT" | keep_structural)"
fi
if [ -z "$STRUCT" ]; then
  echo "  ✓ sin rutas personales, correos ni tokens"
else
  echo "  ✗ filtraciones:"
  printf '%s\n' "$STRUCT" | head -20
  BAD=1
fi

echo "== Marcadores prohibidos =="
# Este paquete es independiente: no debe referenciar el repositorio del vault privado.
# El patrón usa [C] para que el propio detector no contenga el literal que prohíbe.
FORBIDDEN_RE='Segundo[C]erebro|Segundo[ ]Cerebro'
FORBIDDEN="$(grep_in_pkg -rnE "$FORBIDDEN_RE" . \
"${EXCLUDES[@]}")"
rc=$?
if [ "$rc" -ge 2 ]; then
  die "el chequeo de marcadores no pudo correr (grep salió $rc)"
fi
if [ -z "$FORBIDDEN" ]; then
  echo "  ✓ sin referencias a proyectos ajenos"
else
  echo "  ✗ referencias prohibidas:"
  printf '%s\n' "$FORBIDDEN" | head -20
  BAD=1
fi

# Las URL de los clones del vendor nombran a sus autores: es atribución, no un dato del operador.
VENDOR_URL_RE='(https?://)?github\.com/(mycelium-hq/ai-brain-starter|adelaidasofia/humanizer)(\.git)?'

echo "== Chequeo de nombres propios =="
TERMS_FILE="${BRAIN_PERSONAL_TERMS:-$HOME/.config/ai-brain/personal-terms.txt}"
TERMS=""
if [ -s "$TERMS_FILE" ]; then
  # Sin CR, líneas vacías ni comentarios: una línea vacía como patrón coincide con todo.
  TERMS="$(mktemp "${TMPDIR:-/tmp}/ai-brain-terms.XXXXXX")" || die "no se pudo crear un temporal"
  trap 'rm -f "$TERMS"' EXIT
  tr -d '\r' < "$TERMS_FILE" | grep -vE '^[[:space:]]*(#|$)' > "$TERMS" || true
fi
if [ -n "$TERMS" ] && [ -s "$TERMS" ]; then
  # LICENSE se excluye: atribución del autor, no dato del operador.
  # odd/ y .atl/ no son archivos de producto.
  RAW="$(grep_in_pkg -rniE -f "$TERMS" . \
"${EXCLUDES[@]}" --exclude=LICENSE)"
  rc=$?
  if [ "$rc" -ge 2 ]; then
    die "el chequeo de nombres no pudo correr (grep salió $rc)"
  fi
  HITS=""
  if [ "$rc" -eq 0 ]; then
    KEPT=""
    raw_file="$(mktemp "${TMPDIR:-/tmp}/ai-brain-names.XXXXXX")" || die "no se pudo crear un temporal"
    printf '%s\n' "$RAW" > "$raw_file"
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      printf '%s\n' "$line" | sed -E "s#$VENDOR_URL_RE##g" | grep -qiE -f "$TERMS" || continue
      readme_attribution "$line" && continue
      KEPT="${KEPT}${line}"$'\n'
    done < "$raw_file"
    rm -f "$raw_file"
    HITS="$KEPT"
  fi
  if [ -z "$HITS" ]; then
    echo "  ✓ sin coincidencias ($TERMS_FILE)"
  else
    echo "  ✗ coincidencias:"
    printf '%s\n' "$HITS" | head -20
    BAD=1
  fi
else
  echo "  ~ sin lista de términos ($TERMS_FILE) — chequeo de nombres omitido"
fi

[ "$BAD" -eq 0 ] && { echo; echo "✓ Paquete limpio"; exit 0; } || { echo; echo "✗ Revisa lo anterior"; exit 1; }
