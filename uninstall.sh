#!/usr/bin/env bash
# uninstall.sh — elimina solo los artefactos sin cambios registrados por este paquete.
#   bash uninstall.sh <ruta-del-vault> [--purge-clones] [--dry-run]
#   --purge-clones  además borra los clones vendorizados (ai-brain-starter, humanizer)
#                   cuando siguen apuntando a su origen y no tienen cambios locales
#   --dry-run       muestra lo que se eliminaría sin tocar nada
#   -h, --help      muestra esta ayuda
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$PKG/scripts/lib"
[ -f "$LIB/common.sh" ] && [ -f "$LIB/ownership.py" ] \
  || { printf '  ✗ paquete incompleto: faltan archivos en scripts/lib\n' >&2; exit 1; }
# shellcheck source=scripts/lib/common.sh
. "$LIB/common.sh"
usage() { sed -n '2,/^set -/p' "$0" | sed '$d'; }

VAULT=""
PURGE=0
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --purge-clones) PURGE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -*) die "flag desconocida: $1 (usa --help)" ;;
    *)
      if [ -n "$VAULT" ]; then
        die "argumento inesperado: $1"
      fi
      VAULT="$1"
      shift
      ;;
  esac
done
[ -n "$VAULT" ] || { usage >&2; exit 1; }
[ -d "$VAULT" ] || die "el vault no existe: $VAULT"
pick_python3 || die "falta Python >= 3.9 (python3, py -3 o python)"
VAULT="$(cd "$VAULT" && pwd)"
MANIFEST="$VAULT/$BRAIN_MANIFEST_REL"

for rel in "scripts" "scripts/jobs" ".opencode" ".opencode/skills" ".opencode/plugins"; do
  if [ -L "$VAULT/$rel" ]; then
    die "$rel/ es un symlink; desinstalación rechazada y manifiesto preservado"
  fi
done

# Sin un manifiesto válido nada es demostrable: ni la programación ni los archivos se tocan.
if ! MANIFEST_ERROR="$(run_python "$LIB/ownership.py" "$MANIFEST" check-uninstall "$VAULT" 2>&1)"; then
  die "manifiesto de propiedad ausente o inválido; no se eliminó nada (${MANIFEST_ERROR#fallo: }). Revisa $MANIFEST o borra a mano lo que sepas que instaló el paquete"
fi

if [ "$DRY_RUN" = 1 ]; then
  echo "== Trabajos programados que se eliminarían (dry-run) =="
  bash "$PKG/scripts/schedule.sh" "$VAULT" --remove --dry-run \
    || warn "no se pudo determinar qué trabajos programados se eliminarían"
else
  echo "== Eliminando trabajos programados verificados =="
  bash "$PKG/scripts/schedule.sh" "$VAULT" --remove || {
    die "falló la limpieza de la programación; se preservaron los artefactos restantes"
  }
fi

echo "== Eliminando artefactos del paquete sin cambios =="
# La lista de rutas gestionadas y las comprobaciones viven en ownership.py.
run_python "$LIB/ownership.py" "$MANIFEST" uninstall "$VAULT" "$PURGE" "$DRY_RUN" \
  || die "desinstalación incompleta; revisa los ✗ de arriba. El manifiesto de propiedad se preservó"

echo
echo "Listo. El contenido sin propiedad, modificado o ambiguo se preservó."
