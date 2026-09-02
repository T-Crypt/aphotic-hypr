pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.services.profile

// Ollama as the Resource Engine's first real claimant: every model
// /api/ps reports resident becomes a background gpu-vram claim, so the
// first foreground claimant to arrive (Gaming, once it exists) negotiates
// against a measured number instead of a placeholder.
//
// Capacity is declared here rather than in ResourceEngine because the
// engine never probes hardware (see its header). nvidia-smi is the only
// total-VRAM source this repo can currently trust; on an AMD/Intel
// machine nothing is declared at all, which leaves "gpu-vram" undeclared
// and therefore never arbitrated -- the correct degrade, not a gap to
// paper over with a guessed capacity.
//
// Everything is driven off the runningModels the parent hands in, so this
// owns no poll of its own; AiProviders' single background /api/ps timer is
// the one clock.
QtObject {
    id: root

    property var runningModels: []
    property string host: ""
    property bool enabled: false

    readonly property string owner: "ollama"
    readonly property string resource: "gpu-vram"

    property bool _probed: false
    property bool _declared: false

    onEnabledChanged: root._probe()
    onRunningModelsChanged: root._sync()

    Component.onCompleted: root._probe()

    function _probe(): void {
        if (root._probed || !root.enabled)
            return;
        root._probed = true;
        root._probeProc.running = true;
    }

    // Re-registers only what actually changed: register() is an upsert
    // that re-runs contention on every call, so re-asserting an unchanged
    // claim each poll would re-raise a negotiation the user already
    // answered with "keep", every five seconds.
    //
    // A model /api/ps reports with size_vram 0 is resident in system RAM,
    // not on the GPU (Ollama falls back to CPU inference when it can't fit
    // or can't reach the card), so it is not a gpu-vram claimant at all.
    // Registering it anyway would put a zero-amount claim in the table that
    // adds nothing to the total but can still be picked as the incumbent to
    // suspend -- offering to stop a CPU-resident model to free VRAM it was
    // never holding.
    function _sync(): void {
        if (!root._declared)
            return;

        const resident = {};
        for (const model of (root.runningModels ?? [])) {
            if (!model?.name)
                continue;
            const amount = Math.round((model.size_vram ?? 0) / (1024 * 1024));
            if (amount <= 0)
                continue;
            resident[model.name] = true;
            const known = ResourceEngine.claimById(model.name);
            if (known && known.owner === root.owner && known.amount === amount)
                continue;
            ResourceEngine.register({
                id: model.name,
                owner: root.owner,
                resource: root.resource,
                amount: amount,
                priority: "background",
                label: model.name,
                origin: "dynamic"
            });
        }

        for (const claim of ResourceEngine.claimsOf(root.owner)) {
            if (!resident[claim.id])
                ResourceEngine.release(claim.id);
        }
    }

    // Deliberately does not release the claim: the next /api/ps poll does
    // that, once the model is actually gone. ResourceEngine's contract is
    // that the claim table keeps telling the truth even when a stop is
    // slow or silently fails.
    function _unload(id: string): void {
        if (!id || !root.host)
            return;
        root._unloadProc.exec(["curl", "-s", "-m", "10", "-X", "POST", `${root.host}/api/generate`, "-d", JSON.stringify({
            model: id,
            keep_alive: 0
        })]);
    }

    // `sh -c` with a command -v guard rather than execing nvidia-smi
    // directly: the binary is absent on most machines and a missing
    // command is a Process-failed-to-start log line on every shell start
    // (issue #43), where this just prints nothing.
    property Process _probeProc: Process {
        command: ["sh", "-c", "command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Summed across cards because size_vram from /api/ps is
                // itself a total across every GPU Ollama loaded onto --
                // capacity has to be the same aggregate the claims are.
                const total = text.trim().split("\n").map(line => parseInt(line.trim(), 10)).filter(v => !isNaN(v) && v > 0).reduce((a, b) => a + b, 0);
                if (total <= 0)
                    return;

                ResourceEngine.declareResource(root.resource, {
                    label: qsTr("GPU VRAM"),
                    unit: "MB",
                    capacity: total,
                    safetyMargin: 0.1
                });
                ProfileEngine.register({
                    id: root.owner,
                    label: qsTr("Ollama"),
                    gracefulStop: claim => root._unload(claim?.id ?? "")
                });
                root._declared = true;
                root._sync();
            }
        }
    }

    property Process _unloadProc: Process {}
}
