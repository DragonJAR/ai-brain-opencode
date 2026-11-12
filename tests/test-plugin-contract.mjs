#!/usr/bin/env node
// Contract test for plugin/brain-vault/index.js — no OpenCode runtime required.
// It exercises the documented hook surface with a mock ctx and a malformed config.

import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { pathToFileURL } from "node:url"

const PKG = process.argv[2]
if (!PKG) {
  console.error("FAIL: falta la ruta del paquete")
  process.exit(2)
}

const root = mkdtempSync(join(tmpdir(), "ai-brain-plugin-test."))
let failures = 0
const fail = (message) => {
  console.error("FAIL: " + message)
  failures += 1
}
const ok = (condition, message) => {
  if (!condition) fail(message)
}

function makeVault(name, config) {
  const vault = join(root, name)
  for (const dir of ["⚙️ Meta", "📓 Journals", "👤 CRM", "📝 Notes", "🏠 Home", "💼 Business", "🚀 I+D", "⚙️ Meta/Sessions", "⚙️ Meta/Decisions"]) {
    mkdirSync(join(vault, dir), { recursive: true })
  }
  if (config !== undefined) {
    writeFileSync(join(vault, "⚙️ Meta", "brain-config.json"), typeof config === "string" ? config : JSON.stringify(config), "utf8")
  }
  return vault
}

async function load(vault) {
  const hooks = { context: [], prompt: [], "execute.before": [] }
  const add = (name, fn) => { (hooks[name] ||= []).push(fn) }
  const ctx = {
    location: { directory: vault },
    session: { hook: async (name, fn) => add(name, fn) },
    tool: { hook: async (name, fn) => add(name, fn) },
  }
  const module = await import(pathToFileURL(join(PKG, "plugin", "brain-vault", "index.js")).href + "?v=" + encodeURIComponent(vault))
  await module.default.setup(ctx)
  return hooks
}

