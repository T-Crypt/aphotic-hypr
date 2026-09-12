// Action receipts: what an owner actually did, as opposed to what a
// profile phase says it was about to do.
//
// A phase change proves the lifecycle moved. It does not prove the DND
// toggle landed, the model unloaded or the scheduler call returned. Flow
// shows "requested" the moment the request is filed and promotes the
// label only when the owner reports the operation succeeded, so a failed
// action can never read as a visual success.

var KINDS = ['dnd', 'scheduler', 'power', 'model-unload', 'workspace', 'shelter', 'handover'];
var STATUSES = ['requested', 'applied', 'failed', 'restored', 'restore-failed'];
var LIMITS = {items: 128, text: 64};

function _num(value) {
    return typeof value === 'number' && isFinite(value) ? value : null;
}

// before/after values are shown in a lens and can be exported, so they are
// bounded and stripped of paths. Command lines and prompts never belong in
// a receipt in the first place; this is the backstop.
function redact(value) {
    if (value === null || value === undefined)
        return '';
    if (typeof value === 'boolean' || typeof value === 'number')
        return String(value);
    var out = String(value).trim().replace(/(^|\s)(~?\/[^\s]*)/g, '$1<path>');
    return out.length > LIMITS.text ? out.slice(0, LIMITS.text - 1) + '…' : out;
}

function newState() {
    return {items: [], nextId: 1, dropped: 0, rejected: 0};
}

function byId(state, id) {
    for (var i = state.items.length - 1; i >= 0; i--) {
        if (state.items[i].id === id)
            return state.items[i];
    }
    return null;
}

function request(state, input, now) {
    if (!input || KINDS.indexOf(input.kind) < 0) {
        state.rejected += 1;
        return {ok: false, error: 'unsupported kind'};
    }
    if (!input.profileId) {
        state.rejected += 1;
        return {ok: false, error: 'no profileId'};
    }
    var receipt = {id: 'r' + state.nextId++, profileId: String(input.profileId),
        workloadId: input.workloadId ? String(input.workloadId) : '',
        kind: input.kind, status: 'requested', requestedAt: _num(now) || 0,
        completedAt: null, before: redact(input.before), after: '',
        reason: redact(input.reason), error: '', preserved: false};
    state.items.push(receipt);
    while (state.items.length > LIMITS.items) {
        state.items.shift();
        state.dropped += 1;
    }
    return {ok: true, id: receipt.id, receipt: receipt};
}

function _settle(state, id, patch, from) {
    var receipt = byId(state, id);
    if (!receipt)
        return {ok: false, error: 'unknown receipt'};
    if (from.indexOf(receipt.status) < 0)
        return {ok: false, error: 'receipt is ' + receipt.status};
    for (var key in patch)
        receipt[key] = patch[key];
    return {ok: true, receipt: receipt};
}

function applied(state, id, after, now) {
    return _settle(state, id, {status: 'applied', after: redact(after), completedAt: _num(now) || 0, error: ''}, ['requested']);
}

function failed(state, id, error, now) {
    return _settle(state, id, {status: 'failed', completedAt: _num(now) || 0, error: redact(error) || 'failed'}, ['requested']);
}

// Restore compares what is there now against the value Aphotic applied. If
// they differ the user, or something else, changed it in the meantime, so
// the receipt records that the current value was preserved rather than
// overwriting a deliberate choice.
function restore(state, id, current, now) {
    var receipt = byId(state, id);
    if (!receipt)
        return {ok: false, error: 'unknown receipt'};
    if (receipt.status !== 'applied')
        return {ok: false, error: 'receipt is ' + receipt.status};
    if (redact(current) !== receipt.after) {
        receipt.status = 'restored';
        receipt.preserved = true;
        receipt.completedAt = _num(now) || 0;
        return {ok: true, action: 'preserve', receipt: receipt};
    }
    receipt.status = 'restored';
    receipt.completedAt = _num(now) || 0;
    return {ok: true, action: 'restore', receipt: receipt};
}

function restoreFailed(state, id, error, now) {
    return _settle(state, id, {status: 'restore-failed', completedAt: _num(now) || 0, error: redact(error) || 'restore failed'}, ['applied', 'restored']);
}

function pending(state) {
    return state.items.filter(function (r) {
        return r.status === 'requested';
    });
}

function forProfile(state, profileId) {
    return state.items.filter(function (r) {
        return r.profileId === profileId;
    });
}

function forWorkload(state, workloadId) {
    return state.items.filter(function (r) {
        return r.workloadId === workloadId;
    });
}

function _clock(ms) {
    if (_num(ms) === null || ms <= 0)
        return '';
    var d = new Date(ms);
    return ('0' + d.getHours()).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2);
}

var _VERBS = {requested: 'Requested', applied: 'Applied', failed: 'Failed',
    restored: 'Restored', 'restore-failed': 'Restore failed'};

function label(receipt) {
    if (!receipt)
        return '';
    var when = _clock(receipt.status === 'requested' ? receipt.requestedAt : receipt.completedAt);
    var verb = receipt.preserved && receipt.status === 'restored' ? 'Left as the user set it' : _VERBS[receipt.status] || receipt.status;
    return verb + (when ? ' at ' + when : '');
}

function line(receipt) {
    var parts = [receipt.kind, label(receipt)];
    if (receipt.reason)
        parts.push('reason: ' + receipt.reason);
    if (receipt.before || receipt.after)
        parts.push(receipt.before + ' → ' + (receipt.after || 'pending'));
    if (receipt.error)
        parts.push('error: ' + receipt.error);
    return receipt.profileId + ': ' + parts.join(' · ');
}

function exportText(state) {
    return state.items.map(line).join('\n');
}

function stats(state) {
    return {total: state.items.length, pending: pending(state).length,
        failed: state.items.filter(function (r) { return r.status === 'failed' || r.status === 'restore-failed'; }).length,
        dropped: state.dropped, rejected: state.rejected};
}

function importHandover(state, lease, stage) {
    var id = 'handover:' + lease.id + ':' + stage.id;
    var existing = byId(state, id);
    var statuses = {prepared: 'requested', applying: 'requested', applied: 'applied', restored: 'restored', 'restore-failed': 'restore-failed'};
    if (!statuses[stage.status]) return false;
    var receipt = {id: id, profileId: lease.owner, workloadId: lease.id,
        kind: 'handover', status: statuses[stage.status], requestedAt: stage.requestedAt || lease.createdAt || 0,
        completedAt: stage.restoredAt || stage.completedAt || null, before: redact(stage.kind === 'file' ? 'saved host file' : JSON.stringify(stage.before)),
        after: redact(stage.kind === 'file' ? 'owned host file' : JSON.stringify(stage.after)),
        reason: redact(stage.id), error: redact(stage.error || stage.applyError || ''), preserved: !!stage.preserved};
    if (existing) Object.assign(existing, receipt);
    else state.items.push(receipt);
    while (state.items.length > LIMITS.items) { state.items.shift(); state.dropped++; }
    return true;
}
