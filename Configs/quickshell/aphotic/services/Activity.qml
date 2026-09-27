pragma Singleton

import QtQuick
import Quickshell
import "ActivityCore.js" as Core

// Every ActivityProbe that currently exists. Read on demand -- by the
// `aphotic runtime` IPC call and `aphotic perf` -- never bound to, so it
// adds no work of its own between reads.
Singleton {
    id: root

    property var _probes: []

    function report(probe: var): void {
        if (probe && !root._probes.includes(probe))
            root._probes = root._probes.concat([probe]);
    }

    function forget(probe: var): void {
        root._probes = root._probes.filter(p => p !== probe);
    }

    function snapshot(): var {
        return Core.summarize(root._probes.map(p => ({
                name: p.name,
                kind: p.kind,
                active: p.active,
                interval: p.interval
            })));
    }
}
