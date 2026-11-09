#!/usr/bin/env bash
# uninstall.sh — quita lo que instaló el paquete. NO toca tu contenido.
#   bash uninstall.sh <ruta-del-vault> [--purge-clones]
set -euo pipefail
VAULT="${1:-}"; PURGE=0
[ "${2:-}" = "--purge-clones" ] && PURGE=1
[ -n "$VAULT" ] || { echo "uso: bash uninstall.sh <ruta-del-vault> [--purge-clones]" >&2; exit 1; }
VAULT="$(cd "$VAULT" && pwd)"
cd "$VAULT" || { echo "no existe el vault: $VAULT" >&2; exit 1; }
SLUG="$(basename "$VAULT" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"; SLUG="${SLUG:-cerebro}"
PREFIX="com.ai-brain.$SLUG"
say() { printf '  %s\n' "$*"; }

echo "== Quitando trabajos programados =="
if [ "$(uname -s)" = "Darwin" ]; then
  for j in journal-reminder insights-weekly daily-maintenance update-brain-weekly; do
    launchctl bootout "gui/$(id -u)/$PREFIX.$j" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/$PREFIX.$j.plist"
  done
  say "launchd: $PREFIX.* desinstalados"
else
  crontab -l 2>/dev/null | grep -v "# ai-brain" | crontab - 2>/dev/null || true
  say "crontab: entradas ai-brain eliminadas"
fi

echo "== Quitando cableado =="
# Glob SIN barra final: en bash "*/" no matchea symlinks a directorio.
for l in .opencode/skills/*; do
  [ -L "$l" ] || continue
  n="$(basename "$l")"
  if rm -f "$l"; then say "symlink de skill eliminado: $n"; else printf '  ! no se pudo eliminar %s\n' "$n"; fi
done
for l in .opencode/commands/*.md; do
  [ -L "$l" ] || continue
  rm -f "$l"
done
say "symlinks de comandos eliminados"
rm -rf .opencode/plugins/brain-vault && say "plugin eliminado"
rm -f scripts/verify.sh scripts/jobs/*.sh && rmdir scripts/jobs 2>/dev/null || true
say "scripts del vault eliminados"

if [ "$PURGE" = 1 ]; then
  rm -rf .opencode/skills/ai-brain-starter .opencode/skills/humanizer
  say "clones vendorizados eliminados (--purge-clones)"
fi

echo "== MCP (opcional) =="
if [ -f "$VAULT/opencode.json" ]; then
  python3 - "$VAULT/opencode.json" <<'PY'
import json, pathlib
p = pathlib.Path(__import__("sys").argv[1])
d = json.loads(p.read_text())
srv = d.get("mcp", {}).get("servers", {})
for n in ("granola", "chatprd"):
    if srv.pop(n, None) is not None:
        print(f"  MCP {n} eliminado")
if not srv:
    d.get("mcp", {}).pop("servers", None)
    if not d.get("mcp"):
        d.pop("mcp", None)
p.write_text(json.dumps(d, indent=2) + "\n")
PY
fi

echo
echo "Hecho. Se conserva TODO tu contenido: notas, diario, personas, decisiones, git."
