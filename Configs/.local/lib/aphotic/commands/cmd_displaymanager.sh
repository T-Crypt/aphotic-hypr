#!/usr/bin/env bash
# aphotic displaymanager — report and switch which display manager owns
# the login screen (sddm, or the greetd/Quickshell greeter).
# @cmd: displaymanager
# @cmd.desc: Report or switch the active display manager (sddm/greetd)
# @cmd.group: CONFIG
# @cmd.opt: status                        | Report which display manager is enabled/active (default)
# @cmd.opt: switch <sddm|greetd> [--confirm-tested] | Switch the active display manager
#
# Deliberately separate from install.sh: install.sh's opt-in greetd path
# (setup_greetd_greeter, lib/install/config_deploy.sh) only ever deploys
# the greeter scaffold -- it never flips which display manager is actually
# enabled. This command is the one place that does, and only when asked
# for by name with an explicit --confirm-tested flag, per
# docs/archive/BACKLOG.md's DM-02 entry: a broken switch here can lock
# every user out of login, so nothing about it is ever automatic.

APHOTIC_GREETD_CONFIG="/etc/greetd/config.toml"
APHOTIC_GREETD_BACKUP="/etc/greetd/config.toml.aphotic-backup"
APHOTIC_GREETER_QML="/etc/xdg/quickshell/aphotic-greeter/shell.qml"
APHOTIC_GREETER_HYPR_CONF="/etc/greetd/aphotic/hyprland-greeter.conf"

_aphotic_dm_unit_state() {
    local unit="$1" enabled active
    # `systemctl is-enabled`/`is-active` print real, valid text ("disabled",
    # "masked", "inactive") on a NON-ZERO exit code -- that's documented
    # behavior for a legitimately negative state, not just for a missing
    # unit. `cmd || echo "unknown"` ran the echo on every negative state
    # too, and since $(...) captures both commands' stdout when the first
    # one fails, the result was the real value with "unknown" appended
    # right after it on its own line (seen live: "enabled: disabled
    # unknown"). Checking for empty output is what actually means
    # "nothing came back", and `|| true` on both keeps set -e from
    # treating the expected non-zero exit as a hard abort.
    enabled="$(systemctl is-enabled "$unit" 2>/dev/null)" || true
    [[ -z "$enabled" ]] && enabled="unknown"
    active="$(systemctl is-active "$unit" 2>/dev/null)" || true
    [[ -z "$active" ]] && active="unknown"
    printf '%s (enabled: %s, active: %s)\n' "$unit" "$enabled" "$active"
}

_aphotic_dm_status() {
    echo "Display manager:"
    printf '  %s\n' "$(_aphotic_dm_unit_state sddm.service)"
    printf '  %s\n' "$(_aphotic_dm_unit_state greetd.service)"
    echo
    echo "Aphotic greeter scaffold:"
    if [[ -f "$APHOTIC_GREETER_QML" ]]; then
        printf '  [ok]   %s\n' "$APHOTIC_GREETER_QML"
    else
        printf '  [MISS] %s (run install.sh with --with-greetd-preview, or --config-only after enabling it)\n' "$APHOTIC_GREETER_QML"
    fi
    if [[ -f "$APHOTIC_GREETER_HYPR_CONF" ]]; then
        printf '  [ok]   %s\n' "$APHOTIC_GREETER_HYPR_CONF"
    else
        printf '  [MISS] %s\n' "$APHOTIC_GREETER_HYPR_CONF"
    fi
    if command -v greetd >/dev/null 2>&1; then
        printf '  [ok]   greetd binary on PATH\n'
    else
        printf '  [MISS] greetd package not installed\n'
    fi
}

