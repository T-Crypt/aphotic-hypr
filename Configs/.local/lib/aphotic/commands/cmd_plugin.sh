#!/usr/bin/env bash
# aphotic plugin — install, manage, and run hooks for the plugin system.
# @cmd: plugin
# @cmd.desc: List, install, enable/disable, or remove plugins
# @cmd.group: CONFIG
# @cmd.opt: list [--remote] [--json] [--category <name>]  | List installed (or available-remote) plugins
# @cmd.opt: install <name> [--link]                        | Install a plugin from APHOTIC_PLUGINS_REPO
# @cmd.opt: enable|disable <name>                          | Toggle a plugin without uninstalling it
# @cmd.opt: remove <name>                                  | Uninstall a plugin
# @cmd.opt: trust-security-index                            | Opt into the separate security-category plugin index
# @cmd.opt: untrust-security-index                          | Revoke that opt-in (hides security-category plugins again)
#
# See docs/PLUGIN_SYSTEM.md. A plugin is a directory under
# APHOTIC_PLUGINS_DIR with its own plugin.toml (same "directory +
# manifest" shape as a theme). This file also owns `run-theme-hooks`/
# `run-project-hooks`/`run-workspace-hooks`, the shared implementations
# of each hook-firing loop, called from cmd_theme.sh/Themes.qml/
# Wallpapers.qml/wallswitcher.py (theme), ProjectItem.qml (project), and
# WorkspaceProfilesPane.qml (workspace) respectively -- see
# _aphotic_plugin_run_theme_hooks and _aphotic_plugin_run_hook_by_capability
# below. project/workspace hooks only fire for plugins that declare the
# matching capability tag in their manifest, not every enabled plugin.

_aphotic_plugin_dir() { printf '%s/%s' "$APHOTIC_PLUGINS_DIR" "$1"; }

# Manifest v3 additions (see docs/archive/PLUGIN_SYSTEM.md): [owns] and
# [ui.<surface-kind>] -- only `dashboard_tab` is shipped so far, the
# natural extension point for a second UI-surface kind (a bar module, a
# Settings pane) once a second plugin actually needs one. Both read as
# empty/null on a v1 or v2 manifest, same "optional field, no error"
# contract v2's category addition already established.
_aphotic_plugin_owns_json() {
    local manifest="$1" keys
    keys="$(aphotic_toml_get_array "$manifest" owns config_keys | jq -R . | jq -s .)"
    jq -n --argjson config_keys "${keys:-[]}" '{config_keys: $config_keys}'
}

_aphotic_plugin_ui_json() {
    local manifest="$1" id icon label component
    id="$(aphotic_toml_get "$manifest" ui.dashboard_tab id)"
    icon="$(aphotic_toml_get "$manifest" ui.dashboard_tab icon)"
    label="$(aphotic_toml_get "$manifest" ui.dashboard_tab label)"
    component="$(aphotic_toml_get "$manifest" ui.dashboard_tab component)"

    if [[ -z "$component" ]]; then
        echo 'null'
        return 0
    fi

    jq -n \
        --arg id "${id:-}" \
        --arg icon "${icon:-}" \
        --arg label "${label:-}" \
        --arg component "$component" \
        '{dashboard_tab: {id: $id, icon: $icon, label: $label, component: $component}}'
}

_aphotic_plugin_describe() {
    local name="$1" dir manifest display desc version category caps enabled missing bin
    dir="$(_aphotic_plugin_dir "$name")"
    manifest="${dir}/plugin.toml"
    [[ -f "$manifest" ]] || return 1

    display="$(aphotic_toml_get "$manifest" plugin display_name)"
    desc="$(aphotic_toml_get "$manifest" plugin description)"
    version="$(aphotic_toml_get "$manifest" plugin version)"
    category="$(aphotic_toml_get "$manifest" plugin category)"
    caps="$(aphotic_toml_get_array "$manifest" plugin capabilities | jq -R . | jq -s .)"
    enabled="false"
    aphotic_plugin_is_enabled "$name" && enabled="true"

    missing="[]"
    while IFS= read -r bin; do
        [[ -z "$bin" ]] && continue
        command -v "$bin" >/dev/null 2>&1 || missing="$(jq --arg b "$bin" '. + [$b]' <<<"$missing")"
    done < <(aphotic_toml_get_array "$manifest" requires binaries)

    jq -n \
        --arg name "$name" \
        --arg display_name "${display:-$name}" \
        --arg description "${desc:-}" \
        --arg version "${version:-0.0.0}" \
        --arg category "${category:-}" \
        --argjson capabilities "${caps:-[]}" \
        --argjson enabled "$enabled" \
        --argjson missing_binaries "$missing" \
        --argjson owns "$(_aphotic_plugin_owns_json "$manifest")" \
        --argjson ui "$(_aphotic_plugin_ui_json "$manifest")" \
        '{name: $name, display_name: $display_name, description: $description, version: $version, category: $category, capabilities: $capabilities, enabled: $enabled, missing_binaries: $missing_binaries, owns: $owns, ui: $ui}'
}

