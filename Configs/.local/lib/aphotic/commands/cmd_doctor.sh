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

    echo
    echo "Display manager:"
    local sddm_enabled greetd_enabled
    sddm_enabled="$(systemctl is-enabled sddm.service 2>/dev/null || echo disabled)"
    greetd_enabled="$(systemctl is-enabled greetd.service 2>/dev/null || echo not-installed)"
    printf '  sddm:   %s\n' "$sddm_enabled"
    printf '  greetd: %s\n' "$greetd_enabled"
    if [[ -f /etc/xdg/quickshell/aphotic-greeter/shell.qml ]]; then
        printf '  [ok]   greetd greeter scaffold deployed (aphotic displaymanager status for detail)\n'
    fi
    if [[ "$sddm_enabled" == "enabled" && "$greetd_enabled" == "enabled" ]]; then
        printf '  [warn] both sddm and greetd are enabled -- only one owns display-manager.service; run '\''aphotic displaymanager status'\'' to see which actually wins\n'
    fi

    echo
    if pgrep -f "qs -c aphotic" >/dev/null 2>&1; then
        echo "Daemon: running"
    else
        echo "Daemon: not running (aphotic shell -d)"
    fi

    # TODO: compare APHOTIC_VERSION against APHOTIC_DOTS_DIR git HEAD /
    # a version marker file, the way HyDE's `hyde-shell version` does,
    # to surface "your dots are N commits behind" drift.
}
