#!/usr/bin/env bash
# audit.py inspects the user's content only: vendor/package areas never raise
# criticals, and user folders are audited wherever they live.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd "$TEST_DIR/.." && pwd)"
# shellcheck source=lib/mocks.sh
. "$TEST_DIR/lib/mocks.sh"

TMP_ROOT="$(ai_brain_test_root audit-scope)"
trap 'rm -rf "$TMP_ROOT"' EXIT

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

audit_json() { python3 "$PKG/scripts/audit.py" "$1" --json; }
# Prints "<broken> <untyped>" from the JSON report on stdin.
criticals() {
  python3 -c 'import json, sys; r = json.load(sys.stdin); print(len(r["broken_links"]), len(r["untyped_notes"]))'
}

# --- Fresh-vault-like fixture -----------------------------------------------------
VAULT="$TMP_ROOT/vault"
mkdir -p "$VAULT/⚙️ Meta/Floors" "$VAULT/⚙️ Meta/scripts" "$VAULT/scripts" \
         "$VAULT/📓 Journals" "$VAULT/📝 Notes/Raw"
# The vendor floor notes link to [[floors]], which no vault has.
for floor in one two; do
  printf '# Floor %s\n\nSee [[floors]].\n' "$floor" > "$VAULT/⚙️ Meta/Floors/$floor.md"
done
printf '# helper\n\n[[missing-helper]]\n' > "$VAULT/⚙️ Meta/scripts/README-helper.md"
printf '# pkg\n\n[[missing-pkg]]\n' > "$VAULT/scripts/notes.md"
printf '# Agents\n\n[[missing-agents-target]]\n' > "$VAULT/AGENTS.md"
printf '# Claude\n\n[[missing-claude-target]]\n' > "$VAULT/CLAUDE.md"
# A journal entry may still link a floor note: vendor notes stay link targets.
printf -- '---\ntype: journal\n---\n\nToday on [[one]].\n' > "$VAULT/📓 Journals/2026-01-01.md"

# 1. A fresh vault has no criticals from vendor/package areas.
read -r broken untyped < <(audit_json "$VAULT" | criticals)
[ "$broken" = 0 ] || fail "fresh vault reports $broken broken links from vendor/package areas"
[ "$untyped" = 0 ] || fail "fresh vault reports $untyped untyped notes"
python3 "$PKG/scripts/audit.py" "$VAULT" --strict > "$TMP_ROOT/strict.txt" 2>&1 \
  || fail "audit --strict fails on a fresh vault"

# 2. A user folder named like a package directory is still audited.
mkdir -p "$VAULT/📝 Notes/docs" "$VAULT/📝 Notes/templates" "$VAULT/📝 Notes/tests"
printf -- '---\ntype: note\n---\n\n[[user-docs-missing]]\n' > "$VAULT/📝 Notes/docs/x.md"
printf -- '---\ntype: note\n---\n\n[[user-templates-missing]]\n' > "$VAULT/📝 Notes/templates/y.md"
printf -- '---\ntype: note\n---\n\n[[user-tests-missing]]\n' > "$VAULT/📝 Notes/tests/z.md"
audit_json "$VAULT" > "$TMP_ROOT/user-dirs.json"
for target in user-docs-missing user-templates-missing user-tests-missing; do
  grep -Fq "\"$target\"" "$TMP_ROOT/user-dirs.json" || fail "broken link [[$target]] in a user folder was not reported"
done

# 3. 📝 Notes/Raw/ holds immutable sources: no frontmatter type is required,
#    they are not orphans, and they stay in the pending-ingest queue.
rm -rf "$VAULT/📝 Notes/docs" "$VAULT/📝 Notes/templates" "$VAULT/📝 Notes/tests"
printf '# A source kept exactly as received\n' > "$VAULT/📝 Notes/Raw/fuente.md"
audit_json "$VAULT" > "$TMP_ROOT/raw.json"
read -r broken untyped < <(criticals < "$TMP_ROOT/raw.json")
[ "$untyped" = 0 ] || fail "an untyped source in 📝 Notes/Raw/ is reported as a critical"
python3 - "$TMP_ROOT/raw.json" <<'PY' || fail "a Raw source is an orphan or left the pending-ingest queue"
import json, sys
r = json.load(open(sys.argv[1], encoding="utf-8"))
assert "📝 Notes/Raw/fuente.md" in r["pending_raw"], r["pending_raw"]
assert not any(p.startswith("📝 Notes/Raw/") for p in r["orphan_notes"]), r["orphan_notes"]
PY

if [ "$failures" -ne 0 ]; then
  printf 'FAIL: audit scope had %s failed assertions\n' "$failures" >&2
  exit 1
fi
printf 'PASS: audit scope (vendor areas skipped, user folders audited)\n'
