#!/usr/bin/env bash
# Actualiza el starter y humanizer (ff-only) y regenera los pisos.
set -euo pipefail
VAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$VAULT"
mkdir -p "$VAULT/⚙️ Meta/logs"
LOG="$VAULT/⚙️ Meta/logs/update.log"
R="$VAULT/.opencode/skills/ai-brain-starter"
H="$VAULT/.opencode/skills/humanizer"

if [ -f "$VAULT/scripts/lib/python3.sh" ]; then
  # shellcheck source=/dev/null
  . "$VAULT/scripts/lib/python3.sh"
  require_python3 || { echo "$(date '+%F %T') sin Python 3 válido (python3, py -3, python)" >> "$LOG"; exit 1; }
else
  PY3="python3"   # vault instalado antes de que existiera la lib
fi

if [ -d "$R/.git" ]; then
  git -C "$R" pull --ff-only >> "$LOG" 2>&1 || echo "$(date '+%F %T') pull starter falló" >> "$LOG"
else
  echo "$(date '+%F %T') starter no es repo git; omitido pull" >> "$LOG"
fi

if [ -d "$H/.git" ]; then
  git -C "$H" pull --ff-only >> "$LOG" 2>&1 || echo "$(date '+%F %T') pull humanizer falló" >> "$LOG"
else
  echo "$(date '+%F %T') humanizer no es repo git; omitido pull" >> "$LOG"
fi

if [ -f "$R/scripts/generate_floor_stubs.py" ]; then
  if ! $PY3 "$R/scripts/generate_floor_stubs.py" >> "$LOG" 2>&1; then
    echo "$(date '+%F %T') falló generate_floor_stubs" >> "$LOG"
    echo "falló generate_floor_stubs" >&2
    exit 1
  fi
  if [ -d "$R/floors" ]; then
    mkdir -p "$VAULT/⚙️ Meta/Floors"
    shopt -s nullglob
    floor_files=("$R/floors/"*.md)
    shopt -u nullglob
    # Copia explícita solo de los nuevos: el estado de salida de cp -n no es
    # portable entre versiones de coreutils y las notas del usuario se preservan.
    copied=0
    preserved=0
    for floor in "${floor_files[@]}"; do
      dest="$VAULT/⚙️ Meta/Floors/${floor##*/}"
      if [ -e "$dest" ]; then
        preserved=$((preserved + 1))
        continue
      fi
      if cp "$floor" "$dest" >> "$LOG" 2>&1; then
        copied=$((copied + 1))
      else
        echo "$(date '+%F %T') falló copia de ${floor##*/}" >> "$LOG"
        echo "falló copia de ${floor##*/}" >&2
        exit 1
      fi
    done
    echo "$(date '+%F %T') pisos: ${copied} nuevos, ${preserved} preservados" >> "$LOG"
  else
    echo "$(date '+%F %T') directorio floors ausente en starter; omitida copia" >> "$LOG"
  fi
else
  echo "$(date '+%F %T') generate_floor_stubs.py ausente; omitido" >> "$LOG"
fi
