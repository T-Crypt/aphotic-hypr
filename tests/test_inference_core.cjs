const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');

function load(relativePath) {
    const context = vm.createContext({});
    vm.runInContext(readFileSync(`${__dirname}/../${relativePath}`, 'utf8'), context);
    return context;
}

const inference = load('Configs/quickshell/aphotic/services/ai/InferenceCore.js');
const claims = [
    { id: 'embed', owner: 'llama-swap', resource: 'gpu-vram', amount: 534 },
    { id: 'model', owner: 'llama-swap', resource: 'gpu-vram', amount: 4096 },
    { id: 'other', owner: 'ollama', resource: 'gpu-vram', amount: 8192 },
];
assert.deepEqual(Array.from(inference.eligibleClaims(claims), claim => claim.id), ['model']);
assert.equal(inference.claimSignature(claims), 'model');
assert.equal(inference.claimSignature([{ ...claims[1], amount: 4200 }]), 'model');
assert.equal(inference.claimSignature([{ ...claims[1], id: 'model-2' }]), 'model-2');

const models = [
    { name: 'bge-embed', state: 'running', embedding: true },
    { name: 'CyberTiel', state: 'running' },
    { name: 'Qwen', state: 'loading' },
];
assert.equal(inference.selectModel(models, ''), 'CyberTiel');
assert.equal(inference.selectModel(models, 'Qwen'), 'Qwen');
assert.equal(inference.selectModel([{ name: 'bge-embed', embedding: true }], ''), '');
assert.equal(inference.selectTriggeredModel([
    { label: 'Qwen', claims: [{ resource: 'gpu-vram', amount: 1024 }] },
    { label: 'CyberTiel', claims: [{ resource: 'gpu-vram', amount: 4096 }] },
], [{ name: 'Qwen' }, { name: 'CyberTiel' }], ''), 'CyberTiel');
assert.equal(inference.acceptStatsModel('', 'CyberTiel', false), false);
assert.equal(inference.acceptStatsModel('', 'CyberTiel', true), true);
assert.equal(inference.acceptStatsModel('CyberTiel', 'CyberTiel', false), true);
assert.equal(inference.acceptStatsModel('CyberTiel', 'Qwen', false), false);

let update = inference.updateStats({}, 'CyberTiel', [
    { id: 0, is_processing: true, n_ctx: 32768, next_token: [{ n_decoded: 100 }] },
], 1000);
assert.equal(update.current.generating, true);
assert.equal(update.current.nDecoded, 100);
assert.equal(update.current.nCtx, 32768);
assert.equal(update.current.tokensPerSecond, 0);

update = inference.updateStats(update.samples, 'CyberTiel', [
    { id: 0, is_processing: true, n_ctx: 32768, next_token: [{ n_decoded: 132 }] },
], 2000);
assert.equal(update.current.tokensPerSecond, 32);

update = inference.updateStats(update.samples, 'CyberTiel', [
    { id: 0, is_processing: false, n_ctx: 32768, next_token: [{ n_decoded: 132 }] },
], 3000);
assert.equal(update.current.generating, false);
assert.equal(update.current.tokensPerSecond, 32);

const policy = load('Configs/quickshell/aphotic/services/profile/ResourcePolicy.js');
const incumbent = policy.incumbent([
    { id: 'shell', owner: 'quickshell', amount: 318, priority: 'background' },
    { id: 'model', owner: 'llama-swap', amount: 22000, priority: 'foreground' },
], owner => owner === 'llama-swap');
assert.equal(incumbent.id, 'model');

const registry = load('Configs/quickshell/aphotic/services/PluginRegistryCore.js');
const surfaces = [
    { plugin: 'one', surface: 'notch' },
    { plugin: 'two', surface: 'notch' },
    { plugin: 'one', surface: 'dashboard' },
];
const installed = { one: { shelter: 'unload' }, two: { shelter: '' } };
assert.deepEqual(Array.from(registry.surfacesFor(surfaces, installed, 'notch', true), s => s.plugin), ['two']);
assert.deepEqual(Array.from(registry.surfacesFor(surfaces, installed, 'notch', false), s => s.plugin), ['one', 'two']);

const snapshot = load('Configs/quickshell/aphotic/services/profile/StateSnapshotCore.js');
const render = snapshot.parseRender([
    JSON.stringify({ int: 1 }),
    JSON.stringify({ int: 0 }),
    JSON.stringify({ int: 1 }),
].join('\n'));
assert.deepEqual(JSON.parse(JSON.stringify(render)), { blur: 1, shadow: 0, animations: 1 });
const boolRender = snapshot.parseRender([
    JSON.stringify({ bool: true }),
    JSON.stringify({ bool: false }),
    JSON.stringify({ bool: true }),
].join('\n'));
assert.deepEqual(JSON.parse(JSON.stringify(boolRender)), { blur: 1, shadow: 0, animations: 1 });
assert.equal(snapshot.renderBatch(render, { blur: 1, shadow: 0, animations: 1 }), '');
assert.equal(
    snapshot.renderBatch(render, { blur: 0, shadow: 0, animations: 1 }),
    'keyword decoration:blur:enabled 1 ; keyword decoration:shadow:enabled 0 ; keyword animations:enabled 1',
);

console.log('Inference core: 28 assertions passed');

// A resident model names the mode even before /running has been polled.
assert.equal(
    inference.selectTriggeredModel([{ label: "CyberTiel", claims: [{ resource: "gpu-vram", amount: 22978 }] }], [], ""),
    "CyberTiel");

// Before Quickshell knows the parser, the render command must still work.
{
    const cmd = snapshot.renderCommand({ blur: 0, shadow: 0, animations: 0 }, { blur: 1, shadow: 1, animations: 1 }, false);
    assert.equal(cmd[0], "sh");
    assert.match(cmd[2], /hyprctl eval 'hl\.config\(.*enabled = false.*\)' \| grep -qx ok \|\| hyprctl --batch/);
    assert.equal(snapshot.renderCommand({ blur: 1, shadow: 1, animations: 1 }, { blur: 1, shadow: 1, animations: 1 }, true), null);
}

// A chat model counts while it is still loading; embeddings never do.
assert.deepEqual(inference.runningChatModels([
    { name: "CyberTiel", state: "starting" },
    { name: "my-embedder", state: "ready", embedding: true },
    { name: "Gemma-4-26B", state: "stopping" }
]), ["CyberTiel"]);
