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
| PreToolUse (inspeccionar/mutar input) | `ctx.tool.hook("execute.before")` | **Portado con alcance limitado**: solo herramientas de escritura, solo markdown dentro del vault, solo notas nuevas (auto-fix, no bloqueo) |
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
| auto-update cada ~6 días al abrir sesión | trabajo programado semanal (`update-brain.sh`, ff-only) |
| insights semanal/mensual (cron) | trabajo programado semanal con `opencode run` y gate por número de entradas |
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

**Pendientes** (posibles con la API actual, cuando se necesiten): bloqueo duro de secretos en escrituras (la API
documentada permite mutar input, no bloquear), guardias de shell (`ctx.shell.hook("create.before")`),
inyección de contexto de CRM/instintos, compactación con resumen propio, verificación de claims contra evidencia de
hooks, y el chequeo de zona horaria en eventos de calendario.

## Plataformas

macOS y Linux están soportados de punta a punta (symlinks POSIX + launchd/cron). **Windows nativo** está soportado directamente mediante Git for Windows: el instalador detecta entornos `MINGW*`/`MSYS*`/`CYGWIN*`, realiza el cableado mediante **copias** (`WIRE_MODE=copy`, sin symlinks del paquete) y programa los trabajos automáticos con **Task Scheduler** (`schtasks`, usando los horarios de la misma fuente única que cron/launchd). Requisitos reales en Windows nativo: Git for Windows (con `bash`), Python ≥3.9 (`python3`, `py -3` o `python`), `cygpath` y OpenCode CLI (`opencode run --help`). Evidencia: la ruta Windows está cubierta por fixtures simulados (`uname`/`schtasks` mock) y todavía no por una máquina Windows física; se declara así hasta que exista esa validación. No se requiere Developer Mode ni permisos de administrador. **WSL2** (ej. Ubuntu con cron manual: `sudo service cron start`) continúa disponible como alternativa de ejecución. Otras plataformas (p. ej. FreeBSD) se rechazan tempranamente antes de mutar el vault.

## Cómo se compensa la diferencia de bloqueo

Claude Code bloquea una llamada con exit code 2. OpenCode documenta mutación de input, no bloqueo. Por eso el
plugin **auto-repara** en lugar de impedir: si una nota nueva llega sin frontmatter, se lo antepone. Las reglas
que no se pueden forzar por hook (nunca inventar datos, no usar `git add -A`) viven en AGENTS.md, que se lee en
cada sesión.

## Verificación del puerto

La instalación se configura explícitamente para cada proyecto: el usuario proporciona la ruta del vault y el
instalador no realiza detección global ni modifica la configuración global de OpenCode.

Desde el checkout del paquete, `bash tests/run.sh` y `bash scripts/verify.sh` ejecutan las regresiones determinísticas
con fixtures aislados. Desde un vault instalado, `bash <vault>/scripts/verify.sh` comprueba archivos y herramientas
locales, y **sale con código 1** si algo falla. Estas pruebas no arrancan OpenCode V2 ni comprueban que un runtime cargue los hooks; esa validación requiere
un smoke test explícito de runtime y no se afirma aquí.

## Registro de propiedad

`install.sh`, `scripts/schedule.sh` y `uninstall.sh` comparten `scripts/lib/ownership.py`: un único lugar para el
sellado, la validación y las huellas del manifiesto. `install.sh` copia ese archivo al vault, de modo que
`<vault>/scripts/verify.sh` puede validar el manifiesto sin el checkout del paquete.

