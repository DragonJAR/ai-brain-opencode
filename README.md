# ai-brain-opencode

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux%20%7C%20Windows%20%7C%20WSL2-green.svg)](docs/COMPAT.md)
[![Author](https://img.shields.io/badge/author-DragonJAR%20SAS-orange.svg)](https://www.dragonjar.org)
[![Español](https://img.shields.io/badge/read%20in-Espa%C3%B1ol-blue.svg)](README.es.md)

A personal second brain for **OpenCode V2**: a markdown vault on your disk (journal, notes, CRM, meta) that the AI
reads and writes. One installer clones the [ai-brain-starter](https://github.com/mycelium-hq/ai-brain-starter)
skills and commands into the vault, adapts them to OpenCode, and adds a project plugin. No database, no mandatory
cloud, and no personal data in this package.

## Requirements

| Need | Notes |
|---|---|
| [OpenCode](https://opencode.ai/docs) V2 with a configured model | The runtime; see [docs/COMPAT.md](docs/COMPAT.md) |
| `git` and `bash` | Clones the starter and humanizer; makes the vault's first commit (needs `user.name` / `user.email`) |
| Python 3.9+ (`python3`, `py -3` or `python`) | The installer checks the version |
| macOS, Linux, WSL2 or Windows (Git Bash) | Windows also needs `cygpath`; Developer Mode is not required |
| Node, Obsidian (optional) | `node --check` on the plugin; `--with-obsidian` (macOS/Linux) |

## Install

```bash
git clone https://github.com/DragonJAR/ai-brain-opencode.git
cd ai-brain-opencode
bash install.sh ~/path/to/my-brain
```

The vault path is **always explicit**. Does not automatically detect vaults or modify OpenCode global configuration. Running it again is safe: your content is never overwritten. Then restart OpenCode (or run `/reload`) on the vault.

| Flag | Effect |
|---|---|
| `--config <file>` | Seed `⚙️ Meta/brain-config.json` from your JSON (default: `templates/brain-config.example.json`) |
| `--with-mcp` | Add the remote MCP servers `granola` and `chatprd` to the vault's `opencode.json` (opt-in: they receive your conversation when used) |
| `--with-schedule` | Register the scheduled jobs (see below) |
| `--with-obsidian` | Install the Obsidian community plugins (macOS/Linux) |
| `--wire` | Only re-wire an existing vault (no clone, no scaffold) |
| `--update [vault]` | Update this package checkout (see [Updating](#updating)) |
| `--dry-run` | Check the requirements and print the plan; the vault is not touched |
| `--version` / `--help` | Print the version / the usage (exit 0) |

`--yes` / `-y` is accepted and does nothing: the installer never prompts. A usage error exits 2 in every script.

## What gets created

| In the vault | Purpose |
|---|---|
| `📓 Journals`, `🏠 Home`, `👤 CRM`, `📝 Notes` (+ `Raw`), `💼 Business/Engagements`, `🚀 I+D/…`, `⚙️ Meta/…` | Folder layout, defined once in `scripts/lib/vault_layout.py` |
| `.opencode/skills/` | The starter clone, its skills (links; copies on Windows) and humanizer |
| `.opencode/commands/` | Starter commands as OpenCode-adapted copies, plus the package commands |
| `.opencode/plugins/brain-vault/` | Plugin: per-turn context, close signal, meeting trigger, frontmatter on new notes |
| `AGENTS.md` (+ `CLAUDE.md`: a link, a copy on Windows) | The brain's memory; OpenCode reads it every session |
| `⚙️ Meta/brain-config.json` | Your settings (see [Configuration](#configuration)) |
| `scripts/` (`verify.sh`, `audit.py`, `jobs/`, `lib/`) | Health check, audit, jobs; they run without the package checkout |
| `.opencode/brain-vault-install-manifest.json` | What the package owns, by hash, for a safe uninstall |
| `opencode.json` | Only with `--with-mcp` |

## Commands and skills

Type these in an OpenCode session opened on the vault. The 17 starter commands are copies rewritten for OpenCode on
every platform (they use the `skill` tool and suggest `bash scripts/jobs/update-brain.sh` when a skill is missing).
Each forwards to a skill of the same workflow; all starter skills and `humanizer` sit in `.opencode/skills/`.

| Command | What it does |
|---|---|
| **Journal & meetings** | |
| `/daily-journal` | Journal interview and entry, with emotional-floor tagging |
| `/insights` | Weekly or monthly journal insights: patterns and panel feedback |
| `/meeting-todos` | Pull action items from a meeting note into the right to-do file |
| `/cierre` | After a sales call: CRM, tasks, email draft, reminder, coaching |
| **Vault & knowledge** | |
| `/diagnose` | Self-check of the install: instructions file, Meta folders, skills, hooks, MCPs |
| `/setup-vault-types` | Choose the document types your vault uses and scaffold extractors |
| `/second-brain-mapping` | Structured metadata per typed file, cross-document insights, optional graph |
| `/graphify` | Clustered knowledge graph with HTML and JSON output |
| `/optimize-brain` | Deep optimization: CRM, graphs, dashboards, compression, wikilinks |
| **Patterns & ideas** | |
| `/patterns` | Recurring patterns in recent sessions, turned into rules, concept notes or writing seeds |
| `/deconstruct` | First-principles analysis: hidden assumptions, foundational truths, rebuild |
| `/evolve` | Cluster hardened instincts into a proposed command, skill or agent |
| `/instinct-export` | Export the instinct library to a portable YAML pack |
| `/instinct-import` | Import a YAML instinct pack with a confidence-gated merge |
| **Content** | |
| `/humanizer` | Strip AI-isms from prose and rewrite it in your voice |
| `/repurpose-talk` | Turn a talk into 10–30 pieces of content |
| `/nano-banana` | Generate or edit images with Google's Gemini Image model |
| **Package commands** | |
| `/today` | Daily briefing: journal state, last session, client commitments, follow-ups |
| `/ingest` | Compile sources from `📝 Notes/Raw/` into vault notes; the source stays untouched |
| `/audit` | Deterministic audit: broken wikilinks, orphan notes, untyped markdown, pending sources |
| `/ideas` | Cross-domain pattern discovery over Business, I+D, Notes and Journals |
| `/create` | Content drafting from vault context in your voice, humanizer-strict |

## Scheduled jobs

Installed with `--with-schedule`, or later with `bash scripts/schedule.sh <vault>` (also `--dry-run`, `--remove`,
`--remove --dry-run`). Re-run it after changing the times.

| Job | Default | When |
|---|---|---|
| `journal-reminder.sh` | `20:30` | Monday–Friday |
| `insights-weekly.sh` | `21:00` | Sunday |
| `daily-maintenance.sh` | `03:30` | Every day (commits only `snapshot_paths`) |
| `update-brain.sh` | `08:00` | Monday (updates the vendor skills) |

| OS | Scheduler |
|---|---|
| macOS | launchd. A launch agent cannot read `Documents`, `Desktop`, `Downloads` or iCloud Drive (TCC): `schedule.sh` warns; move the vault or give `/bin/bash` Full Disk Access |
| Linux | cron. On WSL2 start it with `sudo service cron start` (the installer warns) |
| Windows | schtasks, through `scripts/jobs/ai-brain-run.cmd` |

Each job writes `⚙️ Meta/logs/<job>.log` (rotated at 1 MiB) and never overlaps itself. Times use the host clock;
`timezone` only affects the dates the plugin renders. Jobs keep the `PATH` of the shell that scheduled them.

## Configuration

`⚙️ Meta/brain-config.json`, strict JSON (no comments). Invalid values fall back to the default with a warning;
`install.sh --config` shows the same warnings.

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

| Key | Meaning |
|---|---|
| `vault_name`, `language`, `timezone`, `habits`, `accountability`, `schedule.*` | Written into `AGENTS.md` at install |
| `language`, `timezone`, `journal.time`, `habits`, `extra_rules` | Context the plugin adds each turn |
| `journal.topics`, `journal.raw`, `journal.gratitude` | Journal preferences (validated; defaults shown above) |
| `journal.time`, `schedule.*` | Job times, `HH:MM` |
| `snapshot_paths` | What `daily-maintenance` commits. Vault-relative paths only: `.`, `..`, `.git`, absolute paths, `C:`, a leading `-` or `:`, `\` and `*?[` are dropped. If none is left, the default list is used; an explicit `[]` commits nothing |

## Updating

| What | How |
|---|---|
| This package | `bash install.sh --update [vault]` from your checkout |
| Vendor skills (starter, humanizer) | The `update-brain.sh` job, or `bash <vault>/scripts/jobs/update-brain.sh` |

`--update` runs `git pull --ff-only` only from `https://github.com/DragonJAR/ai-brain-opencode`, then re-wires the
vault if you pass it (`--with-schedule` is allowed). It refuses, and changes nothing, when the checkout is not a git
clone, `origin` is another repository, `HEAD` is detached, the branch does not track `origin`, there are local
changes, or the pull is not a fast-forward.

`update-brain.sh` never updates the package: it pulls the starter and humanizer (fast-forward only), regenerates the
floors and re-wires; command copies you did not edit are refreshed. A clone pinned with `BRAIN_STARTER_PIN=<sha>` is
left alone.

## Verify

```bash
bash <vault>/scripts/verify.sh    # structure, links, config, plugin, ownership; exits 1 on any ✗
bash tests/run.sh                 # package test suite
```

Neither starts OpenCode, so they cannot prove the plugin hooks load at runtime ([docs/COMPAT.md](docs/COMPAT.md)).

## Uninstall

```bash
bash uninstall.sh ~/path/to/my-brain --dry-run        # list what would go, including scheduled jobs
bash uninstall.sh ~/path/to/my-brain                  # remove
bash uninstall.sh ~/path/to/my-brain --purge-clones   # also the vendor clones
```

Only unchanged files the manifest proves the package installed are removed; files you edited and foreign links stay
and are reported. Without a valid manifest it refuses and removes nothing. `--purge-clones` drops `ai-brain-starter`
and `humanizer` only while they still point at their origin and have no local changes.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `falta OpenCode CLI`, install aborts | Put `opencode` on `PATH` (the vault was not touched) |
| Jobs never run on WSL2 | `sudo service cron start` |
| A job cannot find `opencode` or Python | Re-run `bash scripts/schedule.sh <vault>` from a shell that has them |
| macOS job fails on a vault in `Documents` | TCC: move the vault or grant Full Disk Access (see above) |
| `bad interpreter: bash\r` | CRLF checkout; clone on a Linux filesystem inside WSL2 |
| Plugin ignores the config | The folder must be `⚙️ Meta` (with the emoji variation selector) |
| `archivo modificado o no verificado, preservado` | Expected: you edited the file, so uninstall keeps it |
| `ya existe una tarea ajena` / `launch agent ajeno` | Another vault with the same folder name owns that entry; rename one |

## More

- Platform status and runtime limits: [docs/COMPAT.md](docs/COMPAT.md). Windows is covered by simulated tests;
  real-hardware reports are welcome.
- Changes per version: [CHANGELOG.md](CHANGELOG.md).
- Privacy check before a release: `bash scripts/check-personal-data.sh`.

## License

MIT — see [LICENSE](LICENSE). Third-party components keep their own terms: [NOTICE.md](NOTICE.md).

*An adaptation to OpenCode V2 of [ai-brain-starter](https://github.com/mycelium-hq/ai-brain-starter) (mycelium-hq).*

**DragonJAR SAS** · [dragonjar.org](https://www.dragonjar.org)
