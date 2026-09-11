// Workload passports: the contract an owner uses to say "this specific
// piece of work is running", separate from the resource claims it holds.
//
// A passport is opened by the plane owner that knows about the work, and
// closed by that same owner. Nothing here releases a resource claim: a
// passport going stale means Aphotic stopped hearing from the source, not
// that the work ended, and guessing the difference is how a view ends up
// showing freed capacity that is still held.
//
// Identity is owner + pid + process start time (or a sessionId for work
// with no process of its own) + optional job id. A pid on its own is
// reused by the kernel and would let a new process inherit the previous
// one's passport.

var LIMITS = {live: 64, history: 32, text: 64, claims: 12};
var PLANES = ['ai', 'gaming', 'security', 'dev'];
var DEFAULT_STALE_MS = 90000;
var DEFAULT_DEBOUNCE_MS = 500;

function _num(value) {
    return typeof value === 'number' && isFinite(value) ? value : null;
}

// Bounded and path-free. Passport text reaches an export file and a
// tooltip, so a project path or a command line must not ride along in a
// display label.
function _text(value) {
    if (typeof value !== 'string')
        return '';
    var out = value.trim().replace(/(^|\s)(~?\/[^\s]*)/g, '$1<path>');
    return out.length > LIMITS.text ? out.slice(0, LIMITS.text - 1) + '…' : out;
}

// A process-backed workload is identified by pid plus start time. Work
// that has no process of its own -- an open project, an engagement, a
// resident model -- names a sessionId instead, and that string is the
// stable half of its identity.
// Identity keys are bounded but never path-stripped: two projects under
// different paths must not collapse into one workload.
function _key(value) {
    if (typeof value !== 'string')
        return '';
    var out = value.trim();
    return out.length > LIMITS.text ? out.slice(0, LIMITS.text) : out;
}

function identity(input) {
    var p = (input && input.process) || {};
    var core = _num(p.pid) !== null ? p.pid + ':' + p.startedAt : 'session:' + (input && input.sessionId);
    return [input && input.owner, core, (input && input.jobId) || ''].join(':');
}

function newState() {
    return {live: {}, order: [], history: [], nextToken: 1, rejected: 0, dropped: 0};
}

// Every measured amount needs a unit and a source timestamp. An entry
// without them is dropped rather than shown as an unqualified number.
function normalizeClaims(list) {
    var out = [];
    (list || []).forEach(function (c) {
        if (!c || !c.resource || out.length >= LIMITS.claims)
            return;
        var amount = _num(c.amount);
        var measuredAt = _num(c.measuredAt);
        if (amount === null || !c.unit || measuredAt === null)
            return;
        out.push({resource: String(c.resource), amount: amount, unit: String(c.unit),
            measuredAt: measuredAt, origin: c.origin === 'declared' ? 'declared' : 'measured'});
    });
    return out;
}

function validate(input) {
    if (!input || typeof input !== 'object')
        return 'no payload';
    if (PLANES.indexOf(input.plane) < 0)
        return 'unknown plane';
    if (!input.owner)
        return 'no owner';
    if (!input.label)
        return 'no label';
    if (!input.trigger)
        return 'no trigger';
    var p = input.process || {};
    var hasProcess = _num(p.pid) !== null || _num(p.startedAt) !== null;
    if (hasProcess && (_num(p.pid) === null || _num(p.startedAt) === null))
        return 'process identity needs pid and startedAt';
    if (!hasProcess && !input.sessionId)
        return 'needs process identity or sessionId';
    if (_num(input.sourceAt) === null)
        return 'no source timestamp';
    return '';
}

function _view(entry) {
    return {token: entry.token, workloadId: entry.workloadId, plane: entry.plane,
        owner: entry.owner, label: entry.label, trigger: entry.trigger,
        process: {pid: entry.process.pid, startedAt: entry.process.startedAt},
        sessionId: entry.sessionId, jobId: entry.jobId, sourceAt: entry.sourceAt, openedAt: entry.openedAt,
        updatedAt: entry.updatedAt, claims: entry.claims.slice(),
        status: entry.status, stale: entry.status === 'stale',
        closedAt: entry.closedAt, closeReason: entry.closeReason};
}

