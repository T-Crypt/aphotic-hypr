const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ctx = vm.createContext({});
vm.runInContext(readFileSync(__dirname + '/../Configs/quickshell/aphotic/services/Posture.js', 'utf8'), ctx);
const P = ctx;

const claim = (id, owner, amount, resource = 'gpu-vram') => ({id, owner, resource, amount, priority: 'background', label: id});
const vram = (extra = {}) => ({'gpu-vram': Object.assign({key: 'gpu-vram', label: 'GPU VRAM', unit: 'MB', capacity: 1000, safetyMargin: 0.1}, extra)});

// Nothing declared, nothing to judge -- even with claims.
let s = P.assess([claim('a', 'ai', 5000)], {}, null, null, false);
assert.equal(s.level, 'quiet');
assert.equal(P.headline(s), '');

// Under 85% of budget (900): quiet.
s = P.assess([claim('a', 'ai', 700)], vram(), null, null, false);
assert.equal(s.level, 'quiet');
assert.equal(s.resource, null);

// At/over 85% of budget with one holder: pressure, not contention.
s = P.assess([claim('a', 'ai', 800)], vram(), null, null, false);
assert.equal(s.level, 'pressure');
assert.equal(s.resource.key, 'gpu-vram');
assert.match(P.headline(s), /GPU VRAM 89% of budget/);

// Measured use counts toward pressure even when claims are small.
s = P.assess([claim('a', 'ai', 100)], vram({measured: {used: 880, total: 1000}}), null, null, false);
assert.equal(s.level, 'pressure');

// Two holders over budget: contention, owners ranked by amount.
s = P.assess([claim('a', 'ai', 600), claim('b', 'game', 400)], vram(), null, null, false);
assert.equal(s.level, 'contention');
assert.equal(s.resource.owners[0].owner, 'ai');
assert.match(P.headline(s), /GPU VRAM contended · ai, game/);

// The engine's overBudget (nothing suspendable) is contention too.
s = P.assess([claim('a', 'ai', 950)], vram(), null, {resource: 'gpu-vram'}, false);
assert.equal(s.level, 'contention');

// A pending negotiation outranks everything and names both sides.
const pending = {id: 3, resource: 'gpu-vram', claimant: {owner: 'ollama'}, requestor: {owner: 'gaming'}};
s = P.assess([claim('a', 'ollama', 600), claim('b', 'gaming', 400)], vram(), pending, null, false);
assert.equal(s.level, 'negotiating');
assert.equal(s.negotiation.claimant, 'ollama');
assert.match(P.headline(s), /gaming vs ollama/);

// Exclusive resources contend on a second holder regardless of amount.
s = P.assess([claim('a', 'x', 0, 'cam'), claim('b', 'y', 0, 'cam')], {cam: {label: 'Camera', exclusive: true}}, null, null, false);
assert.equal(s.level, 'contention');

// Worst resource first when several are active.
const specs = Object.assign(vram(), {memory: {label: 'Memory', unit: 'MiB', capacity: 100, safetyMargin: 0}});
s = P.assess([claim('a', 'ai', 800), claim('m1', 'x', 60, 'memory'), claim('m2', 'y', 50, 'memory')], specs, null, null, false);
assert.equal(s.resource.key, 'memory');
assert.equal(s.resources.length, 2);

// Settling only when nothing else is active.
s = P.assess([], vram(), null, null, true);
assert.equal(s.level, 'settling');
s = P.assess([claim('a', 'ai', 800)], vram(), null, null, true);
assert.equal(s.level, 'pressure');

// Threshold ordering the context layer relies on.
assert.ok(P.atLeast('negotiating', 'pressure'));
assert.ok(P.atLeast('contention', 'contention'));
assert.ok(!P.atLeast('pressure', 'contention'));
assert.ok(!P.atLeast('quiet', 'pressure'));

// The posture agrees with Flow on what counts as contended.
vm.runInContext(readFileSync(__dirname + '/../Configs/quickshell/aphotic/modules/flow/FlowModel.js', 'utf8'), ctx);
for (const claims of [
    [claim('a', 'ai', 600), claim('b', 'game', 400)],
    [claim('a', 'ai', 950)],
    [claim('a', 'ai', 400), claim('b', 'game', 400)],
]) {
    const flow = ctx.summarize(claims, vram(), {}, {}, {}, [], []);
    const posture = P.assess(claims, vram(), null, null, false);
    assert.equal(flow.contentionCount > 0, posture.level === 'contention', JSON.stringify(claims));
}

console.log('Resource posture: passed');

// Contention episodes: fire once on entry to plain contention, not for
// negotiations, not again while it lasts, again after it clears.
const over = [claim('a', 'ai', 600), claim('b', 'game', 400)];
let ep = P.episodes([], P.assess(over, vram(), null, null, false));
assert.deepEqual(Array.from(ep.fresh, r => r.key), ['gpu-vram']);
ep = P.episodes(ep.held, P.assess(over, vram(), null, null, false));
assert.equal(ep.fresh.length, 0);
ep = P.episodes(ep.held, P.assess([claim('a', 'ai', 100)], vram(), null, null, false));
assert.equal(ep.held.length, 0);
ep = P.episodes(ep.held, P.assess(over, vram(), null, null, false));
assert.equal(ep.fresh.length, 1);
// Arriving as a negotiation: no notification now, and none when "keep" leaves it contended.
ep = P.episodes([], P.assess(over, vram(), pending, null, false));
assert.equal(ep.fresh.length, 0);
ep = P.episodes(ep.held, P.assess(over, vram(), null, null, false));
assert.equal(ep.fresh.length, 0);
console.log('Contention episodes: passed');
