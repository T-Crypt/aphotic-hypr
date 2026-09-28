function hold(holders, owner, want, tailing) {
    if (!owner)
        return null;
    const held = Object.prototype.hasOwnProperty.call(holders, owner);
    if (want === held)
        return null;
    const next = Object.assign({}, holders);
    if (want)
        next[owner] = true;
    else
        delete next[owner];
    return { holders: next, replay: want && tailing };
}

function appendBacklog(backlog, event, cap) {
    const next = backlog.concat([event]);
    return next.length > cap ? next.slice(next.length - cap) : next;
}
