#!/usr/bin/env bash
# noctis shell — start the quickshell daemon or pass through an IPC call.
# @cmd: shell
# @cmd.desc: Start the quickshell daemon, or forward an IPC call to it
# @cmd.opt: -d, --daemon    | Start in daemon mode (backgrounded)
# @cmd.opt: <ipc-call> ...  | Forward args to `qs -c noctis ipc call ...`

noctis_cmd_shell() {
    case "${1:-}" in
        -h|--help)
            cat <<HELP
Usage: noctis shell [-d|--daemon]
       noctis shell <ipc-call> [args]

  -d, --daemon   Start the quickshell daemon in the background
  <ipc-call>     Anything else is forwarded to the running daemon's IPC,
                 e.g. \`noctis shell mpris getActive title\`

TODO: implement once quickshell/noctis/ipc/* defines real IPC targets.
Mirrors caelestia's \`caelestia shell mpris getActive trackTitle\` pattern.
HELP
            ;;
        -d|--daemon|"")
            noctis_require qs || return 1
            noctis_log "starting quickshell daemon (qs -c noctis)..."
            nohup qs -c noctis >>"${NOCTIS_STATE_HOME}/shell.log" 2>&1 &
            disown
            noctis_ok "daemon started, logging to ${NOCTIS_STATE_HOME}/shell.log"
            ;;
        *)
            noctis_require qs || return 1
            qs -c noctis ipc call "$@"
            ;;
    esac
}
