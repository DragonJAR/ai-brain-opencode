---
description: "Redacta contenido desde el vault con el skill humanizer, sin prosa de IA"
---

# /create — Redacción Auténtica de Contenido (Humanizer)

Redacta piezas de contenido (artículos, notas técnicas, memos ejecutivos, newsletters o publicaciones) a partir del contexto del vault, aplicando estrictamente las directrices del skill `humanizer` para erradicar cualquier rastro de prosa artificial o clichés de IA.

## Entrada
- `/create [tema, nota del vault o instrucción]`
- Si se referencia una nota (ej: `/create [[📝 Notes/MiConcepto.md]]`), extrae los puntos clave, citas y evidencia técnica de dicha nota.

## Reglas de Redacción (Filosofía Humanizer)

1. **Cero Clichés de IA**:
   - Prohibido usar frases vacías como: "En el vertiginoso mundo actual", "sumergirse en", "un cambio de juego" (game changer), "es un testimonio de", "más crucial que nunca", "tapiz", "navegar el paisaje".
   - Prohibido el abuso de preguntas retóricas como encabezados o introducciones artificiales.

2. **Densidad de Información y Evidencia Real**:
   - Comienza directo en el núcleo del argumento o problema, sin calentamientos ni resúmenes introductorios superfluos.
   - Apóyate en datos concretos, compensaciones técnicas (trade-offs) y ejemplos específicos presentes en el vault.
   - Muestra las dificultades, costos y matices reales; evita conclusiones complacientes donde todo es positivo.

3. **Cadencia y Ritmo Natural**:
   - Alterna oraciones cortas e incisivas con explicaciones compuestas bien hiladas.
   - Escribe con voz enérgica, activa y con un punto de vista definido. Habla como un operador experimentado conversando con un colega de alto nivel.

4. **Flujo de Ejecución**:
   - 1. Identifica el tema y busca las notas pertinentes en el vault (`📝 Notes/`, `🚀 I+D/`, `💼 Business/`).
   - 2. Redacta el borrador completo en la voz solicitada.
   - 3. Pregunta al usuario si desea guardar la pieza en `📝 Notes/<titulo>.md` o exportarla a otro formato.
