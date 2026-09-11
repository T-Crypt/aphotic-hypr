pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// What Aphotic itself is costing, measured from its own process.
//
// This is the one thing in Flow that looks inward. It is deliberately
// separate from the Resource Engine: the shell never registers a claim
// against the resources it is asking other software to yield, and no
// number here reaches arbitration, contention or a negotiation. It is a
// display layer and nothing else.
//
// Reference counted and off unless something is looking, because a shell
// that polls itself to report how little it polls has missed the point.
Singleton {
    id: root

    // Shell CPU time as a share of the whole machine, matching how the
    // metric rail reads CPU. cores is the same number in thread-equivalents,
    // which is the honest unit when one busy thread on a 32-thread box is
    // 3% of the machine and 100% of a core.
    readonly property real cpuPerc: root._cpuPerc
    readonly property real cores: root._cores
    readonly property int memoryMib: root._memoryMib
    readonly property real memoryPerc: SystemCapacity.memoryMib > 0 ? root._memoryMib / SystemCapacity.memoryMib : 0
    readonly property bool measuring: root._holders > 0
    readonly property bool ready: root._lastAt > 0 && root._cpuPerc >= 0

    // Per-process GPU time is not readable without a vendor tool and a
    // process spawn per sample, which would cost more than it reports. The
    // metric rail's GPU figure is the whole card, not Aphotic's share, and
    // this says so rather than implying otherwise.
    readonly property string gpuNote: qsTr("Per-process GPU is not measurable here; the GPU metric is the whole card.")

    function acquire(): void {
        root._holders += 1;
        SystemCapacity.probe("cpu");
        SystemCapacity.probe("memory");
    }

    function release(): void {
        if (root._holders > 0)
            root._holders -= 1;
        if (root._holders === 0) {
            root._lastAt = 0;
            root._cpuPerc = 0;
            root._cores = 0;
        }
    }

    property int _holders: 0
    property real _cpuPerc: 0
    property real _cores: 0
    property int _memoryMib: 0
    property real _lastTicks: 0
    property real _lastAt: 0

    // utime + stime are fields 14 and 15 of /proc/self/stat, after the
    // comm field, which can itself contain spaces -- so the split starts
    // after the closing parenthesis rather than at the first space.
    function _readStat(text: string): void {
        const tail = text.slice(text.lastIndexOf(")") + 2).split(" ");
        const ticks = parseInt(tail[11], 10) + parseInt(tail[12], 10);
        const now = Date.now();
        if (!isFinite(ticks))
            return;
        if (root._lastAt > 0 && now > root._lastAt) {
            // USER_HZ is 100 on every Linux this shell runs on; the value
            // is fixed at kernel build time and is not readable from
            // /proc, so reading it would mean spawning getconf.
            const seconds = (now - root._lastAt) / 1000;
            root._cores = Math.max(0, (ticks - root._lastTicks) / 100 / seconds);
            root._cpuPerc = SystemCapacity.cpuThreads > 0 ? root._cores / SystemCapacity.cpuThreads : 0;
        }
        root._lastTicks = ticks;
        root._lastAt = now;
    }

    function _readStatus(text: string): void {
        const m = text.match(/^VmRSS:\s+(\d+)/m);
        if (m)
            root._memoryMib = Math.round(parseInt(m[1], 10) / 1024);
    }

    property FileView _stat: FileView {
        path: "/proc/self/stat"
        onLoaded: root._readStat(text())
    }

    property FileView _status: FileView {
        path: "/proc/self/status"
        onLoaded: root._readStatus(text())
    }

    Timer {
        running: root._holders > 0
        interval: 2000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root._stat.reload();
            root._status.reload();
        }
    }
}
