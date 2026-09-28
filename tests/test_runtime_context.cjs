const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ctx = vm.createContext({});
vm.runInContext(readFileSync(__dirname + '/../Configs/quickshell/aphotic/services/ContextPolicy.js', 'utf8'), ctx);
vm.runInContext(readFileSync(__dirname + '/../Configs/quickshell/aphotic/services/Posture.js', 'utf8'), ctx);
const C = ctx;

const ids = C.list().map(c => c.id);
assert.equal(ids[0], 'default');
for (const id of ids) {
    const p = C.policy(id);
    assert.ok(['all', 'normal', 'critical', 'none'].includes(p.notifications), id);
    assert.ok(['full', 'reduced'].includes(p.motion), id);
    // Every threshold is a real posture level, and never hides a negotiation.
    assert.ok(ctx.LEVELS.includes(p.resources), id);
    assert.ok(ctx.atLeast('negotiating', p.resources), id);
    assert.ok(p.label && p.description, id);
}

// Unknown names are refused by has() and fall back to default policy.
assert.equal(C.has('bogus'), false);
assert.equal(C.has('toString'), false);
assert.equal(C.policy('bogus'), C.policy('default'));

// Default changes nothing: every urgency pops up, motion stays full.
for (const u of [0, 1, 2]) assert.equal(C.allowsPopup('default', u), true);
assert.equal(C.reducesMotion('default'), false);

// Focus and game hold back all but critical.
for (const id of ['focus', 'game']) {
    assert.equal(C.allowsPopup(id, 0), false);
    assert.equal(C.allowsPopup(id, 1), false);
    assert.equal(C.allowsPopup(id, 2), true);
    assert.equal(C.reducesMotion(id), true);
}

// Dev drops only low urgency.
assert.equal(C.allowsPopup('dev', 0), false);
assert.equal(C.allowsPopup('dev', 1), true);

// Present shows no popups at all, and only surfaces resources for a decision.
for (const u of [0, 1, 2]) assert.equal(C.allowsPopup('present', u), false);
assert.equal(C.resourceThreshold('present'), 'negotiating');
assert.equal(ctx.atLeast('contention', C.resourceThreshold('present')), false);

// Missing urgency is treated as normal.
assert.equal(C.allowsPopup('dev', undefined), true);

console.log('Runtime context: passed');

// Overlays: only game and present unmount them.
for (const id of ids) {
    assert.ok(['shown', 'hidden'].includes(C.policy(id).overlays), id);
    assert.equal(C.hidesOverlays(id), id === 'game' || id === 'present', id);
}
console.log('Context overlays: passed');
