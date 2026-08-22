pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Pure QML/proc-filesystem system monitor -- no native plugin needed
// (unlike real caelestia's Cpu/Memory/Storage, which come from its C++
// plugin). GPU name comes from `lspci` (always available, vendor-neutral).
// Live usage/temp needs vendor-specific tooling (nvidia-smi, radeontop,
// intel_gpu_top) that may not be installed -- when none is found,
// gpuStatsAvailable is false and the dashboard card shows "N/A" for
// usage/temp rather than hiding the whole card, so the performance grid
// doesn't reflow depending on what's installed.
Singleton {
    id: root

    readonly property string cpuName: _cpuName
    readonly property real cpuPerc: _cpuPerc
    readonly property real cpuTemp: _cpuTemp

    readonly property bool gpuDetected: _gpuName.length > 0
    readonly property string gpuName: _gpuName
    readonly property bool gpuStatsAvailable: _gpuStatsAvailable
    readonly property real gpuPerc: _gpuPerc
    readonly property real gpuTemp: _gpuTemp

    readonly property real memPerc: _memTotal > 0 ? _memUsed / _memTotal : 0
    readonly property real memUsed: _memUsed
    readonly property real memTotal: _memTotal

    readonly property var disks: _disks

    property string _cpuName: ""
    property real _cpuPerc: 0
    property real _cpuTemp: 0
    property string _gpuName: ""
    property string _gpuVendor: ""
    property bool _gpuStatsAvailable: false
    property real _gpuPerc: 0
    property real _gpuTemp: 0
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
        id: gpuNameProc
        command: ["sh", "-c", "lspci -mm 2>/dev/null | grep -im1 'vga compatible controller\\|3d controller\\|display controller'"]
        stdout: SplitParser {
            onRead: data => {
                const fields = data.match(/"[^"]*"|\S+/g) ?? [];
                const vendor = (fields[2] ?? "").replace(/"/g, "");
                const device = (fields[3] ?? "").replace(/"/g, "");
                root._gpuName = device || vendor || qsTr("Unknown GPU");
                root._gpuVendor = /nvidia/i.test(vendor) ? "nvidia" : /amd|ati/i.test(vendor) ? "amd" : /intel/i.test(vendor) ? "intel" : "";
                gpuStatsProc.running = true;
            }
        }
    }

    Process {
        id: gpuStatsProc
        command: {
            switch (root._gpuVendor) {
            case "nvidia":
                return ["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu", "--format=csv,noheader,nounits"];
            case "amd":
                return ["sh", "-c", "radeontop -d - -l 1 2>/dev/null | grep -o 'gpu [0-9.]*%' | grep -o '[0-9.]*'"];
            default:
                return ["true"];
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (root._gpuVendor === "nvidia") {
                    const parts = text.trim().split(",").map(s => parseFloat(s.trim()));
                    if (parts.length >= 2 && !isNaN(parts[0])) {
                        root._gpuPerc = parts[0] / 100;
                        root._gpuTemp = parts[1];
                        root._gpuStatsAvailable = true;
                        return;
                    }
                } else if (root._gpuVendor === "amd") {
                    const perc = parseFloat(text.trim());
                    if (!isNaN(perc)) {
                        root._gpuPerc = perc / 100;
                        root._gpuStatsAvailable = true;
                        return;
                    }
                }
                root._gpuStatsAvailable = false;
            }
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
        onTriggered: {
            tempProc.running = true;
            if (root._gpuVendor.length > 0)
                gpuStatsProc.running = true;
        }
    }

    Component.onCompleted: {
        cpuNameProc.running = true;
        gpuNameProc.running = true;
    }
}
