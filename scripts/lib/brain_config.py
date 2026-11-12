#!/usr/bin/env python3
"""brain-config.json reader for ai-brain-opencode.

Single source of truth for the vault config on the shell side: defaults,
validation and fallbacks. install.sh, schedule.sh, verify.sh and the scheduled
jobs all read the config through it. (The plugin is JavaScript and keeps its own
copy of the defaults; a test keeps both in step.)

The defaults come from the package example, which install.sh copies next to
this file as brain-config.defaults.json.

Usage:
    python3 brain_config.py <config-path> <action> [args...]

Actions:
    get <key>...        print the effective value of each dotted key, one per line
    list <key>          print the items of a list key, one per line
    effective           print the whole effective config as JSON
    validate            exit 1 unless the file is a JSON object; warn on bad values
    seed <vault-name>   write the default config (detected timezone) to <config-path>
    today               print today's date (YYYY-MM-DD) in the vault timezone

A missing or unreadable config, or a value of the wrong shape, falls back to the
default with a warning on stderr: a typo never breaks a scheduled job.
"""

import datetime
import json
import os
import pathlib
import re
import sys

sys.dont_write_bytecode = True
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from ownership import configure_stdio  # noqa: E402

DEFAULTS_NAME = "templates/brain-config.example.json"
DEFAULTS_CANDIDATES = (HERE / "brain-config.defaults.json", HERE.parent.parent / "templates" / "brain-config.example.json")
TIME_RE = re.compile(r"^([01]?[0-9]|2[0-3]):[0-5][0-9]$")
TIME_KEYS = ("journal.time", "schedule.insights_time", "schedule.maintenance_time", "schedule.update_time")
# Vault-relative paths only: these are handed to git.
PATH_LIST_KEYS = ("snapshot_paths",)


class ConfigError(Exception):
    pass


def lookup(data, dotted):
    current = data
    for key in dotted.split("."):
        if not isinstance(current, dict) or key not in current:
            raise KeyError(dotted)
        current = current[key]
    return current


def load_defaults():
    for candidate in DEFAULTS_CANDIDATES:
        if candidate.is_file():
            try:
                defaults = json.loads(candidate.read_text(encoding="utf-8"))
            except (OSError, ValueError) as error:
                raise ConfigError("paquete incompleto: %s no es JSON válido: %s" % (DEFAULTS_NAME, error))
            if not isinstance(defaults, dict):
                raise ConfigError("paquete incompleto: %s debe ser un objeto JSON" % DEFAULTS_NAME)
            for key in ("vault_name", "language", "timezone") + TIME_KEYS:
                try:
                    value = lookup(defaults, key)
                except KeyError:
                    value = None
                if not isinstance(value, str) or not value.strip():
                    raise ConfigError("paquete incompleto: %s no declara %s" % (DEFAULTS_NAME, key))
                if key in TIME_KEYS and not TIME_RE.match(value.strip()):
                    raise ConfigError("paquete incompleto: %s en %s no es HH:MM" % (key, DEFAULTS_NAME))
            return defaults
    raise ConfigError("paquete incompleto: falta " + DEFAULTS_NAME)


def read_user(path):
    """(config dict, problem or None). A missing file is not a problem."""
    path = pathlib.Path(path)
    if not path.is_file():
        return {}, None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        return {}, "no es JSON válido: " + str(error)
    if not isinstance(data, dict):
        return {}, "debe ser un objeto JSON (clave/valor)"
    return data, None


# Rejected anywhere in a path handed to git: Windows separators, and the glob
# characters git would expand in a pathspec.
UNSAFE_PATH_CHARS = set("\\*?[")
DRIVE_RE = re.compile(r"^[A-Za-z]:")


def safe_relative(value):
    """A plain path inside the vault: never the vault root, .git, an option or a magic pathspec."""
    path = pathlib.PurePosixPath(value)
    return (
        not path.is_absolute()
        and bool(path.parts)
        and ".." not in path.parts
        and ".git" not in path.parts
        and not value.startswith(("-", ":"))
        and not DRIVE_RE.match(value)
        and not UNSAFE_PATH_CHARS.intersection(value)
    )


