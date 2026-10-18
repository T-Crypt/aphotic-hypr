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

// Several processes of one harness can each report the same event, so a
// session's feed arrives with every line repeated a handful of times
// within a few milliseconds. Repeats would count tokens more than once.
function dedupKey(event) {
    return JSON.stringify([event.event, event.status ?? "", event.toolStatus ?? "", event.toolId ?? "", event.tool ?? "", event.agentId ?? "", event.inputTokens ?? "", event.outputTokens ?? ""]);
}

function isRepeat(last, event, windowMs) {
    const key = dedupKey(event);
    const at = event.t ?? 0;
    const prior = last[event.sessionId];
    return { repeat: !!prior && prior.key === key && Math.abs(at - prior.at) <= windowMs, key: key, at: at };
}

function isBusy(session, now, holdMs) {
    if (session.status === "running" || session.status === "compacting")
        return true;
    return session.status === "idle" && (session.lastBusyAt ?? 0) > 0 && now - session.lastBusyAt < holdMs;
}

// The session a one-line readout headlines. Waiting beats everything; the
// current pick is kept while it is still busy, so two agents working at
// once do not trade places on every event; a short idle between steps
// still counts as busy.
function pickActive(sessions, currentId, now, holdMs) {
    const live = sessions.filter(s => s.status !== "ended");
    if (live.length === 0)
        return "";
    const newest = (list, field) => list.reduce((best, s) => (s[field] ?? 0) > (best[field] ?? 0) ? s : best, list[0]);
    const current = live.find(s => s.id === currentId) ?? null;
    const waiting = live.filter(s => s.status === "waiting");
    if (waiting.length > 0)
        return current && current.status === "waiting" ? current.id : newest(waiting, "statusSince").id;
    if (current && isBusy(current, now, holdMs))
        return current.id;
    const busy = live.filter(s => isBusy(s, now, holdMs));
    if (busy.length > 0)
        return newest(busy, "busySince").id;
    if (current)
        return current.id;
    return newest(live, "updatedAt").id;
}
