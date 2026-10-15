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

const policy = load('Configs/quickshell/aphotic/services/MessagePolicy.js');

// vm.runInContext results carry the sandbox's own prototypes, which
// assert's strict comparison rejects; a JSON round-trip strips them.
function plain(value) {
    return JSON.parse(JSON.stringify(value));
}

const DEVICE = 'aaaaaaaa_bbbb_cccc_dddd_eeeeffff0000';

// The send verb against the stub contract: argv carries --send-sms,
// --destination, and -d with the message, the number, and the device.
assert.deepEqual(
    plain(policy.buildSendArgs(DEVICE, '+15551234567', 'hello')),
    ['--send-sms', 'hello', '--destination', '+15551234567', '-d', DEVICE],
);

// Every blank is a missing address, so every blank sends nothing.
assert.deepEqual(plain(policy.buildSendArgs('', '+15551234567', 'hello')), []);
assert.deepEqual(plain(policy.buildSendArgs(DEVICE, '', 'hello')), []);
assert.deepEqual(plain(policy.buildSendArgs(DEVICE, '+15551234567', '')), []);
assert.deepEqual(plain(policy.buildSendArgs(DEVICE, '+15551234567', '   ')), []);
assert.deepEqual(plain(policy.buildSendArgs(null, null, null)), []);

// The predicate follows the builder.
assert.equal(policy.isSendable(DEVICE, '+15551234567', 'hello'), true);
assert.equal(policy.isSendable(DEVICE, '', 'hello'), false);

// A full triple parses into the thread entry shape.
assert.deepEqual(
    plain(policy.parseIncoming({ deviceId: DEVICE, address: '+15551234567', body: 'hi', timestamp: 1700000000000 })),
    { deviceId: DEVICE, address: '+15551234567', body: 'hi', timestamp: 1700000000000, direction: 'in' },
);

// A missing timestamp stays numeric, never undefined.
assert.deepEqual(
    plain(policy.parseIncoming({ deviceId: DEVICE, address: '+15551234567', body: 'hi' })),
    { deviceId: DEVICE, address: '+15551234567', body: 'hi', timestamp: 0, direction: 'in' },
);

// Short of a full triple, nothing parses.
assert.equal(policy.parseIncoming(null), null);
assert.equal(policy.parseIncoming({}), null);
assert.equal(policy.parseIncoming({ deviceId: DEVICE, address: '', body: 'hi' }), null);
assert.equal(policy.parseIncoming({ deviceId: DEVICE, address: '+15551234567', body: '  ' }), null);

console.log('Phone message policy: passed');
