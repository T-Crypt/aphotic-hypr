function surfacesFor(registrations, installed, surface, sheltered) {
    return (registrations || []).filter(entry => entry.surface === surface
        && !(sheltered && installed?.[entry.plugin]?.shelter === "unload"));
}

// A surface id is only unique within its plugin, so a failed-surface mark
// is keyed by both. The workspace bind and the plane read their verdicts
// through the two functions below rather than matching ids by hand.
function failedKey(surface) {
    return surface && surface.plugin && surface.id ? `${surface.plugin}:${surface.id}` : "";
}

function surfaceFailed(surface, failedSurfaces) {
    const key = failedKey(surface);
    return key.length > 0 && (failedSurfaces || ({}))[key] === true;
}

// Returns the next mark set. Marking is idempotent and a set already in
// the wanted state is returned unchanged, so a caller assigning the
// result never churns bindings that watch it.
function markFailed(failedSurfaces, surface, failed) {
    const current = failedSurfaces || ({});
    const key = failedKey(surface);
    if (key.length === 0 || (current[key] === true) === failed)
        return current;
    const next = Object.assign({}, current);
    if (failed)
        next[key] = true;
    else
        delete next[key];
    return next;
}
