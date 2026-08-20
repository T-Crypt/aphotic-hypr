#!/usr/bin/env bash
# noctis config — read/write shell.json, trigger a live reload on write.
# @cmd: config
# @cmd.desc: Get, set, or edit Noctis shell configuration
# @cmd.opt: get <key>          | Print a config value (dot.path notation)
# @cmd.opt: set <key> <value>  | Write a value and trigger a reload
# @cmd.opt: edit                | Open NOCTIS_CONFIG_FILE in $EDITOR, validate on save

noctis_cmd_config() {
    local sub="${1:-}"; shift || true
    case "$sub" in
        get)
            [[ -z "${1:-}" ]] && { noctis_err "usage: noctis config get <key>"; return 1; }
            noctis_require jq || return 1
            noctis_json_get "$1"
            ;;
        set)
            [[ -z "${2:-}" ]] && { noctis_err "usage: noctis config set <key> <value>"; return 1; }
            noctis_require jq || return 1
            noctis_json_set "$1" "$2"
            noctis_ok "set ${1} = ${2}"
            noctis_log "reloading to apply..."
            source "${COMMANDS_DIR}/cmd_reload.sh"
            noctis_cmd_reload
            ;;
        edit)
            [[ -f "$NOCTIS_CONFIG_FILE" ]] || echo '{}' > "$NOCTIS_CONFIG_FILE"
            "${EDITOR:-nano}" "$NOCTIS_CONFIG_FILE"
            noctis_require jq || return 1
            if jq empty "$NOCTIS_CONFIG_FILE" 2>/dev/null; then
                noctis_ok "config valid"
            else
                noctis_err "config is not valid JSON — fix before reloading"
                return 1
            fi
            ;;
        ""|-h|--help)
            cat <<HELP
Usage: noctis config <get|set|edit> [args]

  get <key>          Print a value, dot.path notation (e.g. bar.position)
  set <key> <value>  Write a value, then reload
  edit               Open ${NOCTIS_CONFIG_FILE} in \$EDITOR, validate on save
HELP
            ;;
        *)
            noctis_err "unknown config subcommand: ${sub}"
            return 1
            ;;
    esac
}
