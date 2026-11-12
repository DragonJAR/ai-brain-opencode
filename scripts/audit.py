#!/usr/bin/env python3
"""audit.py — Auditoría determinista de integridad estructural del vault.

Inspecciona el vault buscando:
1. Enlaces wikilinks rotos ([[destino]]).
2. Notas de contenido huérfanas (sin enlaces entrantes).
3. Documentos markdown sin tipado en frontmatter (type: ...).
4. Fuentes sin procesar en 📝 Notes/Raw/ pendientes de ingesta (/ingest).

Uso:
    python3 scripts/audit.py [ruta-del-vault] [--json] [--strict] [--verbose]
"""

import argparse
import json
import os
import pathlib
import re
import sys

WIKILINK_RE = re.compile(r"\[\[([^\]|#\r\n]+)(?:#[^\]|\r\n]*)?(?:\|[^\]\r\n]*)?\]\]")
FRONTMATTER_RE = re.compile(r"^---\r?\n([\s\S]*?)\r?\n---")
TYPE_ATTR_RE = re.compile(r"^type:\s*(\S+)", re.MULTILINE)

# Never walked, at any depth (dot directories are skipped as well).
EXCLUDED_DIRS = {
    "node_modules",
    "__pycache__",
}

# Package/vendor areas, anchored at the vault root: their files stay valid link
# targets but are not audited, so a user folder with the same name still is.
ROOT_EXCLUDED_PATHS = (
    "odd/",
    "docs/",
    "templates/",
    "tests/",
    "scripts/",
    "⚙️ Meta/Floors/",
    "⚙️ Meta/scripts/",
)

ROOT_EXCLUDED_FILES = {
    "AGENTS.md",
    "CLAUDE.md",
    "README.md",
    "README.es.md",
    "LICENSE.md",
    "NOTICE.md",
    "CHANGELOG.md",
}

TYPED_FOLDERS = (
    "📓 Journals/",
    "👤 CRM/",
    "🏠 Home/",
    "📝 Notes/",
    "💼 Business/",
    "🚀 I+D/",
    "⚙️ Meta/Sessions/",
    "⚙️ Meta/Decisions/",
)

# Immutable sources: never typed, never orphans; only the pending-ingest queue applies.
RAW_PREFIX = "📝 Notes/Raw/"

CONTENT_FOLDERS_FOR_ORPHANS = (
    "📝 Notes/",
    "👤 CRM/",
    "🚀 I+D/",
    "💼 Business/",
)


def strip_code_blocks(text: str) -> str:
    """Elimina bloques de código y código inline para evitar falsos positivos de wikilinks."""
    text = re.sub(r"```[\s\S]*?```", "", text)
    text = re.sub(r"`[^`\r\n]+`", "", text)
    return text


def is_audited(rel_path: str) -> bool:
    if rel_path in ROOT_EXCLUDED_FILES:
        return False
    return not any(rel_path.startswith(prefix) for prefix in ROOT_EXCLUDED_PATHS)


