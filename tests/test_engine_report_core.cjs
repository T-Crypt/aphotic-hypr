const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const core = vm.createContext({});
vm.runInContext(readFileSync(`${__dirname}/../Configs/quickshell/aphotic/services/ai/EngineReportCore.js`, 'utf8'), core);

const gateway = core.parse(JSON.stringify({
    protocol: 'aphotic-engine/1',
    engine: { id: 'gate', label: 'Gate' },
    engines: [
        { id: 'expert', label: 'Expert Engine', state: 'active', cpuPercent: 121.37, threads: 20,
          models: [{ name: 'big-moe', state: 'ready', pid: 532015, vramMiB: 23896.4, ramMiB: 46012 }] },
        { id: 'Bad Id', models: [] },
        { id: 'expert', models: [] },
        { id: 'painter', models: [{ name: '', pid: 1 }, { name: 'sdxl', pid: -4, vramMiB: 'x' }] }
    ]
}), 'gate');
assert.equal(gateway.ok, true);
assert.deepEqual(JSON.parse(JSON.stringify(gateway.engines)), [
    { id: 'expert', label: 'Expert Engine', state: 'active', cpuPercent: 121.4, threads: 20,
      models: [{ name: 'big-moe', state: 'ready', embedding: false, pid: 532015, vramMiB: 23896, ramMiB: 46012 }] },
    { id: 'painter', label: 'painter', state: 'ready', cpuPercent: null, threads: null,
      models: [{ name: 'sdxl', state: '', embedding: false, pid: 0, vramMiB: 0, ramMiB: 0 }] }
]);

const single = core.parse(JSON.stringify({
    protocol: 'aphotic-engine/1', engine: { id: 'vega', label: 'Vega' },
    models: [{ name: 'vega-8b', state: 'ready', pid: 4213, vramMiB: 9120 }]
}), 'vega');
assert.equal(single.engines.length, 1);
assert.equal(single.engines[0].id, 'vega');
assert.equal(single.engines[0].label, 'Vega');
assert.equal(single.engines[0].models[0].vramMiB, 9120);

assert.equal(core.parse('{"protocol":"aphotic-engine/9"}', 'x').ok, false);
assert.equal(core.parse('nope', 'x').engines.length, 0);
assert.equal(core.parse('null', 'x').ok, false);

const taken = id => id === 'llama-swap';
const engines = [{ id: 'llama-swap' }, { id: 'expert' }];
assert.deepEqual(core.claimable(engines, {}, taken).map(e => e.id), ['expert']);
assert.deepEqual(core.claimable(engines, { 'llama-swap': true }, taken).map(e => e.id), ['llama-swap', 'expert']);

console.log('PASS: engine report core');
