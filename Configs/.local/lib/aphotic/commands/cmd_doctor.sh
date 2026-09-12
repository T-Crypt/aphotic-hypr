#!/usr/bin/env bash
# aphotic doctor — dependency + version drift check.
# @cmd: doctor
# @cmd.desc: Check dependencies and report version/config drift
# @cmd.group: CORE

_aphotic_doctor_check() {
    local bin="$1"
    if command -v "$bin" >/dev/null 2>&1; then
        printf '  [ok]   %s\n' "$bin"
    else
        printf '  [MISS] %s\n' "$bin"
    fi
}

# A layer installs the tooling; a plugin is what makes the shell react to
# it. Nothing forces the two to agree, so a machine can have the `gaming`
# layer with no gaming plugin installed and silently get none of the
# behaviour it paid for -- which is exactly the state an upgrade past
# PLG-03 leaves behind. Driven off the plugin catalogue's own
# `requires_layer` declarations rather than a hardcoded layer->plugin map:
# core must never name a plugin (docs/PLUGIN_LAYER_MODEL.md).
_aphotic_doctor_layer_plugins() {
    local repo="${APHOTIC_PLUGINS_REPO:-$HOME/aphotic-plugins}" manifest name layer layers found=0

    [[ -d "$repo" ]] || {
        echo "  [skip] plugin catalogue not cloned ($repo)"
        return 0
    }

    layers="$(aphotic_toml_get_array "${APHOTIC_DOTS_DIR}/aphotic.toml" install layers | tr '\n' ' ')"
    [[ -n "${layers// /}" ]] || {
        echo "  [skip] no layers recorded in aphotic.toml"
        return 0
    }

    for manifest in "$repo"/*/plugin.toml; do
        [[ -f "$manifest" ]] || continue
        name="$(basename "$(dirname "$manifest")")"
        layer="$(aphotic_toml_get "$manifest" profile requires_layer)"
        [[ -n "$layer" ]] || layer="$(aphotic_toml_get "$manifest" ui.notch_tile requires_layer)"
        [[ -n "$layer" ]] || layer="$(aphotic_toml_get "$manifest" ui.dashboard_tab requires_layer)"
        [[ -n "$layer" ]] || layer="$(aphotic_toml_get "$manifest" ui.settings_pane requires_layer)"
        [[ -n "$layer" ]] || continue
        [[ " $layers " == *" $layer "* ]] || continue

        found=1
        if [[ ! -d "${APHOTIC_PLUGINS_DIR}/${name}" ]]; then
            printf '  [MISS] %s (%s layer on, not installed: aphotic plugin install %s)\n' "$name" "$layer" "$name"
        elif aphotic_plugin_is_enabled "$name"; then
            printf '  [ok]   %s (%s layer)\n' "$name" "$layer"
        else
            printf '  [off]  %s (%s layer on, installed but disabled)\n' "$name" "$layer"
        fi
    done

    [[ "$found" == "1" ]] || echo "  [ok]   no layer-gated plugins in the catalogue"
}

# APHOTIC_VERSION already comes straight off APHOTIC_DOTS_DIR/VERSION, so
# it never itself drifts from the checkout -- what it can't say is whether
# that checkout is behind origin/main. Formats _aphotic_state_version_drift
# (lib/aphotic/state.sh), shared with `aphotic status`/`aphotic diff` so
# all three agree on what "behind" means.
_aphotic_doctor_version_drift() {
    source "${LIB_DIR}/state.sh"

    local status branch head behind
    IFS=$'\t' read -r status branch head behind < <(_aphotic_state_version_drift)

    if [[ "$status" == "notgit" ]]; then
        echo "  [skip] ${APHOTIC_DOTS_DIR} is not a git checkout"
        return 0
    fi

    printf '  checked out: %s @ %s (v%s)\n' "$branch" "$head" "$APHOTIC_VERSION"
    case "$status" in
        not-main)
            echo "  [skip] not on main -- drift check only compares main against origin/main"
            ;;
        no-origin-ref)
            echo "  [skip] no origin/main ref cached -- run 'git fetch' to enable this check"
            ;;
        behind)
            printf '  [warn] %s commit(s) behind origin/main (cached as of last fetch) -- aphotic sync to catch up\n' "$behind"
            ;;
        ok)
            echo "  [ok]   up to date with origin/main (as of last fetch)"
            ;;
    esac
}

aphotic_cmd_doctor() {
    echo "Aphotic doctor — aphotic ${APHOTIC_VERSION}"
    echo
    echo "Core dependencies:"
    for bin in hyprctl qs jq git; do
        _aphotic_doctor_check "$bin"
    done

    echo
    echo "Paths:"
    for p in "$APHOTIC_CONFIG_HOME" "$APHOTIC_STATE_HOME" "$QUICKSHELL_CONFIG_DIR" "$APHOTIC_DOTS_DIR"; do
        if [[ -e "$p" ]]; then
            printf '  [ok]   %s\n' "$p"
        else
            printf '  [MISS] %s\n' "$p"
        fi
    done

    echo
    echo "Layer plugins:"
    _aphotic_doctor_layer_plugins

    source "${LIB_DIR}/state.sh"
    local services daemon_state dm_state dm_detail shellunit_state shellunit_detail
    services="$(_aphotic_state_service_drift)"
    IFS=$'\t' read -r _ daemon_state _ <<<"$(grep '^daemon' <<<"$services")"
    IFS=$'\t' read -r _ dm_state dm_detail <<<"$(grep '^displaymanager' <<<"$services")"
    IFS=$'\t' read -r _ shellunit_state shellunit_detail <<<"$(grep '^shellunit' <<<"$services")"

    echo
    echo "Display manager:"
    # A unit systemd has never heard of still writes "not-found" to
    # stdout before exiting non-zero -- `|| echo disabled` inside the
    # same command substitution let both land in the variable at once
    # ("not-found\ndisabled" on one line). The fallback only applies when
    # nothing came back at all.
    local sddm_enabled greetd_enabled
    sddm_enabled="$(systemctl is-enabled sddm.service 2>/dev/null)" || true
    [[ -n "$sddm_enabled" ]] || sddm_enabled="disabled"
    greetd_enabled="$(systemctl is-enabled greetd.service 2>/dev/null)" || true
    [[ -n "$greetd_enabled" ]] || greetd_enabled="not-installed"
    printf '  sddm:   %s\n' "$sddm_enabled"
    printf '  greetd: %s\n' "$greetd_enabled"
    if [[ -f /etc/xdg/quickshell/aphotic-greeter/shell.qml ]]; then
        printf '  [ok]   greetd greeter scaffold deployed (aphotic displaymanager status for detail)\n'
    fi
    if [[ "$dm_state" == "conflict" ]]; then
        printf '  [warn] %s; run '\''aphotic displaymanager status'\'' to see which actually wins\n' "$dm_detail"
    fi

    echo
    if [[ "$daemon_state" == "running" ]]; then
        echo "Daemon: running"
    else
        echo "Daemon: not running (aphotic shell -d)"
    fi
    if [[ "$shellunit_state" != "enabled" ]]; then
        printf '  [warn] aphotic-shell.service: %s -- %s\n' "$shellunit_state" "$shellunit_detail"
    fi

    echo
    echo "Version:"
    _aphotic_doctor_version_drift
    echo
    _aphotic_state_passthrough
}
