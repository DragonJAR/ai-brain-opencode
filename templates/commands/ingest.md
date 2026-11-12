---
description: "Compila las fuentes de 📝 Notes/Raw/ en notas enlazadas sin tocar el original"
---

# /ingest — Ingesta y compilación de fuentes crudas (Karpathy LLM Wiki)

Procesa documentos, transcripciones, lecturas o artículos depositados en `📝 Notes/Raw/` y los compila en conocimiento estructurado dentro del vault (`👤 CRM/`, `🚀 I+D/`, `💼 Business/`, `📝 Notes/`), tejiendo wikilinks bidireccionales y preservando la fuente original intacta.

## Entrada
- Si el usuario proporciona un argumento (ej: `/ingest ruta/al/archivo.pdf` o `/ingest https://...`):
  - Guarda o copia la fuente en `📝 Notes/Raw/<nombre-descriptivo>.ext`.
  - Procede a compilar esa fuente específica.
- Si no proporciona argumentos (`/ingest`):
  - Revisa todos los archivos presentes en `📝 Notes/Raw/` y sus subcarpetas (excluyendo `.gitkeep`).
  - Consulta `⚙️ Meta/logs/ingest.log` para identificar qué fuentes aún no han sido procesadas.

## Protocolo de Compilación

1. **Lectura profunda de la fuente**:
   - Lee el contenido completo del documento raw sin alterar el archivo original. Las fuentes en `📝 Notes/Raw/` son inmutables para garantizar trazabilidad.

2. **Extracción y enrutamiento estructurado**:
   - **Personas y contactos** → Crea o actualiza `👤 CRM/<Nombre>.md` (rol, organización, temas tratados, fecha).
   - **Herramientas e investigación tecnológica** → Crea o actualiza `🚀 I+D/Herramientas/<Herramienta>.md` o `🚀 I+D/Investigación/<Tema>.md`.
   - **Proyectos y oportunidades comerciales** → Actualiza o crea `💼 Business/Engagements/<Proyecto>.md`.
   - **Conceptos y notas de síntesis** → Crea `📝 Notes/<Concepto>.md` con las ideas fundamentales, aplicaciones prácticas y contexto.

3. **Interconexión con Wikilinks**:
   - Cada nota generada o actualizada debe contener enlaces `[[...]]` hacia conceptos relacionados, personas o proyectos ya existentes en el vault.
   - Enlaza bidireccionalmente la nota conceptual con la fuente cruda usando `[[📝 Notes/Raw/<archivo>]]`.

4. **Registro inmutable en log**:
   - Añade una entrada al final de `⚙️ Meta/logs/ingest.log` con el siguiente formato:
     ```markdown
     ## [YYYY-MM-DD HH:MM] ingest | <fuente> -> <destinos>
     - Síntesis: <resumen de una o dos oraciones>
     - Notas creadas/actualizadas: [[Nota1]], [[Nota2]]
     ```
   - `<fuente>` es la ruta exacta del archivo en el vault (ej. `📝 Notes/Raw/articulo.pdf`): `/audit` compara ese nombre exacto para saber qué queda pendiente. Este log se versiona con el vault; los logs de los trabajos no.

5. **Salida al usuario**:
   - Muestra un reporte conciso con las notas creadas, actualizadas y los wikilinks generados.