def scan_vault(vault_dir: pathlib.Path) -> dict:
    all_files = {}
    stems = {}
    rel_markdowns = []

    for root, dirs, files in os.walk(vault_dir):
        dirs[:] = [d for d in dirs if d not in EXCLUDED_DIRS and not d.startswith(".")]
        for file in files:
            full_path = pathlib.Path(root) / file
            rel_path = full_path.relative_to(vault_dir).as_posix()
            all_files[rel_path] = full_path
            stem_key = full_path.stem.lower()
            stems.setdefault(stem_key, []).append(rel_path)
            if file.endswith(".md") and is_audited(rel_path):
                rel_markdowns.append(rel_path)

    broken_links = []
    incoming_links = {md: set() for md in rel_markdowns}
    untyped_notes = []
    total_wikilinks = 0

    # Sin `str | None`: esa sintaxis en una anotación falla en Python 3.9, el mínimo documentado.
    def resolve_link(target, source_rel):
        target_norm = target.strip().replace("\\", "/").strip("/")
        if not target_norm:
            return None

        # 1. Coincidencia exacta relativa al vault (con o sin .md)
        if target_norm in all_files:
            return target_norm
        if target_norm + ".md" in all_files:
            return target_norm + ".md"

        # 2. Coincidencia relativa al directorio del archivo fuente
        source_parent = pathlib.PurePosixPath(source_rel).parent
        if str(source_parent) != ".":
            candidate = (source_parent / target_norm).as_posix()
            if candidate in all_files:
                return candidate
            if candidate + ".md" in all_files:
                return candidate + ".md"

        # 3. Coincidencia por basename / stem (insensible a mayúsculas)
        target_stem = pathlib.PurePosixPath(target_norm).stem.lower()
        if target_stem in stems:
            matches = stems[target_stem]
            if len(matches) == 1:
                return matches[0]
            # Si hay varios, preferir uno con nombre idéntico respetando mayúsculas
            raw_stem = pathlib.PurePosixPath(target_norm).stem
            for m in matches:
                if pathlib.PurePosixPath(m).stem == raw_stem:
                    return m
            return matches[0]

        return None

    for rel_md in sorted(rel_markdowns):
        full_md = all_files[rel_md]
        try:
            content = full_md.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue

        # Auditoría de frontmatter / tipado: solo en carpetas tipadas del vault
        is_typed_scope = any(rel_md.startswith(prefix) for prefix in TYPED_FOLDERS)
        is_workflow_doc = rel_md.startswith("⚙️ Meta/Workflows/")
        if is_typed_scope and not is_workflow_doc and not rel_md.startswith(RAW_PREFIX):
            fm_match = FRONTMATTER_RE.match(content)
            if not fm_match or not TYPE_ATTR_RE.search(fm_match.group(1)):
                untyped_notes.append(rel_md)

        # Auditoría de wikilinks
        scrubbed = strip_code_blocks(content)
        lines = scrubbed.splitlines()
        for idx, line in enumerate(lines, start=1):
            for match in WIKILINK_RE.finditer(line):
                total_wikilinks += 1
                raw_target = match.group(1).strip()
                resolved = resolve_link(raw_target, rel_md)
                if resolved:
                    if resolved in incoming_links and resolved != rel_md:
                        incoming_links[resolved].add(rel_md)
                else:
                    broken_links.append({
                        "source": rel_md,
                        "line": idx,
                        "target": raw_target,
                    })

    # Auditoría de notas huérfanas
    orphan_notes = []
    for rel_md in sorted(rel_markdowns):
        # Solo verificar carpetas de contenido
        is_content = any(rel_md.startswith(prefix) for prefix in CONTENT_FOLDERS_FOR_ORPHANS)
        if not is_content:
            continue
        # Excluir 📝 Notes/Raw/ (es cola de ingesta, no notas estructuradas)
        if rel_md.startswith(RAW_PREFIX):
            continue
        # Excluir notas índice o templates
        stem_lower = pathlib.PurePosixPath(rel_md).stem.lower()
        if stem_lower in {"index", "readme", "home", "overview"}:
            continue
        if len(incoming_links.get(rel_md, set())) == 0:
            orphan_notes.append(rel_md)

    # Auditoría de fuentes raw pendientes de /ingest
    pending_raw = []
    ingest_log_file = vault_dir / "⚙️ Meta" / "logs" / "ingest.log"
    logged_sources = set()
    if ingest_log_file.is_file():
        try:
            log_text = ingest_log_file.read_text(encoding="utf-8", errors="replace")
            for line in log_text.splitlines():
                if "ingest |" in line:
                    logged_sources.add(line.strip())
        except OSError:
            pass

    raw_dir = vault_dir / "📝 Notes" / "Raw"
    if raw_dir.is_dir():
        for f in raw_dir.iterdir():
            if f.is_file() and f.name != ".gitkeep" and not f.name.startswith("."):
                rel_f = f.relative_to(vault_dir).as_posix()
                # Verificar si el archivo aparece en el log
                is_logged = any(f.name in line or rel_f in line for line in logged_sources)
                if not is_logged:
                    pending_raw.append(rel_f)
    pending_raw.sort()

    return {
        "vault": str(vault_dir.resolve()),
        "markdown_files_count": len(rel_markdowns),
        "total_wikilinks": total_wikilinks,
        "broken_links": broken_links,
        "orphan_notes": orphan_notes,
        "untyped_notes": untyped_notes,
        "pending_raw": pending_raw,
    }


