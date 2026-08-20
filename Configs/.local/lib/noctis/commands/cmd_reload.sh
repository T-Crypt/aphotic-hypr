#!/usr/bin/env bash
# noctis reload — hot-reload the shell, optionally the full session.
# @cmd: reload
# @cmd.desc: Reload Noctis shell modules, optionally the full session
# @cmd.opt: --full          | Also reload Hyprland config
# @cmd.opt: --modules-only  | Reload only quickshell modules (default)

noctis_cmd_reload() {
    local full=0

    for arg in "$@"; do
        case "$arg" in
            --full) full=1 ;;
            --modules-only) full=0 ;;
            -h|--help)
                cat <<EOF
Usage: noctis reload [--full|--modules-only]

  --modules-only   Reload quickshell modules only (default)
  --full           Also run hyprctl reload after the module reload
EOF
                return 0
                ;;
            *)
                noctis_warn "reload: ignoring unknown flag '$arg'"
                ;;
        esac
    done

    noctis_log "reloading quickshell modules..."
    # NOTE: exact IPC call name is a placeholder until the daemon's IPC
    # surface is implemented (see quickshell/noctis/ipc/*). Mirrors
    # caelestia's `caelestia shell <ipc-call>` pattern.
    if pgrep -f "qs -c noctis" >/dev/null 2>&1; then
        if qs -c noctis ipc call reload >/dev/null 2>&1; then
            noctis_ok "quickshell modules reloaded"
        else
            noctis_warn "IPC reload call failed — daemon running but not responding"
        fi
    else
        noctis_warn "quickshell daemon not running — starting it (noctis shell -d)"
        nohup qs -c noctis >/dev/null 2>&1 &
        disown
        noctis_ok "quickshell daemon started"
    fi

    if [[ "$full" -eq 1 ]]; then
        noctis_require hyprctl || return 1
        noctis_log "reloading Hyprland..."
        hyprctl reload && noctis_ok "hyprland reloaded"
    fi
}
