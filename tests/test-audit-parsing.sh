#!/usr/bin/env bash
# audit.py parses notes the way Obsidian links them: note names keep their dots,
# attachments keep their extension, code is skipped without shifting line
# numbers, Unicode forms and VS16 compare equal, and the ingest queue matches
# exact sources anywhere under 📝 Notes/Raw/.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

TMP_ROOT="$(ai_brain_test_root audit-parsing)"
trap 'rm -rf "$TMP_ROOT"' EXIT

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

VAULT="$TMP_ROOT/vault"
python3 - "$VAULT" <<'PY'
import pathlib, sys
vault = pathlib.Path(sys.argv[1])
TYPED = "---\ntype: note\n---\n\n"
VS16 = "\ufe0f"
files = {
    "📝 Notes/v1.2 plan.md": TYPED + "plan\n",
    "📝 Notes/Note.md": TYPED + "target\n",
    "📝 Notes/x.md": TYPED + "only [[x.pdf]] points near me\n",
    "📝 Notes/att/x.pdf": "",
    "📝 Notes/only-md.md": TYPED + "linked as a pdf only\n",
    "📝 Notes/a/Dup.md": TYPED + "a\n",
    "📝 Notes/b/Dup.md": TYPED + "b\n",
    "📝 Notes/Café.md": TYPED + "nfc name\n",
    "⚙" + VS16 + " Meta/Decisions/d1.md": TYPED + "decision\n",
    "📝 Notes/bom.md": "\ufeff" + TYPED + "bom\n",
    "📝 Notes/empty-type.md": "---\ntype:\ntags: x\n---\n\nbody\n",
    "📝 Notes/quoted-empty-type.md": "---\ntype: \"\"\n---\n\nbody\n",
    "📝 Notes/Raw/a.pdf": "",
    "📝 Notes/Raw/port.pdf": "",
    "📝 Notes/Raw/sub/deep.md": "deep source\n",
    "⚙" + VS16 + " Meta/logs/ingest.log":
        "## [2026-01-01 10:00] ingest | 📝 Notes/Raw/a.pdf -> [[Note]]\n"
        "## [2026-01-01 11:00] ingest | 📝 Notes/Raw/report.pdf -> [[Note]]\n",
}
hub = [
    "---", "type: note", "---", "",
    "[[v1.2 plan]] [[Note^block1]] [[Note#Heading]] [[Note|alias]] ![[Note]]",
    "[[only-md.pdf]]",
    "[[a/Dup]] [[zzz/Dup]] [[x.pdf]]",
    "[[Cafe\u0301]] [[⚙ Meta/Decisions/d1]]",
    "~~~",
    "[[in-tilde-fence]]",
    "~~~",
    "````md",
    "```",
    "[[in-nested-fence]]",
    "```",
    "````",
    "Inline `[[in-inline]]` and ``a `[[in-double]]` b``.",
    "[[after-fences-missing]]",
]
files["💼 Business/hub.md"] = "\n".join(hub) + "\n"
for rel, text in files.items():
    path = vault / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
PY

python3 "$PKG/scripts/audit.py" "$VAULT" --json > "$TMP_ROOT/report.json" || fail "audit.py failed"
python3 - "$TMP_ROOT/report.json" <<'PY' || fail "audit parsing assertions failed"
import json, sys
r = json.load(open(sys.argv[1], encoding="utf-8"))
broken = {(b["target"], b["line"]) for b in r["broken_links"]}
targets = {t for t, _ in broken}
problems = []
expect_broken = {("only-md.pdf", 6), ("zzz/Dup", 7), ("after-fences-missing", 18)}
for item in sorted(expect_broken - broken):
    problems.append("not reported as broken (or wrong line): %s:%s" % item)
for target in sorted(targets - {t for t, _ in expect_broken}):
    problems.append("reported as broken although it resolves or sits in code: [[%s]]" % target)
orphans = set(r["orphan_notes"])
if "📝 Notes/b/Dup.md" not in orphans:
    problems.append("[[a/Dup]] or [[zzz/Dup]] resolved to b/Dup.md")
if "📝 Notes/a/Dup.md" in orphans:
    problems.append("[[a/Dup]] did not resolve by path")
if "📝 Notes/x.md" not in orphans:
    problems.append("[[x.pdf]] resolved to x.md")
untyped = set(r["untyped_notes"])
if "📝 Notes/bom.md" in untyped:
    problems.append("a UTF-8 BOM before the frontmatter hid its type")
for rel in ("📝 Notes/empty-type.md", "📝 Notes/quoted-empty-type.md"):
    if rel not in untyped:
        problems.append("an empty type: was accepted in %s" % rel)
pending = set(r["pending_raw"])
if "📝 Notes/Raw/a.pdf" in pending:
    problems.append("a source logged by its exact path is still pending")
if "📝 Notes/Raw/port.pdf" not in pending:
    problems.append("port.pdf counted as ingested because report.pdf is in the log")
if "📝 Notes/Raw/sub/deep.md" not in pending:
    problems.append("a source in a Raw subfolder is not in the ingest queue")
if problems:
    sys.stderr.write("\n".join(problems) + "\n")
    sys.exit(1)
PY

# The ingest log is the queue's record, so the install-time .gitignore must
# keep it versioned while the job logs stay ignored.
GV="$TMP_ROOT/git-vault"
mkdir -p "$GV/.opencode" "$GV/⚙️ Meta/logs"
git -C "$GV" init -q
python3 "$PKG/scripts/lib/ownership.py" "$GV/.opencode/brain-vault-install-manifest.json" init > /dev/null
python3 "$PKG/scripts/lib/ownership.py" "$GV/.opencode/brain-vault-install-manifest.json" ensure-gitignore "$GV" > /dev/null
if git -C "$GV" check-ignore -q "⚙️ Meta/logs/ingest.log"; then
  fail "the install .gitignore ignores ⚙️ Meta/logs/ingest.log"
fi
git -C "$GV" check-ignore -q "⚙️ Meta/logs/daily-maintenance.log" || fail "job logs are no longer ignored"

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: audit parsing had %s failed assertions\n' "$failures" >&2
  exit 1
fi
printf 'PASS: audit parsing (dotted names, attachments, fences, Unicode, path links, BOM, ingest queue)\n'
