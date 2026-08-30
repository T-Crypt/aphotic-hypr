#!/usr/bin/env bash
# tests/test_codex_hooks.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/install/codex_hooks.sh"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

HOOK="$WORKDIR/codex_hook.sh"
printf '#!/bin/sh\n' > "$HOOK"
chmod +x "$HOOK"

HOOKS="$WORKDIR/.codex/hooks.json"

# No pre-existing ~/.codex/hooks.json -- should create one with all six
# events wired.
HOME="$WORKDIR" configure_codex_hooks "$HOOK"
[[ -f "$HOOKS" ]] || fail "hooks.json was not created"
for event in SessionStart PreToolUse PostToolUse SubagentStop Stop SessionEnd; do
    jq -e --arg cmd "$HOOK" --arg ev "$event" '.hooks[$ev][] | select(.hooks[0].command == $cmd)' "$HOOKS" >/dev/null \
        || fail "missing $event hook entry"
done

# PreToolUse/PostToolUse must run async -- Codex executes those two
# synchronously and a blocking telemetry worker would add latency to every
# tool call.
jq -e --arg cmd "$HOOK" '.hooks.PreToolUse[0].hooks[0] | select(.command == $cmd and .async == true)' "$HOOKS" >/dev/null \
    || fail "PreToolUse hook is not async"
jq -e --arg cmd "$HOOK" '.hooks.PostToolUse[0].hooks[0] | select(.command == $cmd and .async == true)' "$HOOKS" >/dev/null \
    || fail "PostToolUse hook is not async"
jq -e --arg cmd "$HOOK" '.hooks.SessionEnd[0].hooks[0] | select(.command == $cmd and .timeout == 3)' "$HOOKS" >/dev/null \
    || fail "SessionEnd hook is not capped at Codex's 3s timeout"

# Re-running must not duplicate the entry.
HOME="$WORKDIR" configure_codex_hooks "$HOOK"
count=$(jq --arg cmd "$HOOK" '[.hooks.PreToolUse[] | select(.hooks[0].command == $cmd)] | length' "$HOOKS")
[[ "$count" -eq 1 ]] || fail "expected exactly one PreToolUse entry after re-running, got $count"

# A pre-existing, unrelated hook on the same event must survive untouched.
echo '{"hooks":{"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/some/other/hook.sh"}]}]}}' > "$HOOKS"
HOME="$WORKDIR" configure_codex_hooks "$HOOK"
jq -e '.hooks.PostToolUse[] | select(.matcher == "Bash" and .hooks[0].command == "/some/other/hook.sh")' "$HOOKS" >/dev/null \
    || fail "pre-existing unrelated PostToolUse hook was clobbered"
jq -e --arg cmd "$HOOK" '.hooks.PostToolUse[] | select(.hooks[0].command == $cmd)' "$HOOKS" >/dev/null \
    || fail "codex_hook.sh entry missing after merging alongside an existing hook"

# Non-executable hook path should fail cleanly, not corrupt hooks.json.
rm -f "$HOOKS"
NOEXEC="$WORKDIR/not_executable.sh"
touch "$NOEXEC"
if HOME="$WORKDIR" configure_codex_hooks "$NOEXEC" 2>/dev/null; then
    fail "expected configure_codex_hooks to fail on a non-executable hook path"
fi

# remove_codex_hooks drops only Aphotic's entries, prunes emptied events,
# and leaves an unrelated hook on the same event alone.
rm -f "$HOOKS"
HOME="$WORKDIR" configure_codex_hooks "$HOOK"
jq '.hooks.PostToolUse += [{"hooks":[{"type":"command","command":"/some/other/hook.sh"}]}]' "$HOOKS" \
    > "$WORKDIR/hooks.tmp" && mv "$WORKDIR/hooks.tmp" "$HOOKS"
HOME="$WORKDIR" remove_codex_hooks "$HOOK"
jq -e '.hooks.SessionStart == null' "$HOOKS" >/dev/null \
    || fail "emptied event survived remove_codex_hooks"
jq -e '.hooks.PostToolUse | length == 1' "$HOOKS" >/dev/null \
    || fail "unrelated PostToolUse hook did not survive remove_codex_hooks"
jq -e '.hooks.PostToolUse[0].hooks[0].command == "/some/other/hook.sh"' "$HOOKS" >/dev/null \
    || fail "removed the wrong PostToolUse entry"

echo "PASS: configure_codex_hooks wires all six events (async Pre/Post, 3s SessionEnd), is idempotent, and preserves unrelated hooks; remove_codex_hooks prunes only Aphotic's entries"