_aphotic_plugin_list_installed_json() {
    local name entries=()
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        entries+=("$(_aphotic_plugin_describe "$name")")
    done < <(aphotic_plugin_names)
    printf '%s\n' "${entries[@]:-}" | jq -s 'map(select(. != null))'
}

_aphotic_plugin_list_remote_json() {
    aphotic_require curl || return 1
    local main_data security_data
    main_data="$(curl -fsSL -m 10 "$APHOTIC_PLUGINS_INDEX_URL" 2>/dev/null || echo '{"plugins": []}')"

    # Security-category plugins only ever appear here once the user has
    # explicitly trusted the separate security index (see
    # aphotic_plugins_security_index_trusted) -- untrusted, this
    # function behaves exactly as if that index didn't exist, not just
    # "installable but hidden" -- it's not fetched at all.
    if aphotic_plugins_security_index_trusted; then
        security_data="$(curl -fsSL -m 10 "$APHOTIC_PLUGINS_SECURITY_INDEX_URL" 2>/dev/null || echo '{"plugins": []}')"
        jq -n --argjson a "$main_data" --argjson b "$security_data" \
            '{plugins: (($a.plugins // []) + ($b.plugins // []))}'
    else
        echo "$main_data"
    fi
}

# Fire every enabled theme-hook plugin's on_theme_change script, piping
# the current resolved palette (~/.local/state/aphotic/palette.json,
# regenerated by wallust on every theme apply — see wallust.toml's
# `plugin_palette` template) to it on stdin as JSON. Fire-and-forget with
# a timeout: a broken/hanging plugin hook must never block or fail the
# theme switch it's piggybacking on, matching the existing
# papirus-folders/sddm-sync "warn and no-op" precedent in this same
# command group.
_aphotic_plugin_run_theme_hooks() {
    local palette_file="${APHOTIC_STATE_HOME}/palette.json"
    [[ -f "$palette_file" ]] || return 0

    local name dir manifest hook caps
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        aphotic_plugin_is_enabled "$name" || continue

        dir="$(_aphotic_plugin_dir "$name")"
        manifest="${dir}/plugin.toml"
        caps="$(aphotic_toml_get_array "$manifest" plugin capabilities)"
        grep -qx "theme-hook" <<<"$caps" || continue

        hook="$(aphotic_toml_get "$manifest" hooks on_theme_change)"
        [[ -n "$hook" && -x "${dir}/${hook}" ]] || continue

        (
            timeout 5 "${dir}/${hook}" < "$palette_file" >/dev/null 2>&1 \
                || aphotic_warn "plugin '${name}': on_theme_change hook failed or timed out"
        ) &
        disown 2>/dev/null || true
    done < <(aphotic_plugin_names)
}

# Shared shape for the two new v2 hooks below: only plugins that declare
# the matching capability tag AND set the matching [hooks] key get
# fired -- not every enabled plugin -- so a theming-only plugin doesn't
# get invoked on every project switch or workspace launch it has no
# reason to care about. $1: capability tag, $2: hooks key, $3: single
# positional argument passed to the hook script.
_aphotic_plugin_run_hook_by_capability() {
    local capability="$1" hooks_key="$2" arg="$3"
    local name dir manifest hook caps
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        aphotic_plugin_is_enabled "$name" || continue

        dir="$(_aphotic_plugin_dir "$name")"
        manifest="${dir}/plugin.toml"
        caps="$(aphotic_toml_get_array "$manifest" plugin capabilities)"
        grep -qx "$capability" <<<"$caps" || continue

        hook="$(aphotic_toml_get "$manifest" hooks "$hooks_key")"
        [[ -n "$hook" && -x "${dir}/${hook}" ]] || continue

        (
            timeout 5 "${dir}/${hook}" "$arg" >/dev/null 2>&1 \
                || aphotic_warn "plugin '${name}': ${hooks_key} hook failed or timed out"
        ) &
        disown 2>/dev/null || true
    done < <(aphotic_plugin_names)
}

