#!/usr/bin/env bash
# lib/install/claude_hooks.sh
set -euo pipefail

# Wires Configs/.local/lib/aphotic/agent_hook.sh into the user's real
# Claude Code settings.json (~/.claude/settings.json, not a repo-managed
# file) so the bar's agent popout gets live per-session state instead of
# just presence/count -- without this, agent_hook.sh never fires.
# SessionEnd is what retires a session now (Stop fires at the end of every
# assistant turn, not at the end of the session -- an install still on the
# old four-event set leaves idle sessions on screen until agent_hook.py's
# own staleness sweep clears them). Merged
# with jq (guaranteed present, both profiles' prep stage installs it)
# rather than templated, so any hooks the user already has for other
# tools are preserved untouched. Idempotent -- re-running install.sh
# (or a fresh clone at a different path) doesn't duplicate the entry, it
# replaces the one this function itself previously added.
configure_claude_code_hooks() {
  local hook_script="$1"
  local settings_dir="$HOME/.claude"
  local settings_file="$settings_dir/settings.json"

  if [[ ! -x "$hook_script" ]]; then
    echo "agent_hook.sh not found or not executable at $hook_script" >&2
    return 1
  fi

  mkdir -p "$settings_dir"
  [[ -f "$settings_file" ]] || echo '{}' > "$settings_file"

  if ! jq -e . "$settings_file" >/dev/null 2>&1; then
    echo "existing $settings_file is not valid JSON; leaving Claude Code hooks unconfigured" >&2
    return 1
  fi

  local tmp
  tmp="$(mktemp)"
  jq \
    --arg cmd "$hook_script" \
    '
    def entry($timeout): {matcher: "", hooks: [{type: "command", command: $cmd} + (if $timeout > 0 then {timeout: $timeout} else {} end)]};
    def upsert($event; $timeout):
      .hooks[$event] = ((.hooks[$event] // []) | map(select((.hooks // []) | any(.command == $cmd) | not)) + [entry($timeout)]);
    upsert("SessionStart"; 10)
    | upsert("PreToolUse"; 30)
    | upsert("PostToolUse"; 30)
    | upsert("PostToolUseFailure"; 30)
    | upsert("Notification"; 10)
    | upsert("Stop"; 0)
    | upsert("SubagentStop"; 0)
    | upsert("SessionEnd"; 10)
    ' \
    "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"
}

# The inverse of configure_claude_code_hooks, for a re-run where the user
# de-selected the `ai` layer: drops only the entries pointing at this repo's
# own agent_hook.sh and leaves every other hook the user has configured
# untouched. Also prunes hook events left with no entries at all, so
# settings.json doesn't accumulate empty arrays.
remove_claude_code_hooks() {
  local hook_script="$1"
  local settings_file="$HOME/.claude/settings.json"

  [[ -f "$settings_file" ]] || return 0

  if ! jq -e . "$settings_file" >/dev/null 2>&1; then
    echo "existing $settings_file is not valid JSON; leaving Claude Code hooks alone" >&2
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
    "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"
}
