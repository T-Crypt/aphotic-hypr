#!/usr/bin/env bash
# noctis scheme — colour scheme control (static or matugen-style dynamic).
# @cmd: scheme
# @cmd.desc: Set the active colour scheme
# @cmd.opt: set -n <name> | Apply a named scheme

noctis_cmd_scheme() {
    case "${1:-}" in
        set)
            shift
            local name=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    -n|--name) name="$2"; shift 2 ;;
                    *) shift ;;
                esac
            done
            [[ -z "$name" ]] && { noctis_err "usage: noctis scheme set -n <name>"; return 1; }
            noctis_json_set "scheme.active" "$name"
            noctis_log "scheme set to '${name}' in config — wire up matugen/palette generation (TODO)"
            ;;
        ""|-h|--help)
            cat <<HELP
Usage: noctis scheme set -n <name>

  set -n <name>   Apply a named colour scheme
HELP
            ;;
        *)
            noctis_err "unknown scheme subcommand: $1"
            return 1
            ;;
    esac
}
