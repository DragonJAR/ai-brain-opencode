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

import { existsSync, readFileSync } from "node:fs"
import { isAbsolute, join, relative, resolve } from "node:path"

const DEFAULTS = {
  vault_name: "mi-cerebro",
  language: "es",
  timezone: "UTC",
  journal: { time: "20:30", topics: ["all"], raw: true, gratitude: true },
  habits: [],
  accountability: [],
  extra_rules: [],
  // Lo que confirma el snapshot diario (lo lee daily-maintenance.sh, no el plugin).
  snapshot_paths: ["📓 Journals", "⚙️ Meta/Sessions", "⚙️ Meta/Decisions", "⚙️ Meta/journal-index.json"],
  schedule: {
    insights_time: "21:00",
    maintenance_time: "03:30",
    update_time: "08:00",
  },
}

const TIME_PATTERN = /^([01]?\d|2[0-3]):[0-5]\d$/

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function stringList(value) {
  if (!Array.isArray(value)) return []
  return value.filter((item) => typeof item === "string" && item.trim()).map((item) => item.trim())
}

function readConfig(vaultDir) {
  let raw = {}
  let isCorrupt = false
  let corruptReason = ""

  try {
    const content = readFileSync(join(vaultDir, "⚙️ Meta", "brain-config.json"), "utf8")
    try {
      raw = JSON.parse(content)
      if (!isObject(raw)) {
        isCorrupt = true
        corruptReason = "el contenido raíz no es un objeto JSON"
        raw = {}
      }
    } catch (err) {
      isCorrupt = true
      corruptReason = err instanceof Error ? err.message : String(err)
      raw = {}
    }
  } catch (err) {
    if (err && err.code !== "ENOENT") {
      isCorrupt = true
      corruptReason = err instanceof Error ? err.message : String(err)
    }
    raw = {}
  }

  const issues = []
  if (isCorrupt) {
    issues.push(`archivo corrupto o ilegible (${corruptReason})`)
  }

  let timezone = DEFAULTS.timezone
  if (typeof raw.timezone === "string" && raw.timezone) {
    try {
      new Intl.DateTimeFormat("en-CA", { timeZone: raw.timezone }).format(new Date())
      timezone = raw.timezone
    } catch {
      issues.push(`timezone inválida '${raw.timezone}'`)
    }
  }

  const journal = isObject(raw.journal) ? raw.journal : {}
  let journalTime = DEFAULTS.journal.time
  if (journal.time !== undefined) {
    const val = String(journal.time ?? "")
    if (TIME_PATTERN.test(val)) {
      journalTime = journal.time
    } else {
      issues.push(`journal.time inválida '${journal.time}'`)
    }
  }

  const schedule = isObject(raw.schedule) ? raw.schedule : {}

  if (issues.length > 0) {
    console.warn(`[brain-vault] Advertencia en ⚙️ Meta/brain-config.json (${issues.join(", ")}); usando valores por defecto`)
  }

  // Allowlist, never a blind spread: unknown or malformed keys cannot leak
  // into consumers of this config.
  return {
    vault_name: typeof raw.vault_name === "string" && raw.vault_name.trim() ? raw.vault_name : DEFAULTS.vault_name,
    language: raw.language === "en" ? "en" : "es",
    timezone,
    journal: {
      time: journalTime,
      topics: stringList(journal.topics).length > 0 ? stringList(journal.topics) : [...DEFAULTS.journal.topics],
      raw: journal.raw === false ? false : DEFAULTS.journal.raw,
      gratitude: journal.gratitude === false ? false : DEFAULTS.journal.gratitude,
    },
    schedule: {
      insights_time: TIME_PATTERN.test(String(schedule.insights_time ?? "")) ? schedule.insights_time : DEFAULTS.schedule.insights_time,
      maintenance_time: TIME_PATTERN.test(String(schedule.maintenance_time ?? "")) ? schedule.maintenance_time : DEFAULTS.schedule.maintenance_time,
      update_time: TIME_PATTERN.test(String(schedule.update_time ?? "")) ? schedule.update_time : DEFAULTS.schedule.update_time,
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

const stripVS16 = (str) => String(str ?? "").replace(/\uFE0F/g, "")

const FOLDER_TYPES = [
  ["📓 Journals/", "journal"],
  ["👤 CRM/", "person"],
  ["⚙️ Meta/Sessions/", "session"],
  ["⚙️ Meta/Decisions/", "decision"],
  ["⚙️ Meta/", "note"],
  ["🏠 Home/", "note"],
  // Raw sources are immutable: an empty type leaves them untouched.
  ["📝 Notes/Raw/", ""],
  ["📝 Notes/", "note"],
  ["💼 Business/", "note"],
  ["🚀 I+D/", "note"],
].map(([prefix, type]) => [stripVS16(prefix), type])

function noteType(relPath) {
  if (!relPath) return ""
  const normalized = stripVS16(relPath)
  const match = FOLDER_TYPES.find(([prefix]) => normalized.startsWith(prefix))
  return match ? match[1] : ""
}

// Real frontmatter, not a markdown thematic break that merely starts with "---".
const FRONTMATTER_PATTERN = /^---\r?\n[\s\S]*?\r?\n---/

export default {
  id: "brain-vault",
  async setup(ctx) {
    let vault = ctx?.location?.directory
    if (!vault) {
      vault = process.cwd()
      console.warn(`[brain-vault] ctx.location.directory no provisto; usando cwd como vault (${vault})`)
    }

    // No config file = not a vault of this package. Registering hooks here
    // would mutate writes in unrelated projects.
    const configFile = join(vault, "⚙️ Meta", "brain-config.json")
    if (!existsSync(configFile)) {
      console.warn(`[brain-vault] sin ${configFile}; este directorio no es un vault del paquete y el plugin queda inactivo`)
      return
    }

    const cfg = readConfig(vault)

    let dateFormatter
    try {
      dateFormatter = new Intl.DateTimeFormat("en-CA", {
        timeZone: cfg.timezone,
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
      })
    } catch {
      dateFormatter = new Intl.DateTimeFormat("en-CA", {
        timeZone: "UTC",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
      })
    }

    // Close signals must END the message and the message must be short:
    // "buenas noches, empecemos" o "me voy a explicarte el bug" no son cierres.
    // Longest-first: "eso es todo por hoy" antes que "eso es todo".
    const closeWords =
      cfg.language === "es"
        ? /(?:chao|adi[oó]s|buenas noches|hasta ma[nñ]ana|nos vemos|eso es todo por hoy|gracias eso es todo|eso es todo|terminamos por hoy|cerramos por hoy|me voy)\s*[.!?...]*\s*$/i
        : /(?:bye|good\s?night|see you|that'?s all|that is all|wrap up|we'?re done)\s*[.!?...]*\s*$/i
    const CLOSE_MAX_LENGTH = 400
    const meetingWords =
      cfg.language === "es"
        ? /\b(acabo de tener una (reuni[oó]n|llamada|junta)|tuve una (reuni[oó]n|llamada)|termin[oó] la (reuni[oó]n|llamada)|reuni[oó]n terminada)\b/i
        : /\b(just had a (meeting|call)|meeting (is )?(done|just ended))\b/i

    const isEn = cfg.language === "en"

    const rules = isEn
      ? [
          "[brain-vault] Vault rules (always apply):",
          "- Before creating files review the Vault Map and ⚙️ Meta/Folder Resolvers/. Never duplicate folders or notes.",
          "- Every new note must include frontmatter with `type:` (journal, person, note, decision, session...).",
          "- Never use `git add -A` or `git add .`: always use explicit paths.",
          "- Never invent technical data (CVEs, versions, IPs, tool outputs): use MISSING / [PENDING_DATA].",
          "- Respond in the vault language (en) with an actionable-first, no-filler criterion.",
          "- Journal: " + cfg.journal.time + " (" + cfg.timezone + "); tracked habits: " + (cfg.habits.join(", ") || "none") + ".",
          ...cfg.extra_rules.map((rule) => "- " + rule),
        ].join("\n")
      : [
          "[brain-vault] Reglas del vault (aplican siempre):",
          "- Antes de crear archivos revisa el Vault Map y ⚙️ Meta/Folder Resolvers/. Nunca dupliques carpetas ni notas.",
          "- Toda nota nueva lleva frontmatter con `type:` (journal, person, note, decision, session...).",
          "- Nunca uses `git add -A` ni `git add .`: siempre rutas explícitas.",
          "- Nunca inventes datos técnicos (CVE, versiones, IPs, salidas de herramientas): usa MISSING / [PENDING_DATA].",
          "- Responde en el idioma del vault (" + cfg.language + ") y con criterio de no-despedida: lo accionable primero, sin relleno.",
          "- Diario: " + cfg.journal.time + " (" + cfg.timezone + "); hábitos trackeados: " + (cfg.habits.join(", ") || "ninguno") + ".",
          ...cfg.extra_rules.map((rule) => "- " + rule),
        ].join("\n")

    const closeNote = isEn
      ? "\n\n[brain-vault] Close signal detected: before finishing run the session close cascade — save ⚙️ Meta/Sessions/<date-time>.md (summary and pending items), record decisions in ⚙️ Meta/Decisions/ if any, commit only touched paths and say goodbye."
      : "\n\n[brain-vault] Señal de cierre detectada: antes de terminar ejecuta el cierre de sesión — guarda ⚙️ Meta/Sessions/<fecha-hora>.md (resumen y pendientes), registra decisiones en ⚙️ Meta/Decisions/ si las hay, compromete solo las rutas tocadas y despídete."

    const meetingNote = isEn
      ? "\n\n[brain-vault] Meeting trigger detected: run the meeting-todos workflow (or client-call-close if it is a sales call) — extract tasks with owner and due date, file them into the canonical tasks file, save the note under 💼 Business/Engagements/<client>/ if applicable, and record 'Filed to <tasks> on <date>' in the action items section."
      : "\n\n[brain-vault] Disparador de reunión detectado: usa el flujo meeting-todos (o cierre-de-llamada si es llamada comercial) — extrae tareas con responsable y fecha, archívalas en el archivo de tareas canónico, guarda la nota en 💼 Business/Engagements/<cliente>/ si aplica y anota 'Filed to <tareas> on <fecha>' en la sección de action items."

    const sessionHook = typeof ctx?.session?.hook === "function" ? ctx.session.hook.bind(ctx.session) : null
    const toolHook = typeof ctx?.tool?.hook === "function" ? ctx.tool.hook.bind(ctx.tool) : null

    // Each registration stands alone: a runtime rejecting one event name must
    // not disable the other hooks.
    if (sessionHook) {
      try {
        await sessionHook("context", (event) => {
          if (Array.isArray(event?.system)) event.system.push({ type: "text", text: rules })
        })

        await sessionHook("prompt", (event) => {
          const text = String(event?.prompt?.text ?? "").normalize("NFC")
          if (!text) return
          if (meetingWords.test(text)) {
            event.prompt.text = text + meetingNote
          } else if (text.length <= CLOSE_MAX_LENGTH && closeWords.test(text.trim())) {
            event.prompt.text = text + closeNote
          }
        })
      } catch (err) {
        console.warn("[brain-vault] ctx.session.hook rechazó el registro; contexto y cierre inactivos: " + (err instanceof Error ? err.message : String(err)))
      }
    } else {
      console.warn("[brain-vault] ctx.session.hook no está disponible; contexto y cierre inactivos")
    }

    if (!toolHook) {
      console.warn("[brain-vault] ctx.tool.hook no está disponible; frontmatter automático inactivo")
      return
    }

    try {
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
        // Only NEW notes get frontmatter (COMPAT scope); overwrites of existing
        // files are left exactly as the author wrote them.
        if (existsSync(resolve(vault, rel))) return
        if (FRONTMATTER_PATTERN.test(input.content.trimStart())) return
        input.content = `---\ntype: ${type}\ncreated: ${dateFormatter.format(new Date())}\n---\n\n` + input.content
      })
    } catch (err) {
      console.warn("[brain-vault] ctx.tool.hook rechazó el registro; frontmatter automático inactivo: " + (err instanceof Error ? err.message : String(err)))
    }
  },
}
