pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.services

// Per-process CPU/RSS sampling. SystemUsage covers the aggregate meters
// (and is the only thing that should) -- this is strictly the per-PID
// breakdown nothing else in the shell had a source for.
//
// Same "sleeping until seen" gate as SystemUsage.detailedMonitoring and
// GpuVramSource.scanning: a full /proc sweep every couple of seconds is
// not something to run for a surface nobody has open, so object lifetime
// (ProcessUsageWatch) is the registration.
Singleton {
    id: root

    // Top `count` entries, already ordered by whichever key sortBy names.
    // Each entry: { pid, name, cpu, rssKib } -- cpu is percent of ONE
    // core, the same scale top(1) reports, so a busy multithreaded
    // process legitimately exceeds 100.
    readonly property var processes: {
        // GPU is a join, not just a different sort key: only processes
        // holding VRAM belong in that list at all, and a list mostly made
        // of zeroes would say nothing. No object spread -- Quickshell's JS
        // engine rejects it outright (see SystemUsage.qml).
        if (root.sortBy === "gpu") {
            const byPid = root._gpuByPid;
            const held = [];
            for (let i = 0; i < root._samples.length; i++) {
                const sample = root._samples[i];
                const mib = byPid[sample.pid];
                if (mib === undefined)
                    continue;
                held.push({
                    pid: sample.pid,
                    name: sample.name,
                    cpu: sample.cpu,
                    rssKib: sample.rssKib,
                    gpuMib: mib
                });
            }
            return held.sort((a, b) => b.gpuMib - a.gpuMib).slice(0, root.count);
        }

        const key = root.sortBy === "mem" ? "rssKib" : "cpu";
        return root._samples.slice().sort((a, b) => b[key] - a[key]).slice(0, root.count);
    }

    // "cpu" | "mem" | "gpu"
    property string sortBy: "cpu"

    // Per-process VRAM has exactly one source that works here: nvidia-smi.
    // The NVIDIA driver publishes no DRM fdinfo (verified on this box --
    // only the i915 iGPU's clients carry drm-* keys), and AMD's
    // drm-resident-vram path is the one GpuVramSource.qml already declines
    // to trust without real hardware to verify against. So rather than
    // hide the tab on unsupported hardware and reflow the tile, this is
    // surfaced as a capability the tile explains -- the same call
    // SystemUsage makes for GPU stats generally.
    readonly property bool gpuSupported: (SystemUsage.selectedGpu?.vendor ?? "") === "nvidia"
    readonly property bool gpuAvailable: root.gpuSupported && root._gpuSeen
    readonly property int count: Config.notch.processCount
    readonly property bool sampling: root._watchers > 0
    // False for exactly one tick after sampling starts: a CPU percentage
    // is a delta between two samples, so the first sweep can only prime.
    readonly property bool primed: root._samples.length > 0

    function beginSampling(): void {
        root._watchers = root._watchers + 1;
    }

    function endSampling(): void {
        root._watchers = Math.max(0, root._watchers - 1);
        if (root._watchers === 0) {
            root._prev = null;
            root._samples = [];
            root._gpuByPid = ({});
        }
    }

    property var _samples: []
    property var _gpuByPid: ({})
    property bool _gpuSeen: false
    property var _prev: null
    property real _prevAt: 0
    property int _watchers: 0
    property int _clockTicks: 100
    property real _pageKib: 4

    function _ingest(text: string): void {
        const now = Date.now();
        const prev = root._prev;
        const elapsed = prev ? (now - root._prevAt) / 1000 : 0;
        const divisor = root._clockTicks * elapsed;
        const next = {};
        const out = [];
        const rows = text.split("\n");

        for (let i = 0; i < rows.length; i++) {
            const parts = rows[i].split("\t");
            if (parts.length < 4)
                continue;
            const pid = parseInt(parts[0], 10);
            const jiffies = parseInt(parts[2], 10);
            const pages = parseInt(parts[3], 10);
            if (isNaN(pid) || isNaN(jiffies))
                continue;

            next[pid] = jiffies;
            if (divisor <= 0)
                continue;

            const before = prev[pid];
            out.push({
                pid,
                name: parts[1],
                cpu: before === undefined ? 0 : Math.max(0, (jiffies - before) / divisor * 100),
                rssKib: (isNaN(pages) ? 0 : pages) * root._pageKib
            });
        }

        root._prev = next;
        root._prevAt = now;
        if (divisor > 0)
            root._samples = out;
    }

    Process {
        id: unitsProc
        command: ["sh", "-c", "getconf CLK_TCK; getconf PAGESIZE"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const ticks = parseInt(lines[0], 10);
                const page = parseInt(lines[1], 10);
                if (!isNaN(ticks) && ticks > 0)
                    root._clockTicks = ticks;
                if (!isNaN(page) && page > 0)
                    root._pageKib = page / 1024;
            }
        }
    }

    Process {
        id: sampleProc
        // One awk over every /proc/<pid>/stat rather than ps(1): ps's
        // %cpu is the process's lifetime average, not what it is doing
        // now, so a long-lived idle process outranks a busy new one --
        // useless for a live monitor. Cumulative jiffies differenced
        // against the previous sweep gives the real instantaneous figure.
        //
        // comm is bracketed and may itself contain spaces or ')', so the
        // line is split on the LAST ')' instead of by whitespace. Past
        // that split the remaining fields start at `state`, i.e. two
        // lower than the numbering in proc(5): utime 14 -> 12, stime
        // 15 -> 13, rss 24 -> 22.
        command: ["sh", "-c", "awk 'FNR==1{s=$0;i=index(s,\")\");pid=substr(s,1,index(s,\" \")-1);name=substr(s,index(s,\"(\")+1,i-index(s,\"(\")-1);rest=substr(s,i+2);split(rest,f,\" \");print pid\"\\t\"name\"\\t\"(f[12]+f[13])\"\\t\"f[22]}' /proc/[0-9]*/stat 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root._ingest(text)
        }
    }

    function _ingestGpu(xml: string): void {
        const byPid = {};
        for (const block of xml.match(/<process_info>[\s\S]*?<\/process_info>/g) ?? []) {
            const field = tag => {
                const m = block.match(new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`));
                return m ? m[1].trim() : "";
            };
            const pid = field("pid");
            // used_memory carries its unit ("214 MiB"); parseInt stops at
            // the space and an "N/A" entry becomes NaN and is dropped.
            const mib = parseInt(field("used_memory"), 10);
            if (!pid || isNaN(mib) || mib <= 0)
                continue;
            byPid[pid] = mib;
        }
        root._gpuByPid = byPid;
        if (Object.keys(byPid).length > 0)
            root._gpuSeen = true;
    }

    Process {
        id: gpuProc
        // Same invocation GpuVramSource.qml settled on, and for the same
        // reason: the --query-compute-apps CSV only ever reports C-type
        // processes, so everything holding VRAM for rendering -- which on
        // a desktop is nearly all of it -- is invisible to it. The XML is
        // the only structured source covering every type.
        command: ["sh", "-c", "command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -q -x"]
        stdout: StdioCollector {
            onStreamFinished: root._ingestGpu(text)
        }
    }

    function _sweep(): void {
        if (!sampleProc.running)
            sampleProc.running = true;
    }

    function _sweepGpu(): void {
        if (!gpuProc.running)
            gpuProc.running = true;
    }

    Timer {
        interval: Config.notch.processUpdateInterval
        running: root.sampling
        repeat: true
        triggeredOnStart: true
        onTriggered: root._sweep()
    }

    // The steady-state timer above can only prime on its first tick, so
    // without this the list stays empty for a full interval every time
    // the tile is opened. One short follow-up sweep puts real numbers on
    // screen immediately; its narrower window is coarser than a steady
    // tick but is replaced by one a moment later.
    // Its own, slower cadence, and only while the GPU column is the one
    // being shown: one nvidia-smi -q -x costs ~120ms of subprocess here,
    // far too much to hang off the 1.5s /proc tick, and VRAM allocations
    // do not move at anything like that rate anyway.
    Timer {
        interval: Config.notch.gpuUpdateInterval
        running: root.sampling && root.sortBy === "gpu" && root.gpuSupported
        repeat: true
        triggeredOnStart: true
        onTriggered: root._sweepGpu()
    }

    Timer {
        id: primeTimer
        interval: 350
        onTriggered: root._sweep()
    }

    onSamplingChanged: {
        if (root.sampling)
            primeTimer.restart();
        else
            primeTimer.stop();
    }

    Component.onCompleted: unitsProc.running = true
}
