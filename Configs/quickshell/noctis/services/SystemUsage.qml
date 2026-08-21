pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Pure QML/proc-filesystem system monitor -- no native plugin needed
// (unlike real caelestia's Cpu/Memory/Storage, which come from its C++
// plugin). GPU is deliberately left unimplemented (gpuType always
// "NONE") -- real GPU% needs vendor-specific tooling (nvidia-smi,
// radeontop, intel_gpu_top), out of scope for now; every dashboard card
// that reads gpuType already treats "NONE" as "hide this card".
Singleton {
    id: root

    readonly property string cpuName: _cpuName
    readonly property real cpuPerc: _cpuPerc
    readonly property real cpuTemp: _cpuTemp

    readonly property string gpuType: "NONE"
    readonly property string gpuName: ""
    readonly property real gpuPerc: 0
    readonly property real gpuTemp: 0

    readonly property real memPerc: _memTotal > 0 ? _memUsed / _memTotal : 0
    readonly property real memUsed: _memUsed
    readonly property real memTotal: _memTotal

    readonly property var disks: _disks

    property string _cpuName: ""
    property real _cpuPerc: 0
    property real _cpuTemp: 0
    property real _memUsed: 0
    property real _memTotal: 0
    property var _disks: []

    property var _prevCpu: null

    function formatKib(kib: real): var {
        const mib = kib / 1024;
        if (mib >= 1024)
            return {
                value: mib / 1024,
                unit: "GiB"
            };
        return {
            value: mib,
            unit: "MiB"
        };
    }

    function _parseStatLine(line: string): var {
        const parts = line.trim().split(/\s+/).slice(1).map(Number);
        const idle = parts[3] + (parts[4] ?? 0);
        const total = parts.reduce((a, b) => a + b, 0);
        return {
            idle,
            total
        };
    }

    Process {
        id: cpuNameProc
        command: ["sh", "-c", "grep -m1 'model name' /proc/cpuinfo | cut -d: -f2"]
        stdout: SplitParser {
            onRead: data => root._cpuName = data.trim()
        }
    }

    Process {
        id: statProc
        command: ["head", "-n1", "/proc/stat"]
        stdout: SplitParser {
            onRead: data => {
                const sample = root._parseStatLine(data);
                if (root._prevCpu) {
                    const dIdle = sample.idle - root._prevCpu.idle;
                    const dTotal = sample.total - root._prevCpu.total;
                    if (dTotal > 0)
                        root._cpuPerc = Math.max(0, Math.min(1, 1 - dIdle / dTotal));
                }
                root._prevCpu = sample;
            }
        }
    }

    Process {
        id: tempProc
        command: ["sh", "-c", "cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0"]
        stdout: SplitParser {
            onRead: data => {
                const milli = parseInt(data.trim(), 10);
                if (!isNaN(milli))
                    root._cpuTemp = milli / 1000;
            }
        }
    }

    Process {
        id: memProc
        command: ["cat", "/proc/meminfo"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const m = data.match(/^(MemTotal|MemAvailable):\s+(\d+)/);
                if (!m)
                    return;
                if (m[1] === "MemTotal")
                    root._memTotal = parseInt(m[2], 10);
                else
                    root._memUsed = root._memTotal - parseInt(m[2], 10);
            }
        }
    }

    Process {
        id: diskProc
        command: ["df", "-B1", "--output=target,used,size"]
        stdout: SplitParser {
            splitMarker: "\n"
            property var rows: []
            onRead: data => {
                if (data.startsWith("Mounted") || !data.trim())
                    return;
                const parts = data.trim().split(/\s+/);
                if (parts.length < 3)
                    return;
                const [mount, used, size] = parts;
                if (mount !== "/" && !mount.startsWith("/home") && !mount.startsWith("/mnt"))
                    return;
                rows.push({
                    mount,
                    used: parseInt(used, 10) / 1024,
                    total: parseInt(size, 10) / 1024,
                    perc: parseInt(size, 10) > 0 ? parseInt(used, 10) / parseInt(size, 10) : 0
                });
            }
        }
        onExited: {
            root._disks = stdout.rows.slice(0, 4);
            stdout.rows = [];
        }
    }

    Timer {
        interval: Config.dashboard.resourceUpdateInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statProc.running = true;
            memProc.running = true;
            diskProc.running = true;
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: tempProc.running = true
    }

    Component.onCompleted: cpuNameProc.running = true
}
