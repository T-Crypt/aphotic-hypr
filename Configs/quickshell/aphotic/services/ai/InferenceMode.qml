pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.services.ai
import qs.services.profile
import "InferenceCore.js" as Core
import "../profile/StateSnapshotCore.js" as SnapshotCore

Singleton {
    id: root

    readonly property bool active: root._active
    property string mode: "auto"
    readonly property string model: root._model
    readonly property var tuned: root._tuned

    property bool _active: false
    property string _model: ""
    property var _tuned: []
    property string _signature: ""
    property string _manualOverride: ""
    property string _passport: ""
    property var _shelters: ({})
    property bool _ready: false

    // The pre-inference render state survives a shell crash here. Without it
    // a restart mid-inference would re-enter, capture the tuned-down
    // compositor as the baseline, and never bring blur back.
    readonly property string _renderStatePath: `${Quickshell.env("HOME")}/.local/state/aphotic/inference-render.json`

    function enter(reason: string): void {
        root._manualOverride = "enter";
        graceTimer.stop();
        root._activate(reason || "manual");
    }

    function exit(reason: string): void {
        root._manualOverride = "exit";
        graceTimer.stop();
        root._deactivate(reason || "manual");
    }

    function setMode(value: string): void {
        const next = value === "off" ? "off" : "auto";
        root._manualOverride = "";
        root.mode = next;
        root._sync("mode");
    }

    function status(): string {
        return JSON.stringify({
            active: root.active,
            mode: root.mode,
            model: root.model,
            tuned: root.tuned
        });
    }

    function _eligible(): var {
        return Core.eligibleClaims(ResourceEngine.claims).map(c => c.id)
            .concat(Core.runningChatModels(AiProviders.llamaSwapRunningModels));
    }

    function _stateSignature(): string {
        const models = AiProviders.llamaSwapRunningModels
            .filter(entry => entry?.name && !entry.name.startsWith("text-embedding"))
            .map(entry => entry.name).sort().join("|");
        const triggered = Core.triggeredModels(WorkloadPassports.ofOwner("llama-swap")).sort().join("|");
        return `${Core.claimSignature(ResourceEngine.claims)}#${models}#${triggered}`;
    }

    function _candidateModel(): string {
        return Core.selectTriggeredModel(WorkloadPassports.ofOwner("llama-swap"), AiProviders.llamaSwapRunningModels, root._model);
    }

    function _onModelChange(): void {
        const signature = root._stateSignature();
        if (signature === root._signature)
            return;
        root._signature = signature;
        if (root._ready)
            root._manualOverride = "";

        const nextModel = root._candidateModel();
        if (nextModel !== root._model) {
            root._model = nextModel;
            if (root._active) {
                root._closePassport("model-changed");
                root._openPassport();
            }
        }
        root._sync("model-change");
    }

    function _sync(reason: string): void {
        if (!root._ready)
            return;
        if (root._manualOverride === "enter") {
            root._activate(reason);
            return;
        }
        if (root._manualOverride === "exit" || root.mode === "off") {
            graceTimer.stop();
            root._deactivate(reason);
            return;
        }
        if (root._eligible().length > 0) {
            graceTimer.stop();
            root._activate(reason);
        } else if (root._active) {
            graceTimer.restart();
        }
    }

    function _activate(reason: string): void {
        if (root._active)
            return;
        root._model = root._candidateModel();
        root._active = true;
        if (!ProfileEngine.activate("inference", reason || "llama-swap")) {
            root._active = false;
            return;
        }
        root._openPassport();
        if (reason !== "startup")
            Toaster.toast(qsTr("Inference mode on"), qsTr("%1 is loaded. Effects and paused plugins come back when it unloads.").arg(root._model || qsTr("A model")), "memory");
    }

    function _deactivate(reason: string): void {
        if (!root._active)
            return;
        root._active = false;
        root._closePassport(reason || "exit");
        ProfileEngine.deactivate("inference", reason || "exit");
        Toaster.toast(qsTr("Inference mode off"), qsTr("Effects and plugins are back."), "memory");
    }

    function _apply(): void {
        // Without a render snapshot there is nothing to restore to, so the
        // compositor is left alone; sheltering does not depend on it.
        const render = StateSnapshot.snapshotOf("inference")?.render;
        if (render) {
            const changed = [];
            if (render.blur)
                changed.push("blur");
            if (render.shadow)
                changed.push("shadow");
            if (render.animations)
                changed.push("animations");
            root._tuned = changed;
            const command = SnapshotCore.renderCommand({ blur: 0, shadow: 0, animations: 0 }, render, Hypr.usingLua);
            if (command) {
                stateWrite.exec(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"', "sh", root._renderStatePath, JSON.stringify(render)]);
                tuneProcess.exec(command);
            }
        }
        root._shelterOthers();
    }

    function _restore(): void {
        stateWrite.exec(["rm", "-f", root._renderStatePath]);
        root._releaseShelters();
        root._tuned = [];
    }

    function _shelterOthers(): void {
        for (const id of Object.keys(ProfileEngine.profiles)) {
            if (id === "inference" || !ProfileEngine.canShelter(id) || root._shelters[id])
                continue;
            const receipt = ProfileEngine.requestShelter(id, "local inference in the foreground");
            if (receipt)
                root._shelters[id] = receipt;
        }
    }

    function _releaseShelters(): void {
        for (const id of Object.keys(root._shelters)) {
            ProfileEngine.releaseShelter(id, root._shelters[id]);
            delete root._shelters[id];
        }
    }

    function _openPassport(): void {
        root._passport = WorkloadPassports.open({
            plane: "ai",
            owner: "inference",
            label: `Inference mode · ${root._model || "llama-swap"}`,
            trigger: "llama-swap",
            workloadId: "inference-mode",
            sessionId: "inference-mode",
            sourceAt: Date.now()
        });
    }

    function _closePassport(reason: string): void {
        if (!root._passport)
            return;
        WorkloadPassports.close(root._passport, reason);
        root._passport = "";
    }

    Component.onCompleted: {
        root.mode = AiConfig.inferenceMode === "off" ? "off" : "auto";
        ProfileEngine.register({
            id: "inference",
            label: qsTr("Inference"),
            snapshot: ["render"],
            onApply: () => root._apply(),
            onRestore: () => root._restore()
        });
        root._signature = root._stateSignature();
        staleRead.exec(["cat", root._renderStatePath]);
    }

    function _start(): void {
        root._ready = true;
        root._sync("startup");
    }

    onModeChanged: {
        const normalized = root.mode === "off" ? "off" : "auto";
        if (root.mode !== normalized) {
            root.mode = normalized;
            return;
        }
        if (AiConfig.inferenceMode !== normalized)
            AiConfig.inferenceMode = normalized;
        root._sync("mode");
    }

    Connections {
        target: AiConfig
        function onInferenceModeChanged(): void {
            const persisted = AiConfig.inferenceMode === "off" ? "off" : "auto";
            if (root.mode !== persisted)
                root.mode = persisted;
        }
    }

    Connections {
        target: ResourceEngine
        function onClaimRegistered(): void { root._onModelChange(); }
        function onClaimReleased(): void { root._onModelChange(); }
    }

    Connections {
        target: AiProviders
        function onLlamaSwapRunningModelsChanged(): void { root._onModelChange(); }
    }

    Connections {
        target: WorkloadPassports
        function onOpened(): void { root._onModelChange(); }
        function onChanged(): void { root._onModelChange(); }
        function onEnded(): void { root._onModelChange(); }
    }

    Timer {
        id: graceTimer
        interval: 20000
        repeat: false
        onTriggered: {
            if (root.mode === "auto" && root._manualOverride !== "enter" && root._eligible().length === 0)
                root._deactivate("idle-grace");
        }
    }

    Process {
        id: staleRead
        property string text: ""
        stdout: StdioCollector {
            onStreamFinished: staleRead.text = text
        }
        onExited: {
            let saved = null;
            try {
                saved = JSON.parse(staleRead.text);
            } catch (e) {}
            const command = saved ? SnapshotCore.renderCommand(saved, null, Hypr.usingLua) : null;
            if (command)
                staleRestore.exec(command);
            else
                root._start();
        }
    }

    Process {
        id: staleRestore
        onExited: {
            stateWrite.exec(["rm", "-f", root._renderStatePath]);
            root._start();
        }
    }

    Process {
        id: stateWrite
    }

    Process {
        id: tuneProcess
    }

    IpcHandler {
        target: "inference"

        function enter(): string {
            root.enter("ipc");
            return root.status();
        }

        function exit(): string {
            root.exit("ipc");
            return root.status();
        }

        function auto(): string {
            root.setMode("auto");
            return root.status();
        }

        function off(): string {
            root.setMode("off");
            return root.status();
        }

        function status(): string {
            return root.status();
        }
    }
}
