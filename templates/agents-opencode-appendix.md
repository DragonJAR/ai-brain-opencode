## Adaptación OpenCode (generada por install.sh)

Se genera en la primera instalación, junto con el resto de `AGENTS.md`. Ninguna re-ejecución la sobrescribe: si necesitas regenerarla, borra `AGENTS.md` y vuelve a instalar.

### Idioma
Responde y escribe en {{LANGUAGE}}. Los nombres de carpeta quedan en inglés a propósito: los skills del sistema tienen rutas fijas y traducirlos genera carpetas duplicadas.

### Diario
- Compromiso: `/journal` a las {{JOURNAL_TIME}} ({{TIMEZONE}}).
- Hábitos trackeados: {{HABITS}}.
- Accountability: {{ACCOUNTABILITY}}.
- Cada entrada se etiqueta sola con su piso emocional (High-Rise, 34 niveles). Notas de piso en `⚙️ Meta/Floors/`. Tú nunca te autoetiquetas.

### Ruteo
- Trabajo con clientes o con la compañía → `💼 Business/` (un engagement = una carpeta en `Engagements/`).
- Investigación, herramientas propias, experimentos → `🚀 I+D/`.
- Reflexión personal → `📓 Journals/` y `🏠 Home/`.
- Si algo sirve a los dos frentes: se escribe en `🚀 I+D/` y se referencia desde `💼 Business/`.

### Dual-write
- Lo que valga entre sesiones termina como archivo del vault. La memoria indexada es un índice, no el archivo: si no está en el vault, no está.
- Nunca uses `git add -A` ni `git add .`: siempre rutas explícitas.
- Nunca inventes datos técnicos (CVE, versiones, IPs, salidas de herramientas): usa `MISSING` / `[PENDING_DATA]`.

### Sesión
- Inicio: lee este archivo y `⚙️ Meta/Sessions/` (última sesión).
- Cierre: el plugin `brain-vault` detecta la señal de cierre ("chao", "eso es todo"...) e inyecta el cascade: guarda `⚙️ Meta/Sessions/<fecha-hora>.md`, registra decisiones en `⚙️ Meta/Decisions/` y compromete solo las rutas tocadas.
- Verificación: `bash scripts/verify.sh`.

### Scheduler (si se instaló con `--with-schedule`)
Los horarios salen de `⚙️ Meta/brain-config.json`; los días son fijos.
- Recordatorio del diario: {{JOURNAL_TIME}} ({{TIMEZONE}}), de lunes a viernes — notificación del sistema operativo.
- Revisión semanal: domingo {{INSIGHTS_TIME}} (headless con `opencode run "/insights"`, solo si hay entradas).
- Mantenimiento diario: {{MAINTENANCE_TIME}} (índice del diario + snapshot git).
- Actualización del starter: lunes {{UPDATE_TIME}}.
