#!/usr/bin/env bash
# tests/test_claude_hooks.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/install/claude_hooks.sh"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

HOOK="$WORKDIR/agent_hook.sh"
printf '#!/bin/sh\n' > "$HOOK"
chmod +x "$HOOK"

SETTINGS="$WORKDIR/.claude/settings.json"

# No pre-existing ~/.claude/settings.json -- should create one with all
# four events wired.
HOME="$WORKDIR" configure_claude_code_hooks "$HOOK"
[[ -f "$SETTINGS" ]] || fail "settings.json was not created"
for event in PreToolUse PostToolUse Notification Stop; do
    jq -e --arg cmd "$HOOK" --arg ev "$event" '.hooks[$ev][] | select(.hooks[0].command == $cmd)' "$SETTINGS" >/dev/null \
        || fail "missing $event hook entry"
done

# Re-running must not duplicate the entry.
HOME="$WORKDIR" configure_claude_code_hooks "$HOOK"
count=$(jq --arg cmd "$HOOK" '[.hooks.PreToolUse[] | select(.hooks[0].command == $cmd)] | length' "$SETTINGS")
[[ "$count" -eq 1 ]] || fail "expected exactly one PreToolUse entry after re-running, got $count"

# A pre-existing, unrelated hook on the same event must survive untouched.
echo '{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/some/other/hook.sh"}]}]}}' > "$SETTINGS"
HOME="$WORKDIR" configure_claude_code_hooks "$HOOK"
jq -e '.hooks.PostToolUse[] | select(.matcher == "Bash" and .hooks[0].command == "/some/other/hook.sh")' "$SETTINGS" >/dev/null \
    || fail "pre-existing unrelated PostToolUse hook was clobbered"
jq -e --arg cmd "$HOOK" '.hooks.PostToolUse[] | select(.hooks[0].command == $cmd)' "$SETTINGS" >/dev/null \
    || fail "agent_hook.sh entry missing after merging alongside an existing hook"

# Non-executable hook path should fail cleanly, not corrupt settings.json.
rm -f "$WORKDIR/.claude/settings.json"
NOEXEC="$WORKDIR/not_executable.sh"
touch "$NOEXEC"
if HOME="$WORKDIR" configure_claude_code_hooks "$NOEXEC" 2>/dev/null; then
    fail "expected configure_claude_code_hooks to fail on a non-executable hook path"
fi

echo "PASS: configure_claude_code_hooks wires all four events, is idempotent, and preserves unrelated hooks"
