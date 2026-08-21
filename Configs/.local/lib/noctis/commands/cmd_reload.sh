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

    # Quickshell hot-reloads its own QML on file change already — there's
    # no separate "reload" IPC target to call. What this actually needs
    # to guard against: a hot-reload can silently miss an edit (seen
    # firsthand — see the lock screen incident in the SDD ledger), so a
    # clean kill+restart is the only way to *guarantee* the daemon is
    # running the current on-disk QML, not just assume the watcher caught up.
    if pgrep -f "qs -c noctis" >/dev/null 2>&1; then
        noctis_log "restarting quickshell daemon..."
        pkill -f "qs -c noctis" >/dev/null 2>&1
        sleep 0.5
        nohup qs -c noctis >/dev/null 2>&1 &
        disown
        noctis_ok "quickshell daemon restarted"
    else
        noctis_warn "quickshell daemon not running — starting it"
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
