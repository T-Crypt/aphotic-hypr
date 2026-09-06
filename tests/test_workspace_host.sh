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
grep -qE 'property bool workspace' "$STATE" || fail "Workspace has no per-screen state"
grep -qE 'PluginRegistry\.surfacesFor\("workspace"\)' "$CONTENT" || fail "Workspace does not use generic registrations"
grep -qE 'source: .*componentUrl' "$CONTENT" || fail "Workspace does not dynamically load plugin content"
grep -qE 'surfaceActive' "$CONTENT" || fail "Workspace loads plugin content while hidden"
grep -qE 'PluginRegistry\.surfacesFor\("workspace"\)\.length > 0' "$WINDOW" || fail "Workspace window does not disappear when no plugin is eligible"
grep -qE 'id: workspaceWindows' "$SHELL" || fail "shell has no Workspace window variants"
grep -qE 'workspace: \(\) =>' "$SHELL" || fail "shell has no Workspace toggle route"
grep -qE 'target: "workspace"' "$SHELL" || fail "shell has no Workspace IPC target"
grep -qE 'width: content.width' "$WINDOW" || fail "Workspace panel does not shield its backdrop from interior clicks"
grep -qE 'id: "workspace\.open"' "$ACTIONS" || fail "Workspace action is missing"
grep -qE 'PluginRegistry\.surfacesFor\("workspace"\)' "$ACTIONS" || fail "Workspace action is not availability-gated"

echo "PASS: tests/test_workspace_host.sh"