_aphotic_dm_print_validation_steps() {
    cat <<STEPS
Before switching, validate the greeter *without* making greetd the active
display manager:

  1. Temporarily set a password for the 'greeter' system user:
       sudo passwd greeter
  2. Switch to a spare, unused VT (e.g. Ctrl+Alt+F3) and log in as 'greeter'.
  3. Run the exact command greetd would run:
       Hyprland --config ${APHOTIC_GREETER_HYPR_CONF}
  4. Confirm the Aphotic greeter renders, accepts a real username/password,
     and hands off to your real Hyprland session on success.
  5. Ctrl+Alt+F<N> back to your normal session, then remove the password
     you just set:
       sudo passwd -l greeter

Only once that round-trip works should you re-run this with --confirm-tested.
STEPS
}

_aphotic_dm_switch_to_greetd() {
    if [[ ! -f "$APHOTIC_GREETER_QML" || ! -f "$APHOTIC_GREETER_HYPR_CONF" ]]; then
        aphotic_err "greeter scaffold not deployed yet -- re-run install.sh with --with-greetd-preview first"
        return 1
    fi
    if ! command -v greetd >/dev/null 2>&1; then
        aphotic_err "greetd is not installed -- add it via install.sh's --with-greetd-preview, or 'sudo pacman -S greetd'"
        return 1
    fi

    aphotic_log "Backing up the current greetd config (if any)..."
    if [[ -f "$APHOTIC_GREETD_CONFIG" && ! -f "$APHOTIC_GREETD_BACKUP" ]]; then
        sudo cp "$APHOTIC_GREETD_CONFIG" "$APHOTIC_GREETD_BACKUP"
    fi

    aphotic_log "Writing the Aphotic greeter's greetd config..."
    sudo cp "${APHOTIC_DOTS_DIR}/Configs/greetd/config.toml" "$APHOTIC_GREETD_CONFIG"

    aphotic_log "Disabling sddm (left installed, not removed -- this is the rollback)..."
    sudo systemctl disable sddm.service &>/dev/null || true

    aphotic_log "Enabling greetd for next boot (not starting it now, to avoid switching VT out from under this session)..."
    sudo systemctl enable greetd.service

    aphotic_ok "greetd will take over the login screen on next reboot."
    aphotic_log "To go back at any time: aphotic displaymanager switch sddm --confirm-tested"
}

_aphotic_dm_switch_to_sddm() {
    aphotic_log "Disabling greetd..."
    sudo systemctl disable greetd.service &>/dev/null || true

    if [[ -f "$APHOTIC_GREETD_BACKUP" ]]; then
        aphotic_log "Restoring the greetd config that was active before the switch to greetd..."
        sudo cp "$APHOTIC_GREETD_BACKUP" "$APHOTIC_GREETD_CONFIG"
    fi

    aphotic_log "Re-enabling sddm..."
    sudo systemctl enable --now sddm.service

    aphotic_ok "sddm is the active display manager again."
}

_aphotic_dm_switch() {
    local target="${1:-}" confirm="${2:-}"

    case "$target" in
        greetd|sddm) ;;
        *)
            aphotic_err "usage: aphotic displaymanager switch <sddm|greetd> [--confirm-tested]"
            return 1
            ;;
    esac

    if [[ "$confirm" != "--confirm-tested" ]]; then
        _aphotic_dm_print_validation_steps
        aphotic_warn "refusing to switch without --confirm-tested (see steps above)"
        return 1
    fi

    if [[ "$target" == "greetd" ]]; then
        _aphotic_dm_switch_to_greetd
    else
        _aphotic_dm_switch_to_sddm
    fi
}

aphotic_cmd_displaymanager() {
    local sub="${1:-status}"
    case "$sub" in
        status) _aphotic_dm_status ;;
        switch) shift || true; _aphotic_dm_switch "${1:-}" "${2:-}" ;;
        ""|-h|--help)
            cat <<HELP
Usage: aphotic displaymanager [status|switch <sddm|greetd> [--confirm-tested]]

  status                        Report which display manager is enabled/active,
                                 and whether the Aphotic greeter scaffold is deployed.
  switch <sddm|greetd>          Switch the active display manager. Refuses to run
                                 without --confirm-tested; run it once first to see
                                 the manual validation steps.
HELP
            ;;
        *)
            aphotic_err "unknown displaymanager subcommand: ${sub}"
            return 1
            ;;
    esac
}
