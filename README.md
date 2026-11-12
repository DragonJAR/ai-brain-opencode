# ai-brain-opencode

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux%20%7C%20Windows%20%7C%20WSL2-green.svg)](docs/COMPAT.md)
[![Author](https://img.shields.io/badge/author-DragonJAR%20SAS-orange.svg)](https://www.dragonjar.org)
[![Español](https://img.shields.io/badge/read%20in-Espa%C3%B1ol-blue.svg)](README.es.md)

> A personal second brain: a markdown vault on your disk, driven by OpenCode V2—no mandatory cloud, no personal data in the package.

## What this is

- A **markdown vault on your machine** (journals, notes, CRM, meta)—the AI reads and writes files you own.
- **OpenCode V2** as the runtime (not Claude Code); see [docs/COMPAT.md](docs/COMPAT.md).
- One **installer** that clones vendor skills, wires relative symlinks, and installs a project plugin—**no personal data** ships in this repo.
- **No required database or SaaS**: optional remote MCP only if you pass `--with-mcp`.

## What gets installed

| In the vault | Purpose |
|---|---|
| Folder tree (`📓 Journals/`, `🏠 Home/`, `👤 CRM/`, `📝 Notes/`, `💼 Business/`, `🚀 I+D/`, `⚙️ Meta/`) | Canonical layout for notes and meta |
| `.opencode/skills/ai-brain-starter/` (+ skill/command symlinks) | Vendor starter clone; skills/commands are relative links |
| `.opencode/plugins/brain-vault/index.js` | OpenCode plugin (context, close signal, meeting trigger, frontmatter) |
| `AGENTS.md` (+ `CLAUDE.md` → `AGENTS.md`) | Per-session brain memory; OpenCode reads it each session |
| `⚙️ Meta/brain-config.json` | Language, timezone, journal time, habits, schedule times |
| `scripts/verify.sh`, `scripts/audit.py`, `scripts/jobs/*.sh` | Health check, integrity audit, scheduled jobs |
| `scripts/lib/` (`ownership.py`, `wire.py`, `brain_config.py`, `common.sh`, `python3.sh`, `brain-config.defaults.json`) | Shared libraries: the vault verifies itself, runs its jobs and re-wires a starter update without the package checkout |
| `.opencode/brain-vault-install-manifest.json` | Ownership fingerprints for safe uninstall |
| `opencode.json` | **Only** with `--with-mcp` (remote MCP servers) |

## Requirements

| Need | Why |
|---|---|
| [OpenCode](https://opencode.ai/docs) with a configured model | Runtime that loads the vault and plugin |
| Git | Clone starter + humanizer; vault bootstrap commit |
| Python 3.9+ (`python3`, `py -3` or `python` on `PATH`) | Installer, ownership and journal helpers (the installer validates the version) |
| Node (optional) | Lets the installer syntax-check the plugin with `node --check`; the version is not validated |
| macOS, Linux, WSL2 Ubuntu, or Windows native (Git Bash) | POSIX: symlinks + launchd/cron · Windows: file copies + **schtasks** |
| Obsidian (optional) | Browse the vault; `--with-obsidian` installs five community plugins |

## Install

```bash
git clone https://github.com/DragonJAR/ai-brain-opencode.git
cd ai-brain-opencode
bash install.sh ~/path/to/my-brain
```

The vault path is **always explicit**. Does not automatically detect vaults or modify OpenCode global configuration. The installer does not edit `~/.config/opencode/opencode.json`.

| Flag | Effect |
|---|---|
| `--config <file>` | Seed `⚙️ Meta/brain-config.json` from a JSON file |
| `--wire` | Re-link an existing vault after starter updates (no clone/scaffold; may combine with `--with-schedule`) |
| `--with-mcp` | Add remote MCP servers `granola` + `chatprd` into vault `opencode.json` (sends conversation when used—opt-in) |
| `--with-obsidian` | Install five Obsidian community plugins under `.obsidian/plugins/` (macOS/Linux only) |
| `--with-schedule` | Register scheduled jobs (launchd on macOS, cron on Linux, schtasks on Windows) |

| `--dry-run` | Check the requirements and print the plan; the vault is not touched |

Also accepted: `--help` / `-h`, `--version`, and `--yes` / `-y` (no prompts; installer is non-interactive).

Update the starter by hand, then re-wire. Without `--with-schedule` nothing updates on its own; with it, the weekly `update-brain.sh` job pulls the starter and humanizer (fast-forward only) and re-wires what changed. A clone pinned with `BRAIN_STARTER_PIN=<sha>` is never pulled:

```bash
BRAIN_STARTER_UPDATE=1 bash install.sh ~/path/to/my-brain
bash install.sh ~/path/to/my-brain --wire
```

## Verify

```bash
bash tests/run.sh                 # package regression suite
bash <vault>/scripts/verify.sh    # vault health: structure, symlinks, config, plugin, ownership
```

`<vault>/scripts/verify.sh` prints `✓` / `✗` and **exits 1** if any check fails. Package tests and vault verify **do not** start OpenCode V2 or prove hooks loaded in a live runtime (`docs/COMPAT.md`). After install: restart OpenCode or run `/reload` so it picks up `.opencode/plugins/`.

## Daily use

The installer copies the plugin to `<vault>/.opencode/plugins/brain-vault/index.js`. OpenCode loads project plugins from `.opencode/plugins/` (and globals from `~/.config/opencode/plugins/`). If the runtime lacks a hook API, the plugin **warns and degrades** (`ctx.session.hook` / `ctx.tool.hook` missing)—it does not crash the session.

| Behavior | Source of truth |
|---|---|
| Context rules each turn | `brain-config.json` (`language`, `journal.time`, `timezone`, `habits`, `extra_rules`) |
| Close-signal cascade | Prompt words like “chao” / “that’s all” (language-aware) |
| Meeting trigger | Phrases like “just had a meeting” → meeting-todos workflow |
| Auto frontmatter on new markdown | Folder-based `type:` + `created:` before writes |

## Slash commands

The 17 commands below ship with ai-brain-starter and the installer wires them into your vault as
`.opencode/commands/*.md` (relative symlinks on macOS/Linux/WSL2, copies on Windows). Type them in an
OpenCode session opened on the vault; each forwards to its skill, which the installer already installed
— no bootstrap step needed.

| Command | What it does |
|---|---|
| **Journal & meetings** | |
| `/daily-journal` | Daily journal interview and entry creator, with emotional-floor tagging |
| `/insights` | Weekly or monthly journal insights: pattern recognition and panel feedback |
| `/meeting-todos` | Extract action items from a meeting note and route them to the right to-do file |
| `/cierre` | A sales call just ended: full follow-up — CRM, tasks, email draft, reminder, coaching |
| `/today` | Executive daily briefing cross-referencing journal, active sessions, engagements and CRM |
| **Vault & knowledge** | |
| `/diagnose` | Self-check of the install (instructions file, Meta folders, skills, hooks, MCPs) |
| `/setup-vault-types` | Configure which document types your vault uses and scaffold extractors |
| `/second-brain-mapping` | Map the vault: structured metadata per typed file, cross-doc insights, optional graph |
| `/graphify` | Turn the vault into a clustered knowledge graph with HTML and JSON outputs |
| `/optimize-brain` | Deep vault optimization: CRM, graphs, dashboards, compression, wikilinks |
| `/ingest` | Ingest raw sources from `📝 Notes/Raw/` into compiled knowledge notes with wikilinks |
| `/audit` | Deterministic vault audit: broken wikilinks, orphan notes, untyped markdown, pending raw |
| **Patterns & ideas** | |
| `/patterns` | Scan recent sessions for recurring patterns and turn them into captures (rules, concept notes, writing seeds) |
| `/deconstruct` | First-principles analyst: surface hidden assumptions, find foundational truths, rebuild |
| `/evolve` | Cluster hardened instincts into a proposed command / skill / agent (Instinct Engine) |
| `/instinct-export` | Export the instinct library to a portable YAML pack (Instinct Engine) |
| `/instinct-import` | Import a portable YAML instinct pack with confidence-gated merge (Instinct Engine) |
| `/ideas` | Cross-domain pattern discovery across Business, I+D, and Notes |
| **Content** | |
| `/humanizer` | Strip AI-isms from external prose and rewrite in your actual voice |
| `/repurpose-talk` | Turn a speaking engagement into 10–30 pieces of content |
| `/nano-banana` | Generate or edit images using Google's Gemini Image model |
| **Package commands (this repo)** | |
| `/create` | Authentic content drafting from vault context (humanizer-strict, zero AI clichés) |
| `/today` | Daily executive briefing: journal state, last session, client commitments, people follow-ups |
| `/ingest` | Compile raw sources from `📝 Notes/Raw/` into structured vault knowledge, keeping the source intact |
| `/audit` | Deterministic vault integrity audit: broken wikilinks, orphan notes, untyped markdown, pending raw sources |
| `/ideas` | Cross-domain pattern discovery and synthesis over Business, I+D, Notes and Journals |

## Configuration

Seeded as `⚙️ Meta/brain-config.json` from `templates/brain-config.example.json` (strict JSON, not JSONC):

```json
{
  "vault_name": "mi-cerebro",
  "language": "es",
  "timezone": "UTC",
  "journal": {
    "time": "20:30",
    "topics": [
      "all"
    ],
    "raw": true,
    "gratitude": true
  },
  "habits": [],
  "accountability": [],
  "extra_rules": [],
  "snapshot_paths": [
    "📓 Journals",
    "⚙️ Meta/Sessions",
    "⚙️ Meta/Decisions",
    "⚙️ Meta/journal-index.json"
  ],
  "schedule": {
    "insights_time": "21:00",
    "maintenance_time": "03:30",
    "update_time": "08:00"
  }
}
```

## Scheduled jobs

Defaults from `templates/brain-config.example.json` and `scripts/schedule.sh`:

| Job | Default time | When |
|---|---|---|
| `journal-reminder.sh` | `20:30` | Monday–Friday |
| `insights-weekly.sh` | `21:00` | Sunday |
| `daily-maintenance.sh` | `03:30` | Every day |
| `update-brain.sh` | `08:00` | Monday |

`daily-maintenance.sh` commits only the paths listed in `snapshot_paths` (add `👤 CRM`, `📝 Notes`… if you want them in the daily snapshot); anything else you staged yourself is left alone. Each job writes to `⚙️ Meta/logs/`, rotates its log at 1 MiB and never overlaps a run of itself. Jobs keep the `PATH` of the shell that scheduled them, so re-run the scheduler after moving `opencode` or Python.

Times fire in the **host system timezone**; `timezone` in `brain-config.json` governs the dates the
plugin renders, not the scheduler clock.

```bash
bash scripts/schedule.sh ~/path/to/my-brain --dry-run   # show jobs; no launchd/cron writes
bash scripts/schedule.sh ~/path/to/my-brain             # install, or re-apply after editing the times
bash scripts/schedule.sh ~/path/to/my-brain --remove    # remove only verified owned entries
```

On **WSL2**, cron does not start by itself: `sudo service cron start` (installer warns when WSL is detected).

## Platforms

| Platform | Support |
|---|---|
| macOS | Full: symlinks + **launchd** |
| Linux | Full: symlinks + **cron** |
| WSL2 (Ubuntu) | Supported inside WSL; start **cron** manually (`sudo service cron start`) |
| Windows native (Git Bash) | Implemented: **file copies** (no package symlinks) + **schtasks**. Needs `git`, Python ≥3.9, `bash`, `cygpath`, and `opencode run --help`. Developer Mode is **not** required. Evidence: covered by simulated Windows fixtures (`uname`/`schtasks` mocks); real-hardware validation is still pending, so please open an issue if something breaks. WSL2 remains a fine alternative. |

## Uninstall

```bash
bash uninstall.sh ~/path/to/my-brain
bash uninstall.sh ~/path/to/my-brain --purge-clones
bash uninstall.sh ~/path/to/my-brain --dry-run        # list what would go; remove nothing
```

Removes only **unchanged owned** artifacts from the install manifest. Modified files, foreign symlinks, and ambiguous items are **preserved** and reported. `--purge-clones` also drops the vendor clones (`ai-brain-starter`, `humanizer`) while they still point at their origin and have no local changes.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `falta OpenCode CLI` then abort | `opencode` missing from `PATH` (vault untouched) |
| Jobs never run on WSL2 | Cron inactive → `sudo service cron start` |
| `archivo modificado o no verificado, preservado` on uninstall | You edited the file, or filesystem mode drift (e.g. DrvFs)—expected safety |
| `bad interpreter: bash\r` | CRLF checkout; use a Linux filesystem inside WSL2 |
| Plugin ignores config | Folder named `⚙ Meta` (no VS16) ≠ `⚙️ Meta` |
| A scheduled job cannot find `opencode` | It was scheduled from a shell without it on `PATH` → re-run `bash scripts/schedule.sh <vault>` from one that has it |
| `ya existe una tarea ajena` / `launch agent ajeno` | Another vault with the same folder name already owns that schedule entry; rename one of the folders |
| `propiedad de cron heredada o no soportada` | Manifest from an early version, never migrated automatically: remove its scheduled entries by hand, delete `.opencode/brain-vault-install-manifest.json`, then re-run `install.sh` |
| `refusing to modify a symlinked… opencode.json` / missing git identity | Regular `opencode.json` required for `--with-mcp`; set `user.name` / `user.email` before install |

## Privacy

- No operator personal data in the package; run `bash scripts/check-personal-data.sh`.
- MCP remotes are **opt-in** (`--with-mcp`) and send conversation content when those servers are used.
- Your vault content stays on disk under the path you pass to `install.sh`.

## Structure

```
ai-brain-opencode/
├── install.sh · uninstall.sh
├── plugin/brain-vault/index.js
├── scripts/{schedule,verify,check-personal-data}.sh · scripts/audit.py
├── scripts/lib/{ownership,wire,brain_config}.py · scripts/lib/{common,python3}.sh
├── templates/brain-config.example.json
├── templates/commands/*.md
├── templates/jobs/*.sh
├── tests/run.sh · .github/workflows/ci.yml
├── VERSION · CHANGELOG.md
└── docs/COMPAT.md
```

## License + Author

MIT — see [LICENSE](LICENSE). Third-party systems keep their own terms — [NOTICE.md](NOTICE.md).

*An adaptation to OpenCode V2 of [ai-brain-starter](https://github.com/mycelium-hq/ai-brain-starter) (mycelium-hq).*

**DragonJAR SAS** · [dragonjar.org](https://www.dragonjar.org)

[Español](README.es.md)
