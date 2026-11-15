#!/usr/bin/env bash
# Deja el starter y humanizer en los commits que fija el paquete instalado,
# regenera los pisos y re-cablea. No descarga versiones nuevas por su cuenta:
# el paquete y los commits del vendor solo cambian con
# `bash install.sh --update <vault>`, desde el repositorio oficial del paquete.
set -euo pipefail
LIB="$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
[ -f "$LIB" ] || { echo "falta scripts/lib/common.sh; re-ejecuta install.sh sobre este vault" >&2; exit 1; }
# shellcheck source=/dev/null
. "$LIB"
job_init
R="$VAULT/.opencode/skills/ai-brain-starter"

while IFS=$'\t' read -r rel url commit; do
  [ -n "$rel" ] || continue
  rc=0
  sync_vendor_clone "$VAULT/$rel" "$url" "$commit" || rc=$?
  case "$rc" in
    0) job_log "$rel en el commit fijado por el paquete (${commit:0:8})" ;;
    3) job_log "$rel no es un clon de $url; no se toca" ;;
    *) job_log "$rel: no se pudo activar el commit fijado ${commit:0:8} (¿sin red o con cambios locales?)" ;;
  esac
done <<EOF
$(vendor_lock)
EOF

if [ -f "$R/scripts/generate_floor_stubs.py" ]; then
  run_python "$R/scripts/generate_floor_stubs.py" >> "$LOG" 2>&1 || job_fail "falló generate_floor_stubs"
  if [ -d "$R/floors" ]; then
    copied="$(copy_new_floors "$R/floors" "$VAULT/$BRAIN_FLOORS_REL" 2>> "$LOG")" || job_fail "falló copia de notas de piso"
    job_log "pisos: ${copied} nuevos; los existentes se preservan"
  else
    job_log "directorio floors ausente en starter; omitida copia"
  fi
else
  job_log "generate_floor_stubs.py ausente; omitido"
fi

# Lo que el starter agregó o retiró se cablea igual que en la instalación.
if [ -f "$VAULT/$BRAIN_MANIFEST_REL" ] && [ -f "$R/SKILL.md" ]; then
  WIRE_MODE="link"
  if is_windows; then WIRE_MODE="copy"; fi
  run_python "$BRAIN_LIB_DIR/wire.py" "$VAULT" --mode "$WIRE_MODE" >> "$LOG" 2>&1 || job_fail "falló el re-cableado del starter"
else
  job_log "sin manifiesto de propiedad o sin starter; omitido re-cableado"
fi
