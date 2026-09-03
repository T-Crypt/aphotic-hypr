#!/usr/bin/env bash
# lib/install/ui.sh
set -euo pipefail

# Every interactive stage prompt goes through these three -- the one place
# that owns the "[ACTION]" formatting and y/n parsing, replacing what used
# to be ~8 ad hoc `read -rep` call sites with their own inconsistent y/n
# checks (install.sh/assistant.sh matched `== "Y" || == "y"` literally;
# wizard.sh already used the more permissive `^[Yy]$` regex below, which is
# the one convention this project now uses everywhere). `printf '%b'`
# expands install.sh's existing `$CAC`/etc color vars (literal backslash-e,
# meant for `echo -e`) into real escape bytes, since `read -rep`'s prompt
# argument -- unlike `echo -e` -- never interprets `\e` itself.
_ui_action_tag() { printf '%b' "${CAC:-[ACTION]}"; }

# Where every "please report this" path in the installer points.
APHOTIC_ISSUES_URL="${APHOTIC_ISSUES_URL:-https://github.com/T-Crypt/Aphotic-Hypr/issues}"

# Keep every <prompt> here to one short line and echo any explanation
# above the call instead: `read -e` hands the prompt to readline, which
# redraws a prompt longer than the terminal width as a truncated "<...end
# of prompt" fragment, so a wordy question silently loses its beginning on
# an 80-column terminal.
#
# confirm <prompt> [default: y|n] -- returns 0 for yes, 1 for no. A closed/
# exhausted stdin (read failing outright, not just an empty Enter) always
# resolves to "no" regardless of the requested default -- matching what
# every prompt site this replaces did on EOF, since assuming "yes" to
# something like installing a GPU-dependent assistant with nobody there to
# ask is never the safe fallback.
confirm() {
  local prompt="$1" default="${2:-n}" answer hint
  [[ "$default" == "y" ]] && hint="Y/n" || hint="y/N"
  if ! read -rep "$(_ui_action_tag) - $prompt ($hint) " answer; then
    answer="n"
  fi
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy]$ ]]
}

# choose <prompt> <default-value> -- echoes the typed value, or the default
# on an empty answer or closed stdin. Caller validates the value if only
# specific answers are meaningful.
choose() {
  local prompt="$1" default="$2" answer
  read -rep "$(_ui_action_tag) - $prompt [$default] " answer || answer="$default"
  echo "${answer:-$default}"
}

# prompt_text <prompt> -- echoes the raw typed value, which may be empty.
prompt_text() {
  local prompt="$1" answer
  read -rep "$(_ui_action_tag) - $prompt " answer || answer=""
  echo "$answer"
}
