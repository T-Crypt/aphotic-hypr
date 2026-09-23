const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');

function load(relativePath) {
    const context = vm.createContext({});
    vm.runInContext(readFileSync(`${__dirname}/../${relativePath}`, 'utf8'), context);
    return context;
}

const registry = load('Configs/quickshell/aphotic/services/ai/LocalInferenceCore.js');
const mapping = load('Configs/quickshell/aphotic/services/ai/BackendModels.js');
const inference = load('Configs/quickshell/aphotic/services/ai/InferenceCore.js');

let backends = registry.report({}, 'ollama', 'Ollama', [
    { name: 'chat-ready', state: 'ready' },
    { name: 'chat-starting', state: 'starting' },
    { name: 'chat-loading', state: 'loading' },
    { name: 'embed-ready', state: 'ready', embedding: true },
    { name: 'chat-stopping', state: 'stopping' },
], 10);
backends = registry.report(backends, 'lm-studio', 'LM Studio', [
    { name: 'studio-loaded', state: 'loaded' },
    { name: 'studio-empty' },
], 20);
assert.deepEqual(Array.from(registry.activeModels(backends), model => `${model.owner}:${model.name}`), [
    'ollama:chat-ready',
    'ollama:chat-starting',
    'ollama:chat-loading',
    'lm-studio:studio-loaded',
    'lm-studio:studio-empty',
]);
assert.equal(backends.ollama.at, 10);
assert.equal(backends['lm-studio'].label, 'LM Studio');
const cleared = registry.report(backends, 'ollama', 'Ollama', [], 30);
assert.equal(cleared.ollama.models.length, 0);
assert.equal(registry.activeModels(cleared).some(model => model.owner === 'ollama'), false);

assert.equal(mapping.ollamaEmbedding({ capabilities: ['embedding'] }), true);
assert.equal(mapping.ollamaEmbedding({ capabilities: ['embedding', 'completion'] }), false);
assert.equal(mapping.ollamaEmbedding({ capabilities: ['completion'] }), false);
const ollama = mapping.ollamaRunningModels({ models: [
    { name: 'one', size: 20, size_vram: 10 },
    { name: 'two', size: 30, size_vram: 25 },
] }, { two: true });
assert.equal(ollama[0].embedding, false);
assert.equal(ollama[1].embedding, true);

const fixture = JSON.parse(readFileSync(`${__dirname}/fixtures/lm_studio_models.json`, 'utf8'));
const studio = mapping.lmStudioModels(fixture);
assert.deepEqual(Array.from(studio, model => `${model.name}:${model.embedding}:${model.state}`), [
    'chat-model:false:ready',
    'embed-model:true:ready',
]);

assert.equal(inference.eligibleClaims([
    { id: 'ollama-only', owner: 'ollama', resource: 'gpu-vram', amount: 4096 },
], { ollama: backends.ollama }).length, 1);
assert.equal(inference.eligibleClaims([
    { id: 'studio-only', owner: 'lm-studio', resource: 'memory', amount: 4096 },
], { 'lm-studio': backends['lm-studio'] }).length, 1);
assert.equal(inference.eligibleClaims([
    { id: 'unknown', owner: 'other', resource: 'gpu-vram', amount: 4096 },
], backends).length, 0);
assert.equal(inference.eligibilityKeys([
    { owner: 'ollama', label: 'Ollama', name: 'ollama-only' },
], [], { ollama: {} }).length, 1);
assert.equal(inference.eligibilityKeys([
    { owner: 'lm-studio', label: 'LM Studio', name: 'studio-only' },
], [], { 'lm-studio': {} }).length, 1);

console.log('Local inference registry and backend mappings passed');
