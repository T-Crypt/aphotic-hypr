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
    if pgrep -f "qs -c aphotic" >/dev/null 2>&1; then
        echo "Daemon: running"
    else
        echo "Daemon: not running (aphotic shell -d)"
    fi

    # TODO: compare APHOTIC_VERSION against APHOTIC_DOTS_DIR git HEAD /
    # a version marker file, the way HyDE's `hyde-shell version` does,
    # to surface "your dots are N commits behind" drift.
}
