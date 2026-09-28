// services/VpnCore.js: the aggregator Vpn.qml applies to `aphotic vpn
// list --json`, plus the QML wiring that feeds it.
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');

const services = `${__dirname}/../Configs/quickshell/aphotic/services`;
const core = vm.createContext({});
vm.runInContext(readFileSync(`${services}/VpnCore.js`, 'utf8'), core);
const plain = v => JSON.parse(JSON.stringify(v));

const listed = JSON.stringify({ providers: [
    { id: 'openvpn', label: 'OpenVPN profile', available: true,
      connections: [{ id: 'profile', name: 'lab.ovpn', active: false, detail: '' }] },
    { id: 'tailscale', label: 'Tailscale', available: true,
      connections: [{ id: 'tailnet', name: 'example.ts.net', active: true, detail: '100.64.0.1' }, { id: '' }, null] },
    { id: 'mullvad', label: 'Mullvad', available: false,
      connections: [{ id: 'se-got', active: true }] },
    { label: 'no id' },
    null
] });

const providers = plain(core.parse(listed));
assert.deepEqual(providers.map(p => p.id), ['openvpn', 'tailscale', 'mullvad']);
assert.deepEqual(providers[1].connections, [{
    provider: 'tailscale', providerLabel: 'Tailscale', id: 'tailnet',
    name: 'example.ts.net', active: true, detail: '100.64.0.1'
}]);

// Unavailable providers never count, even if they report an active row.
assert.deepEqual(plain(core.connections(providers)).map(c => `${c.provider}/${c.id}`),
    ['openvpn/profile', 'tailscale/tailnet']);
assert.deepEqual(plain(core.active(providers)).map(c => c.id), ['tailnet']);

const status = plain(core.status(providers));
assert.equal(status.connected, true);
assert.equal(status.count, 1);
assert.equal(status.primary.name, 'example.ts.net');
assert.equal(status.available, true);

// Bad input degrades to "nothing", never throws.
for (const bad of ['', 'not json', 'null', '{}', '{"providers":"x"}', '[]'])
    assert.deepEqual(plain(core.parse(bad)), [], bad);
assert.deepEqual(plain(core.status([])), { connected: false, count: 0, primary: null, available: false });

// Label and name fall back to ids.
const bare = plain(core.parse('{"providers":[{"id":"x","available":true,"connections":[{"id":"c"}]}]}'));
assert.equal(bare[0].label, 'x');
assert.equal(bare[0].connections[0].name, 'c');
assert.equal(bare[0].connections[0].active, false);

// Vpn.qml reads the contract through the core, with no timer.
const qml = readFileSync(`${services}/Vpn.qml`, 'utf8').replace(/\/\/.*$/gm, '');
assert.match(qml, /import "VpnCore\.js" as Core/);
assert.match(qml, /command: \["aphotic", "vpn", "list", "--json"\]/);
assert.match(qml, /root\.providers = Core\.parse\(text\)/);
assert.match(qml, /\["aphotic", "vpn", action, "--provider", provider\]/);
for (const fn of ['refresh', 'list', 'connectProvider', 'disconnectProvider'])
    assert.match(qml, new RegExp(`function ${fn}\\(`), fn);
assert.doesNotMatch(qml, /^\s*Timer\s*\{/m);

console.log('PASS: VPN provider aggregator');
