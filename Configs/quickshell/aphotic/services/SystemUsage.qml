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
        // Every matching controller, not just the first -- a desktop with
        // both a CPU iGPU (Intel/AMD) and a discrete GPU reports both, and
        // lspci's default output is sorted by PCI bus number, which always
        // puts the CPU's own iGPU (bus 00) before a card in a PCIe slot
        // (bus 01+). `-m1` on the old grep meant this always picked the
        // iGPU on exactly that (very common) hardware combination -- an
        // i9-14900K + RTX 4090 reported "UHD Graphics 770", never the
        // 4090 -- regardless of which one is actually doing any work.
        command: ["sh", "-c", "lspci -mm 2>/dev/null | grep -i 'vga compatible controller\\|3d controller\\|display controller'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const candidates = text.split("\n").filter(l => l.length > 0).map(line => {
                    const fields = line.match(/"[^"]*"|\S+/g) ?? [];
                    return {
                        vendor: (fields[2] ?? "").replace(/"/g, ""),
                        device: (fields[3] ?? "").replace(/"/g, "")
                    };
                });
                // Prefer a discrete GPU over an integrated one when a
                // system reports both -- Intel/AMD's own iGPU is never
                // the one a "Performance" card exists to show on a
                // machine that also has a real GPU, and it's the only
                // one of the three vendor(s) that never gets a live
                // usage/temp reading below anyway (see gpuStatsProc).
                const rank = v => /nvidia/i.test(v) || /amd|ati/i.test(v) ? 1 : 0;
                candidates.sort((a, b) => rank(b.vendor) - rank(a.vendor));
                const best = candidates[0];
                root._gpuName = best ? (best.device || best.vendor || qsTr("Unknown GPU")) : qsTr("Unknown GPU");
                root._gpuVendor = best ? (/nvidia/i.test(best.vendor) ? "nvidia" : /amd|ati/i.test(best.vendor) ? "amd" : /intel/i.test(best.vendor) ? "intel" : "") : "";
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
