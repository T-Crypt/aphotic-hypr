pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.services
import qs.services.profile

// The one place "gpu-vram" is ever declared, and the catch-all claim
// source for GPU memory held by anything that isn't a domain plugin.
//
// Lives here rather than in services/profile/ because it is not part of
// the substrate: it reads hardware on a timer, and services/profile/ is
// the dormant engine, which owns no timer and no file watch (an invariant
// tests/test_profile_substrate.sh enforces). This is a consumer that
// feeds the engine, not part of it.
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

    // Smallest change that is worth re-registering an existing claim for.
    // register() re-runs contention on every call, and a conflict answered
    // with "keep" is deliberately re-raisable once the claims change -- so
    // without a deadband the compositor's own idle drift re-opens the
    // prompt. Measured on this desktop: Hyprland alone swings ~20 MB and
    // the shell ~15 MB while nothing is happening, and one such blip was
    // enough to re-raise a negotiation the user had just answered.
    //
    // Compared against the *registered* amount rather than the previous
    // sample, so a slow real drift still lands: error against reality is
    // bounded by this value instead of accumulating.
    readonly property int claimDeadbandMb: 64
    readonly property string vendor: SystemUsage.selectedGpu?.vendor ?? ""

    // Read back from the engine rather than cached here. A local flag is
    // a second copy of a fact ResourceEngine already owns, and
    // ResourceEngine.reset() clears its copy only -- which left _probe()
    // early-returning forever, so gpu-vram was never re-declared and
    // every negotiation on it was silently impossible for the rest of
    // the session. Derived, the two cannot disagree.
    readonly property bool declared: !!(ResourceEngine.resources ?? ({}))[root.resource]

    // Whatever dropped the declaration -- a reset, an undeclare -- the
    // file that owns this resource re-asserts it. Deferred for the reason
    // onScanningChanged is: this is a handler on a property derived from
    // ResourceEngine's own state, re-entering it to declare.
    onDeclaredChanged: {
        if (!root.declared)
            Qt.callLater(root._probe);
    }

    // Zero idle cost: the scan only runs when there is something to
    // arbitrate *against* -- a claim this file did not register itself, or
    // a PID a profile has adopted. A base install with a GPU but no local
    // model loaded and no game running pays nothing: capacity is still
    // declared (one probe, at startup), but nothing polls, and the claims
    // this file registered are dropped rather than left to go stale.
    //
    // Excluding its own claims from that test is what stops the scan
    // keeping itself alive forever once it has run a single time.
    readonly property bool scanning: root.declared && root.vendor === "nvidia" && (root._hasForeignClaim || root._hasAdoptions)

    readonly property bool _hasAdoptions: Object.keys(root._adopted).length > 0
    readonly property bool _hasForeignClaim: (ResourceEngine.claims ?? []).some(c => c.resource === root.resource && !root._isMine(c.id))

    // Deferred, not called straight from the handler: `scanning` is
    // derived from ResourceEngine.claims, and releasing claims inside its
    // own change handler mutates that dependency mid-evaluation. QML sees
    // the reentrancy as a binding loop on `claims`, breaks the binding,
    // and every claims-derived property (including ResourceEngine's own
    // `dormant`) silently goes stale. Confirmed live before this fix.
    onScanningChanged: {
        if (!root.scanning)
            Qt.callLater(root._releaseAll);
    }

    function _isMine(id: string): bool {
        return id.startsWith(root.claimPrefix) || root._isAdoptedId(id);
    }

    function _releaseAll(): void {
        for (const claim of ResourceEngine.claims) {
            if (root._isMine(claim.id))
                ResourceEngine.release(claim.id);
        }
    }

    // PIDs a profile has taken ownership of, pid -> {owner, priority}.
    // The scan below registers every process holding VRAM through one
    // loop, and consults this only to decide the claim's id/owner/
    // priority -- so an adopted PID cannot end up with both a generic
    // gpu-proc- claim and a profile-owned one. Keeping a single
    // registration path makes that structural rather than something the
    // two call sites have to agree about.
    property var _adopted: ({})

    function adopt(pid: int, owner: string, priority: string): void {
        if (!pid || !owner)
            return;
        const next = Object.assign({}, root._adopted);
        next[String(pid)] = {
            owner: owner,
            priority: priority === "foreground" ? "foreground" : "background"
        };
        root._adopted = next;
        ResourceEngine.release(`${root.claimPrefix}${pid}`);
    }

    function unadopt(pid: int): void {
        const key = String(pid);
        if (!Object.prototype.hasOwnProperty.call(root._adopted, key))
            return;
        const owned = root._adopted[key];
        const next = Object.assign({}, root._adopted);
        delete next[key];
        root._adopted = next;
        ResourceEngine.release(root._adoptedId(key, owned.owner));
    }

    function _adoptedId(pid: string, owner: string): string {
        return `${owner}-proc-${pid}`;
    }

    property string _probeVendor: ""

    onVendorChanged: root._probe()

    Component.onCompleted: root._probe()

    function _probe(): void {
        if (root.declared || root._capacityProc.running || !root.vendor)
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

    function _unescape(value: string): string {
        return value.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&apos;/g, "'").replace(/&amp;/g, "&");
    }

    // <type> is deliberately not read at all. A process holding VRAM
    // holds it whether the driver calls it C, G or C+G, and branching on
    // the letter is exactly how a C+G workload ends up mishandled as some
    // unrecognised third kind -- mpv reports C+G here, live. Ollama is
    // recognised by path instead, which is type-independent.
    //
    // used_memory carries its unit here ("9218 MiB"), unlike the
    // --format=nounits CSV this replaced; parseInt stops at the space,
    // and an "N/A" entry becomes NaN and is dropped.
    function _parseProcesses(xml: string): var {
        const found = [];
        for (const block of xml.match(/<process_info>[\s\S]*?<\/process_info>/g) ?? []) {
            const field = tag => {
                const m = block.match(new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`));
                return m ? m[1].trim() : "";
            };
            const pid = field("pid");
            const path = root._unescape(field("process_name"));
            const amount = parseInt(field("used_memory"), 10);
            if (!pid || !path || isNaN(amount) || amount <= 0)
                continue;
            found.push({
                pid: pid,
                path: path,
                amount: amount
            });
        }
        return found;
    }

    // A scan can still be in flight when the gate closes (the model
    // unloaded, the game exited). Without this the late result
    // re-registers everything _releaseAll() just dropped, leaving claims
    // behind with the timer already stopped and nothing left to clear
    // them.
    // nvidia-smi's process_name is not always just an executable path:
    // Electron GPU helpers report the whole command line, so the last
    // path segment can be a multi-kilobyte argument blob. Taking the
    // first whitespace-delimited token before basenaming keeps the
    // claim owner (and the negotiation prompt) readable.
    function _displayName(path: string): string {
        const exe = path.split(/\s+/)[0] || path;
        return exe.split("/").pop() || exe;
    }

    function _syncProcesses(text: string): void {
        if (!root.scanning)
            return;

        const seen = ({});

        for (const proc of root._parseProcesses(text)) {
            if (root._isOllama(proc.path))
                continue;

            const name = root._displayName(proc.path);
            const owned = root._adopted[proc.pid] ?? null;
            const owner = owned ? owned.owner : name;
            const id = owned ? root._adoptedId(proc.pid, owner) : `${root.claimPrefix}${proc.pid}`;
            seen[id] = true;

            const known = ResourceEngine.claimById(id);
            if (known && known.owner === owner && Math.abs(known.amount - proc.amount) < root.claimDeadbandMb)
                continue;

            ResourceEngine.register({
                id: id,
                owner: owner,
                resource: root.resource,
                amount: proc.amount,
                priority: owned ? owned.priority : "background",
                label: name,
                origin: "dynamic"
            });
        }

        for (const claim of ResourceEngine.claims) {
            if (claim.origin !== "dynamic" || seen[claim.id])
                continue;
            if (root._isMine(claim.id))
                ResourceEngine.release(claim.id);
        }
    }

    function _isAdoptedId(id: string): bool {
        for (const pid of Object.keys(root._adopted)) {
            if (id === root._adoptedId(pid, root._adopted[pid].owner))
                return true;
        }
        return false;
    }

    property Process _capacityProc: Process {
        stdout: StdioCollector {
            onStreamFinished: root._declareFrom(text)
        }
    }

    // `-q -x` rather than --query-compute-apps: the CSV query flags only
    // ever report C-type processes, so a game -- a G-type process -- was
    // invisible to arbitration entirely. There is no --query-graphics-apps
    // (verified against driver 610's own --help), and the XML block is the
    // only structured source covering every type. Scraping plain
    // nvidia-smi's process table would be the fragile alternative.
    //
    // AMD exposes per-process VRAM only through DRM fdinfo
    // (drm-resident-vram in /proc/<pid>/fdinfo/<fd>, kernel 5.14+), which
    // needs a real parser and real hardware to verify before it can be
    // trusted here.
    property Process _processProc: Process {
        command: ["sh", "-c", "command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -q -x"]
        stdout: StdioCollector {
            onStreamFinished: root._syncProcesses(text)
        }
    }

    // Catch-all background accounting, deliberately slower than the 5s
    // cadence Ollama's own /api/ps poll runs at, and only while something
    // is actually contending (see `scanning`).
    property Timer _processPoll: Timer {
        interval: 12000
        repeat: true
        triggeredOnStart: true
        running: root.scanning
        onTriggered: root._processProc.running = true
    }
}
