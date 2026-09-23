pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// llama-swap's adapter onto BackendClaims. /running names each model but
// not the memory it holds, so each model is matched to the llama-server
// serving it (by the port llama-swap started it on) and that PID is
// adopted: the claim carries nvidia-smi's measured figure. A model with no
// matching local process (llama-swap on another machine) holds no VRAM
// here and claims nothing.
//
// Foreground priority: a loaded model is the top claim, but it keeps its
// graceful stop, so a later foreground claimant can still negotiate and
// Suspend unloads it.
BackendClaims {
    id: root

    property var runningModels: []
    property string host: ""

    property var _portToPid: ({})
    property string _resolvedKey: ""
    property string _pendingKey: ""

    owner: "llama-swap"
    label: qsTr("llama-swap")
    priority: "foreground"
    models: (root.runningModels ?? []).map(m => ({
        name: m?.name ?? "",
        pid: root._portToPid[String(m?.port ?? 0)] ?? 0
    }))
    unload: name => {
        if (root.host)
            root._unloadProc.exec(["curl", "-s", "-m", "10", "-X", "POST", `${root.host}/api/models/unload/${encodeURI(name)}`]);
    }

    onRunningModelsChanged: root._resolve()

    function _modelKey(): string {
        return (root.runningModels ?? []).map(m => `${m.name}:${m.port}:${m.state}`).sort().join("|");
    }

    // The PID lookup only reruns when a model starts, stops or changes
    // state. Every other poll reuses the last mapping.
    function _resolve(): void {
        const key = root._modelKey();
        if (key === root._resolvedKey)
            return;
        if (key === "") {
            root._resolvedKey = key;
            root._portToPid = ({});
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