# Fired from the launcher's "@" project-switcher (ProjectItem.qml) after
# it dispatches its own terminal+editor launch -- plugins never replace
# that, they just get told a project was opened.
_aphotic_plugin_run_project_hooks() {
    local path="$1"
    [[ -n "$path" ]] || return 0
    _aphotic_plugin_run_hook_by_capability "project-hook" "on_project_open" "$path"
}

# Fired from Workspace Profiles' launchProfile() after it dispatches the
# profile's own hyprctl execs.
_aphotic_plugin_run_workspace_hooks() {
    local profile_name="$1"
    [[ -n "$profile_name" ]] || return 0
    _aphotic_plugin_run_hook_by_capability "workspace-hook" "on_workspace_launch" "$profile_name"
}

# Confirmation gate for the separate security-category plugin index --
# same shape as lib/install/blackarch.sh's ensure_blackarch_repo: a real
# warning, explicit y/N, persisted only once accepted. --yes skips the
# interactive prompt for a non-interactive caller (Settings -> Plugins,
# which renders its own warning/confirm UI before calling this) --
# mirrors exploit_disclaimer.sh's TTY-vs-flag split, just simpler since
# there's no scripted-install angle here to fail loudly against.
_aphotic_plugin_trust_security_index() {
    local skip_prompt="$1"

    if [[ "$skip_prompt" != "true" ]]; then
        cat <<'EOF'
================================================================
         SECURITY-CATEGORY PLUGIN INDEX
================================================================

This index carries offensive-security tooling (e.g. Bloodhound,
Caido) as installable plugins -- separate from the main,
maintainer-curated aphotic-plugins index, and not vetted the
same way.

Only enable this if you understand what you're installing and
intend to use it for legitimate, authorized security work.
================================================================

EOF
        local confirm
        read -rep $'[\e[1;33mACTION\e[0m] - Trust the security plugin index? (y,N) ' confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            aphotic_log "not trusted -- security-category plugins will stay hidden"
            return 0
        fi
    fi

    aphotic_plugins_set_security_index_trusted true
    aphotic_ok "security plugin index trusted -- security-category plugins now visible in 'aphotic plugin list --remote'"
}

_aphotic_plugin_untrust_security_index() {
    aphotic_plugins_set_security_index_trusted false
    aphotic_ok "security plugin index untrusted -- security-category plugins hidden again (already-installed ones are unaffected)"
}

# JSON status query -- PluginsPane.qml uses this (not a heuristic over
# whether any security-category entries happen to be present in the
# fetched list) to decide whether to show the trust-prompt UI for the
# security category.
_aphotic_plugin_security_index_status() {
    local trusted="false"
    if aphotic_plugins_security_index_trusted; then
        trusted="true"
    fi
    jq -n --argjson trusted "$trusted" '{trusted: $trusted}'
}

