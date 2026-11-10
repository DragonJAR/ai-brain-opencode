#!/usr/bin/env bash
# schedule.sh — installs the vault's scheduled jobs.
#   bash scripts/schedule.sh <vault-path>            install (launchd on macOS, cron on Linux)
#   bash scripts/schedule.sh <vault-path> --dry-run  show planned jobs without registering them
#   bash scripts/schedule.sh <vault-path> --remove   remove verified package-owned jobs
set -euo pipefail

VAULT="${1:-}"
MODE="${2:-install}"
[ -n "$VAULT" ] || { echo "usage: $0 <vault-path> [--dry-run|--remove]" >&2; exit 1; }
[ -d "$VAULT" ] || { echo "vault does not exist: $VAULT" >&2; exit 1; }
case "$MODE" in install|--dry-run|--remove) ;; *) echo "unknown schedule mode: $MODE" >&2; exit 2 ;; esac
VAULT="$(cd "$VAULT" && pwd)"
OS="$(uname -s)"
SLUG="$(basename "$VAULT" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')"
SLUG="${SLUG:-cerebro}"
PREFIX="com.ai-brain.$SLUG"
J="$VAULT/scripts/jobs"
BRC="$VAULT/⚙️ Meta/brain-config.json"
MANIFEST="$VAULT/.opencode/brain-vault-install-manifest.json"

