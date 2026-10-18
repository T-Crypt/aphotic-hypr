// The HTTP engine adapter's parsing: model lists, process picks, ports.
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');

const core = vm.createContext({});
vm.runInContext(readFileSync(`${__dirname}/../Configs/quickshell/aphotic/services/ai/EngineHttpCore.js`, 'utf8'), core);
const plain = v => JSON.parse(JSON.stringify(v));

assert.deepEqual(plain(core.parseModels('{"object":"list","data":[{"id":"a"},{"id":"b","status":{"value":"loaded"}},{"id":"c","status":{"value":"unloaded"}},{"id":""}]}')),
    [{ name: 'a', state: 'ready' }, { name: 'b', state: 'ready' }, { name: 'c', state: 'unloaded' }]);
assert.equal(core.parseModels('<html>'), null);
assert.equal(core.parseModels('{"error":"no"}'), null);

const procs = plain(core.parseProcesses('12 python -m vllm serve x --port 8000\n13 python -m vllm serve y --port=8001\n'));
assert.equal(procs.length, 2);
assert.equal(core.portOf(procs[0].cmdline, '--port'), 8000);
assert.equal(core.portOf(procs[1].cmdline, '--port'), 8001);
assert.equal(core.pickProcess(procs, 8001, '--port').pid, 13);
assert.equal(core.pickProcess(procs, 0, '--port'), null);
assert.equal(core.pickProcess([procs[0]], 0, '--port').pid, 12);

assert.equal(core.joinUrl('http://h:1/', '/v1/models'), 'http://h:1/v1/models');
assert.equal(core.hostPort('http://127.0.0.1:8080'), 8080);
assert.equal(core.hostPort('http://host/'), 0);

const desc = vm.createContext({});
vm.runInContext(readFileSync(`${__dirname}/../Configs/quickshell/aphotic/services/ai/EngineDescriptorCore.js`, 'utf8'), desc);
const fromProcess = desc.normalize({ id: 'x', protocol: 'openai-models', endpoint: '/v1/models', process: 'x-serve', port_flag: '--port' }, 'drop-in', 'x.toml');
assert.ok(fromProcess.descriptor, fromProcess.warnings.join());
const noHost = desc.normalize({ id: 'y', protocol: 'openai-models', endpoint: '/v1/models', process: 'y-serve' }, 'drop-in', 'y.toml');
assert.equal(noHost.descriptor, null);

console.log('ok engine http core');
