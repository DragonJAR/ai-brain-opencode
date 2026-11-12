## Adaptación OpenCode (generada por install.sh)

Se genera en la primera instalación, junto con el resto de `AGENTS.md`. Ninguna re-ejecución la sobrescribe: si necesitas regenerarla, borra `AGENTS.md` y vuelve a instalar.

### Idioma
Responde y escribe en {{LANGUAGE}}. Los nombres de carpeta quedan en inglés a propósito: los skills del sistema tienen rutas fijas y traducirlos genera carpetas duplicadas.

### Diario
- Compromiso: `/daily-journal` a las {{JOURNAL_TIME}} ({{TIMEZONE}}).
- Hábitos trackeados: {{HABITS}}.
- Accountability: {{ACCOUNTABILITY}}.
- Cada entrada se etiqueta sola con su piso emocional (High-Rise, 34 niveles). Notas de piso en `⚙️ Meta/Floors/`. Tú nunca te autoetiquetas.

### Ruteo
- Trabajo con clientes o con la compañía → `💼 Business/` (un engagement = una carpeta en `Engagements/`).
- Investigación, herramientas propias, experimentos → `🚀 I+D/`.
- Reflexión personal → `📓 Journals/` y `🏠 Home/`.
- Fuentes y lecturas crudas inmutables → `📝 Notes/Raw/` (compilables con `/ingest`).
- Si algo sirve a los dos frentes: se escribe en `🚀 I+D/` y se referencia desde `💼 Business/`.

### Dual-write
- Lo que valga entre sesiones termina como archivo del vault. La memoria indexada es un índice, no el archivo: si no está en el vault, no está.
- Nunca uses `git add -A` ni `git add .`: siempre rutas explícitas.
- Nunca inventes datos técnicos (CVE, versiones, IPs, salidas de herramientas): usa `MISSING` / `[PENDING_DATA]`.

### Sesión
- Inicio: lee este archivo y `⚙️ Meta/Sessions/` (última sesión).
- Cierre: el plugin `brain-vault` detecta la señal de cierre ("chao", "eso es todo"...) e inyecta el cascade: guarda `⚙️ Meta/Sessions/<fecha-hora>.md`, registra decisiones en `⚙️ Meta/Decisions/` y compromete solo las rutas tocadas.
- Configuración personal: `/setup-brain` (la entrevista del paquete).
- Verificación: `bash scripts/verify.sh` y auditoría de integridad `python3 scripts/audit.py .` (o `/audit`; en Windows el intérprete puede ser `py -3`).

### Skills del starter (escritos para Claude Code)
Los skills de `.opencode/skills/` vienen de ai-brain-starter y hablan de Claude Code. En este vault léelos así:
- Una ruta de skills dentro de la carpeta personal de Claude Code es aquí `.opencode/skills/<skill>`; `CLAUDE.md` es este `AGENTS.md`.
- Los hooks y el `settings.json` de Claude Code no existen aquí: su trabajo lo hace el plugin `brain-vault`. No los instales ni los reportes como faltantes.
- La salud de la instalación se revisa con `bash scripts/verify.sh` y `/audit`; `/diagnose` es el chequeo del vendor y sus hallazgos sobre la instalación de Claude Code no aplican.
- El instalador del vendor (skill `ai-brain-starter`) está oculto con una regla de permisos en `opencode.json`: no la quites.
- Un skill que pida una clave o un programa externo (p. ej. `nano-banana`: clave de Gemini; `graphify`: su paquete de Python) lo dice antes de instalar nada.

### Scheduler (si se instaló con `--with-schedule`)
Los horarios salen de `⚙️ Meta/brain-config.json`; los días son fijos y el sistema operativo dispara los
trabajos en la zona horaria del host (la `timezone` declarada gobierna las fechas que renderiza el plugin,
no el reloj del scheduler).
- Recordatorio del diario: {{JOURNAL_TIME}}, de lunes a viernes (zona horaria declarada: {{TIMEZONE}}) — notificación del sistema operativo.
- Revisión semanal: domingo {{INSIGHTS_TIME}} (headless con `opencode run --auto`, que pide la skill `insights` porque `opencode run` no ejecuta comandos `/`; solo si hay entradas).
- Mantenimiento diario: {{MAINTENANCE_TIME}} (índice del diario + snapshot git).
- Actualización del starter: lunes {{UPDATE_TIME}}.
Estos valores son una foto de la instalación: para cambiarlos edita `⚙️ Meta/brain-config.json` y re-ejecuta
`bash install.sh <vault> --wire --with-schedule`.
