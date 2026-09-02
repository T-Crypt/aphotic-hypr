pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.services
import qs.services.profile

// The one place "gpu-vram" is ever declared, and the catch-all claim
// source for GPU memory held by anything that isn't a domain plugin.
//
// Capacity is vendor-routed off SystemUsage.selectedGpu.vendor rather
// than re-detected here -- that singleton already enumerates every
// controller via lspci at startup and is the repo's single source of GPU
// vendor truth.
//
// The per-process half exists because building an integration per
// inference framework is unbounded and always one tool behind:
// nvidia-smi reports every process holding GPU memory by PID, whatever
// it happens to be. Those claims carry the real process name as owner,
// so the negotiation prompt's "no graceful-stop hook" line names the
// actual thing holding the memory.
QtObject {
    id: root

    readonly property string resource: "gpu-vram"
    readonly property string claimPrefix: "gpu-proc-"
    readonly property string vendor: SystemUsage.selectedGpu?.vendor ?? ""

    readonly property bool declared: root._declared

    property bool _declared: false
    property string _probeVendor: ""

    onVendorChanged: root._probe()

    Component.onCompleted: root._probe()

    function _probe(): void {
        if (root._declared || !root.vendor)
            return;

        switch (root.vendor) {
        case "nvidia":
            root._capacityProc.command = ["sh", "-c", "command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits"];
            break;
        case "amd":
            // Connector entries (card0-DP-1) glob alongside the card
            // itself and their `device` link resolves to the DRM node
            // rather than the PCI device, so the same card can appear
            // more than once -- resolve and dedupe before summing.
            root._capacityProc.command = ["sh", "-c", "for f in /sys/class/drm/card*/device/mem_info_vram_total; do [ -r \"$f\" ] && readlink -f \"$f\"; done | sort -u | while read -r p; do cat \"$p\"; done"];
            break;
        default:
            // Intel is integrated and carves its framebuffer out of
            // system RAM, so there is no dedicated-VRAM total to
            // declare. Leaving the resource undeclared is the whole
            // answer: ResourceEngine never arbitrates a resource it has
            // no capacity for, so nothing else needs a special case.
            return;
        }

        root._probeVendor = root.vendor;
        root._capacityProc.running = true;
    }

    // amdgpu reports bytes (kernel docs, "Misc AMDGPU driver
    // information"); nvidia-smi reports MiB. Both are summed across
    // cards to match the aggregate Ollama's own claims sum against.
    function _declareFrom(text: string): void {
        const values = text.trim().split("\n").map(line => parseInt(line.trim(), 10)).filter(v => !isNaN(v) && v > 0);
        if (values.length === 0)
            return;

        const total = values.reduce((a, b) => a + b, 0);
        const mb = root._probeVendor === "amd" ? Math.round(total / (1024 * 1024)) : total;
        if (mb <= 0)
            return;

        ResourceEngine.declareResource(root.resource, {
            label: qsTr("GPU VRAM"),
            unit: "MB",
            capacity: mb,
            safetyMargin: 0.1
        });
        root._declared = true;
    }

    // Ollama is excluded because OllamaClaims registers a precise
    // per-model claim from /api/ps already, and nvidia-smi's figure for
    // the same runner is both larger (it includes CUDA context
    // overhead) and coarser (one row for all loaded models).
    //
    // Matched on the path, not the bare basename: current Ollama runs
    // /usr/lib/ollama/llama-server, and excluding every "llama-server"
    // by name would also hide a user's own llama.cpp server -- exactly
    // the process this catch-all exists to notice.
    function _isOllama(path: string): bool {
        const name = path.split("/").pop() ?? "";
        return name === "ollama" || name === "ollama_llama_server" || path.indexOf("/ollama/") !== -1;
    }

    function _syncProcesses(text: string): void {
        const seen = ({});

        for (const line of text.trim().split("\n")) {
            if (line.length === 0)
                continue;
            const parts = line.split(",").map(s => s.trim());
            if (parts.length < 3)
                continue;

            const pid = parts[0];
            const amount = parseInt(parts[1], 10);
            const path = parts.slice(2).join(",");
            if (!pid || isNaN(amount) || amount <= 0 || root._isOllama(path))
                continue;

            const name = path.split("/").pop() || path;
            const id = `${root.claimPrefix}${pid}`;
            seen[id] = true;

            const known = ResourceEngine.claimById(id);
            if (known && known.amount === amount && known.owner === name)
                continue;

            ResourceEngine.register({
                id: id,
                owner: name,
                resource: root.resource,
                amount: amount,
                priority: "background",
                label: name,
                origin: "dynamic"
            });
        }

        for (const claim of ResourceEngine.claims) {
            if (claim.id.startsWith(root.claimPrefix) && !seen[claim.id])
                ResourceEngine.release(claim.id);
        }
    }

    property Process _capacityProc: Process {
        stdout: StdioCollector {
            onStreamFinished: root._declareFrom(text)
        }
    }

    // NVIDIA only: this is the sole structured per-process GPU *memory*
    // source nvidia-smi offers. `pmon` lists graphics processes too but
    // reports no framebuffer figure (verified live -- its columns are
    // utilisation percentages), and AMD exposes per-process VRAM only
    // through DRM fdinfo (drm-resident-vram in /proc/<pid>/fdinfo/<fd>,
    // kernel 5.14+), which needs a real parser and real hardware to
    // verify before it can be trusted here.
    property Process _processProc: Process {
        command: ["sh", "-c", "command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-compute-apps=pid,used_memory,process_name --format=csv,noheader,nounits"]
        stdout: StdioCollector {
            onStreamFinished: root._syncProcesses(text)
        }
    }

    // Catch-all background accounting, deliberately slower than the 5s
    // cadence Ollama's own /api/ps poll runs at.
    property Timer _processPoll: Timer {
        interval: 12000
        repeat: true
        triggeredOnStart: true
        running: root._declared && root.vendor === "nvidia"
        onTriggered: root._processProc.running = true
    }
}
