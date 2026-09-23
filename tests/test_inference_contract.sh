#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

QS="Configs/quickshell/aphotic"
AI="$QS/services/ai"
PROFILE="$QS/services/profile"

for file in "$AI/LlamaSwapStats.qml" "$AI/InferenceMode.qml" \
            "$AI/InferenceCore.js" "$PROFILE/ResourcePolicy.js" \
            "$PROFILE/StateSnapshotCore.js" "$QS/services/PluginRegistryCore.js"; do
    [[ -f "$file" ]] || fail "missing $file"
done

grep -q '^singleton LlamaSwapStats 1.0 LlamaSwapStats.qml$' "$AI/qmldir" \
    || fail "LlamaSwapStats is not registered"
grep -q '^singleton InferenceMode 1.0 InferenceMode.qml$' "$AI/qmldir" \
    || fail "InferenceMode is not registered"
grep -qE '_residentSingletons:.*InferenceMode' "$QS/shell.qml" \
    || fail "InferenceMode is not resident"

grep -q 'id: "llama-swap"' "$AI/AgentRoles.qml" \
    || fail "llama-swap role is absent"
grep -q 'llamaSwapLoadedModels' "$QS/services/AgentProviders.qml" \
    || fail "AgentProviders does not expose loaded llama-swap models"
grep -q 'property string inferenceMode: "auto"' "$AI/AiConfig.qml" \
    || fail "inference mode is not persisted by AiConfig"
grep -q 'onInferenceModeChanged' "$AI/InferenceMode.qml" \
    || fail "InferenceMode does not follow persisted mode changes"

grep -q 'root._wanted ? root._runningModels : \[\]' "$AI/LlamaSwapStats.qml" \
    || fail "LlamaSwapStats creates pollers without holders"
grep -q 'interval: 1000' "$AI/LlamaSwapStats.qml" \
    || fail "LlamaSwapStats does not poll held models once per second"

grep -q 'snapshot: \["render"\]' "$AI/InferenceMode.qml" \
    || fail "InferenceMode does not use the render snapshot"
grep -q 'target: "inference"' "$AI/InferenceMode.qml" \
    || fail "InferenceMode IPC is absent"
grep -q 'WorkloadPassports.open' "$AI/InferenceMode.qml" \
    || fail "InferenceMode does not open a workload passport"
grep -q 'ProfileEngine.requestShelter' "$AI/InferenceMode.qml" \
    || fail "InferenceMode does not shelter other owners"
grep -q 'if (render)' "$AI/InferenceMode.qml" \
    || fail "InferenceMode makes sheltering depend on a successful render read"

grep -q 'priority: "foreground"' "$AI/LlamaSwapClaims.qml" \
    && grep -q 'adopt(pid, root.owner, root.priority)' "$AI/BackendClaims.qml" \
    || fail "llama-swap claims are not foreground priority"
grep -q 'Policy.incumbent' "$PROFILE/ResourceEngine.qml" \
    || fail "ResourceEngine does not use the tested incumbent policy"

grep -q 'addressableParts:.*"render"' "$PROFILE/StateSnapshot.qml" \
    || fail "render is not addressable by StateSnapshot"
grep -q 'hyprctl getoption decoration:blur:enabled -j' "$PROFILE/StateSnapshot.qml" \
    || fail "render capture does not read Hyprland state"
grep -q 'Core.renderCommand(snapshot.render, current, Hypr.usingLua)' "$PROFILE/StateSnapshot.qml" \
    || fail "render restore does not use the parser-aware render command"

grep -q 'inference-render.json' "$AI/InferenceMode.qml" \
    && grep -q 'id: staleRestore' "$AI/InferenceMode.qml" \
    || fail "InferenceMode does not recover render state after a crash"

grep -q 'if (!contention.claimantSuspendable || !ProfileEngine.isRegistered(claim.owner))' "$PROFILE/ResourceEngine.qml" \
    && grep -q 'readonly property var overBudget' "$PROFILE/ResourceEngine.qml" \
    || fail "a conflict with nothing suspendable must not open a prompt"

grep -q 'id: "plugin-surfaces"' "$QS/services/PluginRegistry.qml" \
    || fail "PluginRegistry does not register the core shelter owner"
grep -q 'RegistryCore.surfacesFor' "$QS/services/PluginRegistry.qml" \
    || fail "PluginRegistry does not apply the tested shelter filter"

grep -q 'LlamaSwapStats.hold("settings-ai", root.visible)' "$QS/modules/settings/panes/AiPane.qml" \
    || fail "AI settings does not hold stats only while visible"
grep -q 'label: qsTr("Inference mode")' "$QS/modules/settings/panes/AiPane.qml" \
    || fail "AI settings has no inference mode row"

echo "PASS: inference shared API contract"
