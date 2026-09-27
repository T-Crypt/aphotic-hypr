// The Resource Engine's state reduced to one ambient answer: how much
// does the machine need the user's attention right now, and about what.
// Plain functions so tests/test_resource_posture.cjs runs them under node;
// ResourcePosture.qml is the reactive wrapper the shell reads.
//
// Levels, least to most:
//   quiet        nothing worth showing
//   settling     a negotiation was just answered; the shell is calming down
//   pressure     a declared resource is near its budget
//   contention   a declared resource is over budget or double-held
//   negotiating  the engine is asking the user to decide
//
// Only declared resources are judged, for the same reason the engine only
// arbitrates declared ones: without a capacity there is nothing to be near.

var LEVELS = ['quiet', 'settling', 'pressure', 'contention', 'negotiating'];

// Share of the budget (capacity minus safety margin) at which a resource
// counts as under pressure.
var PRESSURE_RATIO = 0.85;

function num(v) {
    return typeof v === 'number' && isFinite(v) ? v : 0;
}

function severity(level) {
    var i = LEVELS.indexOf(level);
    return i < 0 ? 0 : i;
}

function atLeast(level, threshold) {
    return severity(level) >= severity(threshold);
}

// Owners holding the resource, largest first, merged per owner.
function owners(held) {
    var by = {};
    held.forEach(function (c) {
        by[c.owner] = (by[c.owner] || 0) + num(c.amount);
    });
    return Object.keys(by).sort(function (a, b) { return by[b] - by[a]; })
        .map(function (o) { return {owner: o, amount: by[o]}; });
}

function resourceState(key, spec, claims) {
    var held = claims.filter(function (c) { return c.resource === key; });
    var total = held.reduce(function (s, c) { return s + num(c.amount); }, 0);
    var budget = num(spec.capacity) > 0 ? spec.capacity * (1 - num(spec.safetyMargin)) : null;
    // What the hardware reports can run ahead of what workloads claimed
    // (anything unclaimed is still using the card), so pressure reads the
    // larger of the two. Contention stays a statement about claims.
    var measured = spec.measured && typeof spec.measured.used === 'number' ? spec.measured.used : 0;
    var used = Math.max(total, measured);
    var ratio = budget ? used / budget : (spec.exclusive && held.length ? 1 : 0);
    var contended = spec.exclusive ? held.length > 1 : (budget !== null && total > budget && held.length > 1);
    var level = contended ? 'contention' : (budget !== null && ratio >= PRESSURE_RATIO ? 'pressure' : 'quiet');
    return {key: key, label: spec.label || key, unit: spec.unit || '', level: level,
        ratio: Math.round(ratio * 1000) / 1000, used: used, total: total, budget: budget,
        owners: owners(held)};
}

function raise(state, level) {
    if (severity(level) > severity(state.level))
        state.level = level;
}

// claims/specs: ResourceEngine.claims/resources. pending/overBudget: the
// engine's properties of the same name. settling: whether a resolution
// is still inside its settle window (the wrapper owns that clock).
function assess(claims, specs, pending, overBudget, settling) {
    claims = claims || [];
    specs = specs || {};
    var resources = Object.keys(specs).map(function (key) {
        return resourceState(key, specs[key], claims);
    });
    resources.forEach(function (r) {
        if (overBudget && overBudget.resource === r.key)
            raise(r, 'contention');
        if (pending && pending.resource === r.key)
            raise(r, 'negotiating');
    });
    var active = resources.filter(function (r) { return r.level !== 'quiet'; })
        .sort(function (a, b) {
            return severity(b.level) - severity(a.level) || b.ratio - a.ratio;
        });
    var top = active[0] || null;
    var level = top ? top.level : (settling ? 'settling' : 'quiet');
    return {level: level, resource: top, resources: active,
        negotiation: pending ? {id: pending.id, resource: pending.resource,
            claimant: pending.claimant ? pending.claimant.owner : '',
            requestor: pending.requestor ? pending.requestor.owner : ''} : null};
}

// One line for a tooltip, a notch chip or a CLI. Empty when quiet.
function headline(state) {
    if (!state || state.level === 'quiet')
        return '';
    if (state.level === 'settling')
        return 'Resources settled';
    var r = state.resource;
    if (!r)
        return '';
    if (state.level === 'negotiating' && state.negotiation)
        return r.label + ': ' + state.negotiation.requestor + ' vs ' + state.negotiation.claimant;
    if (state.level === 'contention')
        return r.label + ' contended' + (r.owners.length ? ' · ' + r.owners.slice(0, 2).map(function (o) { return o.owner; }).join(', ') : '');
    return r.label + ' ' + Math.round(r.ratio * 100) + '% of budget';
}
