# ai-brain-opencode

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Linux%20%7C%20Windows%20%7C%20WSL2-green.svg)](docs/COMPAT.md)
[![Author](https://img.shields.io/badge/author-DragonJAR%20SAS-orange.svg)](https://www.dragonjar.org)
[![Español](https://img.shields.io/badge/read%20in-Espa%C3%B1ol-blue.svg)](README.es.md)

A personal second brain for **OpenCode V2**: a markdown vault on your disk (journal, notes, CRM) that the AI reads
and writes. The installer brings the [ai-brain-starter](https://github.com/mycelium-hq/ai-brain-starter) skills into
the vault, adapts them to OpenCode and adds a plugin. No database, no mandatory cloud, no personal data in the package.

## Install

You need [OpenCode](https://opencode.ai/docs) V2 with a model configured, `git` (with `user.name` / `user.email`),
`bash` and Python 3.9+. Works on macOS, Linux, WSL2 and Windows (Git Bash).

```bash
git clone https://github.com/DragonJAR/ai-brain-opencode.git
cd ai-brain-opencode
bash install.sh ~/path/to/my-brain
```

The vault path is always explicit. Does not automatically detect vaults or modify OpenCode global configuration.
Running it again is safe: your content is never overwritten.

| Flag | Effect |
|---|---|
| `--with-schedule` | Register the scheduled jobs (reminder, weekly insights, daily snapshot, skills update) |
| `--with-mcp` | Add the remote MCP servers `granola` and `chatprd` (opt-in: they receive your conversation when used) |
| `--with-obsidian` | Install the Obsidian community plugins (macOS/Linux) |
| `--config <file>` | Seed the vault config from your own JSON |
| `--wire` | Only re-wire an existing vault |
| `--update [vault]` | Update this package (see [Update](#update)) |
| `--dry-run` | Check the requirements and print the plan; nothing is touched |

## First steps

1. Open OpenCode on the vault (restart it, or run `/reload`, after installing).
2. `/setup-brain` — a short interview that fills in `AGENTS.md` and your config.
3. `/daily-journal` tonight. The first entry gets the system going.
4. `bash <vault>/scripts/verify.sh` whenever you want a health check.

## Commands

| Command | What it does |
|---|---|
| **Journal & meetings** | |
| `/daily-journal` (`/journal`) | Journal interview and entry, tagged with its emotional floor |
| `/insights` | Weekly or monthly patterns in your journal |
| `/meeting-todos` | Action items from a meeting note into the right to-do file |
| `/cierre` | After a sales call: CRM, tasks, email draft, reminder |
| `/today` | Daily briefing: journal, last session, commitments, follow-ups |
| **Vault & knowledge** | |
| `/setup-brain` | Personalize `AGENTS.md` and the config |
| `/ingest` | Compile sources in `📝 Notes/Raw/` into linked notes; the source stays untouched |
| `/audit` | Broken wikilinks, orphan notes, untyped notes, pending sources |
| `/diagnose` | The starter's self-check (written for Claude Code; for this vault prefer `verify.sh` and `/audit`) |
| `/setup-vault-types` | Choose the document types your vault uses |
| `/second-brain-mapping` | Structured metadata and cross-document insights |
| `/graphify` | Knowledge graph of the vault (HTML and JSON); installs the `graphify` Python package |
| `/optimize-brain` | Deep clean-up: CRM, graphs, dashboards, wikilinks |
| **Patterns & ideas** | |
| `/patterns` | Recurring patterns in recent sessions, turned into rules and notes |
| `/ideas` | Connections across Business, I+D, Notes and Journals |
| `/deconstruct` | First-principles analysis of an idea |
| `/evolve` | Turn hardened instincts into a command, skill or agent |
| `/instinct-export` | Export the instinct library to YAML |
| `/instinct-import` | Import an instinct pack |
| **Content** | |
| `/create` | Draft content from vault context, in your voice |
| `/humanizer` | Strip AI-isms from a text |
| `/repurpose-talk` | Turn a talk into 10–30 pieces of content |
| `/nano-banana` | Generate or edit images with Gemini; needs your Gemini API key |

The plugin also works without commands: it adds your rules to every turn, saves the session when you say goodbye,
offers the meeting workflow when you mention a meeting, and types new notes by folder.

The starter skills were written for Claude Code. `AGENTS.md` tells the model how to read them here, and the
starter's own installer skill is hidden with a permission rule in the vault's `opencode.json`.

## Configuration

`⚙️ Meta/brain-config.json`, strict JSON. An invalid value falls back to its default with a warning.

```json
{
  "vault_name": "mi-cerebro",
  "language": "es",
  "timezone": "UTC",
  "journal": {
    "time": "20:30",
    "topics": ["all"],
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
| `language`, `timezone`, `habits`, `extra_rules` | Context the plugin adds each turn (`extra_rules`: your own standing rules) |
| `journal.time`, `schedule.*` | Job times, `HH:MM`, on the host clock |
| `snapshot_paths` | Vault-relative paths the daily snapshot commits; add `👤 CRM` or `📝 Notes` to include them |

After changing a time, re-apply the schedule: `bash install.sh <vault> --wire --with-schedule`.

## Scheduled jobs

With `--with-schedule` (launchd on macOS, cron on Linux, schtasks on Windows). Each writes `⚙️ Meta/logs/<job>.log`.

| Job | Default | What it does |
|---|---|---|
| `journal-reminder` | 20:30, Mon–Fri | Desktop notification |
| `insights-weekly` | 21:00, Sunday | Runs the weekly insights headless |
| `daily-maintenance` | 03:30, daily | Journal index and a git snapshot of `snapshot_paths` |
| `update-brain` | 08:00, Monday | Refreshes the starter skills and humanizer |

Preview or remove them with `bash scripts/schedule.sh <vault> --dry-run` / `--remove`.

## Update

```bash
bash install.sh --update ~/path/to/my-brain
```

The package updates **only** from `https://github.com/DragonJAR/ai-brain-opencode`: `--update` runs
`git pull --ff-only` on this checkout and re-wires the vault. It refuses, and changes nothing, if `origin` is any
other repository, the checkout has local changes, or the pull is not a fast-forward.

The starter skills and humanizer are third-party content, not the tool: the `update-brain` job refreshes them from
their own repositories. It never touches the package.

## Uninstall

```bash
bash uninstall.sh ~/path/to/my-brain --dry-run   # list what would go
bash uninstall.sh ~/path/to/my-brain             # add --purge-clones to drop the starter and humanizer too
```

Only unchanged files the package installed are removed. Your notes, `AGENTS.md`, your config and anything you
edited stay.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `falta OpenCode CLI` | Put `opencode` on `PATH`; the vault was not touched |
| A job cannot find `opencode` or Python | Re-run `bash scripts/schedule.sh <vault>` from a shell that has them |
| macOS job fails on a vault in `Documents`, `Desktop` or iCloud | Move the vault, or give `/bin/bash` Full Disk Access |
| Jobs never run on WSL2 | `sudo service cron start` |
| Plugin ignores the config | The folder must be `⚙️ Meta`, emoji variation selector included |
| `ya existe una tarea ajena` / `launch agent ajeno` | Another vault has the same folder name; rename one |

More: platform status and limits in [docs/COMPAT.md](docs/COMPAT.md), changes in [CHANGELOG.md](CHANGELOG.md).
Windows is covered by simulated tests only; real-hardware reports are welcome.

## License

MIT — see [LICENSE](LICENSE). Third-party components keep their own terms: [NOTICE.md](NOTICE.md).

*An adaptation to OpenCode V2 of [ai-brain-starter](https://github.com/mycelium-hq/ai-brain-starter) (mycelium-hq).*

**DragonJAR SAS** · [dragonjar.org](https://www.dragonjar.org)
