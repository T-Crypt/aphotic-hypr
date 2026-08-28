#!/usr/bin/env bash
# aphotic reload — hot-reload the shell, optionally the full session.
# @cmd: reload
# @cmd.desc: Reload Aphotic shell modules, optionally the full session
# @cmd.group: CORE
# @cmd.opt: --full          | Also reload Hyprland config
# @cmd.opt: --modules-only  | Reload only quickshell modules (default)

aphotic_cmd_reload() {
    local full=0

    for arg in "$@"; do
        case "$arg" in
            --full) full=1 ;;
            --modules-only) full=0 ;;
            -h|--help)
                cat <<EOF
Usage: aphotic reload [--full|--modules-only]

  --modules-only   Reload quickshell modules only (default)
  --full           Also run hyprctl reload after the module reload
EOF
                return 0
                ;;
            *)
                aphotic_warn "reload: ignoring unknown flag '$arg'"
                ;;
        esac
    done

    # Quickshell hot-reloads its own QML on file change already — there's
    # no separate "reload" IPC target to call. What this actually needs
    # to guard against: a hot-reload can silently miss an edit (seen
    # firsthand — see the lock screen incident in the SDD ledger), so a
    # clean kill+restart is the only way to *guarantee* the daemon is
    # running the current on-disk QML, not just assume the watcher caught up.
    #
    # Real bug this used to have: under the normal install, the daemon
    # runs as aphotic-shell.service (Restart=on-failure). A bare `pkill -f
    # "qs -c aphotic"` sends SIGTERM, which systemd counts as a failure
    # and auto-respawns from -- so the old unconditional "pkill, sleep,
    # manually launch a new one" below raced systemd's own respawn and
    # left TWO untracked `qs` processes running (one systemd's, one this
    # script's own orphan, neither aware of the other). Found live via a
    # doubled notification-server-registration warning and a genuinely
    # confusing round of screenshot testing. Route through `systemctl
    # --user restart` when the unit exists -- the exact same path the
    # SUPER+B keybind already uses (see keybinds.lua) -- so there's a
    # single source of truth for "restart the shell" instead of two. Only
    # falls back to the manual pkill+relaunch for a dev/debug session
    # where `qs -c aphotic` was started bypassing the service entirely.
    if systemctl --user list-unit-files aphotic-shell.service >/dev/null 2>&1; then
        aphotic_log "restarting quickshell daemon (aphotic-shell.service)..."
        systemctl --user restart aphotic-shell.service
        aphotic_ok "quickshell daemon restarted"
    elif pgrep -f "qs -c aphotic" >/dev/null 2>&1; then
        aphotic_log "restarting quickshell daemon..."
        pkill -f "qs -c aphotic" >/dev/null 2>&1
        sleep 0.5
        nohup qs -c aphotic >/dev/null 2>&1 &
        disown
        aphotic_ok "quickshell daemon restarted"
    else
        aphotic_warn "quickshell daemon not running — starting it"
        nohup qs -c aphotic >/dev/null 2>&1 &
        disown
        aphotic_ok "quickshell daemon started"
    fi

    if [[ "$full" -eq 1 ]]; then
        aphotic_require hyprctl || return 1
        aphotic_log "reloading Hyprland..."
        hyprctl reload && aphotic_ok "hyprland reloaded"
    fi
}
