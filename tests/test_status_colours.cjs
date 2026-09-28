// services/StatusColours.js: error/warning/success keep a recognisable hue
// and stay readable whatever ANSI slot a wallpaper hands them.
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');

const services = `${__dirname}/../Configs/quickshell/aphotic/services`;
const C = vm.createContext({});
vm.runInContext(readFileSync(`${services}/StatusColours.js`, 'utf8') + '\nthis.SPECS = SPECS; this.MIN_CONTRAST = MIN_CONTRAST;', C);

const hsl = hex => C.rgbToHsl(C.parseHex(hex));
const ratio = (a, b) => C.contrast(C.parseHex(a), C.parseHex(b));

// Seeds a wallpaper can produce for any slot: on-hue, off-hue, grey,
// black, white, pastel, neon.
const seeds = ['#bf616a', '#ff00ff', '#3050ff', '#00ffcc', '#808080', '#000000', '#ffffff',
    '#f5d0e0', '#39ff14', '#b77142', '#8fbcbb', '#2e3440', '#ebcb8b', '#a3be8c', '#5e81ac',
    '#ff5555', '#50fa7b', '#f1fa8c', 'garbage', ''];
// Surface pairs Colours.qml passes: surfaceContainer and surfaceContainerHigh.
const surfaces = [['#000000', '#1f1f1f'], ['#0b0e14', '#1d222c'], ['#1e1e2e', '#313244'],
    ['#2e1a1a', '#452a2a'], ['#0a2a12', '#1c3d24'], ['#eff1f5', '#dce0e8']];

for (const kind of ['error', 'warning', 'success']) {
    const spec = C.SPECS[kind];
    for (const seed of seeds) {
        for (const pair of surfaces) {
            const out = C.derive(kind, seed, pair);
            assert.match(out, /^#[0-9a-f]{6}$/, `${kind} ${seed}`);
            const [h, s] = hsl(out);
            const off = Math.abs(C.hueDelta(h, spec.center));
            assert.ok(off <= spec.spread + 1.5, `${kind} from ${seed} on ${pair}: hue ${h.toFixed(1)} is ${off.toFixed(1)} off ${spec.center}`);
            assert.ok(s >= spec.minSat - 0.03, `${kind} from ${seed}: saturation ${s.toFixed(2)} under ${spec.minSat}`);
            for (const surface of pair)
                assert.ok(ratio(out, surface) >= C.MIN_CONTRAST - 0.05,
                    `${kind} from ${seed}: ${out} on ${surface} is ${ratio(out, surface).toFixed(2)}:1`);
        }
    }
}

// The bands never touch, so the three stay distinguishable on any wallpaper.
const band = k => [C.SPECS[k].center - C.SPECS[k].spread, C.SPECS[k].center + C.SPECS[k].spread];
assert.ok(band('warning')[0] - band('error')[1] >= 15, 'error and warning bands overlap');
assert.ok(band('success')[0] - band('warning')[1] >= 30, 'warning and success bands overlap');
assert.ok(360 + band('error')[0] - band('success')[1] >= 90, 'success and error bands overlap');

// An on-hue, saturated, readable seed passes through untouched: the
// wallpaper still decides the exact shade.
assert.equal(C.derive('error', '#ff5555', ['#000000', '#1f1f1f']), '#ff5555');
assert.equal(C.derive('success', '#50fa7b', ['#000000', '#1f1f1f']), '#50fa7b');

// Hue clamping goes the short way round the wheel.
assert.equal(Math.round(C.clampHue(350, 0, 20)), 350);
assert.equal(Math.round(C.clampHue(300, 0, 20)), 340);
assert.equal(Math.round(C.clampHue(60, 0, 20)), 20);

// Colours.qml routes the semantic roles and wallust's m3error through it.
const qml = readFileSync(`${services}/Colours.qml`, 'utf8').replace(/\/\/.*$/gm, '');
assert.match(qml, /import "StatusColours\.js" as StatusColours/);
for (const kind of ['error', 'warning', 'success'])
    assert.match(qml, new RegExp(`readonly property color ${kind}: root\\._status\\("${kind}"`), kind);
assert.match(qml, /m3error: root\._role\("error", root\.status\.error\)/);

console.log('PASS: status colours hold hue and contrast');
