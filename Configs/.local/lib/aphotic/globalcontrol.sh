#!/usr/bin/env bash
# lib/aphotic/globalcontrol.sh
# Shared environment + helper functions for the aphotic CLI.
# Sourced by bin/aphotic — not meant to be executed directly.
# Naming/role mirrors HyDE's lib/hyde/globalcontrol.sh.

# ---- XDG-compliant paths ---------------------------------------------
APHOTIC_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/aphotic"
APHOTIC_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}/aphotic"
APHOTIC_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/aphotic"
APHOTIC_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/aphotic"

APHOTIC_CONFIG_FILE="${APHOTIC_CONFIG_HOME}/shell.json"
APHOTIC_BACKUP_DIR="${APHOTIC_STATE_HOME}/backups"

# Where the Aphotic-Hypr dots repo lives. Overridable via env for dev/CI.
APHOTIC_DOTS_DIR="${APHOTIC_DOTS_DIR:-$HOME/Aphotic-Hypr}"

# Read from the repo's VERSION file so `aphotic doctor` reflects the
# actual checked-out commit's version, not a string that drifts from it.
if [[ -f "$APHOTIC_DOTS_DIR/VERSION" ]]; then
    APHOTIC_VERSION="$(<"$APHOTIC_DOTS_DIR/VERSION")"
else
    APHOTIC_VERSION="unknown (repo not found at \$APHOTIC_DOTS_DIR: $APHOTIC_DOTS_DIR)"
fi

QUICKSHELL_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/aphotic"

# one-time migration: noctis -> aphotic config path
_APHOTIC_OLD_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/noctis"
if [[ -d "$_APHOTIC_OLD_CONFIG_HOME" ]] && [[ ! -e "$APHOTIC_CONFIG_HOME" ]]; then
    mv "$_APHOTIC_OLD_CONFIG_HOME" "$APHOTIC_CONFIG_HOME"
    echo "[aphotic] migrated config from ${_APHOTIC_OLD_CONFIG_HOME}" >&2
fi

mkdir -p "$APHOTIC_CONFIG_HOME" "$APHOTIC_STATE_HOME" "$APHOTIC_DATA_HOME" \
         "$APHOTIC_RUNTIME_DIR" "$APHOTIC_BACKUP_DIR"

export APHOTIC_VERSION APHOTIC_CONFIG_HOME APHOTIC_STATE_HOME APHOTIC_DATA_HOME \
       APHOTIC_RUNTIME_DIR APHOTIC_CONFIG_FILE APHOTIC_BACKUP_DIR APHOTIC_DOTS_DIR \
       QUICKSHELL_CONFIG_DIR

# ---- logging -----------------------------------------------------------
_APHOTIC_DIM=$'\e[2m'; _APHOTIC_R=$'\e[0m'
_APHOTIC_CYAN=$'\e[36m'; _APHOTIC_RED=$'\e[31m'
_APHOTIC_GREEN=$'\e[32m'; _APHOTIC_YELLOW=$'\e[33m'

aphotic_log()  { printf '%s[aphotic]%s %s\n' "$_APHOTIC_CYAN" "$_APHOTIC_R" "$*"; }
aphotic_ok()   { printf '%s[ ok ]%s %s\n'   "$_APHOTIC_GREEN" "$_APHOTIC_R" "$*"; }
aphotic_warn() { printf '%s[warn]%s %s\n'   "$_APHOTIC_YELLOW" "$_APHOTIC_R" "$*" >&2; }
aphotic_err()  { printf '%s[fail]%s %s\n'   "$_APHOTIC_RED" "$_APHOTIC_R" "$*" >&2; }

# ---- small utilities -----------------------------------------------------
aphotic_confirm() {
    local prompt="${1:-Are you sure?}" reply
    read -r -p "${prompt} [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

# Verify a dependency exists on PATH; used by `aphotic doctor` and by
# individual commands that need to fail fast with a clear message.
aphotic_require() {
    command -v "$1" >/dev/null 2>&1 || { aphotic_err "missing dependency: $1"; return 1; }
}

# JSON getter/setter helpers around APHOTIC_CONFIG_FILE, used by
# cmd_config.sh. Requires jq. Kept here so every command can reuse them.
aphotic_json_get() {
    local key="$1"
    [[ -f "$APHOTIC_CONFIG_FILE" ]] || { echo "null"; return 0; }
    jq -r --arg k "$key" 'getpath($k | split("."))' "$APHOTIC_CONFIG_FILE"
}

aphotic_json_set() {
    local key="$1" value="$2" tmp
    aphotic_require jq || return 1
    [[ -f "$APHOTIC_CONFIG_FILE" ]] || echo '{}' > "$APHOTIC_CONFIG_FILE"
    tmp="$(mktemp)"
    jq --arg k "$key" --arg v "$value" 'setpath($k | split("."); $v)' \
        "$APHOTIC_CONFIG_FILE" > "$tmp" && mv "$tmp" "$APHOTIC_CONFIG_FILE"
}
