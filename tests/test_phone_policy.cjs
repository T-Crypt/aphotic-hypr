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

const phone = load('Configs/quickshell/aphotic/services/PhonePolicy.js');

// vm.runInContext results carry the sandbox's own prototypes, which
// assert's strict comparison rejects; a JSON round-trip strips them.
function plain(value) {
    return JSON.parse(JSON.stringify(value));
}

function devices(text) {
    return plain(phone.parseDevices(text));
}

const TEST_PHONE = 'aaaaaaaa_bbbb_cccc_dddd_eeeeffff0000';

// The summary line is not a device, however many it claims.
assert.deepEqual(devices('0 devices found\n'), []);
assert.deepEqual(devices('1 device found\n'), []);

// One reachable device, in the shape `kdeconnect-cli --list-available
// --id-name-only` printed on the machine this was planned on.
assert.deepEqual(
    devices(`${TEST_PHONE} Test Phone\n`),
    [{ id: TEST_PHONE, label: 'Test Phone' }],
);

// A device the daemon never named carries its own id as the label.
assert.deepEqual(
    devices(`${TEST_PHONE}\n`),
    [{ id: TEST_PHONE, label: TEST_PHONE }],
);

// Noise around a device line leaves exactly the device.
assert.deepEqual(
    devices(`no daemon running\n\n${TEST_PHONE} Test Phone\n2 devices found\n`),
    [{ id: TEST_PHONE, label: 'Test Phone' }],
);

// `--list-devices` prints a different shape. Dropping these is the
// tripwire for someone swapping the command without swapping the parser.
assert.deepEqual(devices(`- Test Phone: ${TEST_PHONE} (paired and reachable)\n`), []);
assert.deepEqual(devices(`- Test Phone: ${TEST_PHONE} (paired)\n`), []);

// Two devices stay in the order the command printed them.
const SECOND = '11111111_2222_3333_4444_555566667777';
assert.deepEqual(
    devices(`${TEST_PHONE} Test Phone\n${SECOND} Second Phone\n`),
    [{ id: TEST_PHONE, label: 'Test Phone' }, { id: SECOND, label: 'Second Phone' }],
);

// Nothing at all, and nothing that arrives as an empty string.
assert.deepEqual(devices(''), []);
assert.deepEqual(devices(null), []);

console.log('Phone policy: passed');
