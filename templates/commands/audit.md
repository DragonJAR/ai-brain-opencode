---
description: "Audita la integridad del vault: enlaces rotos, notas huérfanas, frontmatter y fuentes crudas pendientes"
---

# /audit — Auditoría de Integridad Estructural del Vault

Ejecuta el auditor determinista del vault (`scripts/audit.py`) para detectar y resolver inconsistencias: enlaces rotos, notas huérfanas, markdown sin frontmatter tipado y fuentes crudas pendientes.

## Instrucciones de Ejecución

1. **Ejecutar el script de auditoría**:
   - Corre en terminal:
     ```bash
     python3 scripts/audit.py . --json
     ```
   - Si `scripts/audit.py` no estuviera disponible en el vault, usa la versión del paquete o ejecuta la inspección determinista de enlaces y frontmatter.

2. **Analizar los resultados**:
   - **Enlaces rotos (`broken_links`)**: Revisa los enlaces `[[destino]]` que apuntan a archivos inexistentes.
     - Si es una errata en el nombre del enlace, propón la corrección inmediata.
     - Si es un concepto o persona relevante que aún no tiene nota, ofrece crear un archivo base (stub) con frontmatter tipado.
   - **Notas huérfanas (`orphan_notes`)**: Notas de contenido en `📝 Notes/`, `👤 CRM/`, `🚀 I+D/` o `💼 Business/` sin enlaces entrantes.
     - Sugiere enlaces contextuales desde notas índice (`🏠 Home/`, dashboards) o notas temáticas afines.
   - **Notas sin tipar (`untyped_notes`)**: Archivos markdown sin `type:` en su frontmatter YAML.
     - Ofrece agregar el bloque YAML correspondiente según su carpeta (`journal`, `person`, `note`, `session`, `decision`).
   - **Fuentes raw pendientes (`pending_raw`)**: Archivos en `📝 Notes/Raw/` no registrados en `⚙️ Meta/logs/ingest.log`.
     - Sugiere ejecutar `/ingest` para procesarlos.

3. **Presentación**:
   - Presenta al usuario un diagnóstico claro y priorizado, indicando qué acciones automáticas o guiadas se recomiendan para mantener el vault en perfecto estado.
