#!/usr/bin/env bash
# @cmd: handover
# @cmd.desc: Rehearse, acquire and recover durable host resource leases
# @cmd.group: LIFECYCLE
aphotic_cmd_handover() {
    if [[ "${1:-}" == "drift" ]]; then
        shift
        python3 "${LIB_DIR}/passthrough.py" --config "${APHOTIC_DOTS_DIR}/aphotic.toml" "$@"
        return $?
    fi
    python3 "${LIB_DIR}/handover.py" "$@"
}
