function number(value) {
    return typeof value === 'number' && isFinite(value) ? value : 0;
}

function amount(value, unit) {
    return Math.round(number(value) * 10) / 10 + (unit ? ' ' + unit : '');
}

function build(claims, specs, states, profiles) {
    claims = claims || [];
    specs = specs || {};
    states = states || {};
    profiles = profiles || {};
    const names = {cpu:'CPU', gpu:'GPU', 'gpu-vram':'VRAM', memory:'Memory'};
    const keys = Array.from(new Set(Object.keys(names).concat(Object.keys(specs), claims.map(c => c.resource))));
    const resources = keys.map(key => {
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
    const owners = Array.from(new Set(claims.map(c => c.owner).concat(Object.keys(states).filter(k => states[k].phase !== 'idle'))));
    const workloads = owners.map(key => {
        const held = claims.filter(c => c.owner === key).map(c => Object.assign({}, c, {unit:specs[c.resource] ? specs[c.resource].unit || '' : ''}));
        const state = states[key];
        const foreground = held.some(c => c.priority === 'foreground');
        return {key:key, label:profiles[key] && profiles[key].label || key, claims:held, foreground:foreground,
            phase:state ? state.phase : 'claimant',
            detail:state ? 'Trigger: ' + (state.trigger || 'unspecified') + '\nPhase: ' + state.phase + (state.reason ? '\nReason: ' + state.reason : '') : 'Measured claimant · no registered profile lifecycle',
            summary:(foreground ? 'Foreground' : 'Background') + ' · ' + held.length + ' claims'};
    }).sort((a,b) => Number(b.foreground)-Number(a.foreground) || a.key.localeCompare(b.key));
    const shownResources = resources.slice().sort((a,b) => Number(b.contended)-Number(a.contended) || Number(b.claims.length>0)-Number(a.claims.length>0)).slice(0,6);
    const shownWorkloads = workloads.slice(0,8);
    const edges = [];
    shownResources.forEach((r, ri) => shownWorkloads.forEach((w, wi) => {
        if (w.claims.some(c => c.resource === r.key))
            edges.push({resource:ri, workload:wi, contended:r.contended, foreground:w.foreground});
    }));
    const planes = ['ai','gaming','security','dev'].map(key => {
        const owners = key === 'ai' ? ['ai','ollama'] : [key];
        const active = owners.find(id => states[id] && states[id].phase !== 'idle');
        const hasClaims = claims.some(c => owners.indexOf(c.owner) >= 0);
        return {key:key, label:({ai:'AI',gaming:'Gaming',security:'Security',dev:'Dev'})[key],
            phase:active ? states[active].phase : hasClaims ? 'claims active' : owners.some(id => profiles[id]) ? 'idle' : 'unregistered'};
    });
    return {resources:shownResources, workloads:shownWorkloads, edges:edges.slice(0,24), planes:planes,
        hiddenResources:resources.length-shownResources.length, hiddenWorkloads:workloads.length-shownWorkloads.length,
        hiddenEdges:Math.max(0,edges.length-24), claimCount:claims.length,
        contentionCount:resources.filter(r=>r.contended).length};
}
