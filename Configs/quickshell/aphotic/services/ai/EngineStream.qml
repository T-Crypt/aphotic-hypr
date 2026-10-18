pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.services.profile
import "EngineReportCore.js" as Report

// One engine descriptor that reports through a stream: a long-lived command
// whose every stdout line is a full engine report. Each engine the report
// names becomes its own claimant, so a gateway running three engines shows
// three rows in Flow under their own names.
//
// No poll: the command prints when something changes. An engine that leaves
// the report keeps its claimant with no models, which releases its claims.
Item {
    id: root

    required property var descriptor
    property var gpuVram: null
    property bool enabled: true

    // The ids this stream has claimed, in first-seen order. Only grows, so a
    // claimant is never destroyed while it may still hold a claim.
    property var _ids: []
    property var _models: ({})
    property int _failures: 0

    readonly property var command: {
        const parts = root.descriptor?.stream ?? [];
        if (parts.length === 0)
            return [];
        const head = parts[0];
        if (head.startsWith("/") || root.descriptor.source !== "plugin")
            return parts;
        return [`${PluginRegistry.pluginsDir}/${root.descriptor.sourceName}/${head}`].concat(parts.slice(1));
    }

    function _apply(line: string): void {
        const report = Report.parse(line, root.descriptor.id);
        if (!report.ok) {
            console.warn(`aphotic engine: '${root.descriptor.id}' report ignored, ${report.warning}`);
            return;
        }
        root._failures = 0;
        const owned = {};
        for (const id of root._ids)
            owned[id] = true;
        const engines = Report.claimable(report.engines, owned, id => ProfileEngine.isRegistered(id));
        const ids = root._ids.slice();
        const models = {};
        for (const engine of engines) {
            if (!owned[engine.id])
                ids.push(engine.id);
            models[engine.id] = engine.models;
        }
        root._models = models;
        root._ids = ids;
        EngineRegistry.setLive(root.descriptor.id, engines.map(e => ({
            id: e.id,
            label: EngineRegistry.byId(e.id)?.label ?? e.label,
            state: e.state,
            cpuPercent: e.cpuPercent,
            threads: e.threads,
            gateway: root.descriptor.id,
            models: e.models
        })));
    }

    Component.onDestruction: EngineRegistry.setLive(root.descriptor.id, [])

    Process {
        id: stream

        command: root.command
        running: root.enabled && root.command.length > 0

        stdout: SplitParser {
            onRead: line => root._apply(line)
        }

        onExited: (code, status) => {
            root._models = {};
            EngineRegistry.setLive(root.descriptor.id, []);
            // Exit 0 is the stream saying it has nothing to watch here.
            if (!root.enabled || code === 0)
                return;
            root._failures += 1;
            restart.interval = Math.min(60000, 2000 * Math.pow(2, Math.min(root._failures, 5)));
            restart.restart();
        }
    }

    // A stream that fails is restarted with backoff, up to a minute apart.
    Timer {
        id: restart

        onTriggered: {
            stream.running = false;
            stream.running = root.enabled && root.command.length > 0;
        }
    }

    Instantiator {
        model: root._ids

        delegate: BackendClaims {
            required property string modelData

            owner: modelData
            label: EngineRegistry.byId(modelData)?.label ?? modelData
            enabled: root.enabled
            gpuVram: root.gpuVram
            priority: "foreground"
            models: root._models[modelData] ?? []
        }
    }
}
