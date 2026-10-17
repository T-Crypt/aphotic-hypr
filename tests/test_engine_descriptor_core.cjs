// tests/test_engine_descriptor_core.cjs
//
// EngineDescriptorCore.js is plain functions QML loads at runtime, so the
// parser, the validator and the precedence rule run under node -- tests
// run every tests/*.cjs through tests/test_flow_js.sh, and this one
// directly with `node tests/test_engine_descriptor_core.cjs`. Nothing here
// touches Qt: the module hands back a descriptor and a list of warnings,
// and a hostile manifest value stays text.
const assert = require('node:assert');
const { existsSync, readFileSync } = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');

function load(relativePath) {
    const context = vm.createContext({});
    vm.runInContext(readFileSync(`${__dirname}/../${relativePath}`, 'utf8'), context);
    return context;
}

const core = load('Configs/quickshell/aphotic/services/ai/EngineDescriptorCore.js');
const marker = path.join(os.tmpdir(), `aphotic-engine-core-${process.pid}`);

// --- the flat TOML shape ------------------------------------------------

const LLAMA_SWAP = `
# a comment
[engine]
id = "llama-swap"
label = "llama-swap"
protocol = "llama-swap"
host_key = "llamaSwapHost"
endpoint = "/running"
process = "llama-server"
port_flag = "--port"
manages = ["llama-swap"]
capabilities = ["models", "claims", "stats", "unload"]

[engine.control]
unload = "http POST /api/models/unload/{model}"

[engine.stats]
endpoint = "/slots"
interval = 1000
`;

const parsed = core.parse(LLAMA_SWAP);
assert.equal(parsed.id, 'llama-swap');
assert.equal(parsed.host_key, 'llamaSwapHost');
assert.deepEqual(parsed.manages, ['llama-swap']);
assert.deepEqual(parsed.capabilities, ['models', 'claims', 'stats', 'unload']);
assert.equal(parsed.control.unload, 'http POST /api/models/unload/{model}');
assert.equal(parsed.stats.endpoint, '/slots');
assert.equal(parsed.stats.interval, 1000);

// No [engine] section is no engine: an empty file and a plugin manifest
// that declares none both read null rather than an empty descriptor.
assert.equal(core.parse(''), null);
assert.equal(core.parse('# only a comment\n'), null);
assert.equal(core.parse('[plugin]\nname = "x"\ncapabilities = []\n'), null);

// --- verb() and shell syntax -------------------------------------------

assert.deepEqual(core.verb('http POST /api/x'), { kind: 'http', method: 'POST', path: '/api/x' });
assert.deepEqual(core.verb('run /usr/bin/vega serve'), { kind: 'run', command: '/usr/bin/vega serve' });
assert.equal(core.verb('POST /api/x'), null);
assert.equal(core.verb('http post /api/x'), null, 'a method is upper case');
assert.equal(core.verb('run '), null);
assert.equal(core.verb('curl /api/x'), null);

assert.ok(core.hasShellSyntax('run foo; touch ' + marker));
assert.ok(core.hasShellSyntax('run $(touch ' + marker + ')'));
assert.ok(core.hasShellSyntax('run a | b'));
assert.ok(!core.hasShellSyntax('run /usr/bin/vega serve'));
assert.ok(!core.hasShellSyntax('http POST /api/unload/{model}'), '{model} is a placeholder, not syntax');

// --- normalize: the accepted shape -------------------------------------