// Returns created:false for a repeat of an identity already open, so an
// adapter that re-announces on every poll, or restarts and re-announces
// everything it can still see, re-adopts the passport instead of opening a
// second one for the same work.
function open(state, input, now, debounceMs) {
    var error = validate(input);
    if (error) {
        state.rejected += 1;
        return {ok: false, error: error};
    }
    var key = identity(input);
    var existing = state.live[key];
    var claims = normalizeClaims(input.claims);
    if (existing) {
        var quiet = (now - existing.updatedAt) < (_num(debounceMs) === null ? DEFAULT_DEBOUNCE_MS : debounceMs);
        var revived = existing.status === 'stale';
        existing.status = 'live';
        existing.sourceAt = input.sourceAt;
        existing.updatedAt = now;
        existing.label = _text(input.label);
        existing.trigger = _text(input.trigger);
        existing.claims = claims;
        return {ok: true, token: existing.token, created: false, revived: revived,
            changed: revived || !quiet, passport: _view(existing)};
    }
    if (state.order.length >= LIMITS.live) {
        state.dropped += 1;
        return {ok: false, error: 'live passport limit reached'};
    }
    var p2 = input.process || {};
    var entry = {token: 'w' + state.nextToken++, key: key, plane: input.plane,
        owner: String(input.owner), label: _text(input.label), trigger: _text(input.trigger),
        workloadId: _key(input.workloadId) || ('w' + (state.nextToken - 1)),
        process: {pid: _num(p2.pid), startedAt: _num(p2.startedAt)},
        sessionId: _key(input.sessionId), jobId: _key(input.jobId), sourceAt: input.sourceAt, openedAt: now, updatedAt: now,
        claims: claims, status: 'live', closedAt: null, closeReason: ''};
    state.live[key] = entry;
    state.order.push(key);
    return {ok: true, token: entry.token, created: true, changed: true, passport: _view(entry)};
}

function _findByToken(state, token) {
    for (var i = 0; i < state.order.length; i++) {
        var entry = state.live[state.order[i]];
        if (entry && entry.token === token)
            return entry;
    }
    return null;
}

function heartbeat(state, token, now, claims) {
    var entry = _findByToken(state, token);
    if (!entry)
        return {ok: false, error: 'unknown token'};
    var revived = entry.status === 'stale';
    entry.status = 'live';
    entry.updatedAt = now;
    entry.sourceAt = now;
    if (claims)
        entry.claims = normalizeClaims(claims);
    return {ok: true, revived: revived, passport: _view(entry)};
}

// Close is the owner confirming the work ended. A second close of the same
// token is a no-op, so a duplicate exit event cannot file a second
// completion.
function close(state, token, reason, now) {
    var entry = _findByToken(state, token);
    if (!entry)
        return {ok: false, error: 'unknown or already closed token'};
    entry.status = 'closed';
    entry.closedAt = now;
    entry.closeReason = _text(reason) || 'owner closed';
    delete state.live[entry.key];
    state.order.splice(state.order.indexOf(entry.key), 1);
    state.history.push(_view(entry));
    while (state.history.length > LIMITS.history)
        state.history.shift();
    return {ok: true, passport: _view(entry)};
}

function closeOwner(state, owner, reason, now) {
    var closed = [];
    state.order.slice().forEach(function (key) {
        var entry = state.live[key];
        if (entry && entry.owner === owner)
            closed.push(close(state, entry.token, reason, now).passport);
    });
    return closed;
}

// A source that stops reporting gets marked stale and stays in the list.
// It is never closed here: only the owner can say the work is over.
function sweep(state, now, staleAfterMs) {
    var limit = _num(staleAfterMs) === null ? DEFAULT_STALE_MS : staleAfterMs;
    var changed = [];
    state.order.forEach(function (key) {
        var entry = state.live[key];
        if (entry.status === 'live' && (now - entry.updatedAt) > limit) {
            entry.status = 'stale';
            changed.push(_view(entry));
        }
    });
    return changed;
}

function list(state) {
    return state.order.map(function (key) {
        return _view(state.live[key]);
    });
}

function ofOwner(state, owner) {
    return list(state).filter(function (p) {
        return p.owner === owner;
    });
}

function ofPlane(state, plane) {
    return list(state).filter(function (p) {
        return p.plane === plane;
    });
}

function history(state) {
    return state.history.slice();
}

function stats(state) {
    var all = list(state);
    return {live: all.filter(function (p) { return p.status === 'live'; }).length,
        stale: all.filter(function (p) { return p.status === 'stale'; }).length,
        closed: state.history.length, rejected: state.rejected, dropped: state.dropped};
}