try {
  // 1. Default config: context rules, close/meeting prompt hooks, frontmatter typing.
  const vault = makeVault("default", {
    vault_name: "test-brain",
    language: "es",
    timezone: "Etc/UTC",
    journal: { time: "21:15" },
    habits: ["agua", "caminar"],
    extra_rules: ["Regla extra del operador"],
  })
  const hooks = await load(vault)
  ok(hooks.context.length === 1, "context hook registrado")
  ok(hooks.prompt.length === 1, "prompt hook registrado")
  ok(hooks["execute.before"].length === 1, "tool hook registrado")

  const contextEvent = { system: [] }
  hooks.context[0](contextEvent)
  const rules = contextEvent.system.map((item) => item.text).join("\n")
  ok(rules.includes("21:15"), "las reglas incluyen la hora del diario configurada")
  ok(rules.includes("agua, caminar"), "las reglas incluyen los hábitos configurados")
  ok(rules.includes("Regla extra del operador"), "las reglas incluyen extra_rules")

  const closing = { prompt: { text: "chao" } }
  hooks.prompt[0](closing)
  ok(closing.prompt.text.includes("Señal de cierre detectada"), "la señal de cierre inyecta el cascade")

  const closingPunct = { prompt: { text: "eso es todo por hoy." } }
  hooks.prompt[0](closingPunct)
  ok(closingPunct.prompt.text.includes("Señal de cierre detectada"), "el cierre con puntuación y sufijo largo se detecta")

  const closingNfc = { prompt: { text: "adio\u0301s" } }
  hooks.prompt[0](closingNfc)
  ok(closingNfc.prompt.text.includes("Señal de cierre detectada"), "acentos NFD descompuestos se detectan tras normalizar")

  const meeting = { prompt: { text: "acabo de tener una reunión" } }
  hooks.prompt[0](meeting)
  ok(meeting.prompt.text.includes("Disparador de reunión detectado"), "el disparador de reunión inyecta el flujo")

  const plain = { prompt: { text: "arregla el bug del parser" } }
  hooks.prompt[0](plain)
  ok(plain.prompt.text === "arregla el bug del parser", "un prompt normal no se modifica")

  // Falsos positivos clásicos: saludo o frase en mitad del mensaje no es cierre.
  const greeting = { prompt: { text: "buenas noches, vamos a revisar el plan" } }
  hooks.prompt[0](greeting)
  ok(greeting.prompt.text === "buenas noches, vamos a revisar el plan", "un saludo inicial no dispara el cierre")

  const midphrase = { prompt: { text: "me voy a explicarte el flujo completo" } }
  hooks.prompt[0](midphrase)
  ok(midphrase.prompt.text === "me voy a explicarte el flujo completo", "'me voy a...' en medio del mensaje no dispara el cierre")

  const longText = "chao. " + "contexto largo ".repeat(80)
  const longClose = { prompt: { text: longText } }
  hooks.prompt[0](longClose)
  ok(longClose.prompt.text === longText, "un mensaje largo no se trata como cierre")

  const longMeeting = { prompt: { text: "acabo de tener una reunión " + "y además ".repeat(80) } }
  hooks.prompt[0](longMeeting)
  ok(longMeeting.prompt.text.includes("Disparador de reunión detectado"), "el disparador de reunión no tiene límite de largo")

  const cases = [
    ["📓 Journals/2026-11-10.md", "journal"],
    ["👤 CRM/ana.md", "person"],
    ["⚙️ Meta/Sessions/2026-11-10-0900.md", "session"],
    ["⚙️ Meta/Decisions/2026-11-10.md", "decision"],
    ["📝 Notes/idea.md", "note"],
  ]
  const hook = hooks["execute.before"][0]
  for (const [rel, type] of cases) {
    const event = { tool: "Write", input: { filePath: join(vault, ...rel.split("/")), content: "# hola" } }
    await hook(event)
    ok(event.input.content.startsWith("---\ntype: " + type), `frontmatter type=${type} para ${rel}`)
    ok(/^---\ntype: [a-z]+\ncreated: \d{4}-\d{2}-\d{2}\n---\n\n# hola$/.test(event.input.content), `frontmatter bien formado para ${rel}`)
  }

  const raw = { tool: "write", input: { filePath: join(vault, "📝 Notes", "Raw", "fuente.md"), content: "# fuente" } }
  await hook(raw)
  ok(raw.input.content === "# fuente", "una fuente nueva en 📝 Notes/Raw/ se guarda intacta (inmutable)")

  const outside = { tool: "write", input: { filePath: join(root, "otro-lugar", "nota.md"), content: "# fuera" } }
  await hook(outside)
  ok(outside.input.content === "# fuera", "una ruta fuera del vault no recibe frontmatter")

  const existing = { tool: "write", input: { filePath: join(vault, "📝 Notes", "ya.md"), content: "---\ntype: note\n---\n# ya" } }
  await hook(existing)
  ok(existing.input.content === "---\ntype: note\n---\n# ya", "un archivo con frontmatter no se reescribe")

  const thematic = { tool: "write", input: { filePath: join(vault, "📝 Notes", "regla.md"), content: "----\nun separador, no frontmatter" } }
  await hook(thematic)
  ok(thematic.input.content.startsWith("---\ntype: note"), "un separador temático que no es frontmatter sí recibe frontmatter")

  const onDisk = join(vault, "📝 Notes", "vieja.md")
  writeFileSync(onDisk, "# nota que ya existe", "utf8")
  const overwrite = { tool: "write", input: { filePath: onDisk, content: "# reescritura sin frontmatter" } }
  await hook(overwrite)
  ok(overwrite.input.content === "# reescritura sin frontmatter", "sobrescribir un archivo existente no añade frontmatter")

  const notMarkdown = { tool: "write", input: { filePath: join(vault, "📝 Notes", "datos.json"), content: "{}" } }
  await hook(notMarkdown)
  ok(notMarkdown.input.content === "{}", "un archivo que no es markdown no se toca")

  // 2. Malformed config: wrong types and an invalid timezone must not break setup.
  const broken = makeVault("broken", {
    language: "fr",
    timezone: "Mars/Base",
    journal: "no-es-un-objeto",
    habits: "agua",
    accountability: null,
    extra_rules: { a: 1 },
  })
  const brokenHooks = await load(broken)
  const brokenContext = { system: [] }
  brokenHooks.context[0](brokenContext)
  const brokenRules = brokenContext.system.map((item) => item.text).join("\n")
  ok(brokenRules.includes("20:30"), "una hora inválida cae al valor por defecto 20:30")
  ok(brokenRules.includes("hábitos trackeados: ninguno"), "hábitos con tipo inválido degradan a 'ninguno'")
  ok(brokenRules.includes("idioma del vault (es)"), "un idioma no soportado degrada a es")

  const brokenWrite = { tool: "write", input: { filePath: join(broken, "📓 Journals", "x.md"), content: "# x" } }
  await brokenHooks["execute.before"][0](brokenWrite)
  ok(/created: \d{4}-\d{2}-\d{2}/.test(brokenWrite.input.content), "una zona horaria inválida cae a UTC sin romper el hook")

  // 3. A directory without brain-config.json is not a vault of this package:
  // the plugin must stay inactive instead of mutating foreign writes.
  const missing = makeVault("missing")
  const warns = []
  const originalWarn2 = console.warn
  console.warn = (message) => warns.push(String(message))
  let missingHooks
  try {
    missingHooks = await load(missing)
  } finally {
    console.warn = originalWarn2
  }
  ok(missingHooks.context.length === 0 && missingHooks.prompt.length === 0 && missingHooks["execute.before"].length === 0,
     "sin brain-config.json el plugin no registra hooks")
  ok(warns.some((w) => w.includes("no es un vault del paquete")), "la inactividad por falta de config se anuncia")

  // 4. Missing hook API degrades gracefully (on a real vault, with config).
  const noHooksVault = makeVault("no-hooks", { language: "es" })
  const module = await import(pathToFileURL(join(PKG, "plugin", "brain-vault", "index.js")).href + "?v=no-hooks")
  let threw = false
  const originalWarn = console.warn
  console.warn = () => {}
  try {
    await module.default.setup({ location: { directory: noHooksVault } })
  } catch {
    threw = true
  } finally {
    console.warn = originalWarn
  }
  ok(!threw, "un runtime sin ctx.session.hook no rompe el setup")

  // 5. Close signals: questions are not farewells; ellipsis, emoji and curly apostrophes are.
  const closeCases = [
    [hooks, "chao…", true],
    [hooks, "nos vemos 👋", true],
    [hooks, "buenas noches 🌙✨", true],
    [hooks, "¿ya terminamos por hoy?", false],
    [hooks, "¿eso es todo?", false],
    [hooks, "eso es todo? 🤔", false],
    [hooks, "nachao", false],
  ]
  const enHooks = await load(makeVault("english", { language: "en" }))
  closeCases.push(
    [enHooks, "that’s all", true],
    [enHooks, "we’re done!", true],
    [enHooks, "bye 👋🏽", true],
    [enHooks, "are we done?", false],
    [enHooks, "that's all?", false],
  )
  for (const [target, text, expected] of closeCases) {
    const event = { prompt: { text } }
    target.prompt[0](event)
    const fired = event.prompt.text !== text
    ok(fired === expected, `${JSON.stringify(text)} ${expected ? "debe" : "no debe"} disparar el cierre`)
  }

  // 6. The tool hook replaces the input instead of mutating the caller's object.
  const original = { filePath: join(vault, "📝 Notes", "reemplazo.md"), content: "# nueva" }
  const replaced = { tool: "write", input: original }
  await hook(replaced)
  ok(original.content === "# nueva", "el input original no se muta")
  ok(replaced.input !== original && replaced.input.content.startsWith("---\ntype: note"), "el hook reemplaza event.input con el frontmatter")

  // 7. patch: every new note in a typed folder gets frontmatter; Raw, existing, typed and non-md files do not.
  const patchText = [
    "*** Begin Patch",
    "*** Add File: 📝 Notes/desde-patch.md",
    "+# Desde patch",
    "+cuerpo",
    "*** Add File: 📝 Notes/Raw/fuente-patch.md",
    "+# fuente",
    "*** Add File: 👤 CRM/con-fm.md",
    "+---",
    "+type: person",
    "+---",
    "+# ya tipada",
    "*** Add File: 📝 Notes/datos.txt",
    "+texto",
    "*** Update File: 📝 Notes/vieja.md",
    "@@",
    "-# nota que ya existe",
    "+# nota editada",
    "*** End Patch",
  ].join("\n")
  const patchInput = { patchText }
  const patchEvent = { tool: "patch", input: patchInput }
  await hook(patchEvent)
  const patched = String(patchEvent.input?.patchText ?? "")
  ok(patchInput.patchText === patchText, "el input original del patch no se muta")
  ok(/\*\*\* Add File: 📝 Notes\/desde-patch\.md\n\+---\n\+type: note\n\+created: \d{4}-\d{2}-\d{2}\n\+---\n\+\n\+# Desde patch\n/.test(patched),
     "patch: una nota nueva recibe frontmatter")
  ok(patched.includes("*** Add File: 📝 Notes/Raw/fuente-patch.md\n+# fuente\n"), "patch: una fuente en Raw queda intacta")
  ok(patched.includes("*** Add File: 👤 CRM/con-fm.md\n+---\n+type: person\n+---\n"), "patch: una nota con frontmatter no se duplica")
  ok(patched.includes("*** Add File: 📝 Notes/datos.txt\n+texto\n"), "patch: un archivo que no es markdown no se toca")
  ok(patched.includes("*** Update File: 📝 Notes/vieja.md\n@@\n-# nota que ya existe\n+# nota editada\n"), "patch: una actualización no se toca")
  ok((patched.match(/\+type: /g) || []).length === 2, "patch: solo la nota nueva gana frontmatter")
  const applyPatch = { tool: "apply_patch", input: { patchText: "*** Begin Patch\n*** Add File: 📓 Journals/2026-01-02.md\n+hoy\n*** End Patch" } }
  await hook(applyPatch)
  ok(applyPatch.input.patchText.includes("+type: journal"), "apply_patch (nombre de v1) también recibe frontmatter")

  // 8. edit never creates a file in OpenCode v2 (empty oldString and missing files are rejected): left untouched.
  const editInput = { path: join(vault, "📝 Notes", "no-existe.md"), oldString: "", newString: "# nueva" }
  const editEvent = { tool: "edit", input: editInput }
  await hook(editEvent)
  ok(editEvent.input === editInput && editInput.newString === "# nueva", "edit se deja intacto")
} finally {
  rmSync(root, { recursive: true, force: true })
}

if (failures > 0) {
  console.error(`FAIL: plugin contract had ${failures} failed assertions`)
  process.exit(1)
}
console.log("PASS: plugin contract (config hardening, prompt hooks, frontmatter, degradation)")
