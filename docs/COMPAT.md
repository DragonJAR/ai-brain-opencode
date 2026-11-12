# Compatibilidad Claude Code → OpenCode

ai-brain-starter está construido sobre el runtime de Claude Code. OpenCode no tiene su sistema de hooks
(`settings.json` con PreToolUse/UserPromptSubmit), pero sí tiene **plugins con eventos tipados**. Este documento
mapea cada mecanismo, para saber qué está portado, qué se sustituyó y qué no aplica.

## Mecanismos de transporte

| Claude Code | OpenCode | Estado |
|---|---|---|
| hooks en `~/.claude/settings.json` (stdin JSON, exit 2 bloquea) | plugins V2 en `.opencode/plugins/` (JS, hooks tipados) | **Portado** (`plugin/brain-vault/index.js`) |
| UserPromptSubmit | `ctx.session.hook("prompt")` — muta el mensaje entrante | **Portado** |
| SessionStart (contexto) | `ctx.session.hook("context")` — instrucciones de sistema por llamada | **Portado** |
| PreToolUse (inspeccionar/reemplazar input, bloquear) | `ctx.tool.hook("execute.before")` — asignar `event.input` reemplaza el input; lanzar un error aborta la llamada | **Portado con alcance limitado**: `write` y `patch` (las secciones `*** Add File`), solo markdown dentro del vault, solo notas nuevas (auto-fix, no bloqueo). `edit` no crea archivos en v2 |
| PostToolUse | `ctx.tool.hook("execute.after")` | Disponible, no usado |
| PreCompact | `ctx.session.hook("compaction")` | Disponible, no usado |
| Stop / SessionEnd | `ctx.event.subscribe(...)` | Parcial |
| `claude -p` headless (router) | `opencode run "<prompt>"` | **Sustituido** |
| cron/launchd de CC | launchd (macOS) / cron (Linux) / Task Scheduler (Windows) | **Sustituido** |

## Los hooks del upstream y su destino

**Portados al plugin** (mismo efecto, mecanismo distinto):

| Hook CC | Evento CC | En OpenCode |
|---|---|---|
| detect-closing-signal.py | UserPromptSubmit | hook de prompt: señales de cierre EN/ES → inyecta el cascade de cierre |
| inject-meeting-workflow-on-trigger.py | UserPromptSubmit | hook de prompt: trigger de reunión → flujo meeting-todos / cierre-de-llamada |
| vault-context.py, session-start-context.py | SessionStart | hook de contexto: reglas del vault en cada llamada |
| lint-vault-frontmatter.py | PreToolUse | hook de herramienta: antepon frontmatter a notas NUEVAS de markdown dentro del vault (archivos existentes y separadores temáticos que no son frontmatter se respetan) |

**Sustituidos por mecanismo nativo:**

| Hook/script CC | Sustituto |
|---|---|
| auto-update cada ~6 días al abrir sesión | trabajo programado semanal (`update-brain.sh`, ff-only) para el starter y humanizer; el paquete se actualiza a mano con `install.sh --update <vault>`, solo desde `https://github.com/DragonJAR/ai-brain-opencode` |
| insights semanal/mensual (cron) | trabajo programado semanal con `opencode run --auto` (y `--archived` si existe) y gate por número de entradas; invoca `--command insights` si la CLI lo ofrece y, si no (OpenCode v2 no lo tiene y no interpreta `/insights` dentro del mensaje), nombra la skill `insights` |
| daily job (ramas, worktrees, disco) | trabajo programado diario: índice del diario + snapshot git |
| session-end-hook.sh (cascade) | protocolo de sesión en AGENTS.md + hook de prompt |
| post-tool-use-learnings.py | memoria indexada del entorno (Engram o equivalente) |
| journal-preflight / index / metadata | scripts enlazados desde el clon (mismo código, sin copias) |

**No aplican** (infraestructura exclusiva de Claude Code): worktrees y sesiones de CC (`snapshot-pending-work-on-stop`,
`remove-ended-worktree`, `enforce-worktree-cap`, `surface-orphan-worktree-snapshots`, `warn-vault-session-in-worktree`,
`check-cd-outside-worktree`, `warn-stale-dev-checkout`, `relocate-watch-surface`, `dev-hub-refresh-on-session-start`,
`surface-orphan-claude-branches`), settings de CC (`lint-claude-settings`, `pre-write-settings-lint`,
`validate-mcp-json`, `block-*-inline-secret`, `check-claude-code-version`), subagentes de CC
(`agent-briefing-check`, `validate-subagent-return`), cache SDD (`sdd-cache-pre/post`), scrub de JSONL de CC.

**Pendientes** (posibles con la API actual, cuando se necesiten): bloqueo duro de secretos en escrituras (lanzar
un error en `execute.before` aborta la llamada), guardias de shell (`ctx.shell.hook("create.before")`),
inyección de contexto de CRM/instintos, compactación con resumen propio, verificación de claims contra evidencia de
hooks, y el chequeo de zona horaria en eventos de calendario.