say() { printf '%s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }

if [ -L "$VAULT/.opencode" ]; then
  warn "vault .opencode is a symlink; schedule ownership is ambiguous"
  [ "$MODE" = "--remove" ] && exit 0
  exit 1
fi

owner_manifest() {
  python3 - "$MANIFEST" "$@" <<'PY'
import hashlib, json, os, pathlib, stat, sys, uuid

path = pathlib.Path(sys.argv[1])
action = sys.argv[2]

def seal(data):
    body = {key: value for key, value in data.items() if key != "seal"}
    raw = json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()

def load():
    data = json.loads(path.read_text(encoding="utf-8"))
    if (data.get("format") != 1 or data.get("owner") != "ai-brain-opencode"
            or not isinstance(data.get("instance"), str) or len(data["instance"]) != 32
            or data.get("seal") != seal(data)):
        raise ValueError("ownership manifest failed validation")
    for key in ("files", "symlinks", "config", "cron_lines", "launch_agents", "trees"):
        if key not in data:
            raise ValueError("ownership manifest is missing " + key)
    if (not all(isinstance(data[key], dict) for key in ("files", "symlinks", "config", "launch_agents", "trees"))
            or not isinstance(data["cron_lines"], list)):
        raise ValueError("ownership manifest has invalid record collections")
    return data

def save(data):
    data["seal"] = seal(data)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + ".tmp." + str(os.getpid()))
    temp.write_text(json.dumps(data, sort_keys=True, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.chmod(temp, 0o600)
    os.replace(temp, path)

def info(file_path):
    target = pathlib.Path(file_path)
    if target.is_symlink() or not target.is_file():
        raise ValueError("owned file is not a regular file")
    st = target.stat()
    return {"sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
            "mode": stat.S_IMODE(st.st_mode), "nlink": st.st_nlink}

if action == "init":
    if path.exists() or path.is_symlink():
        if path.is_symlink(): raise ValueError("ownership manifest is a symlink")
        load()
    else:
        save({"format": 1, "owner": "ai-brain-opencode", "instance": uuid.uuid4().hex,
              "files": {}, "symlinks": {}, "config": {}, "cron_lines": [],
              "launch_agents": {}, "trees": {}})
elif action == "instance":
    print(load()["instance"])
elif action == "cron-json":
    print(json.dumps(load()["cron_lines"], ensure_ascii=False, separators=(",", ":")))
elif action == "set-cron":
    data = load(); data["cron_lines"] = json.loads(sys.argv[3]); save(data)
elif action == "clear-cron":
    data = load(); data["cron_lines"] = []; save(data)
elif action == "agents-tsv":
    for agent_path, entry in load()["launch_agents"].items():
        print(agent_path + "\t" + entry["label"])
elif action == "agent-matches":
    entry = load()["launch_agents"].get(sys.argv[3]); target = pathlib.Path(sys.argv[3])
    if entry is None or target.is_symlink() or not target.is_file() or entry.get("file") != info(target): sys.exit(1)
elif action == "record-agent":
    data = load(); target = pathlib.Path(sys.argv[3])
    data["launch_agents"][str(target)] = {"label": sys.argv[4], "file": info(target)}; save(data)
elif action == "clear-agents":
    data = load(); data["launch_agents"] = {}; save(data)
else:
    raise ValueError("unknown ownership action: " + action)
PY
}

cron_value() {
  python3 - "$BRC" "$1" "$2" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
default = sys.argv[3]
if not path.is_file():
    print(default); sys.exit(0)
cur = json.loads(path.read_text(encoding="utf-8"))
for key in sys.argv[2].split("."):
    if not isinstance(cur, dict) or key not in cur:
        print(default); sys.exit(0)
    cur = cur[key]
print(cur)
PY
}

hm() { printf '%s\n' "$1" | cut -d: -f1; }
pm() { printf '%s\n' "$1" | cut -d: -f2 | sed 's/^0//'; }

write_cron_lines() {
  local marker="$1"
  printf '%s %s * * 1-5 /bin/bash "%s/journal-reminder.sh" %s\n' "$(hm "$JT")" "$(pm "$JT")" "$J" "$marker"
  printf '%s %s * * 0 /bin/bash "%s/insights-weekly.sh" %s\n' "$(hm "$ITIME")" "$(pm "$ITIME")" "$J" "$marker"
  printf '%s %s * * * /bin/bash "%s/daily-maintenance.sh" %s\n' "$(hm "$MTIME")" "$(pm "$MTIME")" "$J" "$marker"
  printf '%s %s * * 1 /bin/bash "%s/update-brain.sh" %s\n' "$(hm "$UTIME")" "$(pm "$UTIME")" "$J" "$marker"
}

reconcile_crontab() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json, pathlib, sys
current_path, generated_path, output_path = map(pathlib.Path, sys.argv[1:4])
previous = json.loads(sys.argv[4])
current = current_path.read_text(encoding="utf-8").splitlines(keepends=True)
for old in previous:
    for index, line in enumerate(current):
        if line.rstrip("\r\n") == old:
            current.pop(index)
            break
owned = []
for line in generated_path.read_text(encoding="utf-8").splitlines(keepends=True):
    value = line.rstrip("\r\n")
    if not any(existing.rstrip("\r\n") == value for existing in current):
        current.append(line)
        owned.append(value)
output_path.write_text("".join(current), encoding="utf-8")
print(json.dumps(owned, ensure_ascii=False, separators=(",", ":")))
PY
}

read_crontab() {
  local output="$1" errors rc
  errors="$(mktemp "${TMPDIR:-/tmp}/ai-brain-crontab-error.XXXXXX")"
  if crontab -l > "$output" 2> "$errors"; then
    rm -f "$errors"
    return 0
  else
    rc=$?
  fi
  if grep -qi 'no crontab for' "$errors"; then
    : > "$output"
    rm -f "$errors"
    return 0
  fi
  cat "$errors" >&2
  rm -f "$errors"
  return "$rc"
}

if [ "$MODE" = "--remove" ]; then
  if ! CRON_JSON="$(owner_manifest cron-json 2>/dev/null)"; then
    warn "ownership manifest absent or invalid; scheduled artifacts were preserved"
    exit 0
  fi
  if [ "$OS" = "Darwin" ]; then
    AGENT_LIST="$(mktemp "${TMPDIR:-/tmp}/ai-brain-agents.XXXXXX")"
    trap 'rm -f "$AGENT_LIST"' EXIT
    owner_manifest agents-tsv > "$AGENT_LIST"
    while IFS=$'\t' read -r agent_path label; do
      [ -n "$agent_path" ] || continue
      case "$label" in "$PREFIX".*) ;; *) continue ;; esac
      [ "$agent_path" = "$HOME/Library/LaunchAgents/$label.plist" ] || continue
      if owner_manifest agent-matches "$agent_path" >/dev/null 2>&1; then
        launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
        rm -f "$agent_path"
      else
        warn "modified or unverified launch agent preserved: $agent_path"
      fi
    done < "$AGENT_LIST"
    owner_manifest clear-agents
  elif [ "$CRON_JSON" != "[]" ]; then
    CURRENT="$(mktemp "${TMPDIR:-/tmp}/ai-brain-cron-current.XXXXXX")"
    GENERATED="$(mktemp "${TMPDIR:-/tmp}/ai-brain-cron-empty.XXXXXX")"
    UPDATED="$(mktemp "${TMPDIR:-/tmp}/ai-brain-cron-updated.XXXXXX")"
    trap 'rm -f "$CURRENT" "$GENERATED" "$UPDATED"' EXIT
    read_crontab "$CURRENT" || { warn "crontab could not be read; ownership records were preserved"; exit 1; }
    OWNED="$(reconcile_crontab "$CURRENT" "$GENERATED" "$UPDATED" "$CRON_JSON")"
    if ! cmp -s "$CURRENT" "$UPDATED"; then crontab "$UPDATED"; fi
    owner_manifest clear-cron
  else
    say "No verified package-owned cron entries to remove."
  fi
  exit 0
