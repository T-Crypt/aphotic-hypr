pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.services.profile
import qs.services.ai

Singleton {
    id: root
    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/aphotic/handover/index.json"
    property var leases: []
    property var reservations: ({})
    property var passports: ({})
    property var capacityHeld: ({})
    property string error: ""
    readonly property var recovery: leases.filter(l => l.status !== "restored" && !reservations[l.id])

    function preview(plan: var): var {
        if (root.error) return {ok: false, error: root.error};
        if (!plan?.id || !plan.owner || !Array.isArray(plan.resources) || !plan.resources.length)
            return {ok: false, error: "Malformed lease"};
        const seen = {};
        for (const r of plan.resources) {
            if (!r.key || seen[r.key] || typeof r.amount !== "number" || !isFinite(r.amount) || r.amount <= 0)
                return {ok: false, error: "Malformed resource"};
            seen[r.key] = true;
            if (!["cpu", "memory"].includes(r.key) && r.exclusive !== true)
                return {ok: false, error: "Device resources must be exclusive"};
            const held = ResourceEngine.claimsFor(r.key).filter(c => c.leaseId !== plan.id);
            let spec = ResourceEngine.resourceSpec(r.key);
            if (!spec && (r.key === "memory" || r.key === "cpu")) {
                SystemCapacity.probe(r.key);
                const capacity = SystemCapacity.known[r.key];
                if (!capacity) return {ok: false, retry: true, error: "Reading host capacity"};
                spec = {capacity: capacity, safetyMargin: 0.15};
            }
            if (held.length && (r.exclusive || held.some(c => c.exclusive)))
                return {ok: false, error: "Exclusive resource occupied: " + r.key};
            if (!r.exclusive && (!spec || held.reduce((n,c) => n+c.amount, r.amount) > spec.capacity * (1-spec.safetyMargin)))
                return {ok: false, error: "Insufficient declared capacity: " + r.key};
        }
        return {ok: true, claims: plan.resources, agents: AgentEvents.liveSessions.map(s => s.label || s.harness || s.id)};
    }

    function reserve(plan: var): var {
        const result = preview(plan);
        if (!result.ok) return result;
        if (result.agents.length && !plan.acknowledgeAgents)
            return {ok: false, error: "Live agent sessions require acknowledgement: " + result.agents.join(", ")};
        if (reservations[plan.id]) return {ok: false, error: "Lease already reserved"};
        reservations = Object.assign({}, reservations, {[plan.id]: plan});
        syncClaims();
        return {ok: true};
    }

    function releaseLease(payload: var): var {
        const next = Object.assign({}, reservations);
        delete next[payload.id];
        reservations = next;
        // Durable journals remain authoritative until terminal recovery has finished.
        syncClaims();
        return {ok: true};
    }

    function shelterSnapshot(stage: var): var {
        const p = ProfileEngine.profiles[stage.owner];
        if (!ProfileEngine.canShelter(stage.owner) || typeof p?.handoverState !== "function"
                || typeof p?.handoverShelter !== "function" || typeof p?.handoverRestore !== "function")
            return {ok: false, error: "Owner lacks a durable exact-state restore contract: " + stage.owner,
                canShelter: ProfileEngine.canShelter(stage.owner), canSuspend: ProfileEngine.canSuspend(stage.owner)};
        const value = p.handoverState();
        if (typeof value !== "string" || value.length > 64)
            return {ok: false, error: "Owner state must be a bounded string"};
        return {ok: true, value: value};
    }

    function shelterChange(stage: var, restore: bool): var {
        const snapshot = shelterSnapshot(stage);
        if (!snapshot.ok) return snapshot;
        const expected = restore ? stage.after : stage.before;
        const target = restore ? stage.before : stage.after;
        if (snapshot.value === target) return {ok: true};
        if (snapshot.value !== expected) return {ok: false, error: "Owner changed outside this lease; preserving state"};
        const p = ProfileEngine.profiles[stage.owner];
        const result = restore ? p.handoverRestore(target) : p.handoverShelter(target);
        if (result !== true || p.handoverState() !== target)
            return {ok: false, error: "Owner did not confirm requested state"};
        return {ok: true};
    }

    function syncClaims(): void {
        const active = {};
        leases.filter(l => l.status !== "restored").forEach(l => active[l.id] = l);
        Object.keys(reservations).forEach(id => active[id] = reservations[id]);
        const claims = [];
        Object.keys(active).forEach(id => {
            const l = active[id];
            l.resources.forEach(r => claims.push({id: "handover:"+id+":"+r.key, leaseId: id,
                owner: l.owner, resource: r.key, amount: r.amount, exclusive: !!r.exclusive,
                priority: "foreground", origin: "dynamic", label: l.label || id}));
            if (!passports[id]) passports[id] = WorkloadPassports.open({owner: l.owner, plane: l.plane,
                label: l.label || id, trigger: "host handover", sessionId: id, sourceAt: Date.now()});
        });
        Object.keys(passports).forEach(id => {
            if (!active[id]) { WorkloadPassports.close(passports[id], "host restored"); delete passports[id]; }
        });
        const wanted = {};
        claims.forEach(c => { if (c.resource === "memory" || c.resource === "cpu") wanted[c.resource] = true; });
        Object.keys(wanted).forEach(key => { if (!capacityHeld[key]) SystemCapacity.acquire(key); });
        Object.keys(capacityHeld).forEach(key => { if (!wanted[key]) SystemCapacity.release(key); });
        capacityHeld = wanted;
        ResourceEngine.leaseClaims = claims;
        ResourceEngine.leaseRecoveryBlocked = !!error;
    }

    function ingest(text: string): void {
        try {
            const data = JSON.parse(text);
            if (data.schema !== 1 || !Array.isArray(data.leases)) throw "Malformed handover index";
            for (const l of data.leases) {
                if (!l.id || ["index", "__proto__", "constructor", "prototype"].includes(l.id) || !l.owner || !Array.isArray(l.resources) || !Array.isArray(l.stages)) throw "Malformed lease journal";
                if (l.resources.some(r => !r || typeof r.key !== "string" || typeof r.amount !== "number" || !isFinite(r.amount) || r.amount <= 0))
                    throw "Malformed lease resources";
                if (!["acquiring", "active", "restoring", "recovery-required", "restored"].includes(l.status)) throw "Unknown lease state";
            }
            leases = data.leases;
            error = data.errors?.length ? "One or more lease journals need repair; use aphotic handover status" : "";
            for (const l of leases) {
                for (const s of l.stages) ActionReceipts.importHandover(l, s);
                if (l.status === "restored") { const next = Object.assign({}, reservations); delete next[l.id]; reservations = next; }
            }
        } catch (e) { error = "Handover recovery required: " + e; }
        syncClaims();
    }

    function dispatch(method: string, input: string): string {
        try {
            const payload = JSON.parse(input);
            if (method === "preview") return JSON.stringify(preview(payload));
            if (method === "reserve") return JSON.stringify(reserve(payload));
            if (method === "release") return JSON.stringify(releaseLease(payload));
            if (method === "shelterSnapshot") return JSON.stringify(shelterSnapshot(payload));
            if (method === "shelterApply") return JSON.stringify(shelterChange(payload, false));
            if (method === "shelterRestore") return JSON.stringify(shelterChange(payload, true));
            return JSON.stringify({ok: false, error: "Unknown operation"});
        } catch (e) { return JSON.stringify({ok: false, error: String(e)}); }
    }

    FileView {
        path: root.statePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.ingest(text())
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound || root.leases.length) {
                root.error = "Cannot read handover journal; use aphotic handover status";
                root.syncClaims();
            }
        }
    }
    IpcHandler {
        target: "handover"
        function preview(input: string): string { return root.dispatch("preview", input); }
        function reserve(input: string): string { return root.dispatch("reserve", input); }
        function release(input: string): string { return root.dispatch("release", input); }
        function shelterSnapshot(input: string): string { return root.dispatch("shelterSnapshot", input); }
        function shelterApply(input: string): string { return root.dispatch("shelterApply", input); }
        function shelterRestore(input: string): string { return root.dispatch("shelterRestore", input); }
    }
}
