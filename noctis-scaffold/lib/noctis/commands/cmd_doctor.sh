#!/usr/bin/env bash
# noctis doctor — dependency + version drift check.
# @cmd: doctor
# @cmd.desc: Check dependencies and report version/config drift

_noctis_doctor_check() {
    local bin="$1"
    if command -v "$bin" >/dev/null 2>&1; then
        printf '  [ok]   %s\n' "$bin"
    else
        printf '  [MISS] %s\n' "$bin"
    fi
}

noctis_cmd_doctor() {
    echo "Noctis doctor — noctis ${NOCTIS_VERSION}"
    echo
    echo "Core dependencies:"
    for bin in hyprctl qs jq git; do
        _noctis_doctor_check "$bin"
    done

    echo
    echo "Paths:"
    for p in "$NOCTIS_CONFIG_HOME" "$NOCTIS_STATE_HOME" "$QUICKSHELL_CONFIG_DIR" "$NOCTIS_DOTS_DIR"; do
        if [[ -e "$p" ]]; then
            printf '  [ok]   %s\n' "$p"
        else
            printf '  [MISS] %s\n' "$p"
        fi
    done

    echo
    if pgrep -f "qs -c noctis" >/dev/null 2>&1; then
        echo "Daemon: running"
    else
        echo "Daemon: not running (noctis shell -d)"
    fi

    # TODO: compare NOCTIS_VERSION against NOCTIS_DOTS_DIR git HEAD /
    # a version marker file, the way HyDE's `hyde-shell version` does,
    # to surface "your dots are N commits behind" drift.
}
