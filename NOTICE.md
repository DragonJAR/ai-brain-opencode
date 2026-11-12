# Avisos de terceros

Este paquete **no incluye código de terceros**: los descarga en la instalación. Sus licencias se aplican a lo que
termina en tu vault.

| Componente | Origen | Licencia | Papel |
|---|---|---|---|
| ai-brain-starter | https://github.com/mycelium-hq/ai-brain-starter | MIT | Sustelo del sistema: vault, skills, comandos, plantillas, scripts del diario |
| humanizer | https://github.com/adelaidasofia/humanizer | MIT | Skill de humanización de prosa (regla "humaniza lo que va hacia fuera") |
| High-Rise framework | https://github.com/Fundacion-Lontananza/high-rise | MIT | Modelo de pisos emocionales (34 pisos + índices de nivel y serie); lo consume el vendor (las notas de piso se generan desde su copia fijada) |

## Complementos de Obsidian (opcionales, `--with-obsidian`)

Cada complemento conserva su propia licencia; consulta el repositorio de cada uno:

| Complemento | Repositorio |
|---|---|
| Dataview | https://github.com/blacksmithgu/obsidian-dataview |
| Templater | https://github.com/SilentVoid13/Templater |
| Tasks | https://github.com/obsidian-tasks-group/obsidian-tasks |
| Local REST API | https://github.com/coddingtonbear/obsidian-local-rest-api |
| Custom Sort | https://github.com/SebastianMC/obsidian-custom-sort |

## Servicios remotos (opcionales, `--with-mcp`)

`granola` (mcp.granola.ai) y `chatprd` (app.chatprd.ai) son servicios de terceros: reciben la conversación de
la sesión **cuando los usas**. Son opt-in explícito y requieren autenticación por OAuth desde `/mcps` en OpenCode.

## Adaptación OpenCode

El puerto a OpenCode (plugin de hooks, scheduler multiplataforma con launchd/cron/schtasks, y la
compatibilidad Claude Code → OpenCode) está documentado en `docs/COMPAT.md` y implementado en el código de
este paquete (`plugin/` y `scripts/`).
