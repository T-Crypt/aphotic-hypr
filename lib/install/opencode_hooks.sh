#!/usr/bin/env bash
# lib/install/opencode_hooks.sh
set -euo pipefail

# Symlinks Configs/.local/lib/aphotic/opencode_hook.js into OpenCode's own
# global plugin auto-discovery directory (~/.config/opencode/plugins/ --
# any .js/.ts file dropped there loads at startup, no config.json entry
# needed) so the bar's agent popout and the agent graph get live
# per-session state for OpenCode the same way they already do for Claude
# Code, instead of presence/count only. A symlink (not a copy) so the repo
# is the only place the plugin's actual logic ever needs editing, same
# reasoning as configure_claude_code_hooks pointing straight at
# agent_hook.sh rather than a copied version.
configure_opencode_hook() {
  local plugin_script="$1"
  local plugin_dir="$HOME/.config/opencode/plugins"

  if [[ ! -f "$plugin_script" ]]; then
    echo "opencode_hook.js not found at $plugin_script" >&2
    return 1
  fi

  mkdir -p "$plugin_dir"
  ln -sfn "$plugin_script" "$plugin_dir/opencode_hook.js"
}

# The inverse, for a re-run where the user de-selected the `ai` layer --
# only removes the symlink this function itself would have created, never
# touches any other plugin the user has in that directory.
remove_opencode_hook() {
  local plugin_dir="$HOME/.config/opencode/plugins"
  local link="$plugin_dir/opencode_hook.js"

  [[ -L "$link" ]] && rm -f "$link"
  return 0
}
