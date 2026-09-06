#!/usr/bin/env bash
# aphotic agent_statusline -- Claude Code's statusLine command, and the
# only source on this machine for how much of a quota window a harness
# has spent. Invoked once per turn with the session JSON on stdin; what
# it prints becomes the status line the user sees, so it has to be both
# fast and quiet about failure. Same shape as agent_hook.sh: exec into a
# single python3 worker rather than spawning per field, and never exit
# non-zero, because a failing statusLine command is a visible error in
# the user's own terminal.
set -u

hook_dir="${BASH_SOURCE[0]%/*}"
[[ "$hook_dir" == "${BASH_SOURCE[0]}" ]] && hook_dir="."

exec python3 "$hook_dir/agent_statusline.py" || exit 0
