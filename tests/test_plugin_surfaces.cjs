const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');

function load(relativePath) {
    const context = vm.createContext({});
    const source = readFileSync(`${__dirname}/../${relativePath}`, 'utf8')
        .replace(/^\.pragma library[^\n]*\n/, '');
    vm.runInContext(source, context);
    return context;
}

const core = load('Configs/quickshell/aphotic/services/PluginRegistryCore.js');
const plain = value => JSON.parse(JSON.stringify(value));

const ghost = { plugin: 'ghost', surface: 'workspace', id: 'ws' };
const solid = { plugin: 'solid', surface: 'workspace', id: 'solidWs' };

// A mark is keyed by plugin as well as id: two plugins may declare the
// same surface id, and one failing must not hide the other.
assert.equal(core.failedKey(ghost), 'ghost:ws');
assert.equal(core.surfaceFailed(ghost, {}), false);
const marked = core.markFailed({}, ghost, true);
assert.deepEqual(plain(marked), { 'ghost:ws': true });
assert.equal(core.surfaceFailed(ghost, marked), true);
assert.equal(core.surfaceFailed(solid, marked), false);

// Marking is idempotent, and a set already in the wanted state comes back
// as the same object so callers never churn watchers on a no-op.
assert.equal(core.markFailed(marked, ghost, true), marked);

// A successful load clears the mark, so a plugin fixed mid-session is
// counted and bound again without a shell restart.
const cleared = core.markFailed(marked, ghost, false);
assert.deepEqual(plain(cleared), {});
assert.equal(core.surfaceFailed(ghost, cleared), false);

// A null or keyless surface never marks anything.
assert.deepEqual(plain(core.markFailed({}, null, true)), {});
assert.deepEqual(plain(core.markFailed({}, { plugin: '', id: '' }, true)), {});
assert.equal(core.surfaceFailed(null, { '': true }), false);

// surfacesFor keeps its sheltered and surface filters.
const registrations = [
    { plugin: 'a', surface: 'workspace', id: 'a1' },
    { plugin: 'b', surface: 'workspace', id: 'b1' },
    { plugin: 'c', surface: 'dashboard', id: 'c1' }
];
const installed = { a: { shelter: '' }, b: { shelter: 'unload' } };
assert.equal(core.surfacesFor(registrations, installed, 'workspace', true).length, 1);
assert.equal(core.surfacesFor(registrations, installed, 'workspace', false).length, 2);
assert.equal(core.surfacesFor(registrations, installed, 'dashboard', false).length, 1);

console.log('PASS: plugin surface failure-mark assertions');
