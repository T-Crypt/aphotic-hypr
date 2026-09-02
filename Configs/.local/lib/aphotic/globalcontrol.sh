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

# Plugin system (see docs/PLUGIN_SYSTEM.md). Installed plugins are plain
# directories under here, each with its own plugin.toml -- same
# "directory + manifest" shape as ~/.config/awww/<theme>/theme.toml.
APHOTIC_PLUGINS_DIR="${APHOTIC_DATA_HOME}/plugins"
APHOTIC_PLUGINS_STATE_FILE="${APHOTIC_STATE_HOME}/plugins.json"
# Where `aphotic plugin install` looks for a local checkout of the
# aphotic-plugins repo. Override for a dev checkout elsewhere.
APHOTIC_PLUGINS_REPO="${APHOTIC_PLUGINS_REPO:-$HOME/aphotic-plugins}"
# git-clonable, matches the org/repo APHOTIC_PLUGINS_INDEX_URL reads its
# index.json from below -- `aphotic plugin install` clones here on first
# use (see _aphotic_plugin_sync_repo in cmd_plugin.sh) rather than
# requiring a manual clone beforehand.
APHOTIC_PLUGINS_GIT_URL="${APHOTIC_PLUGINS_GIT_URL:-https://github.com/T-Crypt/aphotic-plugins.git}"
APHOTIC_PLUGINS_INDEX_URL="${APHOTIC_PLUGINS_INDEX_URL:-https://raw.githubusercontent.com/T-Crypt/aphotic-plugins/main/index.json}"
# Security-category plugins (Bloodhound, Caido, ...) live in a SEPARATE
# index, not merged into the main one -- mirrors the exploit layer's
# BlackArch precedent (lib/install/blackarch.sh's ensure_blackarch_repo):
# an explicit trust step before this kind of content is even visible,
# not just before it installs. See aphotic_plugins_security_index_trusted
# below and cmd_plugin.sh's trust-security-index subcommand.
APHOTIC_PLUGINS_SECURITY_INDEX_URL="${APHOTIC_PLUGINS_SECURITY_INDEX_URL:-https://raw.githubusercontent.com/T-Crypt/aphotic-plugins-security/main/index.json}"

# Community theme index (see themes/THEME_SPEC.md and cmd_theme.sh's
# `download`/`update`/`remove`). Same clone/pull-a-repo shape as the
# plugin block above, but a theme is just a directory + theme.toml with
# no enable/disable state -- "is this theme downloaded" is answered by
# APHOTIC_AWWW_DIR itself, so unlike APHOTIC_PLUGINS_STATE_FILE there's
# no state file to track here.
APHOTIC_THEMES_REPO="${APHOTIC_THEMES_REPO:-$HOME/aphotic-themes}"
APHOTIC_THEMES_GIT_URL="${APHOTIC_THEMES_GIT_URL:-https://github.com/T-Crypt/aphotic-themes.git}"
APHOTIC_THEMES_INDEX_URL="${APHOTIC_THEMES_INDEX_URL:-https://raw.githubusercontent.com/T-Crypt/aphotic-themes/main/index.json}"

# one-time migration: noctis -> aphotic config path
_APHOTIC_OLD_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/noctis"
if [[ -d "$_APHOTIC_OLD_CONFIG_HOME" ]] && [[ ! -e "$APHOTIC_CONFIG_HOME" ]]; then
    mv "$_APHOTIC_OLD_CONFIG_HOME" "$APHOTIC_CONFIG_HOME"
    echo "[aphotic] migrated config from ${_APHOTIC_OLD_CONFIG_HOME}" >&2
fi

mkdir -p "$APHOTIC_CONFIG_HOME" "$APHOTIC_STATE_HOME" "$APHOTIC_DATA_HOME" \
         "$APHOTIC_RUNTIME_DIR" "$APHOTIC_BACKUP_DIR" "$APHOTIC_PLUGINS_DIR"

export APHOTIC_VERSION APHOTIC_CONFIG_HOME APHOTIC_STATE_HOME APHOTIC_DATA_HOME \
       APHOTIC_RUNTIME_DIR APHOTIC_CONFIG_FILE APHOTIC_BACKUP_DIR APHOTIC_DOTS_DIR \
       QUICKSHELL_CONFIG_DIR APHOTIC_PLUGINS_DIR APHOTIC_PLUGINS_STATE_FILE \
       APHOTIC_PLUGINS_REPO APHOTIC_PLUGINS_GIT_URL APHOTIC_PLUGINS_INDEX_URL APHOTIC_PLUGINS_SECURITY_INDEX_URL \
       APHOTIC_THEMES_REPO APHOTIC_THEMES_GIT_URL APHOTIC_THEMES_INDEX_URL

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

