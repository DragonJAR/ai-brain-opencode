# ai-brain-opencode

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux%20%7C%20Windows%20%7C%20WSL2-green.svg)](docs/COMPAT.md)
[![Author](https://img.shields.io/badge/author-DragonJAR%20SAS-orange.svg)](https://www.dragonjar.org)
[![English](https://img.shields.io/badge/leer%20en-English-blue.svg)](README.md)

Un segundo cerebro personal para **OpenCode V2**: un vault de markdown en tu disco (diario, notas, CRM) que la IA lee
y escribe. El instalador trae los skills de [ai-brain-starter](https://github.com/mycelium-hq/ai-brain-starter) al
vault, los adapta a OpenCode y agrega un plugin. Sin base de datos, sin nube obligatoria y sin datos personales en el
paquete.

## Instalación

Necesitas [OpenCode](https://opencode.ai/docs) V2 con un modelo configurado, `git` (con `user.name` / `user.email`),
`bash` y Python 3.9+. Funciona en macOS, Linux, WSL2 y Windows (Git Bash).

```bash
git clone https://github.com/DragonJAR/ai-brain-opencode.git
cd ai-brain-opencode
bash install.sh ~/ruta/a/mi-cerebro
```

La ruta del vault siempre es explícita. No detecta vaults automáticamente ni modifica la configuración global de OpenCode.
Repetirlo es seguro: tu contenido nunca se sobrescribe.

| Flag | Efecto |
|---|---|
| `--with-schedule` | Programa los trabajos (recordatorio, insights semanal, snapshot diario, actualización de skills) |
| `--with-mcp` | Agrega los MCP remotos `granola` y `chatprd` (opcional: reciben tu conversación cuando los usas) |
| `--with-obsidian` | Instala los complementos de Obsidian (macOS/Linux) |
| `--config <archivo>` | Siembra la config del vault desde tu propio JSON |
| `--wire` | Solo re-cablea un vault existente |
| `--update [vault]` | Actualiza este paquete (ver [Actualización](#actualización)) |
| `--dry-run` | Valida los requisitos y muestra el plan; no toca nada |

## Primeros pasos

1. Abre OpenCode sobre el vault (reinícialo, o ejecuta `/reload`, después de instalar).
2. `/setup-brain`: una entrevista corta que completa `AGENTS.md` y tu config.
3. `/daily-journal` esta noche. La primera entrada pone el sistema en marcha.
4. `bash <vault>/scripts/verify.sh` cuando quieras revisar la salud del vault.

## Comandos

| Comando | Qué hace |
|---|---|
| **Diario y reuniones** | |
| `/daily-journal` (`/journal`) | Entrevista y entrada del diario, etiquetada con su piso emocional |
| `/insights` | Patrones semanales o mensuales de tu diario |
| `/meeting-todos` | Lleva las tareas de una nota de reunión al archivo de pendientes correcto |
| `/cierre` | Tras una llamada comercial: CRM, tareas, borrador de correo, recordatorio |
| `/today` | Briefing del día: diario, última sesión, compromisos, seguimientos |
| **Vault y conocimiento** | |
| `/setup-brain` | Personaliza `AGENTS.md` y la config |
| `/ingest` | Compila las fuentes de `📝 Notes/Raw/` en notas enlazadas; la fuente queda intacta |
| `/audit` | Wikilinks rotos, notas huérfanas, notas sin tipo, fuentes pendientes |
| `/diagnose` | Chequeo de salud de este vault: instalación, config, plugin, notas y logs de los trabajos |
| `/setup-vault-types` | Elige los tipos de documento que usa tu vault |
| `/second-brain-mapping` | Metadatos estructurados y hallazgos entre documentos |
| `/graphify` | Grafo de conocimiento del vault (HTML y JSON); instala el paquete de Python `graphify` |
| `/optimize-brain` | Limpieza profunda: CRM, grafos, tableros, wikilinks |
| **Patrones e ideas** | |
| `/patterns` | Patrones recurrentes de tus sesiones, convertidos en reglas y notas |
| `/ideas` | Conexiones entre Business, I+D, Notes y Journals |
| `/deconstruct` | Análisis de una idea desde primeros principios |
| `/evolve` | Convierte instintos consolidados en un comando, skill o agente |
| `/instinct-export` | Exporta la biblioteca de instintos a YAML |
| `/instinct-import` | Importa un paquete de instintos |
| **Contenido** | |
| `/create` | Redacta contenido desde el contexto del vault, con tu voz |
| `/humanizer` | Quita los vicios de IA de un texto |
| `/repurpose-talk` | Convierte una charla en 10–30 piezas de contenido |
| `/nano-banana` | Genera o edita imágenes con Gemini; necesita tu clave de API de Gemini |

El plugin también trabaja sin comandos: agrega tus reglas a cada turno, guarda la sesión cuando te despides, ofrece
el flujo de reuniones cuando mencionas una y pone el tipo a las notas nuevas según su carpeta.

Los skills del starter se escribieron para Claude Code. `AGENTS.md` le indica al modelo cómo leerlos aquí, y el
skill instalador del propio starter queda oculto con una regla de permisos en el `opencode.json` del vault.

## Configuración

`⚙️ Meta/brain-config.json`, JSON estricto. Un valor inválido cae a su valor por defecto con un aviso.

```json
{
  "vault_name": "mi-cerebro",
  "language": "es",
  "timezone": "UTC",
  "journal": {
    "time": "20:30",
    "topics": ["all"],
    "raw": true,
    "gratitude": true
  },
  "habits": [],
  "accountability": [],
  "extra_rules": [],
  "snapshot_paths": [
    "📓 Journals",
    "⚙️ Meta/Sessions",
    "⚙️ Meta/Decisions",
    "⚙️ Meta/journal-index.json"
  ],
  "schedule": {
    "insights_time": "21:00",
    "maintenance_time": "03:30",
    "update_time": "08:00"
  }
}
```

| Clave | Significado |
|---|---|
| `language`, `timezone`, `habits`, `extra_rules` | Contexto que el plugin agrega en cada turno (`extra_rules`: tus reglas permanentes) |
| `journal.time`, `schedule.*` | Horas de los trabajos, `HH:MM`, en el reloj del equipo |
| `snapshot_paths` | Rutas del vault que confirma el snapshot diario; agrega `👤 CRM` o `📝 Notes` para incluirlas |

Tras cambiar una hora, vuelve a programar: `bash install.sh <vault> --wire --with-schedule`.

## Trabajos programados

Con `--with-schedule` (launchd en macOS, cron en Linux, schtasks en Windows). Cada uno escribe
`⚙️ Meta/logs/<trabajo>.log`.

| Trabajo | Por defecto | Qué hace |
|---|---|---|
| `journal-reminder` | 20:30, lunes a viernes | Notificación de escritorio |
| `insights-weekly` | 21:00, domingo | Ejecuta el insights semanal sin intervención |
| `daily-maintenance` | 03:30, diario | Índice del diario y snapshot git de `snapshot_paths` |
| `update-brain` | 08:00, lunes | Mantiene los skills del starter y humanizer en las versiones que fija este paquete, y re-cablea |

Míralos o quítalos con `bash scripts/schedule.sh <vault> --dry-run` / `--remove`.

## Actualización

```bash
bash install.sh --update ~/ruta/a/mi-cerebro
```

El paquete se actualiza **solo** desde `https://github.com/DragonJAR/ai-brain-opencode`: `--update` hace
`git pull --ff-only` en este checkout y re-cablea el vault. Se niega, sin cambiar nada, si `origin` es cualquier otro
repositorio, si el checkout tiene cambios locales o si el pull no es fast-forward.

Nada más se actualiza por su cuenta. Los skills del starter y humanizer son contenido de terceros fijado a un commit
en `scripts/lib/vault_layout.py`: el instalador y el trabajo `update-brain` activan ese commit y nunca hacen pull, así
que una versión más nueva solo llega a tu vault con una actualización de este paquete.

## Desinstalación

```bash
bash uninstall.sh ~/ruta/a/mi-cerebro --dry-run   # lista lo que se iría
bash uninstall.sh ~/ruta/a/mi-cerebro             # agrega --purge-clones para quitar también starter y humanizer
```

Solo se borran los archivos sin cambios que instaló el paquete. Tus notas, `AGENTS.md`, tu config y todo lo que
editaste se quedan.

## Solución de problemas

| Síntoma | Solución |
|---|---|
| `falta OpenCode CLI` | Pon `opencode` en el `PATH`; el vault no se tocó |
| Un trabajo no encuentra `opencode` o Python | Repite `bash scripts/schedule.sh <vault>` desde un shell que los tenga |
| En macOS falla un trabajo con el vault en `Documents`, `Desktop` o iCloud | Mueve el vault, o da Acceso Total al Disco a `/bin/bash` |
| Los trabajos no corren en WSL2 | `sudo service cron start` |
| El plugin ignora la config | La carpeta debe ser `⚙️ Meta`, con el selector de variación del emoji |
| `ya existe una tarea ajena` / `launch agent ajeno` | Otro vault tiene el mismo nombre de carpeta; renombra uno |

Más: estado por plataforma y límites en [docs/COMPAT.md](docs/COMPAT.md), cambios en [CHANGELOG.md](CHANGELOG.md).
Windows solo está cubierto por tests simulados; se agradecen reportes en equipos reales.

## Licencia

MIT — ver [LICENSE](LICENSE). Los componentes de terceros conservan sus términos: [NOTICE.md](NOTICE.md).

*Una adaptación a OpenCode V2 de [ai-brain-starter](https://github.com/mycelium-hq/ai-brain-starter) (mycelium-hq).*

**DragonJAR SAS** · [dragonjar.org](https://www.dragonjar.org)
