function eligibleClaims(claims, backends) {
    const owners = Object.keys(backends || {});
    return (claims || []).filter(claim => claim
        && owners.includes(claim.owner)
        && Number(claim.amount || 0) >= 2048);
}

function eligibilityKeys(models, claims, backends) {
    const active = (models || []).filter(model => model?.owner && model?.name)
        .map(model => `${model.owner}:${model.name}`);
    return active.concat(eligibleClaims(claims, backends).map(claim => `${claim.owner}:${claim.id}`));
}

function claimSignature(claims, backends) {
    return eligibleClaims(claims, backends)
        .map(claim => `${claim.owner}:${claim.id}`)
        .sort().join("|");
}

function activeSignature(models) {
    return (models || []).map(model => `${model.owner}:${model.name}`).sort().join("|");
}

function _modelName(value) {
    const suffix = " (system RAM)";
    const text = String(value || "");
    return text.endsWith(suffix) ? text.slice(0, -suffix.length) : text;
}

function _claimAmount(model, claims, passports) {
    let largest = 0;
    for (const claim of (claims || [])) {
        if (claim?.owner !== model.owner)
            continue;
        if (_modelName(claim.id) !== model.name && _modelName(claim.label) !== model.name)
            continue;
        largest = Math.max(largest, Number(claim.amount || 0));
    }
    for (const passport of (passports || [])) {
        if (passport?.owner !== model.owner || _modelName(passport.label) !== model.name)
            continue;
        for (const claim of (passport.claims || []))
            largest = Math.max(largest, Number(claim?.amount || 0));
    }
    return largest;
}

function selectActiveModel(models, claims, passports) {
    const active = (models || []).filter(model => model?.owner && model?.name);
    if (active.length === 0)
        return null;
    let selected = active[0];
    let largest = _claimAmount(selected, claims, passports);
    for (let i = 1; i < active.length; i++) {
        const amount = _claimAmount(active[i], claims, passports);
        if (amount > largest) {
            selected = active[i];
            largest = amount;
        }
    }
    return selected;
}

function acceptStatsModel(current, candidate, generating) {
    return generating || (!!current && current === candidate);
}

function decoded(slot) {
    const values = (slot?.next_token || []).map(token => Number(token?.n_decoded || 0));
    return values.length > 0 ? Math.max.apply(null, values) : 0;
}

function updateStats(samples, name, slots, now) {
    const list = Array.isArray(slots) ? slots : [];
    const processing = list.filter(slot => slot?.is_processing);
    const source = (processing.length > 0 ? processing : list).slice()
        .sort((a, b) => decoded(b) - decoded(a))[0] || null;
    const previous = samples?.[name] || null;
    const nDecoded = decoded(source);
    const generating = processing.length > 0;
    let tokensPerSecond = Number(previous?.tokensPerSecond || 0);

    if (generating && previous?.generating && now > previous.at && nDecoded >= previous.nDecoded)
        tokensPerSecond = (nDecoded - previous.nDecoded) / ((now - previous.at) / 1000);

    const current = {
        generating: generating,
        tokensPerSecond: tokensPerSecond,
        nDecoded: nDecoded,
        nCtx: Number(source?.n_ctx || 0),
        at: now,
    };
    const next = Object.assign({}, samples || {});
    next[name] = current;
    return { samples: next, current: current };
}
