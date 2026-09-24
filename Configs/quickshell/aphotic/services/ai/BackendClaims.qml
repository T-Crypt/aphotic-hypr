pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.services.ai
import qs.services.profile

// The one claimant every local inference backend feeds. An adapter turns
// its backend's own report into `models` and supplies `unload`; this turns
// each entry into Resource Engine claims, Flow passports and unload
// receipts the same way for every backend.
//
// A model entry is { name, embedding, state, vramMiB, ramMiB, pid }:
// - with a pid and a gpuVram source, the PID is adopted, so GpuVramSource
//   registers nvidia-smi's measured figure under this owner;
// - otherwise vramMiB is the backend's own measurement, registered as-is;
// - ramMiB is memory the backend reports resident outside the GPU.
//
// Owns no poll: `models` changes when the adapter's source does.
QtObject {
    id: root

    property string owner: ""
    property string label: ""
    property bool enabled: false
    property var gpuVram: null
    property string priority: "background"
    property var models: []
    // function(name: string): void, the adapter's unload request.
    property var unload: null

    property bool _registered: false
    property var _pids: ({})
    property var _tokens: ({})
    property var _unloads: ({})
    property bool _memoryHeld: false

    onEnabledChanged: {
        root._register();
        root._sync();
    }
    onModelsChanged: root._sync()

    Component.onCompleted: {
        root._register();
        root._sync();
    }

    function _register(): void {
        if (root._registered || !root.enabled || !root.owner)
            return;
        root._registered = true;
        ProfileEngine.register({
            id: root.owner,
            label: root.label || root.owner,
            gracefulStop: claim => root._stop(claim?.id ?? "")
        });
    }

    function _adoptedId(pid: int): string {
        return `${root.owner}-proc-${pid}`;
    }

    // Re-registers only what changed: register() re-runs contention, so
    // re-asserting an unchanged claim each poll would re-raise a
    // negotiation the user already answered with "keep".
    function _claim(id: string, resource: string, amount: int, label: string): void {
        const known = ResourceEngine.claimById(id);
        if (known && known.owner === root.owner && known.amount === amount && known.priority === root.priority)
            return;
        ResourceEngine.register({
            id: id,
            owner: root.owner,
            resource: resource,
            amount: amount,
            priority: root.priority,
            label: label,
            origin: "dynamic"
        });
    }

    function _passport(key: string, name: string, trigger: string, workloadId: string, sessionId: string, resource: string, amount: int): void {
        root._tokens[key] = WorkloadPassports.open({
            plane: "ai",
            owner: root.owner,
            label: key,
            trigger: trigger,
            workloadId: workloadId,
            sessionId: sessionId,
            sourceAt: Date.now(),
            claims: amount > 0 ? [{ resource: resource, amount: amount, unit: "MiB",
                measuredAt: Date.now(), origin: "measured" }] : []
        });
    }

    function _sync(): void {
        const models = root.enabled ? (root.models ?? []) : [];
        LocalInference.report(root.owner, root.label, models);
        if (!root._registered)
            return;

        const resident = ({});
        const owned = ({});
        for (const model of models) {
            if (!model?.name)
                continue;
            const name = model.name;
            const pid = model.pid ?? 0;

            const ram = Math.round(model.ramMiB ?? 0);
            if (ram > 0) {
                const ramId = `${name} (system RAM)`;
                resident[ramId] = true;
                owned[ramId] = true;
                if (!root._memoryHeld) {
                    root._memoryHeld = true;
                    SystemCapacity.acquire("memory");
                }
                root._passport(ramId, name, "model-resident-cpu", `${root.owner}-${name}-ram`, `model-ram:${name}`, "memory", ram);
                root._claim(ramId, "memory", ram, ramId);
            }

            if (pid > 0 && root.gpuVram) {
                resident[name] = true;
                owned[root._adoptedId(pid)] = true;
                if (root._pids[name] !== pid) {
                    if (root._pids[name])
                        root.gpuVram.unadopt(root._pids[name]);
                    root.gpuVram.adopt(pid, root.owner, root.priority);
                    root._pids[name] = pid;
                }
                // GpuVramSource registers the claim on its next scan, so the
                // first passport after a load carries no amount yet.
                const measured = ResourceEngine.claimById(root._adoptedId(pid))?.amount ?? 0;
                root._passport(name, name, "model-resident", `${root.owner}-${name}`, `model:${name}`, "gpu-vram", measured);
                continue;
            }

            const vram = Math.round(model.vramMiB ?? 0);
            if (vram <= 0)
                continue;
            resident[name] = true;
            owned[name] = true;
            root._passport(name, name, "model-resident", `${root.owner}-${name}`, `model:${name}`, "gpu-vram", vram);
            root._claim(name, "gpu-vram", vram, name);
        }

        for (const name of Object.keys(root._pids)) {
            if (resident[name])
                continue;
            root.gpuVram?.unadopt(root._pids[name]);
            delete root._pids[name];
        }

        // Adopted claims belong to GpuVramSource's scan; everything else
        // this owner registered is released here once it leaves the report.
        for (const claim of ResourceEngine.claimsOf(root.owner)) {
            if (!owned[claim.id] && !claim.id.startsWith(`${root.owner}-proc-`))
                ResourceEngine.release(claim.id);
        }

        if (root._memoryHeld && ResourceEngine.claimsOf(root.owner).every(c => c.resource !== "memory")) {
            root._memoryHeld = false;
            SystemCapacity.release("memory");
        }

        // The report that proves a model left is what settles its unload
        // receipt. Asking a backend to drop a model is not the same as it
        // dropping.
        for (const key of Object.keys(root._tokens)) {
            if (resident[key])
                continue;
            WorkloadPassports.close(root._tokens[key], "model-unloaded");
            delete root._tokens[key];
            if (root._unloads[key]) {
                ActionReceipts.applied(root._unloads[key], "unloaded");
                delete root._unloads[key];
            }
        }
    }

    // Leaves the claim in place: the next report releases it once the model
    // is really gone, so the claim table stays true when a stop is slow.
    function _stop(claimId: string): void {
        let name = claimId.endsWith(" (system RAM)") ? claimId.slice(0, -" (system RAM)".length) : claimId;
        if (claimId.startsWith(`${root.owner}-proc-`)) {
            const pid = parseInt(claimId.slice(`${root.owner}-proc-`.length), 10);
            name = Object.keys(root._pids).find(n => root._pids[n] === pid) ?? "";
        }
        if (!name || typeof root.unload !== "function")
            return;
        if (!root._unloads[name]) {
            root._unloads[name] = ActionReceipts.request({
                profileId: root.owner,
                workloadId: `${root.owner}-${name}`,
                kind: "model-unload",
                before: "resident",
                reason: "graceful stop requested"
            });
        }
        root.unload(name);
    }
}
