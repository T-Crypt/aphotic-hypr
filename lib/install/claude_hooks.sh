#!/usr/bin/env bash
# lib/install/claude_hooks.sh
set -euo pipefail

# Wires Configs/.local/lib/aphotic/agent_hook.sh into the user's real
# Claude Code settings.json (~/.claude/settings.json, not a repo-managed
# file) so the bar's agent popout gets live per-session state instead of
# just presence/count -- without this, agent_hook.sh never fires. Merged
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
    upsert("PreToolUse"; 30)
    | upsert("PostToolUse"; 30)
    | upsert("Notification"; 10)
    | upsert("Stop"; 0)
    ' \
    "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"
}
