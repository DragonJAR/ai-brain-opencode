#!/usr/bin/env bash
# Actualiza el starter y humanizer (ff-only), regenera los pisos y re-cablea.
set -euo pipefail
LIB="$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
[ -f "$LIB" ] || { echo "falta scripts/lib/common.sh; re-ejecuta install.sh sobre este vault" >&2; exit 1; }
# shellcheck source=/dev/null
. "$LIB"
job_init update
R="$VAULT/.opencode/skills/ai-brain-starter"
H="$VAULT/.opencode/skills/humanizer"

# Un clon fijado a un SHA (BRAIN_STARTER_PIN) queda con HEAD suelto: se respeta.
pull_clone() {
  local name="$1" path="$2"
  if [ ! -d "$path/.git" ]; then
    job_log "$name no es repo git; omitido pull"
  elif ! git -C "$path" symbolic-ref -q HEAD >/dev/null 2>&1; then
    job_log "$name fijado a un commit (HEAD suelto); omitido pull"
  else
    git -C "$path" pull --ff-only >> "$LOG" 2>&1 || job_log "pull $name falló"
  fi
}
pull_clone starter "$R"
pull_clone humanizer "$H"

if [ -f "$R/scripts/generate_floor_stubs.py" ]; then
  run_python "$R/scripts/generate_floor_stubs.py" >> "$LOG" 2>&1 || job_fail "falló generate_floor_stubs"
  if [ -d "$R/floors" ]; then
    copied="$(copy_new_floors "$R/floors" "$VAULT/⚙️ Meta/Floors" 2>> "$LOG")" || job_fail "falló copia de notas de piso"
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
