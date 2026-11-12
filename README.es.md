# ai-brain-opencode

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux%20%7C%20Windows%20%7C%20WSL2-green.svg)](docs/COMPAT.md)
[![Author](https://img.shields.io/badge/author-DragonJAR%20SAS-orange.svg)](https://www.dragonjar.org)
[![English](https://img.shields.io/badge/leer%20en-English-blue.svg)](README.md)

Un segundo cerebro personal para **OpenCode V2**: un vault de markdown en tu disco (diario, notas, CRM, meta) que la
IA lee y escribe. Un instalador clona los skills y comandos de
[ai-brain-starter](https://github.com/mycelium-hq/ai-brain-starter) en el vault, los adapta a OpenCode y agrega un
plugin de proyecto. Sin base de datos, sin nube obligatoria y sin datos personales en este paquete.

## Requisitos

| Necesario | Notas |
|---|---|
| [OpenCode](https://opencode.ai/docs) V2 con un modelo configurado | El runtime; ver [docs/COMPAT.md](docs/COMPAT.md) |
| `git` y `bash` | Clonan el starter y humanizer; hacen el primer commit del vault (requiere `user.name` / `user.email`) |
| Python 3.9+ (`python3`, `py -3` o `python`) | El instalador valida la versión |
| macOS, Linux, WSL2 o Windows (Git Bash) | Windows también requiere `cygpath`; no se exige Developer Mode |
| Node, Obsidian (opcionales) | `node --check` del plugin; `--with-obsidian` (macOS/Linux) |

## Instalación

```bash
git clone https://github.com/DragonJAR/ai-brain-opencode.git
cd ai-brain-opencode
bash install.sh ~/ruta/a/mi-cerebro
```

La ruta del vault es **siempre explícita**. No detecta vaults automáticamente ni modifica la configuración global de OpenCode. Volver a ejecutarlo es seguro: tu contenido nunca se sobrescribe. Luego reinicia OpenCode (o ejecuta `/reload`) sobre el vault.

| Flag | Efecto |
|---|---|
| `--config <archivo>` | Siembra `⚙️ Meta/brain-config.json` desde tu JSON (por defecto: `templates/brain-config.example.json`) |
| `--with-mcp` | Agrega los servidores MCP remotos `granola` y `chatprd` al `opencode.json` del vault (opcional: reciben tu conversación cuando los usas) |
| `--with-schedule` | Registra los trabajos programados (ver abajo) |
| `--with-obsidian` | Instala los complementos comunitarios de Obsidian (macOS/Linux) |
| `--wire` | Solo re-cablea un vault existente (sin clonar ni crear estructura) |
| `--update [vault]` | Actualiza este checkout del paquete (ver [Actualización](#actualización)) |
| `--dry-run` | Valida los requisitos y muestra el plan; no toca el vault |
| `--version` / `--help` | Muestra la versión / el uso (código 0) |

`--yes` / `-y` se acepta y no hace nada: el instalador nunca pregunta. Un error de uso sale con código 2 en todos los scripts.

## Qué se crea

| En el vault | Para qué |
|---|---|
| `📓 Journals`, `🏠 Home`, `👤 CRM`, `📝 Notes` (+ `Raw`), `💼 Business/Engagements`, `🚀 I+D/…`, `⚙️ Meta/…` | Estructura de carpetas, definida una sola vez en `scripts/lib/vault_layout.py` |
| `.opencode/skills/` | El clon del starter, sus skills (enlaces; copias en Windows) y humanizer |
| `.opencode/commands/` | Los comandos del starter como copias adaptadas a OpenCode, más los comandos del paquete |
| `.opencode/plugins/brain-vault/` | Plugin: contexto por turno, señal de cierre, disparador de reunión, frontmatter en notas nuevas |
| `AGENTS.md` (+ `CLAUDE.md`: un enlace, una copia en Windows) | La memoria del cerebro; OpenCode la lee en cada sesión |
| `⚙️ Meta/brain-config.json` | Tus ajustes (ver [Configuración](#configuración)) |
| `scripts/` (`verify.sh`, `audit.py`, `jobs/`, `lib/`) | Verificación, auditoría, trabajos; corren sin el checkout del paquete |
| `.opencode/brain-vault-install-manifest.json` | Lo que es del paquete, por huella, para desinstalar con seguridad |
| `opencode.json` | Solo con `--with-mcp` |

## Comandos y skills

Escríbelos en una sesión de OpenCode abierta sobre el vault. Los 17 comandos del starter son copias reescritas para
OpenCode en todas las plataformas (usan la herramienta `skill` y proponen `bash scripts/jobs/update-brain.sh` si falta
un skill). Cada uno delega en un skill del mismo flujo; todos los skills del starter y `humanizer` quedan en
`.opencode/skills/`.

| Comando | Qué hace |
|---|---|
| **Diario y reuniones** | |
| `/daily-journal` | Entrevista y entrada del diario, con etiquetado de piso emocional |
| `/insights` | Insights semanales o mensuales del diario: patrones y feedback de panel |
| `/meeting-todos` | Lleva las tareas de una nota de reunión al archivo de pendientes correcto |
| `/cierre` | Tras una llamada comercial: CRM, tareas, borrador de correo, recordatorio, coaching |
| **Vault y conocimiento** | |
| `/diagnose` | Autodiagnóstico de la instalación: archivo de instrucciones, carpetas Meta, skills, hooks, MCP |
| `/setup-vault-types` | Elige los tipos de documento de tu vault y crea los extractores |
| `/second-brain-mapping` | Metadatos estructurados por archivo tipado, insights cruzados, grafo opcional |
| `/graphify` | Grafo de conocimiento agrupado con salida HTML y JSON |
| `/optimize-brain` | Optimización profunda: CRM, grafos, dashboards, compresión, wikilinks |
| **Patrones e ideas** | |
| `/patterns` | Patrones recurrentes de sesiones recientes, convertidos en reglas, notas de concepto o semillas de escritura |
| `/deconstruct` | Análisis desde primeros principios: supuestos ocultos, verdades fundacionales, reconstrucción |
| `/evolve` | Agrupa instintos consolidados en un comando, skill o agente propuesto |
| `/instinct-export` | Exporta la librería de instintos a un pack YAML portátil |
| `/instinct-import` | Importa un pack YAML de instintos con fusión según umbrales de confianza |
| **Contenido** | |
| `/humanizer` | Quita los AI-isms de un texto y lo reescribe en tu voz |
| `/repurpose-talk` | Convierte una charla en 10–30 piezas de contenido |
| `/nano-banana` | Genera o edita imágenes con el modelo Gemini Image de Google |
| **Comandos del paquete** | |
| `/today` | Resumen del día: estado del diario, última sesión, compromisos con clientes, seguimientos |
| `/ingest` | Compila fuentes de `📝 Notes/Raw/` en notas del vault; la fuente no se toca |
| `/audit` | Auditoría determinista: wikilinks rotos, notas huérfanas, markdown sin tipo, fuentes pendientes |
| `/ideas` | Descubrimiento de patrones cruzados entre Business, I+D, Notes y Journals |
| `/create` | Redacción de contenido desde el vault en tu voz, con humanizer estricto |

## Trabajos programados

Se instalan con `--with-schedule`, o después con `bash scripts/schedule.sh <vault>` (también `--dry-run`, `--remove`,
`--remove --dry-run`). Vuelve a ejecutarlo tras cambiar los horarios.

| Trabajo | Por defecto | Cuándo |
|---|---|---|
| `journal-reminder.sh` | `20:30` | Lunes a viernes |
| `insights-weekly.sh` | `21:00` | Domingo |
| `daily-maintenance.sh` | `03:30` | Todos los días (confirma solo `snapshot_paths`) |
| `update-brain.sh` | `08:00` | Lunes (actualiza los skills del vendor) |

| Sistema | Programador |
|---|---|
| macOS | launchd. Un launch agent no puede leer `Documents`, `Desktop`, `Downloads` ni iCloud Drive (TCC): `schedule.sh` avisa; mueve el vault o da Acceso total al disco a `/bin/bash` |
| Linux | cron. En WSL2 arráncalo con `sudo service cron start` (el instalador avisa) |
| Windows | schtasks, a través de `scripts/jobs/ai-brain-run.cmd` |

Cada trabajo escribe `⚙️ Meta/logs/<trabajo>.log` (rotado a 1 MiB) y nunca se solapa consigo mismo. Los horarios usan
el reloj del sistema; `timezone` solo afecta las fechas que muestra el plugin. Los trabajos conservan el `PATH` de la
shell que los programó.

## Configuración

`⚙️ Meta/brain-config.json`, JSON estricto (sin comentarios). Un valor inválido vuelve al valor por defecto con un
aviso; `install.sh --config` muestra los mismos avisos.

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
| `vault_name`, `language`, `timezone`, `habits`, `accountability`, `schedule.*` | Se escriben en `AGENTS.md` al instalar |
| `language`, `timezone`, `journal.time`, `habits`, `extra_rules` | Contexto que el plugin agrega en cada turno |
| `journal.topics`, `journal.raw`, `journal.gratitude` | Preferencias del diario (validadas; valores por defecto arriba) |
| `journal.time`, `schedule.*` | Horarios de los trabajos, `HH:MM` |
| `snapshot_paths` | Lo que confirma `daily-maintenance`. Solo rutas relativas al vault: se descartan `.`, `..`, `.git`, rutas absolutas, `C:`, un `-` o `:` inicial, `\` y `*?[`. Si no queda ninguna, se usa la lista por defecto; un `[]` explícito no confirma nada |

## Actualización

| Qué | Cómo |
|---|---|
| Este paquete | `bash install.sh --update [vault]` desde tu checkout |
| Skills del vendor (starter, humanizer) | El trabajo `update-brain.sh`, o `bash <vault>/scripts/jobs/update-brain.sh` |

`--update` ejecuta `git pull --ff-only` solo desde `https://github.com/DragonJAR/ai-brain-opencode` y luego re-cablea
el vault si lo indicas (admite `--with-schedule`). Se niega, sin cambiar nada, si el checkout no es un clon git,
`origin` es otro repositorio, `HEAD` está suelto, la rama no sigue a `origin`, hay cambios locales o el pull no es
fast-forward.

`update-brain.sh` nunca actualiza el paquete: hace pull del starter y humanizer (solo fast-forward), regenera los pisos
y re-cablea; las copias de comandos que no editaste se refrescan. Un clon fijado con `BRAIN_STARTER_PIN=<sha>` no se
toca.

## Verificación

```bash
bash <vault>/scripts/verify.sh    # estructura, enlaces, config, plugin, propiedad; sale con 1 ante cualquier ✗
bash tests/run.sh                 # suite de pruebas del paquete
```

Ninguno arranca OpenCode, así que no prueban que los hooks del plugin carguen en el runtime ([docs/COMPAT.md](docs/COMPAT.md)).

## Desinstalación

```bash
bash uninstall.sh ~/ruta/a/mi-cerebro --dry-run        # lista lo que se quitaría, trabajos programados incluidos
bash uninstall.sh ~/ruta/a/mi-cerebro                  # quita
bash uninstall.sh ~/ruta/a/mi-cerebro --purge-clones   # también los clones del vendor
```

Solo se quitan los archivos sin cambios que el manifiesto prueba que instaló el paquete; los que editaste y los
enlaces ajenos se conservan y se reportan. Sin un manifiesto válido se niega y no quita nada. `--purge-clones` borra
`ai-brain-starter` y `humanizer` solo si siguen apuntando a su origen y no tienen cambios locales.

## Solución de problemas

| Síntoma | Solución |
|---|---|
| `falta OpenCode CLI` y la instalación aborta | Pon `opencode` en el `PATH` (el vault no se tocó) |
| Los trabajos nunca corren en WSL2 | `sudo service cron start` |
| Un trabajo no encuentra `opencode` o Python | Vuelve a ejecutar `bash scripts/schedule.sh <vault>` desde una shell que los tenga |
| Un trabajo de macOS falla con el vault en `Documents` | TCC: mueve el vault o da Acceso total al disco (ver arriba) |
| `bad interpreter: bash\r` | Checkout con CRLF; clona en un sistema de archivos Linux dentro de WSL2 |
| El plugin ignora la configuración | La carpeta debe ser `⚙️ Meta` (con el selector de variación del emoji) |
| `archivo modificado o no verificado, preservado` | Esperado: editaste el archivo y la desinstalación lo conserva |
| `ya existe una tarea ajena` / `launch agent ajeno` | Otro vault con el mismo nombre de carpeta es dueño de esa entrada; renombra uno |

## Más

- Estado por plataforma y límites del runtime: [docs/COMPAT.md](docs/COMPAT.md). Windows está cubierto por pruebas
  simuladas; los reportes en hardware real son bienvenidos.
- Cambios por versión: [CHANGELOG.md](CHANGELOG.md).
- Control de privacidad antes de publicar: `bash scripts/check-personal-data.sh`.

## Licencia

MIT — ver [LICENSE](LICENSE). Los componentes de terceros conservan sus propios términos: [NOTICE.md](NOTICE.md).

*Una adaptación a OpenCode V2 de [ai-brain-starter](https://github.com/mycelium-hq/ai-brain-starter) (mycelium-hq).*

**DragonJAR SAS** · [dragonjar.org](https://www.dragonjar.org)
