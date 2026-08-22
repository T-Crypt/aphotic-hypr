#!/usr/bin/env bash
# aphotic config — read/write shell.json, trigger a live reload on write.
# @cmd: config
# @cmd.desc: Get, set, or edit Aphotic shell configuration
# @cmd.group: CONFIG
# @cmd.opt: get <key>          | Print a config value (dot.path notation)
# @cmd.opt: set <key> <value>  | Write a value and trigger a reload
# @cmd.opt: edit                | Open APHOTIC_CONFIG_FILE in $EDITOR, validate on save

aphotic_cmd_config() {
    local sub="${1:-}"; shift || true
    case "$sub" in
        get)
            [[ -z "${1:-}" ]] && { aphotic_err "usage: aphotic config get <key>"; return 1; }
            aphotic_require jq || return 1
            aphotic_json_get "$1"
            ;;
        set)
            [[ -z "${2:-}" ]] && { aphotic_err "usage: aphotic config set <key> <value>"; return 1; }
            aphotic_require jq || return 1
            aphotic_json_set "$1" "$2"
            aphotic_ok "set ${1} = ${2}"
            aphotic_log "reloading to apply..."
            source "${COMMANDS_DIR}/cmd_reload.sh"
            aphotic_cmd_reload
            ;;
        edit)
            [[ -f "$APHOTIC_CONFIG_FILE" ]] || echo '{}' > "$APHOTIC_CONFIG_FILE"
            "${EDITOR:-nano}" "$APHOTIC_CONFIG_FILE"
            aphotic_require jq || return 1
            if jq empty "$APHOTIC_CONFIG_FILE" 2>/dev/null; then
                aphotic_ok "config valid"
            else
                aphotic_err "config is not valid JSON — fix before reloading"
                return 1
            fi
            ;;
        ""|-h|--help)
            cat <<HELP
Usage: aphotic config <get|set|edit> [args]

  get <key>          Print a value, dot.path notation (e.g. bar.position)
  set <key> <value>  Write a value, then reload
  edit               Open ${APHOTIC_CONFIG_FILE} in \$EDITOR, validate on save
HELP
            ;;
        *)
            aphotic_err "unknown config subcommand: ${sub}"
            return 1
            ;;
    esac
}
