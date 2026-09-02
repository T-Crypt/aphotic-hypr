pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.services.profile

// Ollama as the Resource Engine's first real claimant: every model
// /api/ps reports resident becomes a background gpu-vram claim, so the
// first foreground claimant to arrive (Gaming, once it exists) negotiates
// against a measured number instead of a placeholder.
//
// Capacity for "gpu-vram" belongs to GpuVramSource, not here -- one place
// declares the resource, everything else only claims against it. Claims
// registered before it is declared are tracked and simply never
// arbitrated, so there is no ordering requirement between the two.
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

    property bool _registered: false

    onEnabledChanged: root._register()
    onRunningModelsChanged: root._sync()

    Component.onCompleted: root._register()

    function _register(): void {
        if (root._registered || !root.enabled)
            return;
        root._registered = true;
        ProfileEngine.register({
            id: root.owner,
            label: qsTr("Ollama"),
            gracefulStop: claim => root._unload(claim?.id ?? "")
        });
        root._sync();
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
        if (!root._registered)
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

    property Process _unloadProc: Process {}
}
