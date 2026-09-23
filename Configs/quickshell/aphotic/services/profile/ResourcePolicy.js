function incumbent(claims, canSuspend) {
    const candidates = (claims || []).filter(claim => canSuspend(claim.owner));
    if (candidates.length === 0)
        return (claims || []).slice().sort((a, b) => b.amount - a.amount)[0] || null;

    return candidates.slice().sort((a, b) => {
        if (a.priority !== b.priority)
            return a.priority === "background" ? -1 : 1;
        return b.amount - a.amount;
    })[0] || null;
}
