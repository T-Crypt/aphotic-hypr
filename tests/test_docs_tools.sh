#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
DOCS="$WORKDIR/docs"
BIN="$WORKDIR/bin"
mkdir -p "$DOCS/reference" "$DOCS/archive" "$BIN"

cat > "$DOCS/OVERVIEW.md" <<'EOF'
# Fixture overview

Explains the fixture documentation. A second sentence is not part of the purpose.

## Alpha
Falcon falcon falcon details live here.

### Alpha child
Child details.

## Beta
Turtle details live here.
EOF

cat > "$DOCS/reference/OPERATIONS.md" <<'EOF'
# Operations

Runbook for the fixture.

## In flight
PR #42 is open while the falcon work continues.

## Paths
The tracked file is `tests/test_docs_tools.sh`.
The existing source is `tests/test_agent_hook.py:1`.
Templates may use `profiles/base/*.toml`.
EOF

cat > "$DOCS/STATUS.md" <<'EOF'
# Status

Updated: 2099-01-01

## In flight
Keep this handwritten context.

## Session notes
Existing note.
EOF

cat > "$DOCS/DECISIONS.md" <<'EOF'
# Decisions

### D-01 · 2026-01-01 · Existing decision
EOF

{
    printf '# Many matches\n\nFixture sections for budget testing.\n'
    for number in $(seq 1 60); do
        printf '\n## Match %02d\nFalcon details fill this fixture section so the final ranked block must be truncated to the requested budget.\n' "$number"
    done
} > "$DOCS/MATCHES.md"

: > "$DOCS/LEDGER.md"
for number in $(seq 1 180); do
    printf '## 2099-01-01 · Verbose fixture ledger entry number %03d with searchable detail\nBody.\n\n' "$number" >> "$DOCS/LEDGER.md"
done
cat > "$DOCS/archive/RETIRED.md" <<'EOF'
# Retired notes

Old material that is no longer a source of truth.

## Falcon archive
Falcon appears here too.
EOF

python3 "$ROOT/tools/docs/index.py" --docs "$DOCS"
[[ -f "$DOCS/INDEX.md" ]] || fail "index.py did not write INDEX.md"
[[ -f "$DOCS/.index.json" ]] || fail "index.py did not write .index.json"
[[ $(wc -c < "$DOCS/INDEX.md") -le 24576 ]] || fail "fixture index exceeds 24 KiB"
index_sum=$(sha256sum "$DOCS/INDEX.md" "$DOCS/.index.json")
python3 "$ROOT/tools/docs/index.py" --docs "$DOCS"
[[ "$index_sum" == "$(sha256sum "$DOCS/INDEX.md" "$DOCS/.index.json")" ]] || fail "index output is not deterministic"
grep -q 'OVERVIEW.md' "$DOCS/INDEX.md" || fail "index omits OVERVIEW.md"
if grep -q 'archive/RETIRED.md' "$DOCS/INDEX.md"; then fail "index includes retired documentation"; fi
grep -q '5-10:Alpha' "$DOCS/INDEX.md" || fail "index omits Alpha's section range"
grep -q 'Explains the fixture documentation\.' "$DOCS/INDEX.md" || fail "index purpose is wrong"
python3 - "$DOCS/.index.json" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
ledger = next(item for item in data["files"] if item["path"] == "LEDGER.md")
assert ledger["sections"][0]["heading"].endswith("searchable detail")
PY

alpha=$(python3 "$ROOT/tools/docs/section.py" --docs "$DOCS" OVERVIEW.md alpha)
[[ "$alpha" == *"## Alpha"* ]] || fail "section heading lookup omitted its heading"
[[ "$alpha" == *"### Alpha child"* ]] || fail "section heading lookup omitted its child section"
[[ "$alpha" != *"## Beta"* ]] || fail "section heading lookup crossed into the next section"

range=$(python3 "$ROOT/tools/docs/section.py" --docs "$DOCS" OVERVIEW.md 5-6)
[[ "$range" == $'## Alpha\nFalcon falcon falcon details live here.' ]] || fail "line-range lookup returned the wrong text"