# Clone APHOTIC_PLUGINS_REPO on first use, `git pull --ff-only` on later
# ones -- install() used to just fail with "clone/pull the repo there
# first" and expect a human to have already done that by hand outside
# this tool, which is exactly why Settings -> Plugins' Install button
# looked like it did nothing: the CLI's own real, correct stderr error
# was never surfaced by the QML side (no stderr collector on that
# Process -- see PluginsPane.qml), so it just silently failed every
# single time on a machine that had never manually cloned the repo. A
# pull failure (network hiccup, local edits under APHOTIC_PLUGINS_REPO)
# is non-fatal -- falls through to whatever's on disk already rather
# than blocking install, matching the "warn and continue" convention
# this file already uses for hook failures.
_aphotic_plugin_sync_repo() {
    aphotic_require git || return 1
    if [[ -d "${APHOTIC_PLUGINS_REPO}/.git" ]]; then
        echo "Updating plugin repo: git -C ${APHOTIC_PLUGINS_REPO} pull --ff-only"
        git -C "$APHOTIC_PLUGINS_REPO" pull --ff-only || aphotic_err "pull failed — continuing with the existing local checkout at ${APHOTIC_PLUGINS_REPO}"
    else
        echo "Cloning plugin repo: git clone ${APHOTIC_PLUGINS_GIT_URL} ${APHOTIC_PLUGINS_REPO}"
        git clone "$APHOTIC_PLUGINS_GIT_URL" "$APHOTIC_PLUGINS_REPO" || { aphotic_err "clone failed: ${APHOTIC_PLUGINS_GIT_URL}"; return 1; }
    fi
}