## Plataformas

macOS y Linux están soportados de punta a punta (symlinks POSIX + launchd/cron). **Windows nativo** está soportado directamente mediante Git for Windows: el instalador detecta entornos `MINGW*`/`MSYS*`/`CYGWIN*`, realiza el cableado mediante **copias** (`WIRE_MODE=copy`, sin symlinks del paquete) y programa los trabajos automáticos con **Task Scheduler** (`schtasks`, usando los horarios de la misma fuente única que cron/launchd). Requisitos reales en Windows nativo: Git for Windows (con `bash`), Python ≥3.9 (`python3`, `py -3` o `python`), `cygpath` y OpenCode CLI (`opencode run --help`). Evidencia: la ruta Windows está cubierta por fixtures simulados (`uname`/`schtasks` mock) y todavía no por una máquina Windows física; se declara así hasta que exista esa validación. No se requiere Developer Mode ni permisos de administrador. **WSL2** (ej. Ubuntu con cron manual: `sudo service cron start`) continúa disponible como alternativa de ejecución. Otras plataformas (p. ej. FreeBSD) se rechazan tempranamente antes de mutar el vault.

## Cómo se compensa la diferencia de bloqueo

Claude Code bloquea una llamada con exit code 2. En OpenCode V2 el equivalente documentado es lanzar un error en
`ctx.tool.hook("execute.before")`: la herramienta no se ejecuta y el modelo recibe el mensaje (guía de plugins,
"Migrate from V1"; en la API Effect, `Tool.Error`). Aun así, el plugin **auto-repara** en lugar de impedir: si una
nota nueva llega sin frontmatter por `write` o `patch`, reemplaza el input con el frontmatter antepuesto, en vez de
gastar un turno en un rechazo. `edit` no necesita el arreglo: en v2 rechaza un `oldString` vacío y un archivo que
no existe, así que nunca crea notas. Las reglas
que no se pueden forzar por hook (nunca inventar datos, no usar `git add -A`) viven en AGENTS.md, que se lee en
cada sesión.

## Verificación del puerto

La instalación se configura explícitamente para cada proyecto: el usuario proporciona la ruta del vault y el
instalador no realiza detección global ni modifica la configuración global de OpenCode.

Desde el checkout del paquete, `bash tests/run.sh` y `bash scripts/verify.sh` ejecutan las regresiones determinísticas
con fixtures aislados. Desde un vault instalado, `bash <vault>/scripts/verify.sh` comprueba archivos y herramientas
locales, y **sale con código 1** si algo falla. Estas pruebas no arrancan OpenCode V2 ni comprueban que un runtime cargue los hooks; esa validación requiere
un smoke test explícito de runtime y no se afirma aquí.

## Registro de propiedad y bibliotecas compartidas

Cada pieza de lógica vive en un solo lugar de `scripts/lib/`, y `install.sh` copia esa carpeta al vault para que
`<vault>/scripts/verify.sh` y los trabajos programados funcionen sin el checkout del paquete:

| Biblioteca | Responsabilidad única |
|---|---|
| `ownership.py` | Manifiesto: sellado, huellas, lista de rutas gestionadas, instalación que preserva lo ajeno, desinstalación e informe de deriva |
| `wire.py` | Cableado del starter (skills y scripts: symlinks en POSIX, copias en Windows; comandos: siempre copias adaptadas a OpenCode, herramienta `skill` y rutas `.opencode/`) y poda de lo que el starter retiró; lo usan `install.sh` y `update-brain.sh` |
| `vault_layout.py` | Carpetas del vault, tipo de nota por carpeta y servidores MCP remotos. El plugin mantiene una copia de los tipos que un test compara |
| `brain_config.py` | Lectura de `brain-config.json`: valores por defecto, validación y fallback. El plugin (JavaScript) mantiene una copia de los valores por defecto que un test compara |
| `common.sh` | Mensajes, ayuda y errores de invocación de los scripts (`usage`, `usage_error`), detección de plataforma, intérprete Python y el arranque común de los trabajos (log con rotación, candado, timeout) |
| `python3.sh` | Elección del intérprete (`python3`, `py -3`, `python`) en modo UTF-8 |

Los trabajos programados salen de una única tabla en `scripts/schedule.sh` (nombre, clave del horario, días), de la
que se derivan las líneas de cron, los launch agents y las tareas de `schtasks`. Los clones del vendor se registran
por su origen git, no por huella: un `pull` no les quita el dueño.

Las salidas de Python que lee el shell se emiten en UTF-8 y con saltos de línea `\n` también en Windows, donde el
intérprete nativo usaría `cp1252` y `\r\n`.