# ---- minimal TOML reader -------------------------------------------------
# Shared by cmd_theme.sh (theme.toml) and cmd_plugin.sh (plugin.toml).
# Deliberately minimal — flat key = "value" pairs only, no arrays-of-
# tables, no multi-line strings — mirrors the hand-written parser in
# Themes.qml. See _aphotic_toml_get_array below for the one array shape
# plugin.toml actually needs (capabilities, requires.binaries).
#   _aphotic_toml_get "$dir/theme.toml" wallpaper default
aphotic_toml_get() {
    local file="$1" section="$2" key="$3"
    [[ -f "$file" ]] || return 1
    awk -v section="[$section]" -v key="$key" '
        $0 == section { insec=1; next }
        /^\[/ { insec=0 }
        insec && $0 ~ "^[[:space:]]*"key"[[:space:]]*=" {
            sub(/^[^=]*=[[:space:]]*/, "");
            gsub(/^"|"$/, "");
            print;
            exit
        }
    ' "$file"
}

# Same shape, for `key = ["a", "b", "c"]` — prints one value per line.
# Only handles a single-line bracketed list of quoted strings, matching
# the only array shape plugin.toml uses.
aphotic_toml_get_array() {
    local file="$1" section="$2" key="$3"
    [[ -f "$file" ]] || return 1
    awk -v section="[$section]" -v key="$key" '
        $0 == section { insec=1; next }
        /^\[/ { insec=0 }
        insec && $0 ~ "^[[:space:]]*"key"[[:space:]]*=" {
            sub(/^[^=]*=[[:space:]]*\[/, "");
            sub(/\][[:space:]]*$/, "");
            print;
            exit
        }
    ' "$file" | tr ',' '\n' | sed -e 's/^[[:space:]]*"\?//' -e 's/"\?[[:space:]]*$//' -e '/^$/d'
}

# ---- colour engines -------------------------------------------------------
# theme.toml's [engine].name selects which engine renders a theme's
# palette (themes/THEME_SPEC.md); this is the matugen side, shared by
# cmd_theme.sh's apply path and cmd_scheme.sh's regenerate path. Templates
# and output targets come from ~/.config/matugen/config.toml.
#
# --prefer is not optional: matugen refuses to choose between an image's
# candidate source colours without a terminal to prompt on, which is every
# call made from here.
aphotic_matugen_run() {
    local image="$1" scheme="${2:-}" style="${3:-}" contrast="${4:-}"

    if ! command -v matugen >/dev/null 2>&1; then
        aphotic_warn "matugen not found, skipping palette regeneration"
        return 1
    fi

    local cmd=(matugen image "$image" --prefer saturation -q)
    [[ -n "$scheme" ]] && cmd+=(-t "$scheme")
    [[ -n "$style" ]] && cmd+=(-m "$style")
    [[ -n "$contrast" ]] && cmd+=(--contrast "$contrast")
    "${cmd[@]}"
}

# ---- shell daemon process management --------------------------------------
# Anchored on the command itself. `pgrep -f "qs -c aphotic"` matches any
# process whose command line merely *contains* that string, which includes
# the scripts that call these helpers -- `pkill -f "qs -c aphotic"` in
# cmd_reload killed its own caller that way, live.
APHOTIC_SHELL_PATTERN='^(/[^ ]*/)?qs -c aphotic$'

aphotic_shell_pids() {
    pgrep -f "$APHOTIC_SHELL_PATTERN" 2>/dev/null || true
}

aphotic_shell_running() {
    [[ -n "$(aphotic_shell_pids)" ]]
}

# Quickshell does not reap its Process children when the daemon takes a
# SIGTERM: `nmcli monitor`, `dbus-monitor` and the agent-events `tail`s
# reparent to init and one fresh set accumulates per restart. Counted on a
# machine using the manual path (no aphotic-shell.service): 121 strays
# holding 1.0 GiB RSS, the oldest 13 h. Only the quiet ones survive -- a
# `tail -F` on a file that keeps growing dies of SIGPIPE first, which is
# why the leak read as smaller than it was. A machine on the service path
# has none of this: systemd's KillMode=control-group already takes the
# whole cgroup down (verified on the dev VM: 0 strays).
#
# The group is only safe to signal when the daemon leads it. Started from
# a terminal it inherits that terminal's job group, and `kill -- -PGID`
# there would take the user's own shell down with it -- so the group kill
# is gated on leadership, and aphotic_shell_start uses setsid to make that
# true for anything it launches.
aphotic_shell_stop() {
    local pid pgid child
    local -a stragglers
    for pid in "$@"; do
        [[ -n "$pid" ]] || continue
        pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
        if [[ -n "$pgid" && "$pgid" == "$pid" ]]; then
            kill -TERM -- "-${pgid}" 2>/dev/null || true
            continue
        fi
        # Not a group leader (started from a terminal, or by an older
        # aphotic that did not setsid), so the group is not ours to
        # signal. Collect the children first -- once the parent is gone
        # they reparent to init and there is nothing left to find them by.
        stragglers=()
        while IFS= read -r child; do
            [[ -n "$child" ]] && stragglers+=("$child")
        done < <(pgrep -P "$pid" 2>/dev/null)
        kill -TERM "$pid" 2>/dev/null || true
        [[ ${#stragglers[@]} -gt 0 ]] && kill -TERM "${stragglers[@]}" 2>/dev/null
    done
    return 0
}

aphotic_shell_start() {
    local log="${1:-/dev/null}"
    setsid qs -c aphotic >>"$log" 2>&1 &
    disown
}

# ---- plugin helpers -------------------------------------------------------
# List installed plugin directory names (each has a plugin.toml).
aphotic_plugin_names() {
    local d
    [[ -d "$APHOTIC_PLUGINS_DIR" ]] || return 0
    for d in "$APHOTIC_PLUGINS_DIR"/*/; do
        [[ -f "${d}plugin.toml" ]] && basename "$d"
    done
}

# Enabled by default; explicitly listed in the state file's "disabled"
# array to turn one off. Matches Config.qml's enabled-flag-per-entry
# convention more loosely than mirroring it exactly, since most installed
# plugins are expected to want to just work once installed.
aphotic_plugin_is_enabled() {
    local name="$1"
    [[ -f "$APHOTIC_PLUGINS_STATE_FILE" ]] || return 0
    ! jq -e --arg n "$name" '.disabled // [] | index($n) != null' "$APHOTIC_PLUGINS_STATE_FILE" >/dev/null 2>&1
}

aphotic_plugin_set_enabled() {
    local name="$1" enabled="$2" tmp
    aphotic_require jq || return 1
    [[ -f "$APHOTIC_PLUGINS_STATE_FILE" ]] || echo '{"disabled": []}' > "$APHOTIC_PLUGINS_STATE_FILE"
    tmp="$(mktemp)"
    if [[ "$enabled" == "true" ]]; then
        jq --arg n "$name" '.disabled = ((.disabled // []) - [$n])' "$APHOTIC_PLUGINS_STATE_FILE" > "$tmp"
    else
        jq --arg n "$name" '.disabled = ((.disabled // []) + [$n] | unique)' "$APHOTIC_PLUGINS_STATE_FILE" > "$tmp"
    fi
    mv "$tmp" "$APHOTIC_PLUGINS_STATE_FILE"
}

# Whether the user has explicitly opted into seeing/installing
# security-category plugins from APHOTIC_PLUGINS_SECURITY_INDEX_URL.
# False (untrusted) unless this flag has been set -- see
# cmd_plugin.sh's trust-security-index subcommand for the confirmation
# gate that sets it.
aphotic_plugins_security_index_trusted() {
    [[ -f "$APHOTIC_PLUGINS_STATE_FILE" ]] || return 1
    jq -e '.security_index_trusted // false' "$APHOTIC_PLUGINS_STATE_FILE" >/dev/null 2>&1
}

aphotic_plugins_set_security_index_trusted() {
    local trusted="$1" tmp
    aphotic_require jq || return 1
    [[ -f "$APHOTIC_PLUGINS_STATE_FILE" ]] || echo '{"disabled": []}' > "$APHOTIC_PLUGINS_STATE_FILE"
    tmp="$(mktemp)"
    jq --argjson t "$trusted" '.security_index_trusted = $t' "$APHOTIC_PLUGINS_STATE_FILE" > "$tmp"
    mv "$tmp" "$APHOTIC_PLUGINS_STATE_FILE"
}
