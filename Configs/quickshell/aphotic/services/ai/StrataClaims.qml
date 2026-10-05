pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.services.ai

// Strata's adapter onto BackendClaims.
//
// Strata keeps one engine process resident, so its GPU figure is that
// process's: the PID is adopted into GpuVramSource and nvidia-smi measures
// it. The RAM figure is the engine's own expert arena, handed in by the
// poll -- the status endpoints report memory for the whole host, which is
// not this backend's footprint, so nothing here is inferred from it.
//
// Nothing starts or stops the engine. A graceful stop asks the server to
// give the memory back, and the claim is released by the next report that
// shows the model actually gone.
BackendClaims {
    id: root

    property var runningModels: []

    property int _pid: 0
    property string _resolvedKey: ""
    property string _pendingKey: ""

    owner: "strata"
    label: qsTr("Strata")
    priority: "foreground"
    models: (root.runningModels ?? []).map(m => ({
        name: m?.name ?? "",
        embedding: m?.embedding === true,
        state: m?.state ?? "",
        pid: root._pid,
        ramMiB: Number(m?.ramMiB ?? 0)
    }))
    // One model, so the stop is the engine's rather than a per-model one.
    // The key reaches the server as a request header, never as an argument.
    unload: name => AiProviders.strataUnload(name)

    onModelsChanged: root._resolve()

    function _modelKey(): string {
        return (root.runningModels ?? []).map(m => `${m?.name ?? ""}:${m?.state ?? ""}`).sort().join("|");
    }

    // The lookup reruns only when a model loads, unloads or changes state;
    // every other poll reuses the PID already found for it.
    function _resolve(): void {
        const key = root._modelKey();
        if (key === root._resolvedKey)
            return;
        if (key === "") {
            root._resolvedKey = key;
            root._pid = 0;
            return;
        }
        if (root._pidProc.running)
            return;
        root._pendingKey = key;
        root._pidProc.running = true;
    }

    function _parsePid(text: string): int {
        const lines = text.split("\n").filter(line => /^\d+\s+\S*strata\s+--serve(?:\s|$)/.test(line));
        if (lines.length !== 1)
            return 0;
        const pid = parseInt(lines[0].trim(), 10);
        return pid > 0 ? pid : 0;
    }

    // Match the engine binary and its first argument. A broad process
    // command search can pick up a shell whose script happens to mention
    // --serve and attribute another process's GPU memory to this backend.
    property Process _pidProc: Process {
        command: ["pgrep", "-a", "-x", "strata"]
        stdout: StdioCollector {
            onStreamFinished: root._pid = root._parsePid(text)
        }
        // Settled on exit, so a pgrep that finds nothing still ends the
        // lookup instead of relaunching it forever.
        onRunningChanged: {
            if (root._pidProc.running)
                return;
            root._resolvedKey = root._pendingKey;
            Qt.callLater(root._resolve);
        }
    }
}
