#!/usr/bin/env bash
# lib/noctis/globalcontrol.sh
# Shared environment + helper functions for the noctis CLI.
# Sourced by bin/noctis — not meant to be executed directly.
# Naming/role mirrors HyDE's lib/hyde/globalcontrol.sh.

# ---- XDG-compliant paths ---------------------------------------------
NOCTIS_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/noctis"
NOCTIS_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}/noctis"
NOCTIS_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/noctis"
NOCTIS_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/noctis"

NOCTIS_CONFIG_FILE="${NOCTIS_CONFIG_HOME}/shell.json"
NOCTIS_BACKUP_DIR="${NOCTIS_STATE_HOME}/backups"

# Where the Noctis-Hypr dots repo lives. Overridable via env for dev/CI.
NOCTIS_DOTS_DIR="${NOCTIS_DOTS_DIR:-$HOME/Noctis-Hypr}"

# Read from the repo's VERSION file so `noctis doctor` reflects the
# actual checked-out commit's version, not a string that drifts from it.
if [[ -f "$NOCTIS_DOTS_DIR/VERSION" ]]; then
    NOCTIS_VERSION="$(<"$NOCTIS_DOTS_DIR/VERSION")"
else
    NOCTIS_VERSION="unknown (repo not found at \$NOCTIS_DOTS_DIR: $NOCTIS_DOTS_DIR)"
fi

QUICKSHELL_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/noctis"

mkdir -p "$NOCTIS_CONFIG_HOME" "$NOCTIS_STATE_HOME" "$NOCTIS_DATA_HOME" \
         "$NOCTIS_RUNTIME_DIR" "$NOCTIS_BACKUP_DIR"

export NOCTIS_VERSION NOCTIS_CONFIG_HOME NOCTIS_STATE_HOME NOCTIS_DATA_HOME \
       NOCTIS_RUNTIME_DIR NOCTIS_CONFIG_FILE NOCTIS_BACKUP_DIR NOCTIS_DOTS_DIR \
       QUICKSHELL_CONFIG_DIR

# ---- logging -----------------------------------------------------------
_NOCTIS_DIM=$'\e[2m'; _NOCTIS_R=$'\e[0m'
_NOCTIS_CYAN=$'\e[36m'; _NOCTIS_RED=$'\e[31m'
_NOCTIS_GREEN=$'\e[32m'; _NOCTIS_YELLOW=$'\e[33m'

noctis_log()  { printf '%s[noctis]%s %s\n' "$_NOCTIS_CYAN" "$_NOCTIS_R" "$*"; }
noctis_ok()   { printf '%s[ ok ]%s %s\n'   "$_NOCTIS_GREEN" "$_NOCTIS_R" "$*"; }
noctis_warn() { printf '%s[warn]%s %s\n'   "$_NOCTIS_YELLOW" "$_NOCTIS_R" "$*" >&2; }
noctis_err()  { printf '%s[fail]%s %s\n'   "$_NOCTIS_RED" "$_NOCTIS_R" "$*" >&2; }

# ---- small utilities -----------------------------------------------------
noctis_confirm() {
    local prompt="${1:-Are you sure?}" reply
    read -r -p "${prompt} [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

# Verify a dependency exists on PATH; used by `noctis doctor` and by
# individual commands that need to fail fast with a clear message.
noctis_require() {
    command -v "$1" >/dev/null 2>&1 || { noctis_err "missing dependency: $1"; return 1; }
}

# JSON getter/setter helpers around NOCTIS_CONFIG_FILE, used by
# cmd_config.sh. Requires jq. Kept here so every command can reuse them.
noctis_json_get() {
    local key="$1"
    [[ -f "$NOCTIS_CONFIG_FILE" ]] || { echo "null"; return 0; }
    jq -r --arg k "$key" 'getpath($k | split("."))' "$NOCTIS_CONFIG_FILE"
}

noctis_json_set() {
    local key="$1" value="$2" tmp
    noctis_require jq || return 1
    [[ -f "$NOCTIS_CONFIG_FILE" ]] || echo '{}' > "$NOCTIS_CONFIG_FILE"
    tmp="$(mktemp)"
    jq --arg k "$key" --arg v "$value" 'setpath($k | split("."); $v)' \
        "$NOCTIS_CONFIG_FILE" > "$tmp" && mv "$tmp" "$NOCTIS_CONFIG_FILE"
}
