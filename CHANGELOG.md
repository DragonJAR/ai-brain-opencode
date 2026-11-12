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
- **Candado de los trabajos:** dos ejecuciones simultáneas sobre un candado viejo podían correr ambas, y un candado
  recién creado sin pid se trataba como abandonado. Ahora solo una ejecución lo toma, un candado sin pid se respeta
  hasta que tiene 10 minutos, y el log se rota solo bajo el candado.
- **Tiempo límite de los trabajos:** al agotarse mataba solo el proceso hijo y dejaba vivos sus descendientes
  (p. ej. el servidor de `opencode run`). Ahora mata todo el grupo de procesos (TERM y luego KILL) y en Git Bash
  usa `taskkill /T /F` (simulado en las pruebas; pendiente de validar en una máquina Windows real).
- **Snapshot diario:** una ruta de `snapshot_paths` que tu `.gitignore` ignora hacía fallar el trabajo entero, una
  carpeta borrada nunca se confirmaba y con `commit.gpgsign` activo el commit fallaba o esperaba la frase de paso.
  Ahora se omiten (y se anotan) las rutas ignoradas, los borrados entran en el snapshot y el commit no se firma ni
  pide nada.
- **Revisión semanal (`insights-weekly`):** `opencode run` corría sin `--auto`, así que rechazaba todo permiso y no
  podía guardar el informe, y pedía "/insights" en medio de una frase, que OpenCode v2 envía como texto y no como
  comando. Ahora usa `--auto` (y `--archived` si existe), invoca `--command insights` cuando la CLI lo ofrece y, si
  no, nombra la skill `insights`; sin `--auto` disponible el trabajo falla con un mensaje claro.
- **`schedule.sh`:** fallaba con `CDPATH` exportado; en cron, una ruta del vault con `$`, comillas invertidas o
  comillas se interpretaba (ahora va entre comillas simples y `%` escapado); el listado de `schtasks` en cp1252,
  la página OEM o UTF-16 rompía la programación en Windows (ahora se decodifica). En macOS avisa si el vault está
  en Documentos, Escritorio, Descargas o iCloud Drive (launchd no puede leerlos) y reintenta unas pocas veces el
  `bootstrap` que choca con la descarga anterior del agente.
- **CI:** corre también en los push a `dev`, shellcheck revisa `tests/` y el job de lint comprueba la sintaxis del
  plugin (`node --check`).
- **`check-personal-data.sh`:** no veía correos dentro de archivos binarios, una lista de términos con CRLF no
  coincidía con nada y una línea vacía en ella marcaba todo el paquete. Además, cualquier línea con "humanizer"
  quedaba exenta; ahora solo se eximen las URL de los clones del vendor. Los `#` de la lista son comentarios.
- **`/audit` lee los enlaces como Obsidian:** `[[v1.2 plan]]`, `[[Nota^bloque]]` y los nombres con otra forma
  Unicode o sin el selector VS16 (`⚙ Meta` frente a `⚙️ Meta`) ya no salen como rotos; `[[x.pdf]]` no apunta a
  `x.md`; `[[carpeta/Nota]]` se resuelve por esa ruta (y es roto si la carpeta no coincide); los bloques `~~~` o de
  4+ comillas y el código inline se ignoran sin desplazar los números de línea. Un BOM antes del frontmatter ya no
  oculta el `type:`, y un `type:` vacío ya no se da por válido.
- **Cola de `/ingest`:** busca también en las subcarpetas de `📝 Notes/Raw/` y exige el nombre exacto registrado
  (`port.pdf` ya no cuenta como ingerido porque el log nombra `report.pdf`). `⚙️ Meta/logs/ingest.log` deja de
  estar en el `.gitignore` de la instalación: es el registro de la cola y se versiona con el vault; los logs de
  los trabajos siguen ignorados.
- **Plugin `brain-vault`:** las notas nuevas creadas con `patch` (`*** Add File`) también reciben frontmatter, y el
  hook reemplaza `event.input` en vez de mutar el objeto recibido. La señal de cierre ya no salta con preguntas
  (`¿ya terminamos por hoy?`, `that's all?`) ni dentro de otra palabra, y sí reconoce `…`, emoji y el apóstrofo `’`.
  `docs/COMPAT.md` y el plugin ya no dicen que bloquear no está documentado: lanzar un error en `execute.before`
  aborta la llamada.
- **Apéndice de `AGENTS.md`:** decía que la revisión semanal corre `opencode run "/insights"`, que OpenCode v2
  envía como texto; ahora describe lo que hace el trabajo (`--auto` y la skill `insights`). Un test impide que una
  plantilla o documento vuelva a proponer `opencode run "/…"`.
- **Linux:** el recordatorio del diario busca el bus de sesión en `$XDG_RUNTIME_DIR` cuando está definido, antes de
  `/run/user/<uid>`.

### Añadido
- `tests/run.sh` descubre también `tests/test-*.mjs`; regresiones para la salida UTF-8 de `/audit`, el bus de
  `notify-send`, la limpieza de `AGENTS.md` y el aviso falso de symlink al reinstalar.
- **Ayuda y flags iguales en todos los scripts:** `install.sh`, `uninstall.sh`, `scripts/schedule.sh`,
  `scripts/verify.sh` y `scripts/check-personal-data.sh` usan la misma `usage()` de `scripts/lib/common.sh`:
  `-h`/`--help` imprime la ayuda y sale con 0; una flag desconocida o un argumento de más o de menos sale con 2 y
  el mensaje va a stderr. `verify.sh --help` ya no corre la verificación ni `check-personal-data.sh --help` toma
  la flag por un directorio.
- `scripts/lib/vault_layout.py` (también en `<vault>/scripts/lib/`): la única lista de carpetas del vault y de
  servidores MCP remotos. La usan la instalación, `verify.sh`, `/audit`, la desinstalación y `--with-mcp`; el
  plugin guarda una copia que un test compara.

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