def format_human(report: dict, verbose: bool = False) -> str:
    lines = []
    lines.append("== Auditoría de Integridad del Vault ==")
    lines.append(f"Directorio: {report['vault']}")
    lines.append(f"Archivos markdown analizados: {report['markdown_files_count']}")
    lines.append("")

    broken = report["broken_links"]
    if broken:
        lines.append(f"✗ Wikilinks rotos: {len(broken)} detectados")
        for item in broken[:15 if not verbose else len(broken)]:
            lines.append(f"  - {item['source']}:{item['line']} -> [[{item['target']}]]")
        if not verbose and len(broken) > 15:
            lines.append(f"  ... y {len(broken) - 15} más (usa --verbose para ver todos)")
    else:
        lines.append(f"✓ Wikilinks: {report['total_wikilinks']} enlaces verificados (0 rotos)")

    untyped = report["untyped_notes"]
    if untyped:
        lines.append(f"✗ Tipado frontmatter: {len(untyped)} notas sin 'type:'")
        for item in untyped[:15 if not verbose else len(untyped)]:
            lines.append(f"  - {item}")
        if not verbose and len(untyped) > 15:
            lines.append(f"  ... y {len(untyped) - 15} más (usa --verbose para ver todos)")
    else:
        lines.append("✓ Tipado frontmatter: todas las notas válidas")

    orphans = report["orphan_notes"]
    if orphans:
        lines.append(f"⚠ Notas huérfanas: {len(orphans)} sin enlaces entrantes")
        for item in orphans[:10 if not verbose else len(orphans)]:
            lines.append(f"  - {item}")
        if not verbose and len(orphans) > 10:
            lines.append(f"  ... y {len(orphans) - 10} más")
    else:
        lines.append("✓ Notas huérfanas: ninguna nota aislada")

    pending = report["pending_raw"]
    if pending:
        lines.append(f"ℹ Fuentes raw pendientes de /ingest: {len(pending)}")
        for item in pending:
            lines.append(f"  - {item}")
    else:
        lines.append("✓ Fuentes raw: cola de ingesta al día")

    critical_count = len(broken) + len(untyped)
    warning_count = len(orphans) + len(pending)
    lines.append("")
    if critical_count == 0 and warning_count == 0:
        lines.append("Resultado: Vault 100% íntegro y sincronizado.")
    elif critical_count == 0:
        lines.append(f"Resultado: Vault saludable ({warning_count} advertencias o pendientes menores).")
    else:
        lines.append(f"Resultado: ✗ {critical_count} errores críticos y {warning_count} advertencias.")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Auditoría de integridad del vault.")
    parser.add_argument("vault", nargs="?", default=".", help="Ruta al vault (por defecto: .)")
    parser.add_argument("--json", action="store_true", help="Salida en formato JSON")
    parser.add_argument("--strict", action="store_true", help="Salir con código 1 si hay enlaces rotos o notas sin tipo")
    parser.add_argument("-v", "--verbose", action="store_true", help="Mostrar listados completos")

    args = parser.parse_args()
    # UTF-8 también en Windows, donde la consola usaría cp1252 y los símbolos del informe fallarían.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass
    vault_path = pathlib.Path(args.vault).resolve()
    if not vault_path.is_dir():
        sys.stderr.write(f"Error: la ruta indicada no es un directorio: {vault_path}\n")
        sys.exit(2)

    report = scan_vault(vault_path)

    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        print(format_human(report, verbose=args.verbose))

    if args.strict and (len(report["broken_links"]) > 0 or len(report["untyped_notes"]) > 0):
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
