# brain-vault quality audit — intuitiveness, platforms, reliability, DRY

## Objective
Audit ai-brain-opencode (installer, scheduler, plugin, jobs, docs, tests) for intuitiveness, macOS/Linux/Windows
support, coherence, reliability, efficiency and UX. Fix every gap found, keeping one implementation per concern.

## Found defects (state at audit)
- install.sh §11 base commit: `[ -f opencode.json ]` checked the installer cwd, `|| true "📓 Journals" ...` never
  staged the vault structure, and the commit could run without staging. CONFIRMED.
- `verify.sh` ended with `echo`, so it always exited 0 even with failures. CONFIRMED.
- Windows native accepted by preflight, then failed mid-install (no launchd/cron, `ln -s` copies in Git Bash). CONFIRMED.
- Scheduler accepted any string as `HH:MM` (invalid cron/plist) and crashed on a malformed config. CONFIRMED.
- Plugin: shallow config merge + `.join`/`.map` on unvalidated values killed every hook; `""` timezone threw;
  path regex matched any `Home/` outside the vault and never matched Windows separators. CONFIRMED.
- ~300 lines of ownership code duplicated across install.sh, schedule.sh and uninstall.sh (already drifting:
  install validated `cron_ownership_version` in `load`, schedule did not). CONFIRMED.
- install.sh spawned ~120 python processes for ~90 symlink records. CONFIRMED.
- Dead/unused config keys (`schedule.enabled`, `insights_day`, `update_day`, `mcp`) and hardcoded scheduler times
  in the generated appendix. CONFIRMED.
- `update-brain.sh` overwrote user-edited floor notes (`cp` without `-n`). CONFIRMED.
- `journal-reminder.sh` read the config twice and interpolated the vault name into AppleScript. CONFIRMED.
- `uninstall.sh` left an empty `scripts/` dir and printed English messages in a Spanish product. CONFIRMED.
- Unknown flags were treated as a vault path (`install.sh --bogus`). CONFIRMED.

## Changes (route: inline; complete context was already held)
1. `scripts/lib/ownership.py` — single implementation of seal/validate/fingerprints/actions, plus `record-links`
   batching and a `verify` action. install/schedule/uninstall consume it; install copies it into the vault.
2. install.sh — preflight (platform, WSL2 warning, crontab, package completeness), git init fallback, base commit
   moved to §15 staging only managed artifacts (.gitkeep, not personal content), batched symlink records, `mode`
   argument for managed_copy, real failure on `BRAIN_STARTER_PIN`, MCP error reporting, dead code removed.
3. schedule.sh — platform guard, `--help`, `HH:MM` validation with defaults, resilient config read, Spanish output.
4. verify.sh — exit 1 on failure, manifest validation, CLAUDE.md/ownership checks, no brittle count thresholds.
5. plugin — deep config normalization, timezone validation, vault-relative path typing (journal/person/session/
   decision/note), per-hook degradation, dead imports removed.
6. jobs — single config read + argv-safe AppleScript, log dir creation, `cp -n` for floors.
7. docs/templates — Windows→WSL2 section, troubleshooting table, `--help`, update/pin instructions, honest appendix
   (times from config, `--wire` does not regenerate it), dead config keys removed.
8. tests — shared `tests/lib/mocks.sh`, plugin contract test (node), assertions for the git bootstrap, verify exit
   code, Windows guard, invalid schedule fallback.

## Verification (observed)
- `bash tests/run.sh` → 4/4 PASS (scheduler, uninstall ownership, T3 contract, plugin contract).
- Real macOS install (39 skills, 17 commands, 268 vendor script links, humanizer, 38 floors) → verify 24 ok /
  0 fallos, clean git tree (0 untracked), base commit created.
- Idempotent re-run and `--wire` → no user content touched, tree stays clean.
- `uninstall.sh` and `uninstall.sh --purge-clones` on real vaults → only owned unchanged artifacts removed.
- `schedule.sh --dry-run` on macOS → 4 valid plists, nothing registered in `~/Library/LaunchAgents`.
- `--config` valid → seeded; invalid → clean error, vault untouched. `check-personal-data.sh` → clean.

## Next step
Merged into `main` (fast-forward) on the user's instruction; `main` is now the only working branch and the
feature branch was deleted. `origin/main` stays behind until the user pushes.
