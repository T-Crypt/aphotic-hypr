#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v qs >/dev/null || { echo 'SKIP: qs unavailable'; exit 0; }
PROBE=$(mktemp "$ROOT/Configs/quickshell/aphotic/_probe_dependency_XXXXXX.qml")
TESTHOME=$(mktemp -d)
trap 'rm -f "$PROBE"; rm -rf "$TESTHOME"' EXIT
cat > "$PROBE" <<'QML'
import QtQuick
import Quickshell
import qs.services
ShellRoot {
    Component.onCompleted: {
        const consumer = {ui: {surfaces: [{surface: "workspace", component: "Panel.qml", requires_plugin: "parent"}]}, profile: {id: "example", component: "Profile.qml", requires_plugin: "parent"}, actions: [{id: "example", component: "Action.qml", requires_plugin: "parent"}]};
        const states = [{installed: {consumer: consumer}, disabled: []}, {installed: {consumer: consumer, parent: {}}, disabled: []}, {installed: {consumer: consumer, parent: {}}, disabled: ["parent"]}];
        for (let i = 0; i < states.length; i++) {
            PluginRegistry._data = states[i];
            const expected = i === 1 ? 1 : 0;
            if (PluginRegistry.surfacesFor("workspace").length !== expected || PluginRegistry.profileRegistrations.length !== expected || PluginRegistry.actionRegistrations.length !== expected)
                throw new Error("dependency gate failed for state " + i);
        }
        console.log("PASS dependency runtime");
    }
}
QML
result=0
HOME="$TESTHOME" XDG_RUNTIME_DIR="$TESTHOME" QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 4 qs -p "$PROBE" > "$TESTHOME/output" 2>&1 || result=$?
[[ "$result" == 0 || "$result" == 124 ]] || { cat "$TESTHOME/output"; exit 1; }
grep -q 'PASS dependency runtime' "$TESTHOME/output" || { cat "$TESTHOME/output"; exit 1; }
echo 'PASS: plugin dependency QML runtime'
