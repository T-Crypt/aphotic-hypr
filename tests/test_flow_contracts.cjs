const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const load = rel => {
    const ctx = vm.createContext({});
    vm.runInContext(readFileSync(__dirname + '/../Configs/quickshell/aphotic/services/profile/' + rel, 'utf8'), ctx);
    return ctx;
};
const P = load('Passports.js');
const R = load('Receipts.js');

// --- workload passports -----------------------------------------------
const job = (over = {}) => Object.assign({
    plane: 'dev', owner: 'dev', label: 'build aphotic', trigger: 'build-start',
    process: {pid: 4242, startedAt: 1000}, sourceAt: 1000
}, over);

let s = P.newState();
let a = P.open(s, job(), 1000);
assert.equal(a.ok, true);
assert.equal(a.created, true);

// A repeat announcement of the same identity re-adopts the passport.
let b = P.open(s, job(), 1100);
assert.equal(b.created, false);
assert.equal(b.token, a.token);
assert.equal(P.list(s).length, 1);
assert.equal(b.changed, false, 'a repeat inside the debounce window is not a change');
assert.equal(P.open(s, job(), 9000).changed, true, 'a repeat after it is');

// A reused pid with a different start time is different work.
assert.notEqual(P.open(s, job({process: {pid: 4242, startedAt: 7000}}), 7000).token, a.token);
assert.equal(P.list(s).length, 2);

// Overlapping jobs from one owner stay separate.
assert.equal(P.open(s, job({jobId: 'second'}), 7100).created, true);
assert.equal(P.ofOwner(s, 'dev').length, 3);

// Validation: plane, process identity and measured units.
assert.equal(P.open(P.newState(), job({plane: 'compute'}), 1).error, 'unknown plane');
assert.equal(P.open(P.newState(), job({process: {pid: 1}}), 1).error, 'process identity needs pid and startedAt');
assert.equal(P.open(P.newState(), job({trigger: ''}), 1).error, 'no trigger');
const claimed = P.open(P.newState(), job({claims: [
    {resource: 'cpu', amount: 8, unit: 'threads', measuredAt: 1000, origin: 'declared'},
    {resource: 'cpu', amount: 8},
    {resource: 'memory', amount: 'lots', unit: 'MiB', measuredAt: 1000}
]}), 1000);
assert.equal(claimed.passport.claims.length, 1, 'an amount without a unit and timestamp is dropped');
assert.equal(claimed.passport.claims[0].origin, 'declared');

// Work with no process of its own is identified by session instead.
let sess = P.newState();
const vpn = P.open(sess, {plane: 'security', owner: 'security', label: 'engagement',
    trigger: 'vpn-connect', sessionId: 'vpn', sourceAt: 5}, 5);
assert.equal(vpn.ok, true);
assert.equal(P.open(sess, {plane: 'security', owner: 'security', label: 'engagement',
    trigger: 'vpn-connect', sessionId: 'vpn', sourceAt: 6}, 6).token, vpn.token);
assert.equal(P.open(sess, {plane: 'security', owner: 'security', label: 'lab',
    trigger: 'lab-start', sessionId: 'lab', sourceAt: 6}, 6).created, true);
assert.equal(P.ofPlane(sess, 'security').length, 2);
assert.equal(P.open(P.newState(), {plane: 'ai', owner: 'ollama', label: 'm', trigger: 't', sourceAt: 1}, 1).error,
    'needs process identity or sessionId');

// Paths never reach a label.
assert.equal(P.open(P.newState(), job({label: 'build /home/me/secret/app'}), 1).passport.label, 'build <path>');

// A missing exit goes stale and stays listed; the owner still owns the close.
let t = P.newState();
const live = P.open(t, job(), 0).token;
assert.equal(P.sweep(t, 1000, 90000).length, 0);
const stale = P.sweep(t, 200000, 90000);
assert.equal(stale.length, 1);
assert.equal(stale[0].status, 'stale');
assert.equal(P.list(t).length, 1, 'stale work is not removed');
assert.equal(P.stats(t).stale, 1);

// An adapter that restarts and re-announces revives, it does not duplicate.
const back = P.open(t, job(), 210000);
assert.equal(back.revived, true);
assert.equal(back.token, live);
assert.equal(P.list(t).length, 1);

// Close is the owner's word, and a duplicate exit is a no-op.
assert.equal(P.close(t, live, 'build finished', 220000).ok, true);
assert.equal(P.close(t, live, 'build finished', 220001).ok, false);
assert.equal(P.list(t).length, 0);
assert.equal(P.history(t).length, 1);
assert.equal(P.history(t)[0].closeReason, 'build finished');
assert.equal(P.heartbeat(t, live, 1).ok, false, 'a closed token cannot beat');

