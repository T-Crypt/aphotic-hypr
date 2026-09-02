pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services.profile

// Cross-domain claim arbitration (docs/archive/OPT-IN-FEATURES.md section
// 2). Tracks *claims*, never continuous usage: every state change here is
// driven by a register/release call, so this singleton owns no timer, no
// process and no file watch, and does exactly nothing until a profile
// registers something. `dormant` is that guarantee made observable.
//
// Three boundaries this file must never cross, in order of importance:
//   1. It never terminates anything. The only stop path is
//      suspendRequested -> the owning profile's own gracefulStop hook
//      (ProfileEngine.requestSuspend), and a claim stays registered until
//      that owner releases it, so the claim table keeps telling the truth
//      even if the owner's stop is slow or declines.
//   2. It never touches kernel/sysctl, and never probes hardware. Capacity
//      is *declared* by whoever knows how to measure it, via
//      declareResource(); an undeclared resource is tracked but never
//      arbitrated. Core declares no resources at all, which is why a base
//      install can never raise a negotiation.
//   3. It never resolves a conflict on its own. Contention only ever
//      produces a negotiation the user answers.
Singleton {
    id: root

    readonly property var claims: root._claims
    readonly property var resources: root._resources

    // Head of the negotiation queue -- the one the prompt is showing.
    // Queued rather than concurrent so two simultaneous conflicts can't
    // stack two modal prompts on top of each other.
    readonly property var pending: root._queue.length > 0 ? root._queue[0] : null
    readonly property int pendingCount: root._queue.length

    readonly property bool dormant: root._claims.length === 0 && root._queue.length === 0

    readonly property real defaultSafetyMargin: 0.1

    signal claimRegistered(claim: var)
    signal claimReleased(claim: var)
    signal negotiationRaised(negotiation: var)
    signal negotiationResolved(negotiation: var, decision: string)
    signal suspendRequested(owner: string, claim: var)

    property var _claims: []
    property var _resources: ({})
    property var _queue: []
    property var _ignoredPairs: ({})
    property int _nextId: 1

    function declareResource(key: string, spec: var): bool {
        if (!key)
            return false;
        const next = Object.assign({}, root._resources);
        next[key] = {
            key: key,
            label: spec?.label ?? key,
            unit: spec?.unit ?? "",
            capacity: (typeof spec?.capacity === "number" && spec.capacity > 0) ? spec.capacity : 0,
            safetyMargin: (typeof spec?.safetyMargin === "number") ? spec.safetyMargin : root.defaultSafetyMargin,
            exclusive: !!spec?.exclusive
        };
        root._resources = next;
        return true;
    }

    function undeclareResource(key: string): void {
        if (!Object.prototype.hasOwnProperty.call(root._resources, key))
            return;
        const next = Object.assign({}, root._resources);
        delete next[key];
        root._resources = next;
    }

    function resourceSpec(key: string): var {
        return root._resources[key] ?? null;
    }

    // The Phase 1 claim shape. `origin` is the seam that keeps dynamic
    // claims an additive change rather than a breaking one: Phase 1
    // consumers declare their claims in profile config and register them
    // verbatim ("static"), a later runtime-declared claim registers
    // through this same call with origin "dynamic", and nothing else about
    // the struct or the arbitration path differs. register() upserts on
    // id for the same reason -- re-registering an existing id is already
    // the update path a dynamic claim needs.
    function normalizeClaim(input: var): var {
        if (!input || !input.id || !input.owner || !input.resource)
            return null;
        return {
            id: String(input.id),
            owner: String(input.owner),
            resource: String(input.resource),
            amount: (typeof input.amount === "number" && isFinite(input.amount)) ? input.amount : 0,
            priority: input.priority === "foreground" ? "foreground" : "background",
            label: input.label ? String(input.label) : String(input.id),
            origin: input.origin === "dynamic" ? "dynamic" : "static"
        };
    }

    function claimById(id: string): var {
        return root._claims.find(c => c.id === id) ?? null;
    }

    function claimsFor(resource: string): var {
        return root._claims.filter(c => c.resource === resource);
    }

    function claimsOf(owner: string): var {
        return root._claims.filter(c => c.owner === owner);
    }

    // Returns the negotiation this registration raised, or null. A caller
    // that has to wait for an answer (ProfileEngine's NEGOTIATE phase)
    // uses that return value; a caller that doesn't care can ignore it.
    function register(input: var): var {
        const claim = root.normalizeClaim(input);
        if (!claim) {
            console.warn(`ResourceEngine: rejected malformed claim ${JSON.stringify(input)}`);
            return null;
        }

        const next = root._claims.filter(c => c.id !== claim.id);
        next.push(claim);
        root._claims = next;
        root.claimRegistered(claim);

        const contention = root._contentionFor(claim);
        if (!contention)
            return null;
        return root._raise(contention);
    }

    function release(id: string): void {
        const claim = root.claimById(id);
        if (!claim)
            return;
        root._claims = root._claims.filter(c => c.id !== id);
        root._dropNegotiationsInvolving(id);
        root.claimReleased(claim);
    }

    function releaseOwner(owner: string): void {
        for (const claim of root.claimsOf(owner))
            root.release(claim.id);
    }

    // "suspend" -> ask the claimant's owner to stop (never a kill, and
    // never a release from here -- the owner releases when it has actually
    // stopped). "keep" -> both claims stand, this conflict is answered but
    // an identical one can be raised again after the claims change.
    // "ignore" -> like keep, and this owner pair stops asking about this
    // resource for the rest of the session.
    readonly property var decisions: ["suspend", "keep", "ignore"]

    function resolve(decision: string): bool {
        const negotiation = root.pending;
        if (!negotiation)
            return false;
        if (!root.decisions.includes(decision)) {
            console.warn(`ResourceEngine: '${decision}' is not one of ${root.decisions.join("/")}`);
            return false;
        }

        root._queue = root._queue.slice(1);

        if (decision === "ignore") {
            const next = Object.assign({}, root._ignoredPairs);
            next[negotiation.pairKey] = true;
            root._ignoredPairs = next;
        } else if (decision === "suspend") {
            if (negotiation.claimantSuspendable)
                root.suspendRequested(negotiation.claimant.owner, negotiation.claimant);
            else
                console.warn(`ResourceEngine: no graceful-stop hook for '${negotiation.claimant.owner}', suspend declined`);
        }

        root.negotiationResolved(negotiation, decision);
        return true;
    }

    function isIgnored(a: string, b: string, resource: string): bool {
        return !!root._ignoredPairs[root._pairKey(a, b, resource)];
    }

    function clearIgnored(): void {
        root._ignoredPairs = ({});
    }

    function reset(): void {
        root._claims = [];
        root._queue = [];
        root._ignoredPairs = ({});
        root._resources = ({});
    }

    function _pairKey(a: string, b: string, resource: string): string {
        return [a, b].sort().join("|") + "@" + resource;
    }

    // Only ever compares claims on one resource, and only when that
    // resource has been declared -- an undeclared resource has no capacity
    // and no exclusivity to reason about, so treating it as contended
    // would be a guess, and guessing here means prompting the user about
    // nothing.
    function _contentionFor(claim: var): var {
        const spec = root.resourceSpec(claim.resource);
        if (!spec)
            return null;

        const others = root.claimsFor(claim.resource).filter(c => c.id !== claim.id);
        if (others.length === 0)
            return null;

        const claimant = root._incumbent(others);
        if (!claimant)
            return null;

        if (root.isIgnored(claim.owner, claimant.owner, claim.resource))
            return null;

        if (spec.exclusive)
            return root._negotiation(spec, claimant, claim, "exclusive", 0, 0);

        if (spec.capacity <= 0)
            return null;

        const total = root.claimsFor(claim.resource).reduce((sum, c) => sum + c.amount, 0);
        const budget = spec.capacity * (1 - spec.safetyMargin);
        if (total <= budget)
            return null;

        return root._negotiation(spec, claimant, claim, "capacity", total, budget);
    }

    // Whoever the prompt will name: something that can actually stop,
    // ahead of anything that can't. Only claims whose owner has a
    // graceful-stop hook are real candidates, and among those the
    // cheapest to give up goes first (background before foreground, then
    // largest), so the offer is deterministic rather than
    // registration-order luck.
    //
    // When nothing on the resource can stop, the prompt is informational
    // rather than actionable (NegotiationContent disables Suspend and
    // says why), so ranking by "cheapest to give up" stops meaning
    // anything -- and picking the largest *background* claim actively
    // misleads: with a game and a local model both on the GPU, the
    // largest remaining background claim is the shell itself, so a
    // multi-gigabyte overage was being reported against ~225 MB of
    // compositor. Falling back to the largest claim outright names the
    // thing actually holding the memory. It does not make that thing
    // stoppable -- canSuspend still gates the button.
    function _incumbent(others: var): var {
        const stoppable = others.filter(c => ProfileEngine.canSuspend(c.owner));
        if (stoppable.length === 0)
            return others.slice().sort((a, b) => b.amount - a.amount)[0] ?? null;

        return stoppable.sort((a, b) => {
            if (a.priority !== b.priority)
                return a.priority === "background" ? -1 : 1;
            return b.amount - a.amount;
        })[0] ?? null;
    }

    function _negotiation(spec: var, claimant: var, requestor: var, reason: string, total: real, budget: real): var {
        return {
            id: root._nextId,
            resource: spec.key,
            resourceLabel: spec.label,
            unit: spec.unit,
            reason: reason,
            total: total,
            budget: budget,
            claimant: claimant,
            requestor: requestor,
            claimantSuspendable: ProfileEngine.canSuspend(claimant.owner),
            pairKey: root._pairKey(requestor.owner, claimant.owner, spec.key)
        };
    }

    function _raise(negotiation: var): var {
        root._nextId = root._nextId + 1;
        root._queue = root._queue.concat([negotiation]);
        root.negotiationRaised(negotiation);
        return negotiation;
    }

    // A claim going away takes its unanswered conflicts with it -- asking
    // the user to arbitrate between something that has already stopped and
    // something else is worse than not asking at all.
    function _dropNegotiationsInvolving(claimId: string): void {
        const kept = root._queue.filter(n => n.claimant.id !== claimId && n.requestor.id !== claimId);
        if (kept.length === root._queue.length)
            return;
        const dropped = root._queue.filter(n => n.claimant.id === claimId || n.requestor.id === claimId);
        root._queue = kept;
        for (const n of dropped)
            root.negotiationResolved(n, "withdrawn");
    }
}
