const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');

const context = vm.createContext({});
vm.runInContext(readFileSync(`${__dirname}/../Configs/quickshell/aphotic/services/ai/LlamaCppCore.js`, 'utf8'), context);

assert.deepEqual({ ...context.parseCommand('llama-server -m /models/chat.gguf') }, {
    host: '127.0.0.1',
    port: 8080,
    embedding: false,
    alias: '',
    model: 'chat',
});
assert.deepEqual({ ...context.parseCommand('llama-server --host 0.0.0.0 --port 8099 --embedding --alias coder -m /models/ignored.gguf') }, {
    host: '127.0.0.1',
    port: 8099,
    embedding: true,
    alias: 'coder',
    model: 'ignored',
});
assert.deepEqual({ ...context.parseCommand('llama-server --host=localhost --port=9000 --embeddings --model="/models/Model One.GGUF"') }, {
    host: 'localhost',
    port: 9000,
    embedding: true,
    alias: '',
    model: 'Model One',
});
assert.equal(context.parseCommand('llama-server --reranking').embedding, true);
assert.equal(context.managedParent('llama-swap'), true);
assert.equal(context.managedParent('ollama'), true);
assert.equal(context.managedParent('ollama runner'), true);
assert.equal(context.managedParent('systemd'), false);
assert.deepEqual({ ...context.parseProcessLine('123 systemd llama-server --port 8099') }, {
    pid: 123,
    parentComm: 'systemd',
    cmdline: 'llama-server --port 8099',
});
assert.equal(context.parseProcessLine('not a process'), null);
assert.equal(context.fallbackName({ alias: 'named', model: 'file' }), 'named');
assert.equal(context.fallbackName({ alias: '', model: 'file' }), 'file');
assert.equal(context.fallbackName({ alias: '', model: '', port: 9010 }), 'llama-server:9010');
assert.equal(context.isLoopbackHost('127.0.0.1'), true);
assert.equal(context.isLoopbackHost('::1'), true);
assert.equal(context.isLoopbackHost('192.168.1.5'), false);

console.log('llama.cpp command and process parsing passed');
