#!/usr/bin/env bash
# Mantenimiento diario: índice del diario + snapshot git de lo nuevo.
set -euo pipefail
LIB="$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
[ -f "$LIB" ] || { echo "falta scripts/lib/common.sh; re-ejecuta install.sh sobre este vault" >&2; exit 1; }
# shellcheck source=/dev/null
. "$LIB"
job_init maintenance

if [ -f "⚙️ Meta/scripts/build-journal-index.py" ]; then
  run_python "⚙️ Meta/scripts/build-journal-index.py" --vault-root . >> "$LOG" 2>&1 || job_fail "falló build-journal-index"
else
  job_log "build-journal-index.py ausente; omitido"
fi

if [ ! -d ".git" ]; then
  job_log "sin repositorio git; omitido snapshot"
  exit 0
fi

# Qué se confirma lo decide snapshot_paths en brain-config.json.
SNAPSHOT="$(brain_config "$CFG" list snapshot_paths 2>> "$LOG")" || job_fail "no se pudo leer snapshot_paths"
paths=()
while IFS= read -r p; do
  if [ -n "$p" ] && [ -e "$p" ]; then paths+=("$p"); fi
done <<EOF
$SNAPSHOT
EOF
[ "${#paths[@]}" -gt 0 ] || exit 0

git add -- "${paths[@]}" >> "$LOG" 2>&1 || job_fail "falló git add"
# El pathspec limita el commit a estas rutas: lo que el usuario tenga en el
# index por su cuenta no entra en el snapshot.
if ! git diff --cached --quiet -- "${paths[@]}" 2>/dev/null; then
  git commit -q -m "chore: snapshot diario del vault" -- "${paths[@]}" >> "$LOG" 2>&1 || job_fail "falló git commit"
  job_log "snapshot"
fi
