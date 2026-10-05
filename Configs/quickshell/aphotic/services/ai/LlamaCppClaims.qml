pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.services
import "LlamaCppCore.js" as Core

BackendClaims {
    id: root

    property var _servers: []
    property var _names: ({})
    property var _queryQueue: []
    property string _queryText: ""
    property bool _queryExited: false
    property bool _queryStreamFinished: false
    property int _queryExitCode: -1

    owner: "llama.cpp"
    label: qsTr("llama.cpp")
    priority: "foreground"
    models: root.enabled ? root._servers.map(server => ({
        name: root._names[server.key] ?? "",
        pid: server.pid,
        embedding: server.embedding,
        state: "ready"
    })).filter(model => model.name) : []
    unload: null

    function _scan(): void {
        if (root.enabled && !discovery.running)
            discovery.running = true;
    }

    function _acceptDiscovery(text: string): void {
        if (!root.enabled)
            return;
        const servers = [];
        const queued = Object.create(null);
        for (const line of text.split("\n")) {
            const process = Core.parseProcessLine(line);
            if (!process || Core.managedParent(process.parentComm))
                continue;
            const parsed = Core.parseCommand(process.cmdline);
            const key = `${process.pid}:${parsed.port}`;
            const fallback = Core.fallbackName(parsed);
            servers.push({
                key: key,
                pid: process.pid,
                host: parsed.host,
                port: parsed.port,
                embedding: parsed.embedding,
                fallback: fallback
            });
            if (!Object.prototype.hasOwnProperty.call(root._names, key) && !queued[key]) {
                queued[key] = true;
                root._queryQueue.push({ key: key, host: parsed.host, port: parsed.port, fallback: fallback });
            }
        }
        root._servers = servers;
        root._queryQueue = root._queryQueue.slice();
        root._startQuery();
    }

    function _startQuery(): void {
        if (!root.enabled || modelQuery.running || root._queryQueue.length === 0)
            return;
        const next = root._queryQueue.shift();
        root._queryQueue = root._queryQueue.slice();
        modelQuery.key = next.key;
        modelQuery.fallback = next.fallback;
        if (!Core.isLoopbackHost(next.host)) {
            const names = Object.assign({}, root._names);
            names[next.key] = next.fallback;
            root._names = names;
            Qt.callLater(root._startQuery);
            return;
        }
        root._queryText = "";
        root._queryExited = false;
        root._queryStreamFinished = false;
        root._queryExitCode = -1;
        const host = next.host === "::1" ? "[::1]" : next.host;
        modelQuery.command = ["curl", "--noproxy", "*", "-fsS", "-m", "2", `http://${host}:${next.port}/v1/models`];
        modelQuery.running = true;
    }

    function _settleQuery(): void {
        if (!root._queryExited || !root._queryStreamFinished)
            return;
        let name = "";
        if (root._queryExitCode === 0) {
            try {
                name = String(JSON.parse(root._queryText)?.data?.[0]?.id ?? "");
            } catch (e) {}
        }
        const names = Object.assign({}, root._names);
        names[modelQuery.key] = name || modelQuery.fallback;
        root._names = names;
        Qt.callLater(root._startQuery);
    }

    property Timer _poll: Timer {
        interval: 10000
        repeat: true
        triggeredOnStart: true
        running: root.enabled
        onTriggered: root._scan()
    }

    property ActivityProbe _pollProbe: ActivityProbe {
        name: "ai.llama-cpp-discovery"
        kind: "process"
        timer: root._poll
    }

    property Process discovery: Process {
        command: ["sh", "-c", "pgrep -a -x llama-server | while IFS= read -r line; do pid=${line%% *}; cmd=${line#* }; stat=$(cat \"/proc/$pid/stat\" 2>/dev/null) || continue; fields=${stat##*) }; fields=${fields#* }; ppid=${fields%% *}; parent_comm=$(cat \"/proc/$ppid/comm\" 2>/dev/null) || continue; printf '%s %s %s\\n' \"$pid\" \"$parent_comm\" \"$cmd\"; done"]
        stdout: StdioCollector {
            onStreamFinished: root._acceptDiscovery(text)
        }
    }

    property Process modelQuery: Process {
        property string key: ""
        property string fallback: ""
        stdout: StdioCollector {
            onStreamFinished: {
                root._queryText = text;
                root._queryStreamFinished = true;
                root._settleQuery();
            }
        }
        onExited: exitCode => {
            root._queryExitCode = exitCode;
            root._queryExited = true;
            root._settleQuery();
        }
    }
}
