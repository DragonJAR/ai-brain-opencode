# ai-brain-opencode

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux%20%7C%20Windows%20%7C%20WSL2-green.svg)](docs/COMPAT.md)
[![Author](https://img.shields.io/badge/author-DragonJAR%20SAS-orange.svg)](https://www.dragonjar.org)
[![English](https://img.shields.io/badge/leer%20en-English-blue.svg)](README.md)

> Cerebro personal: un vault de markdown en tu disco, impulsado por OpenCode V2 — sin nube obligatoria y sin datos personales en el paquete.

## Qué es esto

- Un **vault de markdown en tu máquina** (diario, notas, CRM, meta)—la IA lee y escribe archivos que te pertenecen.
- **OpenCode V2** como runtime (no Claude Code); ver [docs/COMPAT.md](docs/COMPAT.md).
- Un **instalador** que clona skills de terceros, cablea symlinks relativos e instala un plugin de proyecto—**este repo no trae datos personales**.
- **Sin base de datos ni SaaS obligatorio**: MCP remoto solo si pasas `--with-mcp`.

## Qué se instala

| En el vault | Para qué |
|---|---|
| Árbol de carpetas (`📓 Journals/`, `🏠 Home/`, `👤 CRM/`, `📝 Notes/`, `💼 Business/`, `🚀 I+D/`, `⚙️ Meta/`) | Layout canónico de notas y meta |
| `.opencode/skills/ai-brain-starter/` (+ symlinks de skills/comandos) | Clon del starter; skills/comandos son enlaces relativos |
| `.opencode/plugins/brain-vault/index.js` | Plugin OpenCode (contexto, cierre, reunión, frontmatter) |
| `AGENTS.md` (+ `CLAUDE.md` → `AGENTS.md`) | Memoria del cerebro por sesión; OpenCode la lee en cada sesión |
| `⚙️ Meta/brain-config.json` | Idioma, zona, hora del diario, hábitos, horarios |
| `scripts/verify.sh`, `scripts/lib/ownership.py`, `scripts/lib/python3.sh`, `scripts/jobs/*.sh` | Salud del vault, propiedad, detección de Python, trabajos |
| `.opencode/brain-vault-install-manifest.json` | Huellas de propiedad para desinstalar con seguridad |
| `opencode.json` | **Solo** con `--with-mcp` (servidores MCP remotos) |

## Requisitos

| Necesario | Para qué |
|---|---|
| [OpenCode](https://opencode.ai/docs) con un modelo configurado | Runtime que carga el vault y el plugin |
| Git | Clonar starter + humanizer; commit base del vault |
| Python 3.9+ (`python3`, `py -3` o `python` en `PATH`) | Instalador, ownership y helpers del diario (el instalador valida la versión) |
| Node (opcional) | Permite al instalador validar la sintaxis del plugin con `node --check`; la versión no se valida |
| macOS, Linux, WSL2 Ubuntu o Windows nativo (Git Bash) | POSIX: symlinks + launchd/cron · Windows: copias de archivo + **schtasks** |
| Obsidian (opcional) | Ver el vault; `--with-obsidian` instala cinco plugins comunitarios |

## Instalación

```bash
git clone https://github.com/DragonJAR/ai-brain-opencode.git
cd ai-brain-opencode
bash install.sh ~/ruta/a/mi-cerebro
```

La ruta del vault es **siempre explícita**. No detecta vaults automáticamente ni modifica la configuración global de OpenCode. El instalador no edita `~/.config/opencode/opencode.json`.

| Flag | Efecto |
|---|---|
| `--config <archivo>` | Siembra `⚙️ Meta/brain-config.json` desde un JSON |
| `--wire` | Re-enlaza un vault existente tras actualizar el starter (sin clonar/scaffold; puede ir con `--with-schedule`) |
| `--with-mcp` | Añade MCP remotos `granola` + `chatprd` en el `opencode.json` del vault (envían conversación al usarlos—opt-in) |
| `--with-obsidian` | Instala cinco plugins comunitarios de Obsidian bajo `.obsidian/plugins/` (solo macOS/Linux) |
| `--with-schedule` | Registra trabajos (launchd en macOS, cron en Linux, schtasks en Windows) |

También acepta: `--help` / `-h`, y `--yes` / `-y` (sin preguntas; el instalador no es interactivo).

Actualizar el starter (explícito, nunca automático) y re-cablear:

```bash
BRAIN_STARTER_UPDATE=1 bash install.sh ~/ruta/a/mi-cerebro
bash install.sh ~/ruta/a/mi-cerebro --wire
```

## Verificación

```bash
bash tests/run.sh                 # suite de regresiones del paquete
bash <vault>/scripts/verify.sh    # salud del vault: estructura, symlinks, config, plugin, propiedad
```

`<vault>/scripts/verify.sh` imprime `✓` / `✗` y **sale con código 1** si algo falla. Las pruebas del paquete y el verify del vault **no** arrancan OpenCode V2 ni prueban que los hooks carguen en un runtime vivo (`docs/COMPAT.md`). Tras instalar: reinicia OpenCode o ejecuta `/reload` para cargar `.opencode/plugins/`.

## Uso diario

El instalador copia el plugin a `<vault>/.opencode/plugins/brain-vault/index.js`. OpenCode carga plugins de proyecto desde `.opencode/plugins/` (y globales desde `~/.config/opencode/plugins/`). Si el runtime no expone la API de hooks, el plugin **avisa y degrada** (`ctx.session.hook` / `ctx.tool.hook` ausentes)—no tumba la sesión.

| Comportamiento | Fuente de verdad |
|---|---|
| Reglas de contexto por turno | `brain-config.json` (`language`, `journal.time`, `timezone`, `habits`, `extra_rules`) |
| Cascade de cierre | Palabras como «chao» / «eso es todo» (según idioma) |
| Disparador de reunión | Frases como «acabo de tener una reunión» → flujo meeting-todos |
| Frontmatter automático en markdown nuevo | `type:` + `created:` según carpeta |

## Comandos slash

Los 17 comandos siguientes vienen de ai-brain-starter y el instalador los cablea a tu vault como
`.opencode/commands/*.md` (symlinks relativos en macOS/Linux/WSL2, copias en Windows). Escríbelos en una
sesión de OpenCode abierta sobre el vault; cada uno delega en su skill, que el instalador ya instaló
— no hace falta ningún paso de bootstrap.

| Comando | Qué hace |
|---|---|
| **Diario y reuniones** | |
| `/daily-journal` | Entrevista de diario diario y creación de la entrada, con etiquetado de piso emocional |
| `/insights` | Insights semanales o mensuales del diario: reconocimiento de patrones y feedback de panel |
| `/meeting-todos` | Extraer action items de una nota de reunión y enrutarlos al archivo de tareas correcto |
| `/cierre` | Terminó una llamada comercial: seguimiento completo — CRM, tareas, borrador de email, recordatorio, coaching |
| `/today` | Briefing ejecutivo diario cruzando diario, sesiones recientes, engagements y CRM |
| **Vault y conocimiento** | |
| `/diagnose` | Autodiagnóstico de la instalación (archivo de instrucciones, carpetas Meta, skills, hooks, MCPs) |
| `/setup-vault-types` | Configurar qué tipos de documento usa tu vault y crear los extractores |
| `/second-brain-mapping` | Mapear el vault: metadatos estructurados por archivo tipado, insights cruzados, grafo opcional |
| `/graphify` | Convertir el vault en un grafo de conocimiento agrupado con salidas HTML y JSON |
| `/optimize-brain` | Optimización profunda del vault: CRM, grafos, dashboards, compresión, wikilinks |
| `/ingest` | Ingesta de fuentes crudas de `📝 Notes/Raw/` hacia notas compiladas con wikilinks |
| `/audit` | Auditoría determinista del vault: enlaces rotos, notas huérfanas, markdown sin tipo, raw pendiente |
| **Patrones e ideas** | |
| `/patterns` | Escanear sesiones recientes en busca de patrones recurrentes y convertirlos en capturas (reglas, notas de concepto, semillas de escritura) |
| `/deconstruct` | Analista de primeros principios: sacar supuestos ocultos, hallar verdades fundacionales, reconstruir |
| `/evolve` | Agrupar instintos endurecidos en un comando / skill / agente propuesto (Instinct Engine) |
| `/instinct-export` | Exportar la librería de instintos a un pack YAML portátil (Instinct Engine) |
| `/instinct-import` | Importar un pack YAML de instintos con merge por umbrales de confianza (Instinct Engine) |
| `/ideas` | Descubrimiento de patrones cruzados entre Negocios, I+D y Notas |
| **Contenido** | |
| `/humanizer` | Quitar los AI-isms de la prosa externa y reescribirla en tu voz real |
| `/repurpose-talk` | Convertir una ponencia en 10–30 piezas de contenido |
| `/nano-banana` | Generar o editar imágenes con el modelo Gemini Image de Google |
| **Comandos del paquete (este repo)** | |
| `/create` | Redacción de contenido humanizado a partir del contexto del vault sin clichés de IA |
| `/today` | Briefing ejecutivo diario: estado del diario, última sesión, compromisos de clientes y seguimientos |
| `/ingest` | Compilar fuentes crudas de `📝 Notes/Raw/` en conocimiento estructurado del vault, preservando la fuente |
| `/audit` | Auditoría determinista de integridad: wikilinks rotos, notas huérfanas, markdown sin tipar, fuentes pendientes |
| `/ideas` | Descubrimiento de patrones y síntesis cruzada entre Business, I+D, Notes y Journals |

## Configuración

Se siembra como `⚙️ Meta/brain-config.json` desde `templates/brain-config.example.json` (JSON estricto, no JSONC):

```json
{
  "vault_name": "mi-cerebro",
  "language": "es",
  "timezone": "UTC",
  "journal": {
    "time": "20:30",
    "topics": [
      "all"
    ],
    "raw": true,
    "gratitude": true
  },
  "habits": [],
  "accountability": [],
  "extra_rules": [],
  "schedule": {
    "insights_time": "21:00",
    "maintenance_time": "03:30",
    "update_time": "08:00"
  }
}
```

## Trabajos programados

Defaults de `templates/brain-config.example.json` y `scripts/schedule.sh`:

| Trabajo | Hora por defecto | Cuándo |
|---|---|---|
| `journal-reminder.sh` | `20:30` | Lunes–viernes |
| `insights-weekly.sh` | `21:00` | Domingo |
| `daily-maintenance.sh` | `03:30` | Todos los días |
| `update-brain.sh` | `08:00` | Lunes |

Los horarios disparan en la **zona horaria del host**; la `timezone` de `brain-config.json` gobierna las
fechas que renderiza el plugin, no el reloj del scheduler.

```bash
bash scripts/schedule.sh ~/ruta/a/mi-cerebro --dry-run   # muestra jobs; no escribe launchd/cron
bash scripts/schedule.sh ~/ruta/a/mi-cerebro             # instala
bash scripts/schedule.sh ~/ruta/a/mi-cerebro --remove    # quita solo entradas propias verificadas
```

En **WSL2**, cron no arranca solo: `sudo service cron start` (el instalador avisa si detecta WSL).

## Plataformas

| Plataforma | Soporte |
|---|---|
| macOS | Completo: symlinks + **launchd** |
| Linux | Completo: symlinks + **cron** |
| WSL2 (Ubuntu) | Dentro de WSL; arranca **cron** a mano (`sudo service cron start`) |
| Windows nativo (Git Bash) | Implementado: **copias de archivo** (sin symlinks del paquete) + **schtasks**. Requiere `git`, Python ≥3.9, `bash`, `cygpath` y `opencode run --help`. **No** hace falta Developer Mode. Evidencia: cubierto con fixtures simulados de Windows (`uname`/`schtasks` mock); falta validación en hardware real, así que abre un issue si algo falla. WSL2 sigue siendo una alternativa válida. |

## Desinstalación

```bash
bash uninstall.sh ~/ruta/a/mi-cerebro
bash uninstall.sh ~/ruta/a/mi-cerebro --purge-clones
```

Solo borra artefactos **propios sin cambios** del manifiesto. Lo modificado, symlinks ajenos y lo ambiguo se **preserva** y se informa. `--purge-clones` también elimina clones de vendor verificados (`ai-brain-starter`, `humanizer`).

## Problemas frecuentes

| Síntoma | Causa probable |
|---|---|
| `falta OpenCode CLI` y aborta | `opencode` ausente del `PATH` (vault intacto) |
| Los jobs no corren en WSL2 | Cron inactivo → `sudo service cron start` |
| `archivo modificado o no verificado, preservado` al desinstalar | Editaste el archivo o hay drift de modos (p. ej. DrvFs)—seguridad esperada |
| `bad interpreter: bash\r` | Checkout CRLF; usa filesystem Linux dentro de WSL2 |
| El plugin ignora la config | Carpeta `⚙ Meta` (sin VS16) ≠ `⚙️ Meta` |
| `refusing to modify a symlinked… opencode.json` / sin identidad git | `--with-mcp` exige `opencode.json` regular; configura `user.name` / `user.email` antes de instalar |

## Privacidad

- Sin datos personales del operador en el paquete; ejecuta `bash scripts/check-personal-data.sh`.
- Los MCP remotos son **opt-in** (`--with-mcp`) y envían conversación cuando usas esos servidores.
- El contenido del vault queda en disco bajo la ruta que pasas a `install.sh`.

## Estructura

```
ai-brain-opencode/
├── install.sh · uninstall.sh
├── plugin/brain-vault/index.js
├── scripts/{schedule,verify,check-personal-data}.sh · scripts/audit.py
├── scripts/lib/ownership.py
├── templates/brain-config.example.json
├── templates/commands/*.md
├── templates/jobs/*.sh
├── tests/run.sh
└── docs/COMPAT.md
```

## Licencia + Autor

MIT — ver [LICENSE](LICENSE). Terceros conservan sus términos — [NOTICE.md](NOTICE.md).

*Una adaptación a OpenCode V2 de [ai-brain-starter](https://github.com/mycelium-hq/ai-brain-starter) (mycelium-hq).*

**DragonJAR SAS** · [dragonjar.org](https://www.dragonjar.org)

[English](README.md)
