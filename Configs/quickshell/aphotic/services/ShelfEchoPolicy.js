// Pure rule for the shelf launch echo, kept out of QML so the timing
// contract is testable without a compositor.
//
// A request is a key plus the moment it was made. It is answerable while
// it is younger than `windowMs`, and answering it consumes it: one launch
// request earns at most one echo, so an app that opens three windows
// does not flash three times.
function answerable(requests, key, now, windowMs) {
    if (!requests || typeof requests !== 'object')
        return false;
    if (typeof key !== 'string' || key.length === 0)
        return false;
    if (typeof windowMs !== 'number' || windowMs <= 0)
        return false;
    var stamp = requests[key];
    if (typeof stamp !== 'number')
        return false;
    var age = now - stamp;
    return age >= 0 && age < windowMs;
}

function consume(requests, key) {
    var next = Object.assign({},requests || {});
    delete next[key];
    return next;
}

// Drop everything that can no longer be answered. Called on write rather
// than from a timer, so an idle shell spends nothing holding these.
function prune(requests, now, windowMs) {
    var next = {};
    var keys = Object.keys(requests || {});
    for (var i = 0; i < keys.length; i++)
        if (answerable(requests,keys[i],now,windowMs))
            next[keys[i]] = requests[keys[i]];
    return next;
}

function record(requests, key, now, windowMs) {
    if (typeof key !== 'string' || key.length === 0)
        return Object.assign({},requests || {});
    var next = prune(requests,now,windowMs);
    next[key] = now;
    return next;
}
function newWindows(known, windows) {
    return (windows || []).filter(function(w) { return !(known || []).includes(w.address); });
}
