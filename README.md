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
| `scripts/verify.sh`, `scripts/lib/ownership.py`, `scripts/lib/python3.sh`, `scripts/jobs/*.sh` | Health check, ownership library, Python detection, scheduled jobs |
| `.opencode/brain-vault-install-manifest.json` | Ownership fingerprints for safe uninstall |
| `opencode.json` | **Only** with `--with-mcp` (remote MCP servers) |

## Requirements

| Need | Why |
|---|---|
| [OpenCode](https://opencode.ai/docs) with a configured model | Runtime that loads the vault and plugin |
| Git | Clone starter + humanizer; vault bootstrap commit |
| Python 3.9+ (`python3`, `py -3` or `python` on `PATH`) | Installer, ownership and journal helpers (the installer validates the version) |
| Node 18+ (optional) | If present, installer runs `node --check` on the plugin |
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
| `--with-obsidian` | Install five Obsidian community plugins under `.obsidian/plugins/` |
| `--with-schedule` | Register scheduled jobs (launchd on macOS, cron on Linux, schtasks on Windows) |

Also accepted: `--help` / `-h`, and `--yes` / `-y` (no prompts; installer is non-interactive).

Update starter (explicit, never automatic), then re-wire:

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
| Meeting trigger | Phrases like “just had a meeting” → meeting-todos guidance |
| Auto frontmatter on new markdown | Folder-based `type:` + `created:` before writes |

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

```bash
bash scripts/schedule.sh ~/path/to/my-brain --dry-run   # show jobs; no launchd/cron writes
bash scripts/schedule.sh ~/path/to/my-brain             # install (requires prior --with-schedule path or this)
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
```

Removes only **unchanged owned** artifacts from the install manifest. Modified files, foreign symlinks, and ambiguous items are **preserved** and reported. `--purge-clones` also drops verified vendor clones (`ai-brain-starter`, `humanizer`).

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `falta OpenCode CLI` then abort | `opencode` missing from `PATH` (vault untouched) |
| Jobs never run on WSL2 | Cron inactive → `sudo service cron start` |
| `archivo modificado o no verificado, preservado` on uninstall | You edited the file, or filesystem mode drift (e.g. DrvFs)—expected safety |
| `bad interpreter: bash\r` | CRLF checkout; use a Linux filesystem inside WSL2 |
| Plugin ignores config | Folder named `⚙ Meta` (no VS16) ≠ `⚙️ Meta` |
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
├── scripts/{schedule,verify,check-personal-data}.sh
├── scripts/lib/ownership.py
├── templates/brain-config.example.json
├── templates/jobs/*.sh
├── tests/run.sh
└── docs/COMPAT.md
```

## License + Author

MIT — see [LICENSE](LICENSE). Third-party systems keep their own terms — [NOTICE.md](NOTICE.md).

*An adaptation to OpenCode V2 of [ai-brain-starter](https://github.com/mycelium-hq/ai-brain-starter) (mycelium-hq).*

**DragonJAR SAS** · [dragonjar.org](https://www.dragonjar.org)

[Español](README.es.md)
