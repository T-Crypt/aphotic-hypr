pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Pure QML/proc-filesystem system monitor -- no native plugin needed.
// GPU name comes from `lspci` (always available, vendor-neutral).
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

    // Every controller lspci reports (iGPU + any discrete card(s)), each
    // with its own live stats -- lets a machine with more than one GPU
    // (the common Intel/AMD-iGPU + NVIDIA/AMD-discrete combo) monitor
    // whichever one the user picks instead of only ever the one the old
    // single-GPU rank heuristic guessed was "the" GPU.
    readonly property var gpus: _gpus
    readonly property int selectedGpuIndex: _selectedGpuIndex
    readonly property var selectedGpu: _gpus[_selectedGpuIndex] ?? null

    readonly property bool gpuDetected: selectedGpu !== null
    readonly property string gpuName: selectedGpu?.name ?? ""
    readonly property bool gpuStatsAvailable: selectedGpu?.statsAvailable ?? false
    readonly property real gpuPerc: selectedGpu?.perc ?? 0
    readonly property real gpuTemp: selectedGpu?.temp ?? 0

    function selectGpu(index: int): void {
        if (index < 0 || index >= _gpus.length || index === _selectedGpuIndex)
            return;
        _selectedGpuIndex = index;
        root._pollGpu();
    }

    // CPU temperature and GPU utilisation/temperature have no
    // always-visible consumer: the bar reads cpuPerc and memPerc and
    // nothing else. Everything that shows the rest -- the Command
    // Center's performance tab, Settings' System pane, the bar's
    // resources popout -- is a surface the user opens, so each mounts a
    // SystemUsageWatch while it is on screen and nothing polls in
    // between. Same "sleeping until seen" shape as GpuVramSource's
    // `scanning` gate.
    readonly property bool detailedMonitoring: root._watchers > 0

    function beginDetailedMonitoring(): void {
        root._watchers = root._watchers + 1;
    }

    function endDetailedMonitoring(): void {
        root._watchers = Math.max(0, root._watchers - 1);
    }

    // A second level on top of detailed monitoring, for a surface showing
    // GPU utilisation as a live meter next to cpuPerc/memPerc -- those
    // come off the 2s base poll, and a GPU figure a full 30s stale
    // standing beside them does not read as slow, it reads as broken.
    // Opt-in so the surfaces that were happy with 30s (the Command
    // Centre's performance tab, Settings' System pane, the bar's
    // resources popout) keep paying exactly what they paid before.
    readonly property bool fastMonitoring: root._fastWatchers > 0

    function beginFastMonitoring(): void {
        root._fastWatchers = root._fastWatchers + 1;
    }

    function endFastMonitoring(): void {
        root._fastWatchers = Math.max(0, root._fastWatchers - 1);
    }

    // Only the selected GPU. Polling every detected controller kept a
    // second card's reading warm for the moment the user cycles the
    // selector, at the cost of a process per card on every tick forever
    // -- and where intel-gpu-tools is installed the iGPU's branch is a
    // one-second intel_gpu_top run, for a card nothing is displaying.
    // selectGpu() polls the newly chosen card immediately instead, which
    // is fresher than a reading up to a tick old.
    function _pollGpu(): void {
        if (root._gpus.length > 0 && !gpuStatsProc.running)
            gpuStatsProc.running = true;
    }

    readonly property real memPerc: _memTotal > 0 ? _memUsed / _memTotal : 0
    readonly property real memUsed: _memUsed
    readonly property real memTotal: _memTotal

    readonly property var disks: _disks

    property string _cpuName: ""
    property real _cpuPerc: 0
    property real _cpuTemp: 0
    // Each entry: { vendor, name, statsAvailable, perc, temp }
    property var _gpus: []
    property int _selectedGpuIndex: 0
    property real _memUsed: 0
    property real _memTotal: 0
    property var _disks: []
    property int _watchers: 0
    property int _fastWatchers: 0

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
        // 4090 -- regardless of which one is actually doing any work. All
        // detected GPUs are now kept (see root.gpus), not just one.
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
                // Word-boundaried: an un-bounded /ati/i matches the "ati"
                // inside "Corporation", which every lspci vendor string
                // ends with -- that false match previously made EVERY
                // vendor (including plain "Intel Corporation") rank as
                // AMD-or-better, so this comparator was a no-op in
                // practice and the first-listed (lowest PCI bus, i.e. the
                // iGPU) entry always won regardless of what discrete GPU
                // was present. Reproduced and confirmed outside QML before
                // fixing -- this was not a hypothetical.
                const detectVendor = v => /nvidia/i.test(v) ? "nvidia" : /\b(amd|ati)\b/i.test(v) ? "amd" : /intel/i.test(v) ? "intel" : "";
                const rank = v => detectVendor(v) === "nvidia" || detectVendor(v) === "amd" ? 1 : 0;
                candidates.sort((a, b) => rank(b.vendor) - rank(a.vendor));

                const prevSelectedVendor = root._gpus[root._selectedGpuIndex]?.vendor;
                root._gpus = candidates.map(c => ({
                            vendor: detectVendor(c.vendor),
                            name: c.device || c.vendor || qsTr("Unknown GPU"),
                            statsAvailable: false,
                            perc: 0,
                            temp: 0
                        }));
                // Keep the user's chosen GPU selected across a re-scan
                // (hotplug is rare, but the name/list refresh isn't
                // otherwise scheduled) by matching on vendor rather than
                // assuming index stability; default to index 0 (the
                // discrete GPU, after the sort above) the first time.
                const rematch = prevSelectedVendor !== undefined ? root._gpus.findIndex(g => g.vendor === prevSelectedVendor) : -1;
                root._selectedGpuIndex = rematch >= 0 ? rematch : 0;
                if (root.detailedMonitoring)
                    root._pollGpu();
            }
        }
    }

    Process {
        id: gpuStatsProc
        command: {
            const gpu = root._gpus[root._selectedGpuIndex];
            if (!gpu)
                return ["true"];
            switch (gpu.vendor) {
            case "nvidia":
                return ["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu", "--format=csv,noheader,nounits"];
            case "amd":
                // Usage from radeontop; temp from the amdgpu hwmon node
                // directly rather than `sensors`, so this doesn't depend
                // on lm-sensors being installed/configured.
                return ["sh", "-c", "radeontop -d - -l 1 2>/dev/null | grep -o 'gpu [0-9.]*%' | grep -o '[0-9.]*'; for f in /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input; do [ -r \"$f\" ] && cat \"$f\" && break; done"];
            case "intel":
                // Usage from intel_gpu_top's JSON sample (falls back to
                // unavailable if it's not installed or needs privileges
                // this process doesn't have -- caught by the isNaN check
                // below, not a hard requirement); temp from the i915/xe
                // hwmon node the same way AMD's does.
                return ["sh", "-c", "timeout 1 intel_gpu_top -J -s 500 -n 1 2>/dev/null | grep -o '\"Render/3D/0\":[^}]*\"value\": *[0-9.]*' | grep -o '[0-9.]*$'; for f in /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input; do [ -r \"$f\" ] && cat \"$f\" && break; done"];
            default:
                return ["true"];
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const idx = root._selectedGpuIndex;
                const gpu = root._gpus[idx];
                if (gpu) {
                    const lines = text.trim().split("\n").map(s => s.trim()).filter(s => s.length > 0);
                    // No object-spread support in Quickshell's JS engine
                    // (confirmed live: `Unexpected token '...'` aborted
                    // the whole shell on load) -- build the updated record
                    // field-by-field instead.
                    const updated = {
                        vendor: gpu.vendor,
                        name: gpu.name,
                        statsAvailable: false,
                        perc: gpu.perc,
                        temp: gpu.temp
                    };
                    if (gpu.vendor === "nvidia") {
                        const parts = lines[0]?.split(",").map(s => parseFloat(s.trim())) ?? [];
                        if (parts.length >= 2 && !isNaN(parts[0])) {
                            updated.perc = parts[0] / 100;
                            updated.temp = parts[1];
                            updated.statsAvailable = true;
                        }
                    } else if (gpu.vendor === "amd") {
                        // radeontop's usage line (if it printed) comes
                        // first; the hwmon millidegree reading is always
                        // last.
                        const perc = lines.length > 0 ? parseFloat(lines[0]) : NaN;
                        const milli = lines.length > 0 ? parseInt(lines[lines.length - 1], 10) : NaN;
                        const gotPerc = !isNaN(perc);
                        const gotTemp = !isNaN(milli) && lines.length > 1;
                        if (gotPerc)
                            updated.perc = perc / 100;
                        if (gotTemp)
                            updated.temp = milli / 1000;
                        updated.statsAvailable = gotPerc || gotTemp;
                    } else if (gpu.vendor === "intel") {
                        // intel_gpu_top's usage line (if it printed) comes
                        // first; the hwmon millidegree reading is always
                        // last -- mirrors the AMD parse above.
                        const perc = lines.length > 1 ? parseFloat(lines[0]) : NaN;
                        const milli = lines.length > 0 ? parseInt(lines[lines.length - 1], 10) : NaN;
                        const gotPerc = !isNaN(perc);
                        const gotTemp = !isNaN(milli) && lines.length > 0;
                        if (gotPerc)
                            updated.perc = perc / 100;
                        if (gotTemp)
                            updated.temp = milli / 1000;
                        updated.statsAvailable = gotPerc || gotTemp;
                    }
                    const gpus = root._gpus.slice();
                    gpus[idx] = updated;
                    root._gpus = gpus;
                }
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
        // Prefers `sensors -j` (coretemp's "Package id 0" on Intel,
        // k10temp/zenpower's "Tctl" on AMD) over a fixed thermal_zone
        // index -- which chip claims zone0 is registration-order
        // dependent and is not reliably the CPU package sensor on every
        // board. Falls back to thermal_zone0 only when lm-sensors isn't
        // installed/configured at all.
        command: ["sh", "-c", "sensors -j 2>/dev/null || cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: {
                const trimmed = text.trim();
                let celsius = NaN;
                try {
                    const json = JSON.parse(trimmed);
                    for (const chipName in json) {
                        if (!/^(coretemp|k10temp|zenpower)/i.test(chipName))
                            continue;
                        const chip = json[chipName];
                        for (const featName in chip) {
                            if (!/^(package id 0|tctl|tdie)/i.test(featName))
                                continue;
                            const feat = chip[featName];
                            for (const key in feat) {
                                if (key.endsWith("_input")) {
                                    celsius = parseFloat(feat[key]);
                                    break;
                                }
                            }
                            if (!isNaN(celsius))
                                break;
                        }
                        if (!isNaN(celsius))
                            break;
                    }
                } catch (e) {
                    // Not JSON -- this was the thermal_zone0 millidegree fallback.
                    const milli = parseInt(trimmed, 10);
                    if (!isNaN(milli))
                        celsius = milli / 1000;
                }
                if (!isNaN(celsius))
                    root._cpuTemp = celsius;
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
        }
    }

    // triggeredOnStart is what makes opening a surface feel instant: the
    // gate going true fires a tick immediately rather than leaving the
    // card blank for up to 30s.
    //
    // diskProc lives here, not on the 2s timer above -- disk usage has no
    // always-visible consumer (only the Performance tab/System pane/
    // resources popout show it, same as tempProc/GPU stats), where
    // cpuPerc/memPerc feed the bar directly and have to stay on the fast
    // tick. `df` was running every 2s forever for a reading nothing was
    // displaying most of the time. See docs/archive/BACKLOG.md's E2-09.
    Timer {
        interval: Config.dashboard.detailUpdateInterval
        running: root.detailedMonitoring
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            tempProc.running = true;
            diskProc.running = true;
        }
    }

    // Split out of the timer above rather than sharing it: the two used to
    // tick together, so making the GPU poll fast enough to sit beside a 2s
    // CPU meter would have dragged `sensors -j` along at the same rate for
    // a reading that moves in single degrees over minutes.
    Timer {
        interval: root.fastMonitoring ? Config.dashboard.detailFastUpdateInterval : Config.dashboard.detailUpdateInterval
        running: root.detailedMonitoring
        repeat: true
        triggeredOnStart: true
        onTriggered: root._pollGpu()
    }

    Component.onCompleted: {
        cpuNameProc.running = true;
        gpuNameProc.running = true;
    }
}
