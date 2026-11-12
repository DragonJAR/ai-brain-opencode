---
description: "Entrevista de configuración: personaliza AGENTS.md y brain-config.json"
---

# /setup-brain — Entrevista de configuración del cerebro

Personaliza este vault ya instalado. El paquete ya creó la estructura, los skills, el plugin y los trabajos: aquí solo se completa lo que es del usuario.

No cargues el skill `ai-brain-starter` (el `setup-brain` del vendor): está escrito para Claude Code y reinstalaría herramientas que este vault ya tiene de otra forma.

## Qué hacer

1. **Lee el estado actual**: `AGENTS.md` y `⚙️ Meta/brain-config.json`. Pregunta solo por lo que falte o siga con el texto de la plantilla.

2. **Entrevista, una pregunta a la vez** y esperando cada respuesta:
   - Quién es y a qué se dedica (sección `## Me`).
   - En qué está enfocado estas semanas (`## Current Focus`).
   - Personas clave y su relación (`## People`).
   - Términos propios de su trabajo (`## Key Terms`) y herramientas que usa (`## Tools I Use`).
   - Idioma de trabajo, zona horaria (formato IANA, p. ej. `Europe/Madrid`) y hora del diario (`HH:MM`).
   - Hábitos que quiere seguir y sobre qué quiere que se le exija cuentas.

3. **Escribe las respuestas**:
   - En `AGENTS.md`, solo en esas secciones personales y en las líneas de "Idioma" y "Diario" de la adaptación OpenCode. No toques las reglas ni el Vault Map.
   - En `⚙️ Meta/brain-config.json`: `language`, `timezone`, `journal.time`, `habits`, `accountability`. Debe seguir siendo JSON estricto; conserva las demás claves tal como están.
   - Si `CLAUDE.md` no es un enlace a `AGENTS.md` (Windows), copia `AGENTS.md` sobre `CLAUDE.md`.

4. **Comprueba**: ejecuta `bash scripts/verify.sh` y corrige lo que marque sobre la configuración.

5. **Cierra** con un resumen de lo que quedó escrito y dos avisos:
   - Si cambió la hora del diario y hay trabajos programados, hay que reprogramarlos desde el checkout del paquete: `bash install.sh <vault> --wire --with-schedule`.
   - El siguiente paso es la primera entrada del diario: `/daily-journal`.