fi

JT="$(cron_value 'journal.time' '20:30')"
ITIME="$(cron_value 'schedule.insights_time' '21:00')"
MTIME="$(cron_value 'schedule.maintenance_time' '03:30')"
UTIME="$(cron_value 'schedule.update_time' '08:00')"

if [ "$MODE" = "--dry-run" ] && [ "$OS" != "Darwin" ]; then
  write_cron_lines "# ai-brain $SLUG owner=<dry-run>"
  exit 0
fi

if [ "$MODE" = "--dry-run" ]; then
  INSTANCE="dry-run"
else
  owner_manifest init || { echo "ownership manifest is invalid; schedule was not changed" >&2; exit 1; }
  INSTANCE="$(owner_manifest instance)"
fi

if [ "$OS" = "Darwin" ]; then
  mk() {
    local job="$1" label="$2" cal="$3" plist=""
    if [ "$MODE" = "--dry-run" ]; then
      plist="$(mktemp "${TMPDIR:-/tmp}/ai-brain-${label}.XXXXXX")"
    else
      plist="$HOME/Library/LaunchAgents/$label.plist"
      if [ -L "$plist" ]; then warn "symlink launch agent preserved: $plist"; return 0; fi
      if [ -e "$plist" ] && ! owner_manifest agent-matches "$plist" >/dev/null 2>&1; then
        warn "unowned or modified launch agent preserved: $plist"
        return 0
      fi
      mkdir -p "$HOME/Library/LaunchAgents"
    fi
    cat > "$plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$J/$job.sh</string></array>
$cal
<key>StandardOutPath</key><string>$VAULT/⚙️ Meta/logs/$job.log</string>
<key>StandardErrorPath</key><string>$VAULT/⚙️ Meta/logs/$job.log</string>
</dict></plist>
PL
    if [ "$MODE" = "--dry-run" ]; then
      echo "  (dry-run) $label"
      plutil -lint "$plist" >/dev/null 2>&1 && echo "    plist valid" || echo "    ! plist invalid"
      rm -f "$plist"
      return 0
    fi
    owner_manifest record-agent "$plist" "$label" || { warn "could not record launch agent: $plist"; return 0; }
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$plist" && echo "  + $label" || echo "  ! $label (bootstrap failed)"
  }
  CAL_J="<key>StartCalendarInterval</key><array>$(for wd in 1 2 3 4 5; do printf '<dict><key>Hour</key><integer>%s</integer><key>Minute</key><integer>%s</integer><key>Weekday</key><integer>%s</integer></dict>' "$(hm "$JT")" "$(pm "$JT")" "$wd"; done)</array>"
  CAL_I="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$ITIME")</integer><key>Minute</key><integer>$(pm "$ITIME")</integer><key>Weekday</key><integer>0</integer></dict>"
  CAL_M="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$MTIME")</integer><key>Minute</key><integer>$(pm "$MTIME")</integer></dict>"
  CAL_U="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$(hm "$UTIME")</integer><key>Minute</key><integer>$(pm "$UTIME")</integer><key>Weekday</key><integer>1</integer></dict>"
  mk journal-reminder "$PREFIX.journal-reminder" "$CAL_J"
  mk insights-weekly "$PREFIX.insights-weekly" "$CAL_I"
  mk daily-maintenance "$PREFIX.daily-maintenance" "$CAL_M"
  mk update-brain-weekly "$PREFIX.update-brain-weekly" "$CAL_U"
else
  MARK="# ai-brain $SLUG owner=$INSTANCE"
  GENERATED="$(mktemp "${TMPDIR:-/tmp}/ai-brain-cron-new.XXXXXX")"
  CURRENT="$(mktemp "${TMPDIR:-/tmp}/ai-brain-cron-current.XXXXXX")"
  UPDATED="$(mktemp "${TMPDIR:-/tmp}/ai-brain-cron-updated.XXXXXX")"
  trap 'rm -f "$GENERATED" "$CURRENT" "$UPDATED"' EXIT
  write_cron_lines "$MARK" > "$GENERATED"
  read_crontab "$CURRENT" || { warn "crontab could not be read; schedule was not changed"; exit 1; }
  PREVIOUS="$(owner_manifest cron-json)"
  OWNED="$(reconcile_crontab "$CURRENT" "$GENERATED" "$UPDATED" "$PREVIOUS")"
  if ! cmp -s "$CURRENT" "$UPDATED"; then
    crontab "$UPDATED"
    echo "  + 4 owned crontab entries ($MARK)"
  else
    echo "  + owned crontab entries already current"
  fi
  owner_manifest set-cron "$OWNED"
fi
