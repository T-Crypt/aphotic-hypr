function report(backends, owner, label, models, now) {
    if (!owner)
        return Object.assign({}, backends || {});
    const next = Object.assign({}, backends || {});
    next[owner] = {
        label: label || owner,
        models: (models || []).filter(model => model?.name).map(model => ({
            name: String(model.name),
            embedding: model.embedding === true,
            state: String(model.state ?? "")
        })),
        at: now
    };
    return next;
}

function activeModels(backends) {
    const activeStates = ["", "starting", "loading", "ready", "loaded"];
    const active = [];
    for (const owner of Object.keys(backends || {})) {
        const backend = backends[owner] || {};
        for (const model of (backend.models || [])) {
            const state = String(model?.state ?? "").toLowerCase();
            if (!model?.name || model.embedding === true || !activeStates.includes(state))
                continue;
            active.push({ owner: owner, label: backend.label || owner, name: String(model.name) });
        }
    }
    return active;
}