const vega = {
    id: 'vega', protocol: 'engine-report', endpoint: '/.aphotic/engine.json',
    host_key: 'vegaHost', default_host: 'http://127.0.0.1:9911', process: 'vega-server',
    capabilities: ['models', 'claims', 'start', 'stop'],
    control: { start: 'run /usr/bin/vega serve', stop: 'run /usr/bin/vega stop' },
    stats: {}
};
const vegaResult = core.normalize(vega, 'plugin', 'vega-stack');
assert.deepEqual(vegaResult.warnings, []);
const vegaDescriptor = vegaResult.descriptor;
assert.equal(vegaDescriptor.id, 'vega');
assert.equal(vegaDescriptor.label, 'vega', 'a label falls back to the id');
assert.equal(vegaDescriptor.hostKey, 'vegaHost');
assert.equal(vegaDescriptor.defaultHost, 'http://127.0.0.1:9911');
assert.equal(vegaDescriptor.portFlag, '--port', 'a process with no port_flag defaults to --port');
assert.deepEqual(vegaDescriptor.manages, ['vega'], 'an empty manages falls back to the id');
assert.deepEqual(vegaDescriptor.capabilities, ['models', 'claims', 'start', 'stop']);
assert.equal(vegaDescriptor.source, 'plugin');
assert.equal(vegaDescriptor.sourceName, 'vega-stack');

// --- normalize: rejections ---------------------------------------------

function rejected(raw, source, sourceName) {
    const out = core.normalize(raw, source, sourceName);
    assert.equal(out.descriptor, null, `expected ${JSON.stringify(raw)} to be rejected`);
    return out.warnings;
}
const base = { id: 'x', protocol: 'engine-report', endpoint: '/x', default_host: 'http://h', capabilities: ['models'] };

assert.deepEqual(rejected({ protocol: 'engine-report', endpoint: '/x', default_host: 'http://h' }, 'drop-in', 'bad.toml'),
    ['aphotic engine: bad.toml skipped, it has no id']);
assert.deepEqual(rejected(Object.assign({}, base, { id: 'Bad' }), 'drop-in', 'bad.toml'),
    ["aphotic engine: 'Bad' skipped, an engine id must be lowercase, start with a letter, and use only [a-z0-9-]"]);
assert.deepEqual(rejected(Object.assign({}, base, { protocol: '' }), 'drop-in', 'x.toml'),
    ["aphotic engine: 'x' skipped, no protocol"]);
assert.deepEqual(rejected(Object.assign({}, base, { protocol: 'comfyui-ws' }), 'drop-in', 'x.toml'),
    ["aphotic engine: 'x' skipped, protocol 'comfyui-ws' is not one this shell speaks"]);
assert.deepEqual(rejected(Object.assign({}, base, { endpoint: '' }), 'drop-in', 'x.toml'),
    ["aphotic engine: 'x' skipped, no endpoint"]);
assert.deepEqual(rejected({ id: 'x', protocol: 'engine-report', endpoint: '/x', capabilities: ['models'] }, 'drop-in', 'x.toml'),
    ["aphotic engine: 'x' skipped, it has no host to ask"]);

// An absolute endpoint needs no host: that is the standalone case.
const absolute = core.normalize({ id: 'x', protocol: 'openai-models', endpoint: 'http://127.0.0.1:9/v1/models', capabilities: ['models'] }, 'drop-in', 'x.toml');
assert.equal(absolute.descriptor.endpoint, 'http://127.0.0.1:9/v1/models');

// --- normalize: accepted with the named part dropped -------------------

function dropped(raw, source, sourceName) {
    const out = core.normalize(Object.assign({}, base, raw), source || 'drop-in', sourceName || 'x.toml');
    assert.ok(out.descriptor, `expected ${JSON.stringify(raw)} to survive`);
    return out;
}

let d = dropped({ capabilities: ['models', 'bogus'] });
assert.deepEqual(d.descriptor.capabilities, ['models']);
assert.deepEqual(d.warnings, ["aphotic engine: 'x' ignored capability 'bogus', which isn't one this shell speaks"]);

d = dropped({ capabilities: ['models', 'start'] });
assert.deepEqual(d.descriptor.capabilities, ['models']);
assert.deepEqual(d.warnings, ["aphotic engine: 'x' ignored capability 'start', nothing in the descriptor provides it"]);

d = dropped({ capabilities: ['stats'], stats: {} });
assert.deepEqual(d.descriptor.capabilities, []);
assert.deepEqual(d.warnings, ["aphotic engine: 'x' ignored capability 'stats', nothing in the descriptor provides it"]);

