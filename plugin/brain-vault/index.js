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
//
// The config is user-edited, so nothing here trusts its shape: a malformed
// value degrades to the documented default instead of breaking every hook.

import { readFileSync } from "node:fs"
import { isAbsolute, join, relative, resolve } from "node:path"

const DEFAULTS = {
  vault_name: "mi-cerebro",
  language: "es",
  timezone: "UTC",
  journal: { time: "20:30", topics: ["all"], raw: true, gratitude: true },
  habits: [],
  accountability: [],
  extra_rules: [],
}

const TIME_PATTERN = /^([01]?\d|2[0-3]):[0-5]\d$/

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function stringList(value) {
  if (!Array.isArray(value)) return []
  return value.filter((item) => typeof item === "string" && item.trim()).map((item) => item.trim())
}

function safeTimeZone(value) {
  if (typeof value !== "string" || !value) return "UTC"
  try {
    new Intl.DateTimeFormat("en-CA", { timeZone: value }).format(new Date())
    return value
  } catch {
    return "UTC"
  }
}

function readConfig(vaultDir) {
  let raw = {}
  try {
    raw = JSON.parse(readFileSync(join(vaultDir, "⚙️ Meta", "brain-config.json"), "utf8"))
  } catch {
    raw = {}
  }
  if (!isObject(raw)) raw = {}
  const journal = isObject(raw.journal) ? raw.journal : {}
  return {
    ...DEFAULTS,
    ...raw,
    language: raw.language === "en" ? "en" : "es",
    timezone: safeTimeZone(raw.timezone),
    journal: {
      ...DEFAULTS.journal,
      ...journal,
      time: TIME_PATTERN.test(String(journal.time ?? "")) ? journal.time : DEFAULTS.journal.time,
    },
    habits: stringList(raw.habits),
    accountability: stringList(raw.accountability),
    extra_rules: stringList(raw.extra_rules),
  }
}

// Vault-relative path, POSIX separators, or "" when the file is outside the vault.
function vaultRelative(vaultDir, filePath) {
  if (!filePath) return ""
  const root = resolve(vaultDir)
  const absolute = isAbsolute(filePath) ? resolve(filePath) : resolve(root, filePath)
  const rel = relative(root, absolute)
  if (!rel || rel.startsWith("..") || isAbsolute(rel)) return ""
  return rel.split(/[\\/]+/).join("/")
}

const FOLDER_TYPES = [
  ["📓 Journals/", "journal"],
  ["👤 CRM/", "person"],
  ["⚙️ Meta/Sessions/", "session"],
  ["⚙️ Meta/Decisions/", "decision"],
  ["⚙️ Meta/", "note"],
  ["🏠 Home/", "note"],
  ["📝 Notes/", "note"],
  ["💼 Business/", "note"],
  ["🚀 I+D/", "note"],
]

function noteType(relPath) {
  const match = FOLDER_TYPES.find(([prefix]) => relPath.startsWith(prefix))
  return match ? match[1] : ""
}

function localDate(timeZone) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date())
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
      ...cfg.extra_rules.map((rule) => "- " + rule),
    ].join("\n")

    const closeNote =
      "\n\n[brain-vault] Señal de cierre detectada: antes de terminar ejecuta el cierre de sesión — guarda ⚙️ Meta/Sessions/<fecha-hora>.md (resumen y pendientes), registra decisiones en ⚙️ Meta/Decisions/ si las hay, compromete solo las rutas tocadas y despídete."
    const meetingNote =
      "\n\n[brain-vault] Disparador de reunión detectado: usa el flujo meeting-todos (o cierre-de-llamada si es llamada comercial) — extrae tareas con responsable y fecha, archívalas en el archivo de tareas canónico, guarda la nota en 💼 Business/Engagements/<cliente>/ si aplica y anota 'Filed to <tareas> on <fecha>' en la sección de action items."

    const sessionHook = typeof ctx?.session?.hook === "function" ? ctx.session.hook.bind(ctx.session) : null
    const toolHook = typeof ctx?.tool?.hook === "function" ? ctx.tool.hook.bind(ctx.tool) : null

    if (sessionHook) {
      await sessionHook("context", (event) => {
        if (Array.isArray(event?.system)) event.system.push({ type: "text", text: rules })
      })

      await sessionHook("prompt", (event) => {
        const text = String(event?.prompt?.text ?? "")
        if (!text) return
        if (meetingWords.test(text)) event.prompt.text = text + meetingNote
        else if (closeWords.test(text)) event.prompt.text = text + closeNote
      })
    } else {
      console.warn("[brain-vault] ctx.session.hook no está disponible; contexto y cierre inactivos")
    }

    if (!toolHook) {
      console.warn("[brain-vault] ctx.tool.hook no está disponible; frontmatter automático inactivo")
      return
    }

    await toolHook("execute.before", (event) => {
      const tool = String(event?.tool ?? "").toLowerCase()
      if (!tool.includes("write")) return
      const input = event.input
      if (!input || typeof input.content !== "string" || !input.content.trim()) return
      const path = String(input.filePath ?? input.file_path ?? input.path ?? input.file ?? "")
      const rel = vaultRelative(vault, path)
      if (!/\.(md|markdown)$/i.test(rel)) return
      const type = noteType(rel)
      if (!type) return
      if (input.content.trimStart().startsWith("---")) return
      input.content = `---\ntype: ${type}\ncreated: ${localDate(cfg.timezone)}\n---\n\n` + input.content
    })
  },
}
