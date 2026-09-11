pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services.profile

// Declares CPU and system-memory capacity to the Resource Engine, but
// only while something is actually claiming against it.
//
// Core declares no resources at rest on purpose: a base install with
// nothing running has nothing to arbitrate and can never raise a
// negotiation prompt. So this is reference counted. The first claimant
// calls acquire(), the last one to leave calls release(), and the
// declaration disappears with it.
//
// Capacity is read once, from the machine, with one-shot reads. There is
// no timer here: a machine does not grow cores while the shell is up, and
// an unreadable capacity stays undeclared rather than being guessed --
// the Resource Engine treats unknown capacity as unknown, never as free.
Singleton {
    id: root

    readonly property var known: root._known
    readonly property int cpuThreads: root._known.cpu || 0
    readonly property int memoryMib: root._known.memory || 0

    property var _known: ({})
    property var _holders: ({})

    // Claimants call this before they register against `key`. It is safe
    // to call repeatedly; the count is what matters.
    function acquire(key: string): void {
        if (key !== "cpu" && key !== "memory")
            return;
        root._holders[key] = (root._holders[key] || 0) + 1;
        if (root._known[key])
            root._declare(key);
        else if (key === "cpu")
            root._cpuProc.running = true;
        else
            root._memProc.running = true;
    }

    // Read a capacity without declaring it. Flow's shell-activity layer
    // needs the thread count to turn the shell's own CPU time into a
    // percentage, and that is a display detail, not a claim on anything.
    function probe(key: string): void {
        if (root._known[key])
            return;
        if (key === "cpu")
            root._cpuProc.running = true;
        else if (key === "memory")
            root._memProc.running = true;
    }

    function release(key: string): void {
        if (!root._holders[key])
            return;
        root._holders[key] -= 1;
        if (root._holders[key] > 0)
            return;
        delete root._holders[key];
        ResourceEngine.undeclareResource(key);
    }

    function _declare(key: string): void {
        if (!root._holders[key] || !root._known[key])
            return;
        ResourceEngine.declareResource(key, key === "cpu" ? {
            label: qsTr("CPU"),
            unit: "threads",
            capacity: root._known.cpu,
            safetyMargin: 0.15
        } : {
            label: qsTr("Memory"),
            unit: "MiB",
            capacity: root._known.memory,
            safetyMargin: 0.2
        });
    }

    function _learn(key: string, value: int): void {
        if (!(value > 0))
            return;
        const next = Object.assign({}, root._known);
        next[key] = value;
        root._known = next;
        root._declare(key);
    }

    property Process _cpuProc: Process {
        command: ["nproc"]
        stdout: StdioCollector {
            onStreamFinished: root._learn("cpu", parseInt(text.trim(), 10))
        }
    }

    property Process _memProc: Process {
        command: ["cat", "/proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/^MemTotal:\s+(\d+)/m);
                if (m)
                    root._learn("memory", Math.round(parseInt(m[1], 10) / 1024));
            }
        }
    }
}
