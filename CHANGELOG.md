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
