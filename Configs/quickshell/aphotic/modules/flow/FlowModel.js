function number(value) {
    return typeof value === 'number' && isFinite(value) ? value : 0;
}

function amount(value, unit) {
    return Math.round(number(value) * 10) / 10 + (unit ? ' ' + unit : '');
}

// One row per plane, and the only place a domain's own vocabulary lives.
// `layer` is an InstallProfile gate, `owners` are ProfileEngine/
// ResourceEngine ids, never plugin ids: the gaming profile ships as a
// plugin and still registers under the `gaming` owner the engine knows.
var PLANES = [
    {key:'ai', label:'AI', layer:'ai', owners:['ai','ollama'], focus:'gpu-vram', focusLabel:'resident',
     verb:'Runtime', idle:'No resident model claims', absent:'No model runtime registered'},
    {key:'gaming', label:'Gaming', layer:'gaming', owners:['gaming'], focus:'gpu-vram', focusLabel:'reserved',
     verb:'Session', idle:'No game session detected', absent:'Gaming profile plugin not installed'},
    {key:'security', label:'Security', layer:'security', owners:['security'], focus:'memory', focusLabel:'engaged',
     verb:'Engagement', idle:'No engagement in progress', absent:'Security profile not registered'},
    {key:'dev', label:'Dev', layer:'dev', owners:['dev'], focus:'cpu', focusLabel:'reserved',
     verb:'Project', idle:'No project session open', absent:'Dev profile not registered'}
];

function resourceNodes(claims, specs) {
    const names = {cpu:'CPU', gpu:'GPU', 'gpu-vram':'VRAM', memory:'Memory'};
    const keys = Array.from(new Set(Object.keys(names).concat(Object.keys(specs), claims.map(c => c.resource))));
    return keys.map(key => {
        const spec = specs[key];
        const held = claims.filter(c => c.resource === key).map(c => Object.assign({}, c, {unit:spec ? spec.unit || '' : ''}));
        const total = held.reduce((sum, c) => sum + number(c.amount), 0);
        const budget = spec && number(spec.capacity) > 0 ? spec.capacity * (1 - number(spec.safetyMargin)) : null;
        const contended = !!spec && (spec.exclusive ? held.length > 1 : budget !== null && total > budget && held.length > 1);
        const unit = spec ? spec.unit || '' : '';
        return {key:key, label:spec && spec.label || names[key] || key, claims:held,
            total:total, budget:budget, unit:unit, contended:contended,
            summary:held.length ? amount(total, unit) + ' claimed' : 'No claims',
            detail:spec ? (spec.exclusive ? 'Exclusive resource' : budget === null ? 'Capacity unavailable' : 'Budget ' + amount(budget,unit) + ' · capacity ' + amount(spec.capacity,unit)) : 'Capacity undeclared · not arbitrated'};
    });
}

function planeNode(desc, claims, specs, states, profiles, layers, passports) {
    const installed = layers[desc.layer] !== false;
    const owned = claims.filter(c => desc.owners.indexOf(c.owner) >= 0)
        .map(c => Object.assign({}, c, {unit:specs[c.resource] ? specs[c.resource].unit || '' : ''}));
    const activeId = desc.owners.find(id => states[id] && states[id].phase !== 'idle');
    const state = activeId ? states[activeId] : null;
    const registered = desc.owners.some(id => profiles[id]);
    const phase = !installed ? 'not installed'
        : state ? state.phase
        : owned.length ? 'claims active'
        : registered ? 'idle' : 'unregistered';
    const work = (passports || []).filter(p => p.plane === desc.key);
    const focusHeld = owned.filter(c => c.resource === desc.focus);
    const focusSpec = specs[desc.focus];
    const focusCopy = focusHeld.length
        ? ' · ' + amount(focusHeld.reduce((sum, c) => sum + number(c.amount), 0), focusSpec ? focusSpec.unit || '' : '') + ' ' + desc.focusLabel
        : '';
    const workCopy = work.length ? '\n' + workSummary(work) : '';
    const detail = !installed ? desc.layer + ' layer not installed on this system'
        : state ? desc.verb + ': ' + (state.trigger || 'unspecified') + focusCopy + (state.reason ? '\nReason: ' + state.reason : '') + workCopy
        : owned.length ? owned.length + (owned.length === 1 ? ' claim held' : ' claims held') + focusCopy + workCopy
        : work.length ? workSummary(work)
        : registered ? desc.idle : desc.absent;
    return {key:desc.key, label:desc.label, layer:desc.layer, owners:desc.owners,
        installed:installed, registered:registered, phase:phase, detail:detail, claims:owned,
        work:work, stale:work.some(w => w.stale),
        active:installed && (!!state || owned.length > 0 || work.length > 0),
        summary:installed ? owned.length + (owned.length === 1 ? ' claim · ' : ' claims · ') + phase : 'Layer not installed'};
}

