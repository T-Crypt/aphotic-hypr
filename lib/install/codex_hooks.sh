#!/usr/bin/env bash
# lib/install/codex_hooks.sh
set -euo pipefail

# Wires Configs/.local/lib/aphotic/codex_hook.sh into the user's real
# Codex hooks file (~/.codex/hooks.json, the dedicated user-level hooks
# source Codex looks at next to config.toml -- deliberately not
# config.toml, so the user's own provider/auth/MCP settings there are
# never touched) so the bar's agent popout and the agent graph get live
# per-session state for Codex the same way they already do for Claude
# Code, instead of presence/count only. Without this, codex_hook.sh never
# fires.
#
# Codex's hooks.json uses the same event schema as Claude Code's
# settings.json hooks for the events Aphotic wires (SessionStart,
# PreToolUse, PostToolUse, SubagentStop, Stop, SessionEnd all hand the
# hooked command a JSON payload whose field names -- session_id,
# hook_event_name, tool_name, tool_use_id, agent_id, agent_type, model,
# cwd -- already match what agent_hook.py reads), so the adapter only
# needs to translate at Codex's own boundary (see
# Configs/.local/lib/aphotic/codex_hook.py), never a second input shape
# for agent_hook.py. PostToolUseFailure and Notification do not exist in
# Codex's hook schema at all.
#
# Merged with jq (guaranteed present, both profiles' prep stage installs
# it) rather than templated, so any hooks the user already has for other
# tools are preserved untouched. Idempotent -- re-running install.sh
# (or a fresh clone at a different path) doesn't duplicate the entry, it
# replaces the one this function itself previously added. PreToolUse and
# PostToolUse run async because Codex executes those two events
# synchronously (they block the calling session's own tool call); async
# keeps the telemetry worker off the critical path. SessionEnd is capped
# at 3 seconds by Codex itself, so that timeout is hard-stopped there.
configure_codex_hooks() {
  local hook_script="$1"
  local hooks_dir="$HOME/.codex"
  local hooks_file="$hooks_dir/hooks.json"

  if [[ ! -x "$hook_script" ]]; then
    echo "codex_hook.sh not found or not executable at $hook_script" >&2
    return 1
  fi

  mkdir -p "$hooks_dir"
  [[ -f "$hooks_file" ]] || echo '{}' > "$hooks_file"

  if ! jq -e . "$hooks_file" >/dev/null 2>&1; then
    echo "existing $hooks_file is not valid JSON; leaving Codex hooks unconfigured" >&2
    return 1
  fi

  local tmp
  tmp="$(mktemp)"
  jq \
    --arg cmd "$hook_script" \
    '
    def entry($timeoutSec; $async):
      {matcher: "", hooks: ([{type: "command", command: $cmd}
        + (if $timeoutSec > 0 then {timeoutSec: $timeoutSec} else {} end)
        + (if $async then {async: true} else {} end)])};
    def upsert($event; $timeoutSec; $async):
      .hooks[$event] = ((.hooks[$event] // [])
        | map(select((.hooks // []) | any(.command == $cmd) | not))
        + [entry($timeoutSec; $async)]);
    upsert("SessionStart"; 5; false)
    | upsert("PreToolUse"; 10; true)
    | upsert("PostToolUse"; 10; true)
    | upsert("SubagentStop"; 5; false)
    | upsert("Stop"; 5; false)
    | upsert("SessionEnd"; 3; false)
    ' \
    "$hooks_file" > "$tmp" && mv "$tmp" "$hooks_file"
}

# The inverse of configure_codex_hooks, for a re-run where the user
# de-selected the `ai` layer: drops only the entries pointing at this
# repo's own codex_hook.sh and leaves every other hook the user has
# configured untouched. Also prunes hook events left with no entries at
# all, so hooks.json doesn't accumulate empty arrays.
remove_codex_hooks() {
  local hook_script="$1"
  local hooks_file="$HOME/.codex/hooks.json"

  [[ -f "$hooks_file" ]] || return 0

  if ! jq -e . "$hooks_file" >/dev/null 2>&1; then
    echo "existing $hooks_file is not valid JSON; leaving Codex hooks alone" >&2
    return 1
  fi

  local tmp
  tmp="$(mktemp)"
  jq \
    --arg cmd "$hook_script" \
    '
    (.hooks // {}) as $hooks
    | .hooks = ($hooks
        | with_entries(.value |= map(select((.hooks // []) | any(.command == $cmd) | not)))
        | with_entries(select((.value | length) > 0)))
    ' \
    "$hooks_file" > "$tmp" && mv "$tmp" "$hooks_file"
}