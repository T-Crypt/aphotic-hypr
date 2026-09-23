function eligibleClaims(claims) {
    return (claims || []).filter(claim => claim
        && claim.owner === "llama-swap"
        && claim.resource === "gpu-vram"
        && Number(claim.amount || 0) >= 2048);
}

// llama-swap lists a model as soon as it starts loading, seconds before its
// VRAM shows up as a measured claim. Embedding models never count.
function runningChatModels(models) {
    return (models || []).filter(model => model?.name
        && !model.embedding
        && (model.state === "starting" || model.state === "ready" || !model.state)).map(model => model.name);
}

function claimSignature(claims) {
    return eligibleClaims(claims).map(claim => String(claim.id)).sort().join("|");
}

function selectModel(models, preferred) {
    const available = (models || []).filter(model => model?.name
        && !model.embedding);
    if (preferred && available.some(model => model.name === preferred))
        return preferred;
    return available[0]?.name || "";
}

function triggeredModels(passports) {
    return (passports || []).filter(passport => (passport?.claims || []).some(claim => claim
        && claim.resource === "gpu-vram"
        && Number(claim.amount || 0) >= 2048)).map(passport => passport.label).filter(Boolean);
}

function selectTriggeredModel(passports, models, preferred) {
    const running = (models || []).filter(model => model?.name
        && !model.embedding).map(model => model.name);
    // Passports close when a model unloads, so they stand on their own;
    // the running list lags a poll behind and is empty until one lands.
    const triggered = triggeredModels(passports).filter(name => running.length === 0 || running.includes(name));
    if (preferred && triggered.includes(preferred))
        return preferred;
    if (triggered.length > 0)
        return triggered[0];
    return selectModel(models, preferred);
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
