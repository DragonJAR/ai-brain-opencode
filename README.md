# ai-brain-opencode

Cerebro personal sobre **[ai-brain-starter](https://github.com/mycelium-hq/ai-brain-starter)**, adaptado a
**OpenCode V2** en lugar de Claude Code. Un instalador, cero datos personales en el paquete.

Tu vault es una carpeta de markdown en tu disco. La IA la lee, escribe en ella y recuerda lo que escribiste.
No hay base de datos, ni nube obligatoria, ni licencia por puesto.

---

## Requisitos

| Necesario | Para qué |
|---|---|
| [OpenCode](https://opencode.ai/docs) con un modelo configurado | el runtime (la IA que lee tu vault) |
| Git | clonar el starter y el skill humanizer |
| Python 3.10+ | scripts del diario (índice, preflight) |
| Node 18+ | OpenCode y el plugin |
| macOS o Linux | el scheduler usa launchd (macOS) o cron (Linux) |
| Obsidian (opcional) | ver el vault con notas enlazadas y Dataview |

## Instalación

```bash
clona o copia este paquete donde quieras tenerlo, por ejemplo: ~/ai-brain-opencode
cd ai-brain-opencode
bash install.sh ~/ruta/a/mi-cerebro
```

Flags:

| Flag | Efecto |
|---|---|
| `--with-schedule` | instala los trabajos programados (recordatorio del diario, revisión semanal, mantenimiento, actualización) |
| `--with-obsidian` | instala los 5 complementos comunitarios en el vault |
| `--with-mcp` | agrega los MCP remotos `granola` y `chatprd` (envían tu conversación cuando los usas: opt-in explícito) |
| `--config <archivo>` | siembra `⚙️ Meta/brain-config.json` con tus valores (idioma, hora del diario, hábitos) |
| `--wire` | solo re-cablea un vault existente (después de actualizar el starter) |
| `--yes` | no interactivo |

El instalador es **idempotente**: re-ejecutarlo actualiza lo que debe y nunca sobrescribe tu contenido.

## Qué queda instalado en tu vault

```
mi-cerebro/
├── AGENTS.md                  ← memoria del cerebro (la IA la lee cada sesión); CLAUDE.md es un symlink
├── opencode.json              ← config de OpenCode (MCP, si los pides)
├── .opencode/
│   ├── skills/ai-brain-starter/   ← clon (fuente única; se actualiza sola)
│   ├── skills/<40 skills>/        ← symlinks al clon (sin copias)
│   ├── commands/<17 comandos>/    ← symlinks al clon
│   └── plugins/brain-vault/       ← hooks de OpenCode (contexto, cierre, frontmatter)
├── 📓 Journals/  🏠 Home/  👤 CRM/  📝 Notes/
├── 💼 Business/Engagements/   🚀 I+D/{Herramientas,Investigación}/
├── ⚙️ Meta/  (Folder Resolvers, Floors, Sessions, Decisions, journal-config, brain-config)
└── scripts/  (verify.sh + trabajos programados)
```

## Configuración: `⚙️ Meta/brain-config.json`

Un solo archivo gobierna el cerebro. El plugin y los trabajos programados lo leen (no hay valores duplicados).

```json
{
  "language": "es",
  "timezone": "UTC",   // el instalador lo detecta del sistema
  "journal": { "time": "20:30", "topics": ["all"], "raw": true, "gratitude": true },
  "habits": ["agua"],
  "accountability": ["sueño"],
  "schedule": { "insights_day": "Sunday" }
}
```

Tras cambiarlo, re-ejecuta `bash install.sh <vault> --wire --with-schedule` para re-aplicar los horarios.

## Verificación

```bash
bash <vault>/scripts/verify.sh
```

Comprueba estructura, symlinks, pisos, config, plugin, git y entorno. En la máquina original esta suite dio
`PASS` en: run headless, carga del plugin, hook de contexto, hook de cierre, hook de write y los 4 trabajos.

## Primeros pasos

1. **Reinicia OpenCode** (o `/reload`) para que cargue el plugin.
2. **Edita `AGENTS.md`** — la sección "Me" es la línea entre una IA genérica y un cerebro que te conoce.
3. **Esta noche: `/journal`.** Es el hábito que hace que todo lo demás funcione.
4. **Cierra siempre con una señal de cierre** ("chao", "eso es todo"): el plugin inyecta el cascade que guarda tu sesión.

## Desinstalar

```bash
bash uninstall.sh <ruta-del-vault>            # quita maquinaria, conserva tu contenido
bash uninstall.sh <ruta-del-vault> --purge-clones   # además borra los clones vendorizados
```

## Licencias y atribución

Este paquete es MIT. El sistema que instala (ai-brain-starter, humanizer, framework High-Rise) es de terceros
y conserva sus propias licencias — ver `NOTICE.md`.
