pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services.profile

// The one profile lifecycle every opt-in domain (AI, Gaming, Dev,
// Security) runs, rather than four near-identical copies of it:
//
//   DETECT -> LOAD -> NEGOTIATE -> APPLY -> MONITOR -> ANOMALY
//                                              \-> EXIT -> RESTORE -> IDLE
//
// A domain plugin does not reimplement any of that. It registers a
// descriptor of hooks (onLoad/onApply/onExit/onRestore/gracefulStop) plus
// its static claims, and this singleton drives the phases, the claim
// registration, the snapshot and the restore in the same order for every
// domain. `phases` and `_allowed` below are the whole contract.
//
// ANOMALY is a real phase, not a callback: reportAnomaly() parks the
// profile there with the anomaly surfaced and *nothing else happens*. The
// only ways out are acknowledgeAnomaly() (back to MONITOR) or
// deactivate(). That is the "surface, don't auto-fix" rule expressed as a
// state machine rather than as a comment nobody has to obey -- there is no
// transition out of ANOMALY that applies a remedy.
Singleton {
    id: root

    readonly property var phases: ["idle", "detect", "load", "negotiate", "apply", "monitor", "anomaly", "exit", "restore"]

    readonly property var profiles: root._profiles
    readonly property var states: root._states
    readonly property var activeIds: Object.keys(root._states).filter(id => root._states[id].phase !== "idle")
    readonly property bool anyActive: root.activeIds.length > 0

    signal profileRegistered(id: string)
    signal profileUnregistered(id: string)
    signal phaseChanged(id: string, from: string, to: string)
    signal anomalySurfaced(id: string, anomaly: var)
    signal anomalyAcknowledged(id: string)

    property var _profiles: ({})
    property var _states: ({})

    readonly property var _allowed: ({
        idle: ["detect"],
        detect: ["load", "idle"],
        load: ["negotiate", "exit"],
        negotiate: ["apply", "exit"],
        apply: ["monitor", "exit"],
        monitor: ["anomaly", "exit"],
        anomaly: ["monitor", "exit"],
        exit: ["restore"],
        restore: ["idle"]
    })

    function register(descriptor: var): bool {
        if (!descriptor || !descriptor.id) {
            console.warn("ProfileEngine: descriptor needs an id");
            return false;
        }
        const id = String(descriptor.id);

        const profiles = Object.assign({}, root._profiles);
        profiles[id] = {
            id: id,
            label: descriptor.label ? String(descriptor.label) : id,
            claims: Array.isArray(descriptor.claims) ? descriptor.claims : [],
            snapshot: Array.isArray(descriptor.snapshot) ? descriptor.snapshot : StateSnapshot.allParts,
            onLoad: descriptor.onLoad ?? null,
            onApply: descriptor.onApply ?? null,
            onExit: descriptor.onExit ?? null,
            onRestore: descriptor.onRestore ?? null,
            gracefulStop: descriptor.gracefulStop ?? null
        };
        root._profiles = profiles;

        if (!root._states[id])
            root._setState(id, { phase: "idle", trigger: "", reason: "", anomalies: [], waitingOn: [], awaitingSnapshot: false, awaitingRestore: false });

        root.profileRegistered(id);
        return true;
    }

    function unregister(id: string): void {
        if (!root._profiles[id])
            return;
        if (root.isActive(id))
            root.deactivate(id, "unregistered");

        const profiles = Object.assign({}, root._profiles);
        delete profiles[id];
        root._profiles = profiles;

        const states = Object.assign({}, root._states);
        delete states[id];
        root._states = states;
        StateSnapshot.discard(id);

        root.profileUnregistered(id);
    }

    function isRegistered(id: string): bool {
        return !!root._profiles[id];
    }

    function isActive(id: string): bool {
        return root.phaseOf(id) !== "idle";
    }

    function phaseOf(id: string): string {
        return root._states[id]?.phase ?? "idle";
    }

    function stateOf(id: string): var {
        return root._states[id] ?? null;
    }

    function canSuspend(id: string): bool {
        return typeof root._profiles[id]?.gracefulStop === "function";
    }

    function activate(id: string, trigger: string): bool {
        const profile = root._profiles[id];
        if (!profile) {
            console.warn(`ProfileEngine: activate for unregistered profile '${id}'`);
            return false;
        }
        if (root.isActive(id))
            return false;

        root._patchState(id, { trigger: trigger ?? "", reason: "", anomalies: [], waitingOn: [], awaitingSnapshot: false, awaitingRestore: false });

        if (!root._transition(id, "detect"))
            return false;
        if (!root._transition(id, "load"))
            return false;
        root._invoke(id, "onLoad");

        if (!root._transition(id, "negotiate"))
            return false;

        const waiting = [];
        for (const claim of profile.claims) {
            const negotiation = ResourceEngine.register(Object.assign({}, claim, { owner: id }));
            if (negotiation)
                waiting.push(negotiation.id);
        }

        if (waiting.length > 0) {
            root._patchState(id, { waitingOn: waiting });
            return true;
        }
        return root._enterApply(id);
    }

    function deactivate(id: string, reason: string): bool {
        if (!root.isActive(id))
            return false;

        root._patchState(id, { reason: reason ?? "", waitingOn: [] });

        if (!root._transition(id, "exit"))
            return false;
        root._invoke(id, "onExit");
        ResourceEngine.releaseOwner(id);

        if (!root._transition(id, "restore"))
            return false;

        // Parks in RESTORE until the rollback has actually been issued --
        // going idle first would report a profile as fully restored while
        // its monitor read was still in flight.
        root._patchState(id, { awaitingRestore: true });
        if (!StateSnapshot.restore(id))
            return root._finishRestore(id);
        return true;
    }

    // Guarded because StateSnapshot's synchronous path emits restored()
    // from inside restore(), so the Connections below can reach here before
    // the caller does.
    function _finishRestore(id: string): bool {
        if (!root._states[id]?.awaitingRestore)
            return root.phaseOf(id) === "idle";
        root._patchState(id, { awaitingRestore: false });
        root._invoke(id, "onRestore");
        return root._transition(id, "idle");
    }

    // Valid only from MONITOR. Records and surfaces; changes nothing else.
    function reportAnomaly(id: string, anomaly: var): bool {
        if (root.phaseOf(id) !== "monitor") {
            console.warn(`ProfileEngine: anomaly for '${id}' ignored in phase '${root.phaseOf(id)}'`);
            return false;
        }
        const entry = {
            at: Date.now(),
            kind: anomaly?.kind ? String(anomaly.kind) : "unspecified",
            detail: anomaly?.detail ? String(anomaly.detail) : ""
        };
        const anomalies = (root._states[id]?.anomalies ?? []).concat([entry]);
        root._patchState(id, { anomalies: anomalies });

        if (!root._transition(id, "anomaly"))
            return false;
        root.anomalySurfaced(id, entry);
        return true;
    }

    function acknowledgeAnomaly(id: string): bool {
        if (root.phaseOf(id) !== "anomaly")
            return false;
        if (!root._transition(id, "monitor"))
            return false;
        root.anomalyAcknowledged(id);
        return true;
    }

    function requestSuspend(owner: string, claim: var): void {
        const hook = root._profiles[owner]?.gracefulStop;
        if (typeof hook !== "function") {
            console.warn(`ResourceEngine: '${owner}' has no graceful-stop hook, nothing suspended`);
            return;
        }
        hook(claim);
    }

    // APPLY is where the profile is allowed to change desktop state, so the
    // snapshot has to be finished before onApply runs -- otherwise a
    // profile that reconfigures a monitor gets its own post-change geometry
    // recorded as the thing to restore to. StateSnapshot's monitors part is
    // asynchronous (see its header), so this parks until captured().
    function _enterApply(id: string): bool {
        const profile = root._profiles[id];
        if (!root._transition(id, "apply"))
            return false;

        root._patchState(id, { awaitingSnapshot: true });
        if (StateSnapshot.capture(id, profile.snapshot).complete)
            return root._finishApply(id);
        return true;
    }

    function _finishApply(id: string): bool {
        if (!root._states[id]?.awaitingSnapshot)
            return root.phaseOf(id) === "monitor";
        root._patchState(id, { awaitingSnapshot: false });
        root._invoke(id, "onApply");
        return root._transition(id, "monitor");
    }

    function _invoke(id: string, hookName: string): void {
        const hook = root._profiles[id]?.[hookName];
        if (typeof hook !== "function")
            return;
        try {
            hook();
        } catch (e) {
            console.warn(`ProfileEngine: '${id}' ${hookName} threw: ${e}`);
        }
    }

    function _transition(id: string, to: string): bool {
        const from = root.phaseOf(id);
        if (from === to)
            return true;
        if (!(root._allowed[from] ?? []).includes(to)) {
            console.warn(`ProfileEngine: '${id}' cannot go ${from} -> ${to}`);
            return false;
        }
        root._patchState(id, { phase: to, since: Date.now() });
        root.phaseChanged(id, from, to);
        return true;
    }

    function _setState(id: string, state: var): void {
        const states = Object.assign({}, root._states);
        states[id] = state;
        root._states = states;
    }

    function _patchState(id: string, patch: var): void {
        const states = Object.assign({}, root._states);
        states[id] = Object.assign({}, states[id] ?? { phase: "idle", anomalies: [], waitingOn: [] }, patch);
        root._states = states;
    }

    Connections {
        target: StateSnapshot

        function onCaptured(profileId: string, parts: var): void {
            if (root._states[profileId]?.awaitingSnapshot && root.phaseOf(profileId) === "apply")
                root._finishApply(profileId);
        }

        function onRestored(profileId: string, applied: var): void {
            if (root._states[profileId]?.awaitingRestore && root.phaseOf(profileId) === "restore")
                root._finishRestore(profileId);
        }
    }

    Connections {
        target: ResourceEngine

        function onSuspendRequested(owner: string, claim: var): void {
            root.requestSuspend(owner, claim);
        }

        // A profile parked in NEGOTIATE proceeds to APPLY once every
        // conflict its own claims raised has an answer -- including
        // "keep"/"ignore", which are answers, not blocks. Nothing is
        // suspended on its behalf here; that only ever happens through
        // the suspend decision above, against the claim's own owner.
        function onNegotiationResolved(negotiation: var, decision: string): void {
            for (const id of Object.keys(root._states)) {
                const waiting = root._states[id].waitingOn ?? [];
                if (!waiting.includes(negotiation.id))
                    continue;
                const remaining = waiting.filter(n => n !== negotiation.id);
                root._patchState(id, { waitingOn: remaining });
                if (remaining.length === 0 && root.phaseOf(id) === "negotiate")
                    root._enterApply(id);
            }
        }
    }
}