function planeNodes(claims, specs, states, profiles, layers, passports) {
    return PLANES.map(desc => planeNode(desc, claims, specs, states, profiles, layers, passports));
}

// The value the view compares before repainting the map or replaying the
// pulse. Metric ticks and palette changes rebuild `flow` without changing
// anything drawn, and a settled map must not redraw on those.
function signature(claims, resources, planes, passports, receipts) {
    return claims.map(c => c.id + ':' + c.owner + ':' + c.resource + ':' + number(c.amount) + ':' + c.priority).sort().join('|')
        + '#' + planes.map(p => p.key + '=' + p.phase).join('|')
        + '#' + resources.filter(r => r.contended).map(r => r.key).join('|')
        + '#' + (passports || []).map(p => p.token + '=' + p.status).sort().join('|')
        + '#' + (receipts || []).map(r => r.id + '=' + r.status).sort().join('|');
}

function summarize(claims, specs, states, profiles, layers, passports, receipts) {
    claims = claims || [];
    specs = specs || {};
    passports = passports || [];
    receipts = receipts || [];
    const resources = resourceNodes(claims, specs);
    const planes = planeNodes(claims, specs, states || {}, profiles || {}, layers || {}, passports);
    return {planes:planes, claimCount:claims.length,
        contentionCount:resources.filter(r => r.contended).length,
        activePlanes:planes.filter(p => p.active).length,
        workloadCount:passports.length,
        staleCount:passports.filter(p => p.status === 'stale').length,
        pendingActions:receipts.filter(r => r.status === 'requested').length};
}

function build(claims, specs, states, profiles, layers, passports, receipts) {
    claims = claims || [];
    specs = specs || {};
    states = states || {};
    profiles = profiles || {};
    layers = layers || {};
    passports = passports || [];
    receipts = receipts || [];
    const resources = resourceNodes(claims, specs);
    const owners = Array.from(new Set(claims.map(c => c.owner)
        .concat(Object.keys(states).filter(k => states[k].phase !== 'idle'))
        .concat(passports.map(p => p.owner))));
    const workloads = owners.map(key => {
        const held = claims.filter(c => c.owner === key).map(c => Object.assign({}, c, {unit:specs[c.resource] ? specs[c.resource].unit || '' : ''}));
        const state = states[key];
        const foreground = held.some(c => c.priority === 'foreground');
        const plane = PLANES.find(p => p.owners.indexOf(key) >= 0);
        const work = workFor(passports, key);
        const owned = receiptsFor(receipts, key);
        const workCopy = work.length ? '\n' + workSummary(work) : '';
        const receiptCopy = owned.length ? '\nActions: ' + receiptSummary(owned) : '';
        return {key:key, label:profiles[key] && profiles[key].label || key, claims:held, foreground:foreground,
            plane:plane ? plane.key : '',
            work:work, receipts:owned, stale:work.some(w => w.stale),
            phase:state ? state.phase : work.length ? 'reported' : 'claimant',
            detail:(plane ? plane.label + ' plane\n' : '') + (state ? 'Trigger: ' + (state.trigger || 'unspecified') + '\nPhase: ' + state.phase + (state.reason ? '\nReason: ' + state.reason : '') : work.length ? 'Reported by its owner' : 'Measured claimant · no registered profile lifecycle') + workCopy + receiptCopy,
            summary:(foreground ? 'Foreground' : 'Background') + ' · ' + held.length + ' claims' + (work.length ? ' · ' + work.length + ' work' : '')};
    }).sort((a,b) => Number(b.foreground)-Number(a.foreground) || a.key.localeCompare(b.key));
    const shownResources = resources.slice().sort((a,b) => Number(b.contended)-Number(a.contended) || Number(b.claims.length>0)-Number(a.claims.length>0)).slice(0,6);
    const shownWorkloads = workloads.slice(0,8);
    const edges = [];
    shownResources.forEach((r, ri) => shownWorkloads.forEach((w, wi) => {
        if (w.claims.some(c => c.resource === r.key))
            edges.push({resource:ri, workload:wi, contended:r.contended, foreground:w.foreground});
    }));
    const planes = planeNodes(claims, specs, states, profiles, layers, passports);
    return {resources:shownResources, workloads:shownWorkloads, edges:edges.slice(0,24), planes:planes,
        workloadCount:passports.length, staleCount:passports.filter(p => p.status === 'stale').length,
        pendingActions:receipts.filter(r => r.status === 'requested').length, receipts:receipts,
        hiddenResources:resources.length-shownResources.length, hiddenWorkloads:workloads.length-shownWorkloads.length,
        hiddenEdges:Math.max(0,edges.length-24), claimCount:claims.length,
        contentionCount:resources.filter(r=>r.contended).length,
        signature:signature(claims, resources, planes, passports, receipts)};
}

