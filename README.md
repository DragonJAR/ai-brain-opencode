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
| Python 3.10+ | scripts del diario (índice, preflight) y registro de propiedad |
| Node 18+ | OpenCode; el plugin se valida con `node --check` si está presente |
| macOS o Linux | el cerebro usa symlinks POSIX y el scheduler usa launchd (macOS) o cron (Linux) |
| Obsidian (opcional) | ver el vault con notas enlazadas y Dataview |

**Windows:** no hay soporte nativo (symlinks POSIX y launchd/cron no existen en Windows). Usa **WSL2 con Ubuntu**
y ejecuta el instalador dentro de WSL. El instalador rechaza Windows nativo antes de tocar nada y, si detecta WSL,
te avisa cuando cron no está activo (`sudo service cron start`).

## Instalación

```bash
clona o copia este paquete donde quieras tenerlo, por ejemplo: ~/ai-brain-opencode
cd ai-brain-opencode
bash install.sh ~/ruta/a/mi-cerebro
```

La instalación siempre recibe explícitamente la ruta de un vault. No detecta vaults automáticamente ni modifica la configuración global de OpenCode.

Flags:

| Flag | Efecto |
|---|---|
| `--with-schedule` | instala los trabajos programados (recordatorio del diario, revisión semanal, mantenimiento, actualización) |
| `--with-obsidian` | instala los 5 complementos comunitarios en el vault |
| `--with-mcp` | agrega los MCP remotos `granola` y `chatprd` (envían tu conversación cuando los usas: opt-in explícito) |
| `--config <archivo>` | siembra `⚙️ Meta/brain-config.json` con tus valores (idioma, hora del diario, hábitos) |
| `--wire` | vuelve a enlazar un vault ya instalado, después de actualizar el starter; no clona, no crea estructura ni modifica configuración o contenido personal. Puede combinarse con `--with-schedule`. |
| `--yes` | aceptado por compatibilidad: el instalador no hace preguntas |
| `--help` | muestra la ayuda |

El instalador es **idempotente**: re-ejecutarlo actualiza lo que debe y nunca sobrescribe tu contenido. Cada
archivo que instala queda registrado en `.opencode/brain-vault-install-manifest.json`; `uninstall.sh` solo borra
lo que sigue intacto.

Actualizar el starter (ff-only, nunca automático):

```bash
BRAIN_STARTER_UPDATE=1 bash install.sh ~/ruta/a/mi-cerebro
bash install.sh ~/ruta/a/mi-cerebro --wire     # re-enlaza skills y comandos nuevos
```

## Qué queda instalado en tu vault

```
mi-cerebro/
├── AGENTS.md                  ← memoria del cerebro (la IA la lee cada sesión); CLAUDE.md es un symlink
├── opencode.json              ← solo con --with-mcp (servidores MCP remotos)
├── .opencode/
│   ├── skills/ai-brain-starter/   ← clon local (fuente única; actualización explícita)
│   ├── skills/<skills>/           ← symlinks al clon (sin copias)
│   ├── commands/<comandos>/       ← symlinks al clon
│   └── plugins/brain-vault/       ← hooks de OpenCode (contexto, cierre, frontmatter)
├── 📓 Journals/  🏠 Home/  👤 CRM/  📝 Notes/
├── 💼 Business/Engagements/   🚀 I+D/{Herramientas,Investigación}/
├── ⚙️ Meta/  (Folder Resolvers, Floors, Sessions, Decisions, journal-config, brain-config)
└── scripts/
    ├── verify.sh              ← salud del vault (exit 1 si algo falla)
    ├── lib/ownership.py       ← registro de propiedad compartido
    └── jobs/                  ← los trabajos programados
```

## Configuración: `⚙️ Meta/brain-config.json`

Un solo archivo gobierna el cerebro. El plugin y los trabajos programados lo leen (no hay valores duplicados).
Un valor inválido nunca rompe el sistema: cae al default documentado y avisa.

```json
{
  "vault_name": "mi-cerebro",
  "language": "es",
  "timezone": "UTC",
  "journal": { "time": "20:30", "topics": ["all"], "raw": true, "gratitude": true },
  "habits": ["agua"],
  "accountability": ["sueño"],
  "extra_rules": [],
  "schedule": { "insights_time": "21:00", "maintenance_time": "03:30", "update_time": "08:00" }
}
```

- `journal.time` y los tres horarios de `schedule` aceptan `HH:MM` (24 h). Los días son fijos: diario de lunes a
  viernes, revisión el domingo, actualización el lunes.
- `language` soporta `es` y `en` (cualquier otro valor usa `es`). `timezone` debe ser una zona IANA válida.
- Tras cambiarlo, re-ejecuta `bash install.sh <vault> --wire --with-schedule` para re-aplicar los horarios.

## Verificación

```bash
bash tests/run.sh            # regresiones del paquete (fixtures aislados)
bash scripts/verify.sh       # desde el checkout: corre las regresiones
bash <vault>/scripts/verify.sh   # desde el vault: estructura, symlinks, config, plugin y propiedad
```

`<vault>/scripts/verify.sh` termina con código 1 y lista los `✗` cuando algo está roto: sirve en CI y en scripts.
Ninguna de estas pruebas arranca OpenCode V2 ni confirma que un runtime cargue los hooks; esa validación requiere
un smoke test explícito de runtime.

## Primeros pasos

1. **Reinicia OpenCode** (o `/reload`) para que cargue el plugin.
2. **Edita `AGENTS.md`** — la sección "Me" es la línea entre una IA genérica y un cerebro que te conoce.
3. **Esta noche: `/journal`.** Es el hábito que hace que todo lo demás funcione.
4. **Cierra siempre con una señal de cierre** ("chao", "eso es todo"): el plugin inyecta el cascade que guarda tu sesión.

## Problemas comunes

| Síntoma | Causa y salida |
|---|---|
| `falta OpenCode CLI` | `opencode` no está en `PATH`. Instálalo y vuelve a ejecutar: el vault no se modificó. |
| `falta crontab` con `--with-schedule` | Linux sin cron instalado. Instala cron o repite sin el flag. |
| En WSL no corren los trabajos | cron no arranca solo: `sudo service cron start` (o `systemctl enable cron`). |
| `--wire` se niega | El vault no tiene manifiesto de propiedad o le falta estructura: corre una instalación normal una vez. |
| `verify.sh` falla en un vault viejo | Falta `scripts/lib/ownership.py` o el manifiesto: re-ejecuta `bash install.sh <vault> --wire`. |
| `uninstall.sh` no borra `AGENTS.md` | Es contenido tuyo, no maquinaria: se preserva a propósito. |

## Desinstalar

```bash
bash uninstall.sh <ruta-del-vault>                 # quita maquinaria, conserva tu contenido
bash uninstall.sh <ruta-del-vault> --purge-clones  # además borra los clones vendorizados
```

Solo elimina artefactos sin cambios registrados por el paquete. Lo modificado, lo que no es del paquete y lo
ambiguo se preserva y se informa. No toca Git: revisa `git status` en el vault y confirma el cambio tú mismo.

## Licencias y atribución

Este paquete es MIT. El sistema que instala (ai-brain-starter, humanizer, framework High-Rise) es de terceros
y conserva sus propias licencias — ver `NOTICE.md`.
