---
description: "Briefing del día: diario, última sesión, compromisos y seguimientos"
---

# /today — Briefing Ejecutivo Diario

Genera un plan de acción y resumen ejecutivo para el día, cruzando el estado del diario personal, la última sesión de trabajo, compromisos de clientes y seguimientos de personas.

## Flujo de Información

1. **Recuperación de contexto**:
   - Revisa `📓 Journals/` (la entrada de hoy o la más reciente) para capturar el estado mental, reflexiones recientes y tareas pendientes.
   - Revisa `⚙️ Meta/Sessions/` (la sesión más reciente) para identificar dónde se detuvo el trabajo y qué temas quedaron abiertos.
   - Revisa `💼 Business/Engagements/` para identificar proyectos activos, fechas límite y entregables comprometidos.
   - Revisa `👤 CRM/` para detectar seguimientos a clientes, socios o contactos clave.

2. **Estructura del Informe**:
   Presenta al usuario un briefing conciso y de alto impacto:
   - **🎯 Foco del Día (Top 3)**: Las tres prioridades críticas con mayor apalancamiento para hoy.
   - **🔄 Continuidad Operativa**: Resumen directo de dónde quedó la última sesión y cuál es el hilo de ejecución a retomar.
   - **👥 Personas y Compromisos**: Llamadas, respuestas pendientes o seguimientos en `💼 Business/` y `👤 CRM/`.
   - **⚡ Acción Inmediata**: La primera tarea específica para comenzar con inercia positiva en los próximos 15 minutos.

3. **Tono y Estilo**:
   - Directo, estratégico y libre de palabrería corporativa o introducciones innecesarias.
   - Incluye wikilinks `[[...]]` a las notas y personas mencionadas para navegación rápida en Obsidian.
