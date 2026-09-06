#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$ROOT/Configs/quickshell/aphotic/components/ScreenState.qml"
SHELL="$ROOT/Configs/quickshell/aphotic/shell.qml"
ACTIONS="$ROOT/Configs/quickshell/aphotic/services/Actions.qml"
CONTENT="$ROOT/Configs/quickshell/aphotic/modules/workspace/WorkspaceContent.qml"
WINDOW="$ROOT/Configs/quickshell/aphotic/modules/workspace/WorkspaceWindow.qml"
KEYBIND="$ROOT/Configs/quickshell/aphotic/services/WorkspaceKeybind.qml"
QMLDIR="$ROOT/Configs/quickshell/aphotic/services/qmldir"
LUA="$ROOT/Configs/hypr/keybinds.lua"

[[ -f "$CONTENT" ]] || fail "Workspace content module is missing"
[[ -f "$WINDOW" ]] || fail "Workspace window module is missing"
grep -qE 'property bool workspace' "$STATE" || fail "Workspace has no per-screen state"
grep -qE 'PluginRegistry\.surfacesFor\("workspace"\)' "$CONTENT" || fail "Workspace does not use generic registrations"
grep -qE 'source: .*componentUrl' "$CONTENT" || fail "Workspace does not dynamically load plugin content"
grep -qE 'surfaceActive' "$CONTENT" || fail "Workspace loads plugin content while hidden"
grep -qE 'property int hoveredIndex' "$CONTENT" || fail "Workspace navigation has no shared hover state"
grep -qE 'SpringAnimation' "$CONTENT" || fail "Workspace navigation does not use notch motion"
grep -qE 'Colours\.layer\(Colours\.palette\.m3surfaceContainerHigh, 2\)' "$CONTENT" || fail "Workspace lacks notch surface elevation"
grep -qE 'PluginRegistry\.surfacesFor\("workspace"\)\.length > 0' "$WINDOW" || fail "Workspace window does not disappear when no plugin is eligible"
grep -qE 'id: workspaceWindows' "$SHELL" || fail "shell has no Workspace window variants"
grep -qE 'workspace: \(\) =>' "$SHELL" || fail "shell has no Workspace toggle route"
grep -qE 'target: "workspace"' "$SHELL" || fail "shell has no Workspace IPC target"
grep -qE 'width: content.width' "$WINDOW" || fail "Workspace panel does not shield its backdrop from interior clicks"
grep -qE 'id: "workspace\.open"' "$ACTIONS" || fail "Workspace action is missing"
grep -qE 'PluginRegistry\.surfacesFor\("workspace"\)' "$ACTIONS" || fail "Workspace action is not availability-gated"

# --- The keybind ------------------------------------------------------
#
# Bound at runtime rather than in keybinds.lua, because the surface only
# exists while a plugin registers a ui.workspace.

[[ -f "$KEYBIND" ]] || fail "Workspace keybind service is missing"
grep -qE 'PluginRegistry\.surfacesFor\("workspace"\)\.length > 0' "$KEYBIND" || fail "Workspace keybind is not gated on a registered surface"
grep -qE 'singleton WorkspaceKeybind 1\.0 WorkspaceKeybind\.qml' "$QMLDIR" || fail "Workspace keybind singleton is not exported"

# A pragma Singleton nothing names is never constructed, and nothing
# about that failure is visible. This one acts on its own, so it needs a
# construction site. CLAUDE.md, and WallpaperCycle and DevDrift both
# shipped broken this way.
grep -qE '_residentSingletons:.*WorkspaceKeybind' "$SHELL" || fail "Workspace keybind singleton has no construction site"

# hyprctl keyword is refused under the Lua parser, and hl.bind is not
# available under the legacy one. Both paths have to exist.
grep -qE 'hl\.bind\(' "$KEYBIND" || fail "Workspace keybind has no Lua-parser bind path"
grep -qE 'hl\.unbind\(' "$KEYBIND" || fail "Workspace keybind has no Lua-parser unbind path"
grep -qE 'keyword", "bindd' "$KEYBIND" || fail "Workspace keybind has no legacy-parser bind path"
grep -qE 'keyword", "unbind' "$KEYBIND" || fail "Workspace keybind has no legacy-parser unbind path"

# `wanted` and `Hypr.usingLua` settle independently. Reading the parser
# once, whenever the registry happened to finish, emitted the refused
# form on a Lua install and left the combo unbound with nothing logged.
grep -qE 'Hypr\.usingLua' "$KEYBIND" || fail "Workspace keybind does not pick a parser form"
grep -qE 'onDesiredFormChanged' "$KEYBIND" || fail "Workspace keybind does not re-sync when the parser resolves"

# HyprKeybinds buckets the cheatsheet by matching this text. Anything
# starting "Open " lands in Apps & System instead of Aphotic Shell.
grep -qE 'description: "Toggle plugin workspace"' "$KEYBIND" || fail "Workspace keybind description changed without checking its cheatsheet category"

# The combo has to stay free in the static file, or the two fight.
grep -qE 'SUPER \+ SHIFT \+ W is the Workspace plane' "$LUA" || fail "keybinds.lua does not reserve the Workspace combo"
if grep -E '^hl\.bind' "$LUA" | grep -qE 'SHIFT \+ W"'; then
    fail "keybinds.lua statically binds the combo the shell manages at runtime"
fi

echo "PASS: tests/test_workspace_host.sh"
