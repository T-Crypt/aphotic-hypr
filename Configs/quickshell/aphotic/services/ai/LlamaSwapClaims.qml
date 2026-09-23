pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.services
import qs.services.profile

// llama-swap as a Resource Engine claimant, beside OllamaClaims.
//
// llama-swap's /running list names each model but not the memory it holds.
// Each model is matched to the llama-server process serving it (by the port
// llama-swap started it on) and that PID is adopted into GpuVramSource, so
// the claim carries nvidia-smi's measured figure under this owner instead
// of an anonymous gpu-proc- claim. A model with no matching local process
// (llama-swap running on another machine) holds no VRAM here and claims
// nothing.
//
// Driven off the runningModels AiProviders hands in; the only process this
// owns is a pgrep that runs when the set of running models changes.
QtObject {
    id: root

    property var runningModels: []
    property string host: ""
    property bool enabled: false
    property var gpuVram: null

    readonly property string owner: "llama-swap"

    property bool _registered: false

    // model name -> adopted PID, passport token, pending unload receipt.
    property var _pids: ({})
    property var _tokens: ({})
    property var _unloads: ({})

    property var _portToPid: ({})
    property string _resolvedKey: ""
    property string _pendingKey: ""

    onEnabledChanged: root._register()
    onRunningModelsChanged: root._resolve()

    Component.onCompleted: root._register()

    function _register(): void {
        if (root._registered || !root.enabled)
            return;
        root._registered = true;
        ProfileEngine.register({
            id: root.owner,
            label: qsTr("llama-swap"),
            gracefulStop: claim => root._unload(claim?.id ?? "")
        });
        root._resolve();
    }

    function _modelKey(): string {
        return (root.runningModels ?? []).map(m => `${m.name}:${m.port}:${m.state}`).sort().join("|");
    }

    // The PID lookup only reruns when a model starts, stops or changes
    // state. Every other poll reuses the last mapping.
    function _resolve(): void {
        if (!root._registered)
            return;
        const key = root._modelKey();
        if (key === root._resolvedKey) {
            root._sync();
            return;
        }
        if (key === "") {
            root._resolvedKey = key;
            root._portToPid = ({});
            root._sync();
            return;
        }
        if (root._pidProc.running)
            return;
        root._pendingKey = key;
        root._pidProc.running = true;
    }

    function _parsePids(text: string): var {
        const map = ({});
        for (const line of text.split("\n")) {
            const pid = parseInt(line, 10);
            const port = line.match(/--port\s+(\d+)/);
            if (pid > 0 && port)
                map[port[1]] = pid;
        }
        return map;
    }

    function _sync(): void {
        const resident = ({});
        for (const model of (root.runningModels ?? [])) {
            const pid = root._portToPid[String(model?.port ?? 0)] ?? 0;
            if (!model?.name || !pid)
                continue;
            resident[model.name] = true;

            if (root._pids[model.name] !== pid) {
                if (root._pids[model.name])
                    root.gpuVram?.unadopt(root._pids[model.name]);
                root.gpuVram?.adopt(pid, root.owner, "background");
                root._pids[model.name] = pid;
            }

            // GpuVramSource registers the claim on its next scan, so the
            // first passport after a load carries no amount yet.
            const claim = ResourceEngine.claimById(`${root.owner}-proc-${pid}`);
            root._tokens[model.name] = WorkloadPassports.open({
                plane: "ai",
                owner: root.owner,
                label: model.name,
                trigger: "model-resident",
                workloadId: `llama-swap-${model.name}`,
                sessionId: `model:${model.name}`,
                sourceAt: Date.now(),
                claims: claim ? [{ resource: "gpu-vram", amount: claim.amount, unit: "MiB",
                    measuredAt: Date.now(), origin: "measured" }] : []
            });
        }

        for (const name of Object.keys(root._pids)) {
            if (resident[name])
                continue;
            root.gpuVram?.unadopt(root._pids[name]);
            delete root._pids[name];
        }

        // Same settle rule as OllamaClaims: the unload receipt stays
        // "requested" until a poll proves the model is gone.
        for (const name of Object.keys(root._tokens)) {
            if (resident[name])
                continue;
            WorkloadPassports.close(root._tokens[name], "model-unloaded");
            delete root._tokens[name];
            if (root._unloads[name]) {
                ActionReceipts.applied(root._unloads[name], "unloaded");
                delete root._unloads[name];
            }
        }
    }

    // Leaves the claim in place: GpuVramSource drops it once the process
    // is gone, and the next /running poll closes the passport.
    function _unload(claimId: string): void {
        const pid = parseInt(claimId.split("-").pop(), 10);
        const name = Object.keys(root._pids).find(n => root._pids[n] === pid) ?? "";
        if (!name || !root.host)
            return;
        if (!root._unloads[name]) {
            root._unloads[name] = ActionReceipts.request({
                profileId: root.owner,
                workloadId: `llama-swap-${name}`,
                kind: "model-unload",
                before: "resident",
                reason: "graceful stop requested"
            });
        }
        root._unloadProc.exec(["curl", "-s", "-m", "10", "-X", "POST", `${root.host}/api/models/unload/${encodeURI(name)}`]);
    }

    property Process _pidProc: Process {
        command: ["pgrep", "-a", "-x", "llama-server"]
        stdout: StdioCollector {
            onStreamFinished: root._portToPid = root._parsePids(text)
        }
        // Settled on exit, not on output, so a pgrep that finds nothing or
        // fails still ends the lookup instead of relaunching it forever. A
        // model that started while it ran is not in its output, so the key
        // is the one taken at launch and a changed list looks again.
        onRunningChanged: {
            if (root._pidProc.running)
                return;
            root._resolvedKey = root._pendingKey;
            Qt.callLater(root._resolve);
        }
    }

    property Process _unloadProc: Process {}
}
