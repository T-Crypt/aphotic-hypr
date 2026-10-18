pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.services
import "EngineHttpCore.js" as Core

// One engine descriptor that answers over HTTP with an OpenAI-style model
// list: vLLM, SGLang and anything else that serves /v1/models. A
// descriptor that names its process is asked only while that process
// runs, so an engine that is not installed costs one pgrep per poll and
// no request.
BackendClaims {
    id: root

    required property var descriptor

    property bool reachable: false
    property var _models: []
    property int _pid: 0
    property string _base: ""

    owner: root.descriptor.id
    label: root.descriptor.label
    priority: "foreground"
    models: root.reachable ? root._models.map(m => Object.assign({ pid: root._pid }, m)) : []
    unload: null

    readonly property string configuredBase: EngineRegistry.baseUrl(root.descriptor.id)

    function _poll(): void {
        if (!root.enabled)
            return;
        if (root.descriptor.process) {
            if (!finder.running)
                finder.running = true;
        } else {
            root._ask(root.configuredBase, 0);
        }
    }

    function _found(text: string): void {
        const processes = Core.parseProcesses(text);
        if (processes.length === 0) {
            root._settle(false, [], 0);
            return;
        }
        const wanted = Core.hostPort(root.configuredBase);
        const process = Core.pickProcess(processes, wanted, root.descriptor.portFlag);
        const port = process ? Core.portOf(process.cmdline, root.descriptor.portFlag) : 0;
        const base = root.configuredBase || (port > 0 ? `http://127.0.0.1:${port}` : "");
        root._ask(base, process?.pid ?? 0);
    }

    function _ask(base: string, pid: int): void {
        if (!base) {
            root._settle(false, [], 0);
            return;
        }
        root._base = base;
        const xhr = new XMLHttpRequest();
        xhr.timeout = 2000;
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            const models = xhr.status === 200 ? Core.parseModels(xhr.responseText) : null;
            root._settle(models !== null, models ?? [], pid);
        };
        xhr.open("GET", Core.joinUrl(base, root.descriptor.endpoint));
        xhr.send();
    }

    function _settle(up: bool, models: var, pid: int): void {
        root._pid = pid;
        root._models = models;
        root.reachable = up;
        EngineRegistry.setLive(root.descriptor.id, up ? [{
                id: root.descriptor.id,
                label: root.descriptor.label,
                state: models.some(m => m.state === "ready") ? "ready" : "idle",
                gateway: "",
                url: root._base,
                pid: pid,
                models: models
            }] : []);
    }

    Component.onDestruction: EngineRegistry.setLive(root.descriptor.id, [])

    property Process finder: Process {
        command: ["pgrep", "-af", "--", root.descriptor.process]
        stdout: StdioCollector {
            onStreamFinished: root._found(text)
        }
    }

    property Timer _timer: Timer {
        id: poll

        interval: 10000
        repeat: true
        triggeredOnStart: true
        running: root.enabled
        onTriggered: root._poll()
    }

    property ActivityProbe _probe: ActivityProbe {
        name: "engines.http"
        kind: "process"
        timer: poll
    }
}