def merge(defaults, user, prefix, warnings):
    """Defaults overlaid with the user's values; each default's type is the schema."""
    result = dict(user)
    for key, default in defaults.items():
        dotted = prefix + key
        value = user.get(key)
        invalid = False
        if isinstance(default, dict):
            invalid = key in user and not isinstance(value, dict)
            result[key] = merge(default, value if isinstance(value, dict) else {}, dotted + ".", warnings)
        elif isinstance(default, bool):
            invalid = key in user and not isinstance(value, bool)
            result[key] = value if isinstance(value, bool) else default
        elif isinstance(default, list):
            invalid = key in user and not isinstance(value, list)
            items = value if isinstance(value, list) else default
            items = [item.strip() for item in items if isinstance(item, str) and item.strip()]
            if dotted in PATH_LIST_KEYS:
                unsafe = [item for item in items if not safe_relative(item)]
                items = [item for item in items if safe_relative(item)]
                if unsafe:
                    warnings.append("%s ignora rutas no válidas (fuera del vault, raíz, .git, comodines o "
                                    "pathspec de git): %s" % (dotted, ", ".join(unsafe)))
                    if not items:
                        items = [item for item in default if isinstance(item, str) and safe_relative(item)]
                        warnings.append("%s sin rutas válidas; se usa %s"
                                        % (dotted, json.dumps(items, ensure_ascii=False)))
            result[key] = items
        else:
            good = isinstance(value, str) and value.strip() != ""
            if good and dotted in TIME_KEYS and not TIME_RE.match(value.strip()):
                good = False
            invalid = key in user and not good
            result[key] = value.strip() if good else default
        if invalid:
            warnings.append("%s inválida en brain-config.json ('%s'); se usa %s"
                            % (dotted, value, json.dumps(result[key], ensure_ascii=False)
                               if not isinstance(result[key], str) else result[key]))
    return result


def effective(path):
    """(effective config, warnings)."""
    warnings = []
    user, problem = read_user(path)
    if problem:
        warnings.append("brain-config.json " + problem + "; se usan los valores por defecto")
    return merge(load_defaults(), user, "", warnings), warnings


def detect_timezone():
    try:
        match = re.search(r"zoneinfo/(.+)$", os.readlink("/etc/localtime"))
        return match.group(1) if match else ""
    except (OSError, AttributeError, NotImplementedError):
        return ""


def seed(path, vault_name):
    data = load_defaults()
    detected = detect_timezone()
    if detected:
        data["timezone"] = detected
    data["vault_name"] = vault_name
    pathlib.Path(path).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if detected:
        print("  + config por defecto creada (zona horaria detectada: " + detected + ")")
    else:
        print("  ! config por defecto creada (zona horaria NO detectada; se usa " + data["timezone"]
              + ") — ajústala en ⚙️ Meta/brain-config.json")


def today(config):
    try:
        from zoneinfo import ZoneInfo
        return datetime.datetime.now(ZoneInfo(config["timezone"])).strftime("%Y-%m-%d")
    except Exception:  # unknown zone, or no tz database on this host: the host clock decides
        return datetime.date.today().strftime("%Y-%m-%d")


def render(value):
    return value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)


def main(argv):
    configure_stdio()
    if len(argv) < 2:
        print("uso: python3 brain_config.py <config> <get|list|effective|validate|seed|today> [args...]",
              file=sys.stderr)
        return 1
    path, action, args = argv[0], argv[1], argv[2:]
    try:
        if action == "seed":
            seed(path, args[0])
            return 0
        if action == "validate":
            _, problem = read_user(path)
            if problem or not pathlib.Path(path).is_file():
                print(problem or "no existe", file=sys.stderr)
                return 1
        config, warnings = effective(path)
        for warning in warnings:
            print("  ! " + warning, file=sys.stderr)
        if action == "get":
            for key in args:
                print(render(lookup(config, key)))
        elif action == "list":
            value = lookup(config, args[0])
            for item in value if isinstance(value, list) else []:
                print(item)
        elif action == "effective":
            print(json.dumps(config, indent=2, ensure_ascii=False))
        elif action == "today":
            print(today(config))
        elif action != "validate":
            raise ConfigError("acción desconocida: " + action)
    except ConfigError as error:
        print("fallo: " + str(error), file=sys.stderr)
        return 1
    except KeyError as error:
        print("fallo: brain-config no declara " + str(error.args[0]), file=sys.stderr)
        return 1
    except (OSError, IndexError) as error:
        print("fallo: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
