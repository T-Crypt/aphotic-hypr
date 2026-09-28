function _text(value, fallback) {
    return typeof value === "string" && value.length > 0 ? value : fallback;
}

// `aphotic vpn list --json` -> providers in the contract shape. Anything
// malformed is dropped, never thrown: a bad adapter must not blank the rest.
function parse(text) {
    let data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return [];
    }
    const list = data && Array.isArray(data.providers) ? data.providers : [];
    return list.filter(p => p && _text(p.id, "") !== "").map(p => {
        const label = _text(p.label, p.id);
        const raw = Array.isArray(p.connections) ? p.connections : [];
        return {
            id: p.id,
            label: label,
            available: p.available === true,
            connections: raw.filter(c => c && _text(c.id, "") !== "").map(c => ({
                provider: p.id,
                providerLabel: label,
                id: c.id,
                name: _text(c.name, c.id),
                active: c.active === true,
                detail: _text(c.detail, "")
            }))
        };
    });
}

function connections(providers) {
    return providers.filter(p => p.available)
        .reduce((all, p) => all.concat(p.connections), []);
}

function active(providers) {
    return connections(providers).filter(c => c.active);
}

function status(providers) {
    const on = active(providers);
    return {
        connected: on.length > 0,
        count: on.length,
        primary: on.length > 0 ? on[0] : null,
        available: providers.some(p => p.available)
    };
}
