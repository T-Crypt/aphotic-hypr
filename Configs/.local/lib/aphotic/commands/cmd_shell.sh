#!/usr/bin/env bash
# aphotic shell — start the quickshell daemon or pass through an IPC call.
# @cmd: shell
# @cmd.desc: Start the quickshell daemon, or forward an IPC call to it
# @cmd.group: CORE
# @cmd.opt: -d, --daemon    | Start in daemon mode (backgrounded)
# @cmd.opt: <ipc-call> ...  | Forward args to `qs -c aphotic ipc call ...`

aphotic_cmd_shell() {
    case "${1:-}" in
        -h|--help)
            cat <<HELP
Usage: aphotic shell [-d|--daemon]
       aphotic shell <ipc-call> [args]

  -d, --daemon   Start the quickshell daemon in the background
  <ipc-call>     Anything else is forwarded to the running daemon's IPC

Real IPC targets (see Configs/quickshell/aphotic/shell.qml):
  aphotic shell launcher toggle
  aphotic shell session toggle
  aphotic shell dashboard toggle
  aphotic shell lock engage
  aphotic shell lock unlock
  aphotic shell lock isLocked
  aphotic shell notifs clear
HELP
            ;;
        -d|--daemon|"")
            aphotic_require qs || return 1
            aphotic_log "starting quickshell daemon (qs -c aphotic)..."
            nohup qs -c aphotic >>"${APHOTIC_STATE_HOME}/shell.log" 2>&1 &
            disown
            aphotic_ok "daemon started, logging to ${APHOTIC_STATE_HOME}/shell.log"
            ;;
        *)
            aphotic_require qs || return 1
            qs -c aphotic ipc call "$@"
            ;;
    esac
}
