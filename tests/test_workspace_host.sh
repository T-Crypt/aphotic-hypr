#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$ROOT/Configs/quickshell/aphotic/components/ScreenState.qml"
SHELL="$ROOT/Configs/quickshell/aphotic/shell.qml"
ACTIONS="$ROOT/Configs/quickshell/aphotic/services/Actions.qml"
CONTENT="$ROOT/Configs/quickshell/aphotic/modules/workspace/WorkspaceContent.qml"
WINDOW="$ROOT/Configs/quickshell/aphotic/modules/workspace/WorkspaceWindow.qml"

[[ -f "$CONTENT" ]] || fail "Workspace content module is missing"
[[ -f "$WINDOW" ]] || fail "Workspace window module is missing"
rg -q 'property bool workspace' "$STATE" || fail "Workspace has no per-screen state"
rg -q 'PluginRegistry\.surfacesFor\("workspace"\)' "$CONTENT" || fail "Workspace does not use generic registrations"
rg -q 'source: .*componentUrl' "$CONTENT" || fail "Workspace does not dynamically load plugin content"
rg -q 'surfaceActive' "$CONTENT" || fail "Workspace loads plugin content while hidden"
rg -q 'PluginRegistry\.surfacesFor\("workspace"\)\.length > 0' "$WINDOW" || fail "Workspace window does not disappear when no plugin is eligible"
rg -q 'id: workspaceWindows' "$SHELL" || fail "shell has no Workspace window variants"
rg -q 'workspace: \(\) =>' "$SHELL" || fail "shell has no Workspace toggle route"
rg -q 'target: "workspace"' "$SHELL" || fail "shell has no Workspace IPC target"
rg -q 'width: content.width' "$WINDOW" || fail "Workspace panel does not shield its backdrop from interior clicks"
rg -q 'id: "workspace\.open"' "$ACTIONS" || fail "Workspace action is missing"
rg -q 'PluginRegistry\.surfacesFor\("workspace"\)' "$ACTIONS" || fail "Workspace action is not availability-gated"

echo "PASS: tests/test_workspace_host.sh"