// Heartbeat clears staleness and refreshes measured claims.
let h = P.newState();
const hb = P.open(h, job(), 0).token;
P.sweep(h, 200000, 90000);
const beat = P.heartbeat(h, hb, 210000, [{resource: 'cpu', amount: 4, unit: 'threads', measuredAt: 210000}]);
assert.equal(beat.revived, true);
assert.equal(beat.passport.claims[0].amount, 4);

// closeOwner ends everything one owner still holds.
let c = P.newState();
P.open(c, job(), 0);
P.open(c, job({jobId: 'x'}), 0);
P.open(c, job({plane: 'ai', owner: 'ollama', process: {pid: 9, startedAt: 9}}), 0);
assert.equal(P.closeOwner(c, 'dev', 'adapter gone', 10).length, 2);
assert.equal(P.list(c).length, 1);

// The live table is bounded.
let big = P.newState();
for (let i = 0; i < 80; i++)
    P.open(big, job({process: {pid: i, startedAt: i}}), 0);
assert.equal(P.list(big).length, 64);
assert.ok(P.stats(big).dropped > 0);

// --- action receipts ---------------------------------------------------
let rs = R.newState();
assert.equal(R.request(rs, {profileId: 'gaming', kind: 'telepathy'}, 0).error, 'unsupported kind');
const dnd = R.request(rs, {profileId: 'gaming', kind: 'dnd', before: 'off', reason: 'game session'}, 1757000000000);
assert.equal(dnd.receipt.status, 'requested');
assert.match(R.label(dnd.receipt), /^Requested at \d\d:\d\d$/);

// A request is not a success until the owner says the operation landed.
assert.equal(R.applied(rs, dnd.id, 'on', 1757000060000).receipt.status, 'applied');
assert.equal(R.applied(rs, dnd.id, 'on', 1).ok, false, 'a settled receipt does not settle twice');
assert.match(R.label(R.byId(rs, dnd.id)), /^Applied at /);

// A failure never reads as applied.
const fail = R.request(rs, {profileId: 'ai', kind: 'model-unload', reason: 'vram contention'}, 10);
R.failed(rs, fail.id, 'ollama refused', 20);
assert.equal(R.byId(rs, fail.id).status, 'failed');
assert.equal(R.byId(rs, fail.id).after, '', 'a failed action has no applied value');
assert.equal(R.pending(rs).length, 0);

// Restore preserves a value the user changed after Aphotic applied it.
const keep = R.request(rs, {profileId: 'gaming', kind: 'scheduler', before: 'balanced'}, 30);
R.applied(rs, keep.id, 'performance', 40);
const preserved = R.restore(rs, keep.id, 'powersave', 50);
assert.equal(preserved.action, 'preserve');
assert.equal(preserved.receipt.preserved, true);
assert.match(R.label(preserved.receipt), /^Left as the user set it/);

const same = R.request(rs, {profileId: 'gaming', kind: 'workspace', before: '1'}, 60);
R.applied(rs, same.id, '5', 70);
assert.equal(R.restore(rs, same.id, '5', 80).action, 'restore');
assert.equal(R.byId(rs, same.id).preserved, false);

// A restore that blows up is its own status.
const rf = R.request(rs, {profileId: 'security', kind: 'power', before: 'ac'}, 90);
R.applied(rs, rf.id, 'battery', 100);
assert.equal(R.restoreFailed(rs, rf.id, 'hyprctl not reachable', 110).receipt.status, 'restore-failed');

// Paths and long values are bounded on the way in.
const red = R.request(rs, {profileId: 'dev', kind: 'shelter', before: '/home/me/project', reason: 'x'.repeat(200)}, 120);
assert.equal(red.receipt.before, '<path>');
assert.ok(red.receipt.reason.length <= 64);

// Lookups and export.
assert.equal(R.forProfile(rs, 'gaming').length, 3);
assert.equal(R.forWorkload(rs, 'nope').length, 0);
assert.match(R.exportText(rs), /gaming: dnd · Applied at /);
assert.ok(R.exportText(rs).indexOf('/home/me') < 0, 'export carries no paths');
assert.equal(R.stats(rs).failed, 2);

// The store is bounded and drops the oldest.
let rb = R.newState();
for (let i = 0; i < 200; i++)
    R.request(rb, {profileId: 'dev', kind: 'dnd'}, i);
assert.equal(R.stats(rb).total, 128);
assert.ok(R.stats(rb).dropped >= 72);

console.log('Flow contracts: passports and receipts passed');
