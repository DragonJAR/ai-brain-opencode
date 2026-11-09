// brain-vault — OpenCode V2 plugin for the ai-brain-starter second brain.
//
// Data-driven: every personal value comes from the vault's config file
// (<vault>/⚙️ Meta/brain-config.json). No personal data lives in this file.
//
// Uses only documented OpenCode APIs:
//   ctx.session.hook("prompt")       <- Claude Code UserPromptSubmit
//   ctx.session.hook("context")      <- Claude Code SessionStart context injection
//   ctx.tool.hook("execute.before")  <- Claude Code PreToolUse (mutates tool input)
// Blocking semantics are NOT assumed: they are not part of the documented API.

import { appendFileSync, existsSync, readFileSync } from "node:fs"
import { join } from "node:path"

const DEFAULTS = {
  language: "es",
  timezone: "UTC",
  journal: { time: "20:30", topics: ["all"], raw: true, gratitude: true },
  habits: [],
  accountability: [],
  extra_rules: [],
}

function readConfig(vaultDir) {
  try {
    const raw = readFileSync(join(vaultDir, "⚙️ Meta", "brain-config.json"), "utf8")
    return { ...DEFAULTS, ...JSON.parse(raw) }
  } catch {
    return DEFAULTS
  }
}

export default {
  id: "brain-vault",
  async setup(ctx) {
    const vault = ctx?.location?.directory || process.cwd()
    const cfg = readConfig(vault)

    const closeWords =
      cfg.language === "es"
        ? /\b(chao|adi[oó]s|buenas noches|hasta ma[nñ]ana|nos vemos|eso es todo|eso es todo por hoy|gracias eso es todo|terminamos por hoy|cerramos por hoy|me voy)\b/i
        : /\b(bye|good\s?night|see you|that'?s all|that is all|wrap up|we'?re done)\b/i
    const meetingWords =
      cfg.language === "es"
        ? /\b(acabo de tener una (reuni[oó]n|llamada|junta)|tuve una (reuni[oó]n|llamada)|termin[oó] la (reuni[oó]n|llamada)|reuni[oó]n terminada)\b/i
        : /\b(just had a (meeting|call)|meeting (is )?(done|just ended))\b/i

    const rules = [
      "[brain-vault] Reglas del vault (aplican siempre):",
      "- Antes de crear archivos revisa el Vault Map y ⚙️ Meta/Folder Resolvers/. Nunca dupliques carpetas ni notas.",
      "- Toda nota nueva lleva frontmatter con `type:` (journal, person, note, decision, session...).",
      "- Nunca uses `git add -A` ni `git add .`: siempre rutas explícitas.",
      "- Nunca inventes datos técnicos (CVE, versiones, IPs, salidas de herramientas): usa MISSING / [PENDING_DATA].",
      "- Responde en el idioma del vault (" + cfg.language + ") y con criterio de no-despedida: lo accionable primero, sin relleno.",
      "- Diario: " + cfg.journal.time + " (" + cfg.timezone + "); hábitos trackeados: " + (cfg.habits.join(", ") || "ninguno") + ".",
      ...(cfg.extra_rules || []).map((r) => "- " + r),
    ].join("\n")

    const closeNote =
      "\n\n[brain-vault] Señal de cierre detectada: antes de terminar ejecuta el cierre de sesión — guarda ⚙️ Meta/Sessions/<fecha-hora>.md (resumen y pendientes), registra decisiones en ⚙️ Meta/Decisions/ si las hay, compromete solo las rutas tocadas y despídete."
    const meetingNote =
      "\n\n[brain-vault] Disparador de reunión detectado: usa el flujo meeting-todos (o cierre-de-llamada si es llamada comercial) — extrae tareas con responsable y fecha, archívalas en el archivo de tareas canónico, guarda la nota en 💼 Business/Engagements/<cliente>/ si aplica y anota 'Filed to <tareas> on <fecha>' en la sección de action items."

    await ctx.session.hook("context", (event) => {
      event.system.push({ type: "text", text: rules })
    })

    await ctx.session.hook("prompt", (event) => {
      const text = String(event.prompt?.text ?? "")
      if (!text) return
      if (meetingWords.test(text)) event.prompt.text = text + meetingNote
      else if (closeWords.test(text)) event.prompt.text = text + closeNote
    })

    await ctx.tool.hook("execute.before", (event) => {
      const tool = String(event.tool ?? "").toLowerCase()
      if (!tool.includes("write")) return
      const input = event.input
      if (!input || typeof input.content !== "string" || !input.content.trim()) return
      const path = String(input.filePath ?? input.file_path ?? input.path ?? input.file ?? "")
      if (!/\.(md|markdown)$/i.test(path)) return
      if (!/(Journals|Notes|CRM|Business|Home|I\+D|Meta)\//.test(path)) return
      if (input.content.trimStart().startsWith("---")) return
      const d = new Date().toISOString().slice(0, 10)
      input.content = `---\ntype: note\ncreated: ${d}\n---\n\n` + input.content
    })
  },
}
