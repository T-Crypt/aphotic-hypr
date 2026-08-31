#!/usr/bin/env bash
# aphotic packages — advisory-only pending-update check, never applies
# anything. `check` is what aphotic-package-check.service's timer calls
# (Settings -> System's package-check frequency toggle enables/disables
# that timer, see SystemPane.qml) and what its own "Check now" button
# runs on demand -- one code path either way.
# @cmd: packages
# @cmd.desc: Advisory pending-update check (official + AUR), never applies anything
# @cmd.group: LIFECYCLE
# @cmd.opt: check [--notify]           | Print (or notify) pending official/AUR update counts
# @cmd.opt: set-timer <off|daily|weekly> | Enable/disable/reschedule aphotic-package-check.timer

# checkupdates (pacman-contrib, already a base dependency in both install
# profiles) queries a separate synced copy of the pacman db rather than
# the real /var/lib/pacman/sync/ a plain `pacman -Sy` would touch, so
# this needs no sudo and never mutates system state. AUR updates are
# checked the same read-only way via whichever AUR helper is on PATH
# (`-Qua`: query updates, AUR only).
_aphotic_packages_check_counts() {
    local official_count=0 aur_count=0 aur_helper=""

    command -v checkupdates >/dev/null 2>&1 && official_count=$(checkupdates 2>/dev/null | wc -l)

    command -v yay >/dev/null 2>&1 && aur_helper="yay"
    [[ -z "$aur_helper" ]] && command -v paru >/dev/null 2>&1 && aur_helper="paru"
    [[ -n "$aur_helper" ]] && aur_count=$("$aur_helper" -Qua 2>/dev/null | wc -l)

    echo "$official_count $aur_count $aur_helper"
}

aphotic_cmd_packages() {
    local sub="${1:-}"; shift || true

    case "$sub" in
        check)
            local notify=0
            [[ "${1:-}" == "--notify" ]] && notify=1

            local official_count aur_count aur_helper
            read -r official_count aur_count aur_helper < <(_aphotic_packages_check_counts)
            local total=$((official_count + aur_count))

            if [[ "$total" -eq 0 ]]; then
                [[ "$notify" -eq 0 ]] && aphotic_log "no pending package updates"
                return 0
            fi

            local body
            if [[ "$official_count" -gt 0 && "$aur_count" -gt 0 ]]; then
                body="${official_count} official + ${aur_count} AUR package updates available"
            elif [[ "$official_count" -gt 0 ]]; then
                body="${official_count} official package updates available"
            else
                body="${aur_count} AUR package updates available"
            fi
            local hint="sudo pacman -Syu"
            [[ -n "$aur_helper" ]] && hint="${hint} or '${aur_helper} -Sua'"

            if [[ "$notify" -eq 1 ]]; then
                aphotic_require hyprctl || return 0
                hyprctl notify -1 15000 "rgb(7DCFFF)" "Aphotic: ${body}. Run ${hint} to update." >/dev/null 2>&1
            else
                aphotic_log "${body}. Run ${hint} to update."
            fi
            ;;
        set-timer)
            local freq="${1:-}"
            local timer="aphotic-package-check.timer"
            local override_dir="$HOME/.config/systemd/user/${timer}.d"

            case "$freq" in
                off)
                    systemctl --user disable --now "$timer" &>/dev/null || true
                    ;;
                daily)
                    # Shipped Configs/systemd/user/aphotic-package-check.timer
                    # already defaults to OnCalendar=daily -- reverting to it
                    # is just removing any override this command previously
                    # wrote, not writing a new one.
                    rm -f "${override_dir}/override.conf"
                    systemctl --user daemon-reload
                    systemctl --user enable --now "$timer" &>/dev/null || true
                    ;;
                weekly)
                    # A drop-in override, not an edit to the tracked unit
                    # file itself (which install.sh's config sync would
                    # just overwrite on the next run anyway). The empty
                    # `OnCalendar=` line clears the shipped unit's own
                    # daily directive before this one's `OnCalendar=weekly`
                    # takes over -- systemd appends list-type directives
                    # like OnCalendar across drop-ins by default, so
                    # skipping the clear would leave both active.
                    mkdir -p "$override_dir"
                    cat > "${override_dir}/override.conf" <<'EOF'
[Timer]
OnCalendar=
OnCalendar=weekly
EOF
                    systemctl --user daemon-reload
                    systemctl --user enable --now "$timer" &>/dev/null || true
                    ;;
                *)
                    aphotic_err "usage: aphotic packages set-timer <off|daily|weekly>"
                    return 1
                    ;;
            esac
            ;;
        -h|--help|"")
            cat <<EOF
Usage: aphotic packages check [--notify]
       aphotic packages set-timer <off|daily|weekly>

  check                   Print pending official/AUR update counts (never
                          applies them)
  check --notify          Same check, delivered as a Hyprland notification
                          instead of stdout -- what aphotic-package-check
                          .timer calls on schedule
  set-timer <freq>        Enable/disable/reschedule aphotic-package-check
                          .timer -- what Settings -> System's pending-update-
                          check frequency control calls
EOF
            ;;
        *)
            aphotic_err "unknown packages subcommand: ${sub}"
            return 1
            ;;
    esac
}
