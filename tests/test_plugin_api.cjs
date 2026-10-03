const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ctx = vm.createContext({});
vm.runInContext(readFileSync(__dirname + '/../Configs/quickshell/aphotic/services/PluginApiCore.js', 'utf8'), ctx);
const A = ctx;
const plain = v => JSON.parse(JSON.stringify(v));

// Grants: declared ∩ known, only while enabled, only for a version this build speaks.
const api = {version: 1, uses: ['resource.observe', 'context.observe', 'bogus.thing']};
assert.deepEqual(plain(A.grants(api, true)), ['context.observe', 'resource.observe']);
assert.deepEqual(plain(A.grants(api, false)), []);
assert.deepEqual(plain(A.grants(null, true)), []);
assert.deepEqual(plain(A.grants({version: 3, uses: ['context.observe']}, true)), []);
assert.deepEqual(plain(A.grants({version: 0, uses: ['context.observe']}, true)), []);
assert.deepEqual(plain(A.grants({version: '1', uses: ['context.observe']}, true)), []);
assert.deepEqual(plain(A.grants({version: 1}, true)), []);

// Surface names are namespaced per plugin and validated.
assert.equal(A.surfaceName('pets', 'panel'), 'plugin:pets/panel');
assert.equal(A.surfaceName('pets', 'launcher'), 'plugin:pets/launcher');
assert.equal(A.surfaceName('pets', 'Bad Name'), '');
assert.equal(A.surfaceName('pets', ''), '');
assert.equal(A.surfaceName('', 'panel'), '');
assert.deepEqual(plain(A.parseSurface('plugin:pets/panel')), {plugin: 'pets', local: 'panel'});
assert.equal(A.parseSurface('launcher'), null);
assert.equal(A.parseSurface('plugin:pets/../x'), null);

// A namespaced plugin surface takes part in surface policy once declared.
vm.runInContext(readFileSync(__dirname + '/../Configs/quickshell/aphotic/services/SurfacePolicy.js', 'utf8'), ctx);
const extra = {'plugin:pets/panel': {role: 'primary'}};
const t = ctx.transition(['launcher'], 'plugin:pets/panel', true, extra);
assert.deepEqual(plain(t.close), ['launcher']);
assert.equal(ctx.focusOwner(plain(t.stack), '', extra), 'plugin:pets/panel');

// Context suggestions are rate-limited per plugin.
assert.equal(A.mayRequest(0, 1000), true);
assert.equal(A.mayRequest(1000, 1000 + A.REQUEST_INTERVAL_MS - 1), false);
assert.equal(A.mayRequest(1000, 1000 + A.REQUEST_INTERVAL_MS), true);

assert.deepEqual(plain(A.grants({version:1, uses:['sonar.register']}, true)), []);
assert.deepEqual(plain(A.grants({version:2, uses:['sonar.register']}, true)), ['sonar.register']);
assert.deepEqual(plain(A.grants({version:1.5, uses:['context.observe']}, true)), []);

console.log('Plugin API core: passed');