d = dropped({ capabilities: ['stats'], stats: { endpoint: '/slots', interval: 1000 } });
assert.deepEqual(d.descriptor.capabilities, ['stats']);
assert.equal(d.descriptor.stats.interval, 1000);

d = dropped({ capabilities: ['start'], control: { start: 'curl /x' } });
assert.deepEqual(d.warnings, [
    "aphotic engine: 'x' ignored control verb 'start', it is neither 'http <METHOD> <path>' nor 'run <command>'",
    "aphotic engine: 'x' ignored capability 'start', nothing in the descriptor provides it"]);

d = dropped({ capabilities: ['start'], control: { start: 'run foo; touch ' + marker } });
assert.deepEqual(d.warnings, [
    "aphotic engine: 'x' ignored control verb 'start', it carries shell syntax",
    "aphotic engine: 'x' ignored capability 'start', nothing in the descriptor provides it"]);
assert.deepEqual(d.descriptor.capabilities, [], 'a shell-syntax verb backs nothing');
assert.ok(!existsSync(marker), 'a verb is never run while parsing');

d = dropped({ capabilities: ['start'], control: { start: 'http POST /load/{model}' } });
assert.deepEqual(d.warnings, [
    "aphotic engine: 'x' ignored control verb 'start', no model is in scope",
    "aphotic engine: 'x' ignored capability 'start', nothing in the descriptor provides it"]);

d = dropped({ host_key: 'bad-key' });
assert.deepEqual(d.warnings, ["aphotic engine: 'x' ignored host key 'bad-key', it is not a settings key name"]);

d = dropped({ key: '1bad' });
assert.deepEqual(d.warnings, ["aphotic engine: 'x' ignored host key '1bad', it is not a settings key name"]);

// --- progress -----------------------------------------------------------

d = dropped({ capabilities: ['progress'], progress: { protocol: 'engine-progress-report', file: '~/p.json', stale_after: 15000, rate_unit: 'steps/s' } });
assert.deepEqual(d.descriptor.capabilities, ['progress']);
assert.equal(d.descriptor.progress.staleAfter, 15000);
assert.equal(d.descriptor.progress.rateUnit, 'steps/s');

d = dropped({ capabilities: ['progress'], progress: { protocol: 'engine-progress-report', file: '' } });
assert.deepEqual(d.warnings, [
    "aphotic engine: 'x' ignored its progress source, it names no file",
    "aphotic engine: 'x' ignored capability 'progress', nothing in the descriptor provides it"]);
assert.deepEqual(d.descriptor.capabilities, []);

d = dropped({ capabilities: ['progress'], progress: { protocol: 'nonsense', file: '~/p.json' } });
assert.deepEqual(d.warnings, [
    "aphotic engine: 'x' ignored its progress source, protocol 'nonsense' is not one this shell speaks",
    "aphotic engine: 'x' ignored capability 'progress', nothing in the descriptor provides it"]);

// --- gateway ------------------------------------------------------------

d = dropped({ gateway: 'llama-swap', gateway_entry: 'comfyui', capabilities: ['claims'] });
assert.equal(d.descriptor.gateway, 'llama-swap');
assert.equal(d.descriptor.gatewayEntry, 'comfyui');
assert.deepEqual(d.warnings, []);

assert.deepEqual(rejected(Object.assign({}, base, { gateway: 'llama-swap', control: { start: 'run x' } }), 'drop-in', 'x.toml'),
    ["aphotic engine: 'x' skipped, it declares control verbs and a gateway, and the gateway owns its lifecycle"]);

d = dropped({ gateway_entry: 'comfyui' });
assert.equal(d.descriptor.gatewayEntry, '');
assert.deepEqual(d.warnings, ["aphotic engine: 'x' ignored its gateway '', no such engine"]);

// --- a hostile value stays text ----------------------------------------

const hostileLabel = 'a$(touch ' + marker + ')';
const hostile = core.normalize({ id: 'x', protocol: 'engine-report', endpoint: '/x', default_host: 'http://h',
    label: hostileLabel, capabilities: ['models'] }, 'drop-in', 'x.toml');
