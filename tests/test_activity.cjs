const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ctx = vm.createContext({});
vm.runInContext(readFileSync(__dirname + '/../Configs/quickshell/aphotic/services/ActivityCore.js', 'utf8'), ctx);
const A = ctx;
const plain = v => JSON.parse(JSON.stringify(v));

// Nothing loaded, nothing reported.
assert.deepEqual(plain(A.summarize([])), {probes: [], active: 0, idle: 0, wakeupsPerMinute: 0});

const s = plain(A.summarize([
    {name: 'weather', kind: 'network', active: true, interval: 1200000},
    {name: 'system.base', kind: 'file', active: true, interval: 2000},
    {name: 'lock.reconcile', kind: 'poll', active: false, interval: 5000},
    // Per-screen modules report once per instance.
    {name: 'bar.capsule-media', kind: 'render', active: true, interval: 1000},
    {name: 'bar.capsule-media', kind: 'render', active: false, interval: 1000},
    {name: '', active: true, interval: 1},
    null,
]));
assert.deepEqual(s.probes.map(p => p.name), ['bar.capsule-media', 'lock.reconcile', 'system.base', 'weather']);
assert.equal(s.active, 3);
assert.equal(s.idle, 1);
const media = s.probes[0];
assert.equal(media.instances, 2);
assert.equal(media.active, 1);
assert.equal(media.wakeupsPerMinute, 60);
// Idle probes still say what they would cost, and add nothing to the total.
assert.equal(s.probes[1].interval, 5000);
assert.equal(s.probes[1].wakeupsPerMinute, 0);
// 60 (media) + 30 (base) + 0.05 (weather), rounded to one decimal.
assert.equal(s.wakeupsPerMinute, 90.1);
// A zero interval never divides.
assert.equal(A.wakeups(0), 0);

console.log('Activity: passed');
