# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Este proyecto sigue
[SemVer](https://semver.org/lang/es/). La versión vigente está en `VERSION` y la muestra `bash install.sh --version`.

## [Unreleased]

### Corregido
- **`/audit`:** un vault recién instalado mostraba 38 enlaces rotos de las notas de piso del vendor. La auditoría
  revisa solo tu contenido: `⚙️ Meta/Floors`, `⚙️ Meta/scripts`, `scripts/` y los archivos raíz (`AGENTS.md`,
  `CLAUDE.md`…) quedan fuera, y una carpeta tuya llamada `docs`, `templates` o `tests` ya no se omite.
- **`📝 Notes/Raw/` inmutable de verdad:** el plugin ya no inyecta frontmatter en las fuentes nuevas y `/audit` no
  exige `type:` allí; siguen fuera de las huérfanas y en la cola de `/ingest`.
- **Logs de los trabajos:** `daily-maintenance` y `update-brain` escribían `maintenance.log` y `update.log` mientras
  launchd escribía `<trabajo>.log`, que nunca se rotaba. Ahora cada trabajo tiene un solo log, `<trabajo>.log`, en
  el trabajo, launchd y cron (que además deja de perder la salida). Los logs antiguos pueden borrarse.
- **`snapshot_paths`:** aceptaba `.` (el snapshot diario confirmaba todo el vault, contenido personal incluido),
  barras invertidas, `.git`, comodines y pathspecs mágicos de git (`:/`, `:(glob)`). Esas entradas se descartan con
  aviso; si no queda ninguna válida se usa la lista por defecto. `install.sh --config` muestra los mismos avisos.
- **`uninstall.sh --dry-run`:** solo decía que los trabajos programados "se conservan". Ahora lista las entradas de
  cron, launch agents o tareas de Windows que se eliminarían, sin tocarlas (`schedule.sh --remove --dry-run`).
- **Commit base sobre un vault existente:** confirmaba `.opencode/`, `scripts/` y `opencode.json` enteros (tu
  configuración con claves, tus agentes, el manifiesto y los clones del vendor como gitlinks). Ahora confirma solo
  las rutas del manifiesto y lo que esa instalación creó; un `.gitignore` existente se completa con las líneas que
  faltan (sin pisarlo) y las rutas que tu `.gitignore` ignora se omiten en vez de abortar la instalación.
- **Manifiesto de propiedad:** la instalación, la desinstalación, `schedule.sh` y la actualización semanal lo
  escriben bajo un mismo candado (`.opencode/.manifest.lock`); dos escrituras simultáneas ya no pierden registros.
  Las rutas con `\`, unidad o `:` se rechazan y ninguna ruta registrada puede salir del vault.
- **`uninstall.sh` sin manifiesto válido:** decía "Listo" y salía con 0. Ahora sale con error antes de tocar la
  programación o los archivos y explica que no se eliminó nada. Sin `--purge-clones`, el `.gitignore` que oculta
  los clones del vendor se conserva mientras ellos sigan ahí.
- **`--with-mcp` con JSONC:** un `opencode.json` con comentarios abortaba la instalación ya hecha, y junto a un
  `opencode.jsonc` se creaba una segunda configuración. Ahora se avisa y se omite el paso MCP sin tocar el archivo.
- **Robustez del shell:** `install.sh`, `uninstall.sh` y `verify.sh` fallaban con `CDPATH` exportado; la
  identidad git se comprobaba en el repo del directorio actual y no en el del vault; un `brain-config.json`,
  `journal-config.md` o `AGENTS.md` que es symlink se escribía a través del enlace (ahora la instalación se rechaza
  antes de tocar nada); un `cp` fallido ya no pasa en silencio.
- **`verify.sh`:** el chequeo de cableado contaba los comandos del paquete y, en Windows, el clon de humanizer
  como skill copiada; ahora cuenta solo lo cableado desde el starter. Los symlinks rotos se buscan también en
  `⚙️ Meta/scripts` y en `CLAUDE.md`.
- **`check-personal-data.sh`:** no veía correos dentro de archivos binarios, una lista de términos con CRLF no
  coincidía con nada y una línea vacía en ella marcaba todo el paquete. Además, cualquier línea con "humanizer"
  quedaba exenta; ahora solo se eximen las URL de los clones del vendor. Los `#` de la lista son comentarios.
- **`check-personal-data.sh`:** no veía correos dentro de archivos binarios, una lista de términos con CRLF no
  coincidía con nada y una línea vacía en ella marcaba todo el paquete. Además, cualquier línea con "humanizer"
  quedaba exenta; ahora solo se eximen las URL de los clones del vendor. Los `#` de la lista son comentarios.
- **Linux:** el recordatorio del diario busca el bus de sesión en `$XDG_RUNTIME_DIR` cuando está definido, antes de
  `/run/user/<uid>`.

### Añadido
- `tests/run.sh` descubre también `tests/test-*.mjs`; regresiones para la salida UTF-8 de `/audit`, el bus de
  `notify-send`, la limpieza de `AGENTS.md` y el aviso falso de symlink al reinstalar.

## [0.2.0] - 2026-11-11

Primera versión numerada. Reúne las correcciones de la auditoría completa del paquete.

### Corregido
- **macOS:** el launch agent de actualización apuntaba a `update-brain-weekly.sh`, que no existe; la actualización
  semanal nunca corría. Al re-programar, el agente antiguo se retira.
- **Trabajos sin `PATH`:** cron y launchd arrancan con un `PATH` mínimo y `insights-weekly` no encontraba
  `opencode`. Cada trabajo conserva ahora el `PATH` del shell que lo programó.
- **Snapshot diario y commit base:** `git commit` sin rutas se llevaba lo que el usuario tuviera en el index.
  Ambos confirman solo sus rutas.
- **`verify.sh` en macOS:** `find -xtype` no existe allí y el chequeo de symlinks rotos pasaba siempre.
- **`--purge-clones`:** los clones se registraban por huella y dejaban de coincidir en el primer `pull`. Ahora se
  registran por su origen git; los registros antiguos se migran al reinstalar.
- **Reinstalación:** aviso falso "directorio padre symlink preservado: CLAUDE.md" en cada ejecución.
- **Textos:** se indicaba `/journal`, que no existe; el comando es `/daily-journal`. `AGENTS.md` ya no conserva
  referencias al chequeo diario de actualización ni a `Last Session.md`.
- **Windows:** `uninstall.sh` usaba `python3` a secas; las salidas de Python llegaban con `\r\n` y en `cp1252`
  (las horas configuradas nunca se respetaban); `schtasks` recibía sus `/Flags` convertidas en rutas por Git Bash;
  el recordatorio del diario no notificaba; el runner podía resolver al `bash.exe` de WSL.
- **Linux:** `notify-send` abortaba el recordatorio bajo cron por no tener el bus de sesión.
- **Colisiones:** dos vaults con el mismo nombre de carpeta; en Windows el segundo pisaba las tareas del primero.
  Ahora lo ajeno se preserva y la programación falla con un mensaje claro.
- **`schedule.sh --remove`:** olvidaba también los launch agents modificados que había preservado.
- **Clon fijado (`BRAIN_STARTER_PIN`):** el trabajo semanal intentaba un `pull` que fallaba siempre.

### Añadido
- `install.sh --dry-run` y `--version`; `uninstall.sh --dry-run`.
- `scripts/lib/wire.py`, `brain_config.py` y `common.sh`: una sola implementación del cableado, de la lectura de la
  config y del arranque de los trabajos (ver `docs/COMPAT.md`).
- El trabajo semanal re-cablea lo que el starter agregó y poda lo que retiró.
- `snapshot_paths` en `brain-config.json`: qué confirma el snapshot diario.
- Rotación de logs, candado contra ejecuciones solapadas y timeout portable en los trabajos.
- `verify.sh` informa la deriva entre el manifiesto y el disco.
- CI en GitHub Actions (Linux, macOS y Windows) y tests de regresión por cada fallo corregido.

### Pendiente de validar
- La ruta de Windows nativo sigue cubierta por fixtures simulados; el job de CI en Windows es la primera
  ejecución sobre un Windows real y se declara informativo hasta que pase de forma estable.