assert.equal(hostile.descriptor.label, hostileLabel, 'a label is data, not syntax');
assert.ok(!existsSync(marker), 'nothing ran while normalizing');

// --- resolve: section 3 precedence -------------------------------------

function descriptor(id, source, sourceName, extra) {
    return Object.assign({ id: id, protocol: 'llama-swap', endpoint: '/running', host_key: 'h', capabilities: ['models'],
        gateway: '', gatewayEntry: '' }, extra || {}, { source: source, sourceName: sourceName || '' });
}

// A drop-in outranks core. Both stay listed, winner first; the loser
// carries the note Settings and `aphotic engine list` show.
let res = core.resolve([
    descriptor('llama-swap', 'drop-in', 'llama-swap.toml'),
    descriptor('llama-swap', 'core', 'llama-swap.toml')
]);
assert.equal(res.descriptors.length, 2);
assert.equal(res.descriptors[0].source, 'drop-in');
assert.equal(res.descriptors[0].overriddenBy, '');
assert.equal(res.descriptors[1].source, 'core');
assert.equal(res.descriptors[1].overriddenBy, '~/.config/aphotic/engines/llama-swap.toml');
assert.equal(res.shadowed.length, 1);
assert.equal(res.shadowed[0].source, 'core');
assert.deepEqual(res.warnings, ["aphotic engine: 'llama-swap' from a drop-in shadows core"]);

// A plugin outranks core, and loses to a drop-in.
res = core.resolve([
    descriptor('vega', 'drop-in', 'vega.toml'),
    descriptor('vega', 'plugin', 'vega-stack'),
    descriptor('vega', 'core', 'vega.toml')
]);
assert.equal(res.descriptors.length, 3);
assert.equal(res.descriptors[0].source, 'drop-in');
assert.equal(res.descriptors[1].source, 'plugin');
assert.equal(res.descriptors[1].overriddenBy, '~/.config/aphotic/engines/vega.toml');
assert.deepEqual(res.shadowed.map(s => s.source), ['plugin', 'core']);
assert.deepEqual(res.warnings, [
    "aphotic engine: 'vega' from a drop-in shadows plugin 'vega-stack'",
    "aphotic engine: 'vega' from a drop-in shadows core"
]);

// A tie keeps the first in registry order and drops the rest.
res = core.resolve([
    descriptor('vega', 'plugin', 'alpha'),
    descriptor('vega', 'plugin', 'beta')
]);
assert.equal(res.descriptors.length, 2);
assert.equal(res.descriptors[0].sourceName, 'alpha');
assert.equal(res.descriptors[1].overriddenBy, "plugin 'alpha'");
assert.deepEqual(res.shadowed, [{ id: 'vega', source: 'plugin', sourceName: 'beta' }]);
assert.deepEqual(res.warnings, ["aphotic engine: 'vega' from plugin 'alpha' shadows plugin 'beta'"]);

// A gateway that names nothing in the list is dropped, not fatal.
res = core.resolve([descriptor('comfyui', 'plugin', 'comfyui', { gateway: 'llama-swap', gatewayEntry: 'comfyui' })]);
assert.equal(res.descriptors[0].gateway, '');
assert.equal(res.descriptors[0].gatewayEntry, '');
assert.deepEqual(res.warnings, ["aphotic engine: 'comfyui' ignored its gateway 'llama-swap', no such engine"]);

// And one that names a descriptor in the list survives.
res = core.resolve([
    descriptor('llama-swap', 'core', 'llama-swap.toml', { protocol: 'llama-swap', manages: ['llama-swap'] }),
    descriptor('comfyui', 'plugin', 'comfyui', { gateway: 'llama-swap', gatewayEntry: 'comfyui', protocol: 'engine-report', endpoint: '/system_stats' })
]);
assert.equal(res.descriptors.find(d => d.id === 'comfyui').gateway, 'llama-swap');

console.log('PASS: engine descriptor core assertions');
