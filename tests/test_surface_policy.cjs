const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ctx = vm.createContext({});
vm.runInContext(readFileSync(__dirname + '/../Configs/quickshell/aphotic/services/SurfacePolicy.js', 'utf8'), ctx);
const P = ctx;
// vm contexts hand back arrays from another realm; compare as plain data.
const eq = (a, b, msg) => assert.deepEqual(JSON.parse(JSON.stringify(a)), b, msg);

// A primary opening closes the other primary and any transient, keeps the workspace plane.
let t = P.transition(['workspace', 'agentPanel', 'dashboard'], 'launcher', true);
eq(t.stack, ['workspace', 'launcher']);
eq(t.close.slice().sort(), ['agentPanel', 'dashboard']);

// Closing only removes.
t = P.transition(['workspace', 'launcher'], 'launcher', false);
eq(t.stack, ['workspace']);
eq(t.close, []);

// Re-entrant close of an already-removed name is a no-op.
t = P.transition(['launcher'], 'dashboard', false);
eq(t.stack, ['launcher']);
eq(t.close, []);

// A primary replaces the session menu (user changed their mind); the session menu closes primaries.
t = P.transition(['session'], 'launcher', true);
eq(t.close, ['session']);
t = P.transition(['settings'], 'session', true);
eq(t.close, ['settings']);
eq(t.stack, ['session']);

// Workspace opening closes primaries and modals.
t = P.transition(['launcher', 'agentPanel'], 'workspace', true);
eq(t.close.slice().sort(), ['agentPanel', 'launcher']);

// A transient displaces only transients.
t = P.transition(['workspace', 'launcher'], 'agentPanel', true);
eq(t.close, []);
eq(t.stack, ['workspace', 'launcher', 'agentPanel']);

// Unknown names neither close nor get closed.
t = P.transition(['launcher'], 'plugin-thing', true);
eq(t.close, []);
t = P.transition(['plugin-thing'], 'launcher', true);
eq(t.stack, ['plugin-thing', 'launcher']);

// Declared (plugin) surfaces take part through `extra`.
const extra = {pluginPanel: {role: 'primary'}};
t = P.transition(['launcher'], 'pluginPanel', true, extra);
eq(t.close, ['launcher']);
assert.equal(P.roleOf('pluginPanel', extra), 'primary');
assert.equal(P.roleOf('pluginPanel'), '');

// Focus: highest role wins; blocking beats all; transients never outrank a primary.
assert.equal(P.focusOwner(['workspace', 'launcher', 'agentPanel']), 'launcher');
assert.equal(P.focusOwner(['workspace']), 'workspace');
assert.equal(P.focusOwner([]), '');
assert.equal(P.focusOwner(['launcher'], 'negotiation'), 'negotiation');

// Mode and engaged.
assert.equal(P.mode([]), 'ambient');
assert.equal(P.mode(['agentPanel']), 'transient');
assert.equal(P.mode(['workspace', 'launcher']), 'primary');
assert.equal(P.mode(['session']), 'modal');
assert.equal(P.mode(['launcher'], 'negotiation'), 'blocked');
assert.equal(P.engaged([]), false);
assert.equal(P.engaged(['agentPanel']), false);
assert.equal(P.engaged(['launcher']), true);
assert.equal(P.engaged(['workspace']), true);
assert.equal(P.engaged([], 'negotiation'), true);

// Back closes the focus owner, never a blocking modal.
assert.equal(P.back(['workspace', 'launcher']), 'launcher');
assert.equal(P.back(['workspace']), 'workspace');
assert.equal(P.back(['launcher'], 'negotiation'), '');
assert.equal(P.back([]), '');

// describe() carries everything the visual layer styles against.
eq(P.describe(['workspace', 'launcher'], ''), {stack: ['workspace', 'launcher'], focusOwner: 'launcher', mode: 'primary', blocking: ''});

// Replaying a sequence of opens never leaves two primaries or two modals open.
let stack = [];
const flags = {};
function set(name, open) {
    const r = P.transition(stack, name, open);
    stack = r.stack;
    flags[name] = open;
    for (const c of r.close) set(c, false);
}
for (const n of ['dashboard', 'agentPanel', 'launcher', 'workspace', 'settings', 'session', 'notificationCenter', 'launcher'])
    set(n, true);
const open = Object.keys(flags).filter(k => flags[k]);
const roles = open.map(n => P.roleOf(n));
assert.ok(roles.filter(r => r === 'primary').length <= 1, 'at most one primary: ' + open);
assert.ok(roles.filter(r => r === 'modal').length <= 1, 'at most one modal: ' + open);
eq(stack.slice().sort(), open.sort(), 'stack agrees with the flags');

console.log('Surface policy: passed');