ask=$(python3 "$ROOT/tools/docs/ask.py" --docs "$DOCS" "where are falcon details" --budget 200)
[[ "${ask%%$'\n'*}" == "OVERVIEW.md:5-7" ]] || fail "ask.py did not rank the strongest section first"
small=$(python3 "$ROOT/tools/docs/ask.py" --docs "$DOCS" "falcon" --budget 20)
[[ ${#small} -le 80 ]] || fail "ask.py exceeded its token budget"
python3 "$ROOT/tools/docs/ask.py" --docs "$DOCS" "falcon" --budget 500 > "$WORKDIR/ask-many.txt"
many_chars=$(python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read()))' "$WORKDIR/ask-many.txt")
[[ "$many_chars" -le 2000 ]] || fail "ask.py failed to count its final newline against the token budget"

cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2 $3 $4" == "pr view 42 --json" ]]; then
    printf '{"state":"MERGED"}\n'
    exit 0
fi
if [[ "$1 $2 $3 $4" == "pr list --state open" ]]; then
    printf '[{"number":77,"title":"Fixture work","headRefName":"feature/fixture","baseRefName":"main","isDraft":false,"updatedAt":"2099-01-01T00:00:00Z"}]\n'
    exit 0
fi
exit 2
EOF
chmod +x "$BIN/gh"

if PATH="$BIN:$PATH" python3 "$ROOT/tools/docs/check.py" --docs "$DOCS" --json > "$WORKDIR/check.json"; then
    fail "check.py did not fail for a merged PR described as open"
fi
python3 - "$WORKDIR/check.json" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
findings = data["findings"]
assert any(item["type"] == "pr" and item["line"] == 6 for item in findings), findings
assert not any(item["type"] == "path" and item["claim"] == "tests/test_agent_hook.py:1" for item in findings), findings
assert not any(item["type"] == "path" and "*" in item["claim"] for item in findings), findings
PY

PATH="$BIN:$PATH" python3 "$ROOT/tools/docs/status.py" --docs "$DOCS" --write
first=$(sha256sum "$DOCS/STATUS.md")
PATH="$BIN:$PATH" python3 "$ROOT/tools/docs/status.py" --docs "$DOCS" --write
second=$(sha256sum "$DOCS/STATUS.md")
[[ "$first" == "$second" ]] || fail "status.py --write is not idempotent"
grep -q '<!-- generated:in-flight:start -->' "$DOCS/STATUS.md" || fail "status.py omitted the start marker"
grep -q 'PR #77.*Fixture work' "$DOCS/STATUS.md" || fail "status.py omitted the open PR"
grep -q 'Keep this handwritten context\.' "$DOCS/STATUS.md" || fail "status.py replaced handwritten prose"

python3 "$ROOT/tools/docs/note.py" --docs "$DOCS" --kind decision "New fixture decision"
grep -q 'D-02.*New fixture decision' "$DOCS/DECISIONS.md" || fail "note.py did not allocate the next decision number"
python3 "$ROOT/tools/docs/note.py" --docs "$DOCS" --kind ledger "Fixture shipped"
grep -q 'Fixture shipped' "$DOCS/LEDGER.md" || fail "note.py did not append to the ledger"

HOOK_REPO="$WORKDIR/hook-repo"
mkdir -p "$HOOK_REPO"
git -C "$HOOK_REPO" init -q
(cd "$HOOK_REPO" && bash "$ROOT/tools/docs/install-hooks.sh") >/dev/null
[[ "$(git -C "$HOOK_REPO" config --get core.hooksPath)" == ".githooks" ]] || fail "install-hooks.sh set the wrong hooks path"
[[ -x "$ROOT/.githooks/post-merge" && -x "$ROOT/.githooks/post-checkout" ]] || fail "docs hooks are not executable"
(cd "$HOOK_REPO" && "$ROOT/.githooks/post-merge") || fail "post-merge blocks Git when docs are absent"
(cd "$HOOK_REPO" && "$ROOT/.githooks/post-checkout") || fail "post-checkout blocks Git when docs are absent"

echo "PASS: docs index, section lookup, search, checks, generated status, and append-only notes"