# Installs whatever this just-copied plugin's plugin.toml declares it
# needs, in the SAME visible kitty terminal `aphotic plugin install`
# already runs in (see PluginsPane.qml's Install button) -- not a second
# spawned window -- so the user watches one continuous clone -> copy ->
# deps -> done flow instead of piecing together output from two terminals.
# Same "shell out to yay/paru in a real terminal, no --noconfirm" contract
# `PkgSearch.qml`'s own install() already established for the package-
# search pane (SUPER+Y) -- yay/paru's own interactive prompts (which
# provider to pick, PKGBUILD review, sudo password) show up exactly as
# they would from a manual `yay -S`, since AUR packages run arbitrary
# build scripts and this repo doesn't silently auto-confirm that anywhere
# else either.
_aphotic_plugin_install_deps() {
    local dest="$1" manifest="${dest}/plugin.toml" bin pkg helper=""
    [[ -f "$manifest" ]] || return 0

    command -v yay >/dev/null 2>&1 && helper="yay"
    [[ -z "$helper" ]] && command -v paru >/dev/null 2>&1 && helper="paru"

    local missing=()
    while IFS= read -r bin; do
        [[ -z "$bin" ]] && continue
        command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
    done < <(aphotic_toml_get_array "$manifest" requires binaries)

    [[ ${#missing[@]} -eq 0 ]] && return 0

    if [[ -z "$helper" ]]; then
        aphotic_warn "missing dependencies (${missing[*]}) but no AUR helper (yay/paru) found on PATH -- install manually"
        return 0
    fi

    # `[requires] packages = [...]` in plugin.toml is an optional,
    # explicit override for the (uncommon) case where a binary's real
    # package name differs from the binary name itself -- e.g. a plugin
    # needing a `foo` binary that actually ships in an AUR package called
    # `foo-bin`. Falls back to installing each missing binary's own name
    # as the package name, which is correct for the common case (openrgb
    # the binary really does come from a package literally named
    # `openrgb`) without requiring every plugin manifest to spell out an
    # otherwise-redundant packages list.
    local explicit_pkgs=()
    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue
        explicit_pkgs+=("$pkg")
    done < <(aphotic_toml_get_array "$manifest" requires packages)

    local to_install=("${missing[@]}")
    [[ ${#explicit_pkgs[@]} -gt 0 ]] && to_install=("${explicit_pkgs[@]}")

    echo "Installing dependencies via ${helper}: ${to_install[*]}"
    if "$helper" -S "${to_install[@]}"; then
        aphotic_ok "dependencies installed"
    else
        aphotic_warn "some dependencies failed to install -- check the output above, or install manually"
    fi
}

# Records/refreshes what `aphotic plugin install <name>` just installed
# in APHOTIC_PLUGINS_STATE_FILE's "installed" map -- this is the
# registry §2.2 of APHOTIC_UNIFIED_VISION.md asks for, recording per-
# installed-plugin what it owns so remove can reverse it symmetrically.
# It's also what PluginRegistry.qml (Quickshell side) reads to resolve
# ui-surface tabs -- one JSON object, two consumers, kept in sync here
# rather than duplicated. Called at the end of install(); enable/disable
# don't touch it, since aphotic_plugin_is_enabled already layers on top
# via the same file's "disabled" array.
_aphotic_plugin_registry_sync() {
    local name="$1" dir manifest version caps owns ui tmp
    aphotic_require jq || return 1
    dir="$(_aphotic_plugin_dir "$name")"
    manifest="${dir}/plugin.toml"
    [[ -f "$manifest" ]] || return 1

    version="$(aphotic_toml_get "$manifest" plugin version)"
    caps="$(aphotic_toml_get_array "$manifest" plugin capabilities | jq -R . | jq -s .)"
    owns="$(_aphotic_plugin_owns_json "$manifest")"
    ui="$(_aphotic_plugin_ui_json "$manifest")"

    [[ -f "$APHOTIC_PLUGINS_STATE_FILE" ]] || echo '{"disabled": []}' > "$APHOTIC_PLUGINS_STATE_FILE"
    tmp="$(mktemp)"
    jq --arg n "$name" \
       --arg version "${version:-0.0.0}" \
       --argjson capabilities "${caps:-[]}" \
       --argjson owns "$owns" \
       --argjson ui "$ui" \
       '.installed = ((.installed // {}) + {($n): {version: $version, capabilities: $capabilities, owns: $owns, ui: $ui}})' \
       "$APHOTIC_PLUGINS_STATE_FILE" > "$tmp" && mv "$tmp" "$APHOTIC_PLUGINS_STATE_FILE"
}

# Reverse of the above -- called from remove(). Deleting the registry
# entry is what makes a ui-surface plugin's tab disappear from the
# running shell (PluginRegistry.qml's dashboardTabs recomputes off this
# same file, watched live via FileView) without the shell needing to
# know anything else changed.
_aphotic_plugin_registry_remove() {
    local name="$1" tmp
    aphotic_require jq || return 1
    [[ -f "$APHOTIC_PLUGINS_STATE_FILE" ]] || return 0
    tmp="$(mktemp)"
    jq --arg n "$name" 'if .installed then .installed |= del(.[$n]) else . end' \
       "$APHOTIC_PLUGINS_STATE_FILE" > "$tmp" && mv "$tmp" "$APHOTIC_PLUGINS_STATE_FILE"
}

# A `ui-surface` plugin's own QML files (AgentGraphTab.qml, etc.) need
# to reference each other -- crucially, a `pragma Singleton` sibling
# like AgentGraphService.qml -- through a real `import`, exactly like
# every first-party qs.* module does (see e.g. services/ai/AiProviders.qml
# importing its own qs.services.ai for its AiKeys/AiConfig siblings).
# Confirmed live (2026-08-30): same-directory `pragma Singleton` access
# with NO qmldir/import does *not* reliably resolve when the root file
# was reached via a dynamic `Loader.source` URL rather than Quickshell's
# own static tree-scan -- it silently returns undefined instead of the
# singleton instance. So a plugin's `qml/` directory needs a real
# qmldir (shipped in the plugin itself, e.g. `module qs.modules.plugins
# .agentGraph`) AND needs to physically sit inside the shell's own `qs.*`
# import root for that module import to resolve at all. This symlinks it
# there -- the one thing besides the plugin's own directory that
# `install`/`remove` touch on disk, and exactly the kind of "what a
# plugin touches outside itself" fact the registry (`owns`) exists to
# make auditable. Only done for a plugin that actually ships a `qml/
# qmldir` -- a hook-only plugin has nothing to link.
_aphotic_plugin_ui_module_name() {
    # kebab-case plugin name -> camelCase QML module segment (QML import
    # identifiers can't contain '-'). "agent-graph" -> "agentGraph".
    echo "$1" | sed -E 's/-([a-z0-9])/\U\1/g'
}

_aphotic_plugin_link_ui_module() {
    local name="$1" dest module_name link_path
    dest="$(_aphotic_plugin_dir "$name")"
    [[ -f "${dest}/qml/qmldir" ]] || return 0

    module_name="$(_aphotic_plugin_ui_module_name "$name")"
    link_path="${QUICKSHELL_CONFIG_DIR}/modules/plugins/${module_name}"
    mkdir -p "${QUICKSHELL_CONFIG_DIR}/modules/plugins"
    ln -sfn "${dest}/qml" "$link_path"
}

_aphotic_plugin_unlink_ui_module() {
    local name="$1" module_name
    module_name="$(_aphotic_plugin_ui_module_name "$name")"
    rm -f "${QUICKSHELL_CONFIG_DIR}/modules/plugins/${module_name}"
}

# Real, live-confirmed architecture gap (2026-08-30): install.sh's
# `deploy_user_configs` does `rm -rf`/`cp -R` over the WHOLE of
# `Configs/quickshell/aphotic` -> `~/.config/quickshell/aphotic` on
# every run (not a symlink -- see that function's own comment on why
# most of the tree is a one-shot copy). `modules/plugins/<name>` lives
# *inside* that same tree, so every config refresh silently deletes it
# along with everything else, breaking any installed `ui-surface`
# plugin until this is called again. This is that "again" -- idempotent,
# safe to call after any config redeploy, and install.sh now does so
# (see its own deploy_user_configs). Also callable by hand:
# `aphotic plugin relink-ui-modules`.
_aphotic_plugin_relink_all_ui_modules() {
    local name
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        aphotic_plugin_is_enabled "$name" || continue
        _aphotic_plugin_link_ui_module "$name"
    done < <(aphotic_plugin_names)
}

_aphotic_plugin_install() {
    local name="$1" link="$2" src dest
    [[ -n "$name" ]] || { aphotic_err "usage: aphotic plugin install <name> [--link]"; return 1; }

    _aphotic_plugin_sync_repo || return 1

    src="${APHOTIC_PLUGINS_REPO}/${name}"
    if [[ ! -d "$src" ]] || [[ ! -f "${src}/plugin.toml" ]]; then
        aphotic_err "no plugin '${name}' in ${APHOTIC_PLUGINS_REPO} (repo synced okay, but this name isn't in it — check 'aphotic plugin list --remote')"
        return 1
    fi

    dest="$(_aphotic_plugin_dir "$name")"
    if [[ -e "$dest" ]]; then
        aphotic_err "already installed: ${dest} (remove it first to reinstall)"
        return 1
    fi

    if [[ "$link" == "true" ]]; then
        ln -s "$src" "$dest"
        echo "Linked ${name} -> ${src}"
    else
        echo "Installing ${name}..."
        cp -r "$src" "$dest"
    fi

    find "$dest" -path "*/hooks/*" -type f -exec chmod +x {} \; 2>/dev/null || true

    _aphotic_plugin_install_deps "$dest"
    _aphotic_plugin_registry_sync "$name"
    _aphotic_plugin_link_ui_module "$name"

    aphotic_ok "installed ${name}"
    echo "PLUGIN INSTALLED: ${name}"
}

_aphotic_plugin_remove() {
    local name="$1" dest
    [[ -n "$name" ]] || { aphotic_err "usage: aphotic plugin remove <name>"; return 1; }
    dest="$(_aphotic_plugin_dir "$name")"
    [[ -e "$dest" ]] || { aphotic_err "not installed: ${name}"; return 1; }
    _aphotic_plugin_unlink_ui_module "$name"
    rm -rf "$dest"
    aphotic_plugin_set_enabled "$name" true # clear any disabled-state entry
    _aphotic_plugin_registry_remove "$name"
    aphotic_ok "removed ${name}"
}

aphotic_cmd_plugin() {
    local sub="${1:-}"; shift || true

    case "$sub" in
        list)
            local remote="false" as_json="false" category=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --remote) remote="true"; shift ;;
                    --json) as_json="true"; shift ;;
                    --category) category="${2:-}"; shift 2 ;;
                    *) shift ;;
                esac
            done

            aphotic_require jq || return 1

            local data
            if [[ "$remote" == "true" ]]; then
                data="$(_aphotic_plugin_list_remote_json)"
                if [[ -n "$category" ]]; then
                    data="$(echo "$data" | jq --arg c "$category" '{plugins: ((.plugins // []) | map(select(.category == $c)))}')"
                fi
                [[ "$as_json" == "true" ]] && { echo "$data" | jq '.plugins // []'; return 0; }
                echo "$data" | jq -r '(.plugins // [])[] | "\(.name)\t\(.display_name)\t\(.version)\t\(.description)"' | column -t -s $'\t'
            else
                data="$(_aphotic_plugin_list_installed_json)"
                [[ "$as_json" == "true" ]] && { echo "$data"; return 0; }
                if [[ "$(echo "$data" | jq 'length')" -eq 0 ]]; then
                    aphotic_log "no plugins installed — see 'aphotic plugin list --remote'"
                else
                    echo "$data" | jq -r '.[] | "\(.name)\t\(.display_name)\t\(if .enabled then "enabled" else "disabled" end)\t\(.version)"' | column -t -s $'\t'
                fi
            fi
            ;;
        install)
            local name="" link="false"
            for arg in "$@"; do
                case "$arg" in
                    --link) link="true" ;;
                    *) name="$arg" ;;
                esac
            done
            _aphotic_plugin_install "$name" "$link"
            ;;
        enable)
            [[ -n "${1:-}" ]] || { aphotic_err "usage: aphotic plugin enable <name>"; return 1; }
            aphotic_plugin_set_enabled "$1" true && aphotic_ok "enabled ${1}"
            ;;
        disable)
            [[ -n "${1:-}" ]] || { aphotic_err "usage: aphotic plugin disable <name>"; return 1; }
            aphotic_plugin_set_enabled "$1" false && aphotic_ok "disabled ${1}"
            ;;
        remove)
            _aphotic_plugin_remove "${1:-}"
            ;;
        relink-ui-modules)
            # Plumbing subcommand — called from install.sh's
            # deploy_user_configs after it re-copies Configs/quickshell/
            # aphotic over ~/.config/quickshell/aphotic (which wipes
            # modules/plugins/* along with everything else). Also safe
            # to run by hand if a ui-surface plugin's Dashboard tab goes
            # missing after any manual config resync.
            _aphotic_plugin_relink_all_ui_modules
            aphotic_ok "relinked ui-surface plugin modules"
            ;;
        run-theme-hooks)
            # Plumbing subcommand — called from cmd_theme.sh and from
            # QML (Wallpapers.qml/Themes.qml) and wallswitcher.py after
            # wallust finishes, never directly by a user. No args: it
            # reads the already-fresh palette.json itself, see above.
            _aphotic_plugin_run_theme_hooks
            ;;
        run-project-hooks)
            # Plumbing subcommand — called from ProjectItem.qml's
            # execute() (the launcher's "@" project switcher).
            _aphotic_plugin_run_project_hooks "${1:-}"
            ;;
        run-workspace-hooks)
            # Plumbing subcommand — called from WorkspaceProfilesPane.qml's
            # launchProfile().
            _aphotic_plugin_run_workspace_hooks "${1:-}"
            ;;
        trust-security-index)
            local skip="false"
            [[ "${1:-}" == "--yes" ]] && skip="true"
            _aphotic_plugin_trust_security_index "$skip"
            ;;
        untrust-security-index)
            _aphotic_plugin_untrust_security_index
            ;;
        security-index-status)
            aphotic_require jq || return 1
            _aphotic_plugin_security_index_status
            ;;
        -h|--help|"")
            cat <<EOF
Usage: aphotic plugin <list|install|enable|disable|remove|...> [args]

  list [--remote] [--json] [--category <name>]
                              List installed plugins (or --remote: what's
                              available from APHOTIC_PLUGINS_INDEX_URL,
                              plus the security index if trusted).
                              --category filters by plugin.toml's
                              [plugin].category (dev/security/mobile/
                              ai/theming/productivity).
  install <name> [--link]    Install from a local checkout of
                              aphotic-plugins (APHOTIC_PLUGINS_REPO,
                              default ~/aphotic-plugins). --link symlinks
                              instead of copying, for plugin development.
  enable <name>               Re-enable an installed plugin
  disable <name>               Disable without uninstalling
  remove <name>                Uninstall
  relink-ui-modules             Re-link every enabled ui-surface plugin's
                              QML module into the shell's config tree --
                              run this if a plugin's Dashboard tab goes
                              missing after a manual config resync
                              (install.sh's --config-only already does
                              this automatically)
  trust-security-index         Opt into the separate security-category
                              plugin index (warns first; see docs)
  untrust-security-index       Revoke that opt-in
EOF
            ;;
        *)
            aphotic_err "unknown plugin subcommand: ${sub}"
            return 1
            ;;
    esac
}
