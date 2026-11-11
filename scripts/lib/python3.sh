#!/usr/bin/env bash
# Fuente única del intérprete Python para install, schedule, verify y los jobs.
# El llamador hace: . scripts/lib/python3.sh && pick_python3
# PY3 puede ser "python3", "python" o "py -3". Se expande sin comillas: $PY3 script.py

# require_python3: fija PY3 o falla ruidosamente (lo usan los trabajos programados).
require_python3() {
  if ! pick_python3; then
    echo "no se encontró un intérprete de Python 3 válido (python3, py -3, python)" >&2
    return 1
  fi
}

pick_python3() {
  PY3=""
  if command -v python3 >/dev/null 2>&1 \
    && python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
    PY3="python3"
  elif command -v py >/dev/null 2>&1 \
    && py -3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
    PY3="py -3"
  elif command -v python >/dev/null 2>&1 \
    && python -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
    PY3="python"
  else
    return 1
  fi
  export PY3
  return 0
}
