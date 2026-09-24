.pragma library

function rankResults(results, query) {
    const needle = String(query || "").trim().toLowerCase();
    if (needle.length === 0)
        return (results || []).slice();

    return (results || []).map((result, index) => ({ result, index })).sort((left, right) => {
        const group = _group(left.result, needle) - _group(right.result, needle);
        if (group !== 0)
            return group;
        const match = _match(left.result, needle) - _match(right.result, needle);
        return match !== 0 ? match : left.index - right.index;
    }).map(entry => entry.result);
}

function _group(result, needle) {
    const name = String(result.name || "").toLowerCase();
    if (name === needle)
        return 0;
    return String(result.repo || "").toLowerCase() === "aur" ? 2 : 1;
}

function _match(result, needle) {
    const name = String(result.name || "").toLowerCase();
    if (name.indexOf(needle) === 0)
        return 0;
    if (name.indexOf(needle) !== -1)
        return 1;
    return String(result.description || "").toLowerCase().indexOf(needle) !== -1 ? 2 : 3;
}
