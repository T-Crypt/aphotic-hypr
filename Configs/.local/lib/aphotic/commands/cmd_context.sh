#!/usr/bin/env bash
# aphotic context — show or switch the running shell's runtime context.
# @cmd: context
# @cmd.desc: Show or switch the runtime context (default/focus/dev/game/present)
# @cmd.group: CONFIG
# @cmd.opt: list                | List contexts, the active one starred
# @cmd.opt: current             | Print the active context
# @cmd.opt: set <name>          | Switch context
# @cmd.opt: revert              | Back to the context before the last switch
#
# Thin wrapper around the shell's "context" IPC target (shell.qml over
# services/RuntimeContext.qml). A context changes how running surfaces
# behave -- popups, decorative motion, when resource state is shown -- and
# installs or starts nothing, so there is no state file here: the running
# shell is the only owner, and a restart lands back in `default`.

_aphotic_context_ipc() {
    aphotic_require qs || return 1
    local out
    if ! out="$(qs -c aphotic ipc call context "$@" 2>/dev/null)"; then
        aphotic_err "failed to reach the running shell via qs ipc -- is 'qs -c aphotic' running?"
        return 1
    fi
    printf '%s\n' "$out"
}

_aphotic_context_set() {
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        aphotic_err "usage: aphotic context set <name>  (see: aphotic context list)"
        return 1
    fi
    if [[ ! "$name" =~ ^[a-z][a-z0-9-]*$ ]]; then
        aphotic_err "invalid context name '${name}'"
        return 1
    fi
    local out
    out="$(_aphotic_context_ipc set "$name")" || return 1
    if [[ "$out" == unknown* ]]; then
        aphotic_err "$out"
        return 1
    fi
    aphotic_ok "context set to '${out}'"
}

aphotic_cmd_context() {
    local sub="${1:-current}"
    shift || true
    case "$sub" in
        list) _aphotic_context_ipc list ;;
        current) _aphotic_context_ipc current ;;
        set) _aphotic_context_set "$@" ;;
        revert)
            local out
            out="$(_aphotic_context_ipc revert)" || return 1
            aphotic_ok "context reverted to '${out}'"
            ;;
        -h|--help)
            cat <<USAGE
Usage: aphotic context <list|current|set|revert> [name]

  list          List contexts, the active one starred
  current       Print the active context (default)
  set <name>    Switch context
  revert        Back to the context before the last switch
USAGE
            ;;
        *)
            aphotic_err "unknown context subcommand: ${sub}"
            return 1
            ;;
    esac
}
