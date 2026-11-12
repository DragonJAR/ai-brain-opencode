---
description: "Autochequeo del vault en OpenCode: instalación, config, plugin e integridad de las notas"
---

# /diagnose — Autochequeo del vault

Revisa la salud de este vault tal como está instalado en OpenCode. No uses el skill `diagnose` del starter: audita una instalación de Claude Code (`CLAUDE.md`, hooks, `settings.json`) y daría este vault por roto.

## Qué hacer

1. **Instalación**: ejecuta `bash scripts/verify.sh`. Cada `✗` es un fallo real; cada `~` es un aviso (por ejemplo, un archivo del paquete que el usuario modificó).

2. **Contenido**: ejecuta `python3 scripts/audit.py . --json` (en Windows el intérprete puede ser `py -3`). Revisa `broken_links`, `untyped_notes`, `orphan_notes` y `pending_raw`.

3. **Trabajos programados**, solo si existe `⚙️ Meta/logs/`: mira las últimas líneas de cada `⚙️ Meta/logs/<trabajo>.log` y señala los que terminaron con error.

4. **Informe**: una lista corta, de lo más grave a lo menos, con la causa y el arreglo de cada punto:
   - Falta un archivo del paquete o un enlace está roto → repetir `bash install.sh <vault>` desde el checkout del paquete.
   - Un trabajo no encuentra `opencode` o Python → repetir `bash scripts/schedule.sh <vault>` desde un shell que los tenga.
   - `brain-config.json` inválido → corregir el valor que señala `verify.sh`.
   - Enlaces rotos o notas sin tipo → ofrecer corregirlos uno por uno; no los cambies sin confirmación.

Si todo está en orden, dilo en una línea y no inventes mejoras.