// --- workload passports -------------------------------------------------
// A passport says what an owner is running. A claim says what it holds.
// They are joined by owner, and a passport never invents a claim: work the
// owner reported with no measured amount shows as work, not as capacity.

function workFor(passports, owner) {
    return (passports || []).filter(p => p.owner === owner).map(p => ({
        token: p.token, label: p.label, trigger: p.trigger, status: p.status,
        stale: p.status === 'stale',
        claims: p.claims || [],
        detail: p.trigger + (p.status === 'stale' ? ' · source went quiet' : '')
    }));
}

function workSummary(work) {
    if (!work.length)
        return '';
    const stale = work.filter(w => w.stale).length;
    return work.length + (work.length === 1 ? ' workload' : ' workloads')
        + (stale ? ' · ' + stale + ' stale' : '');
}

// --- action receipts ----------------------------------------------------
// Requested and applied are different facts. The lens shows both, in the
// order they happened, and never promotes one to the other.

function clock(ms) {
    if (!number(ms))
        return '';
    const d = new Date(ms);
    return ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2);
}

var RECEIPT_VERBS = {requested:'Requested', applied:'Applied', failed:'Failed',
    restored:'Restored', 'restore-failed':'Restore failed'};

function receiptLabel(r) {
    if (!r)
        return '';
    const when = clock(r.status === 'requested' ? r.requestedAt : r.completedAt);
    const verb = r.preserved && r.status === 'restored' ? 'Left as the user set it' : RECEIPT_VERBS[r.status] || r.status;
    return verb + (when ? ' at ' + when : '');
}

function receiptsFor(receipts, owner) {
    return (receipts || []).filter(r => r.profileId === owner)
        .map(r => Object.assign({}, r, {statusLabel:receiptLabel(r)}));
}

function receiptSummary(list) {
    if (!list.length)
        return '';
    const pending = list.filter(r => r.status === 'requested').length;
    const failed = list.filter(r => r.status === 'failed' || r.status === 'restore-failed').length;
    const parts = [];
    if (pending)
        parts.push(pending + ' pending');
    if (failed)
        parts.push(failed + ' failed');
    return parts.length ? parts.join(' · ') : list.length + ' settled';
}

// --- contention preview -------------------------------------------------
// What the user is about to be asked about, stated before they answer it.
// Every number here is declared budget and existing claim arithmetic. No
// scheduler, renice or cgroup call happens at any point.

function projection(negotiation, claims) {
    if (!negotiation)
        return null;
    const owner = negotiation.claimant ? negotiation.claimant.owner : '';
    const reclaimable = (claims || [])
        .filter(c => c.owner === owner && c.resource === negotiation.resource)
        .reduce((sum, c) => sum + number(c.amount), 0);
    const unit = negotiation.unit || '';
    const budget = number(negotiation.budget);
    const after = number(negotiation.total) - reclaimable;
    return {
        projection: true,
        owner: owner,
        resource: negotiation.resource,
        budget: amount(budget, unit),
        requested: amount(negotiation.requestor ? negotiation.requestor.amount : 0, unit),
        held: amount(negotiation.total, unit),
        reclaimable: amount(reclaimable, unit),
        after: amount(after, unit),
        fits: after <= budget,
        supported: !!negotiation.claimantSuspendable,
        note: negotiation.claimantSuspendable
            ? 'Projection from declared budgets. Nothing changes until you choose.'
            : 'This owner has no graceful stop, so that action stays unavailable.'
    };
}
