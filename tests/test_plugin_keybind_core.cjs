// tests/test_plugin_keybind_core.cjs
//
// The keybind combo parser and the quoting every manifest value crosses
// into the shell through. Plain functions in a .js QML loads at runtime,
// so they can be tested outside a compositor -- tests/test_flow_js.sh
// runs this with the other tests/*.cjs.
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { existsSync, readFileSync } = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');

function load(relativePath) {
    const context = vm.createContext({});
    vm.runInContext(readFileSync(`${__dirname}/../${relativePath}`, 'utf8'), context);
    return context;
}

const core = load('Configs/quickshell/aphotic/services/PluginKeybindCore.js');

// Cross-realm objects, so compare plain fields rather than the object.
function parsed(combo) {
    const out = core.parse(combo);
    return out.error
        ? {error: out.error}
        : {key: out.key, modmask: out.modmask, legacy: out.legacy};
}

const marker = path.join(os.tmpdir(), `aphotic-keybind-core-${process.pid}`);

// --- the combo ----------------------------------------------------------

// The documented form, and the spellings a plugin author actually writes.
// All of them parse to one combo: the tokens, not the separators or the
// case, are what a bind is made of.
assert.deepEqual(parsed('SUPER + SHIFT + R'), {key: 'R', modmask: 65, legacy: 'SUPER SHIFT, R'});
assert.deepEqual(parsed('SUPER+SHIFT+R'), {key: 'R', modmask: 65, legacy: 'SUPER SHIFT, R'});
assert.deepEqual(parsed('super + shift + r'), {key: 'r', modmask: 65, legacy: 'SUPER SHIFT, r'});
assert.deepEqual(parsed('SUPER  +  SHIFT  +  R'), {key: 'R', modmask: 65, legacy: 'SUPER SHIFT, R'});

// A modless combo keeps the legacy line's empty modifiers field. Without
// that comma the legacy parser reads the key as a modifier and the bind
// lands nowhere.
assert.deepEqual(parsed('XF86AudioMute'), {key: 'XF86AudioMute', modmask: 0, legacy: ', XF86AudioMute'});

// The names Hyprland's parsers accept for the same bit as the four this
// repo's own binds use, so a combo spelled either way gets the modmask the
// live bind table is compared against.
assert.equal(parsed('MOD4 + R').modmask, 64);
assert.equal(parsed('WIN + R').modmask, 64);
assert.equal(parsed('LOGO + R').modmask, 64);
assert.equal(parsed('MOD1 + R').modmask, 8);
assert.equal(parsed('CONTROL + R').modmask, 4);
assert.equal(parsed('CAPS + R').modmask, 2);
assert.equal(parsed('MOD2 + R').modmask, 16);
assert.equal(parsed('MOD3 + R').modmask, 32);
assert.equal(parsed('MOD5 + R').modmask, 128);

// Refused, not derived: none of these has both a legacy form and a
// modmask, and a bind derived anyway would be one Hyprland rejects under a
// modmask that matches no live bind -- the destructive case the conflict
// check exists for. Every message names what could not be represented.
const refusals = [
    '',
    '   ',
    'SUPER + SHIFT + ',
    'SUPER + + R',
    'SUPER + SHIFT + R + X',
    'MOD9 + R',
    'SUPER + SHIFT + $(touch ' + marker + ')',
    'SUPER + SHIFT + R"',
    "SUPER + SHIFT + R'",
    'SUPER + SHIFT + R\\',
    'SUPER, SHIFT, R',
    'SUPER + SHIFT + R`',
    'SUPER + SHIFT + R\n'
];
for (const combo of refusals) {
    const out = parsed(combo);
    assert.ok(typeof out.error === 'string' && out.error.length > 0, `expected ${JSON.stringify(combo)} to be refused`);
    assert.equal(core.comboKey(combo), '', `${JSON.stringify(combo)} must have no combo identity`);
}
assert.equal(parsed('SUPER + SHIFT + R + X').error, "'R' is not a modifier both parsers know");
assert.equal(parsed('MOD9 + R').error, "'MOD9' is not a modifier both parsers know");

// The registry's dedupe asks this: one physical combo, one key, whatever
// two plugins called it. A prototype's own name is an ordinary key, which
// is what an object keyed on the combo got wrong.
assert.equal(core.comboKey('SUPER + SHIFT + R'), core.comboKey('MOD4 + SHIFT + r'));
assert.equal(core.comboKey('super+shift+r'), core.comboKey('SUPER + SHIFT + R'));
assert.equal(core.comboKey('XF86AudioMute'), core.comboKey('XF86AudioMute'));
assert.notEqual(core.comboKey('SUPER + SHIFT + R'), core.comboKey('SUPER + SHIFT + E'));
assert.equal(core.comboKey('constructor'), '0|constructor');
assert.equal(core.comboKey('toString'), '0|tostring');

// --- the description ----------------------------------------------------

// A label is a label: quotes and substitutions are quoted on the way in.
assert.equal(core.label("Player's shortcut"), "Player's shortcut");
assert.equal(core.label('He said "hi"'), 'He said "hi"');
assert.equal(core.label('$(touch ' + marker + ')'), '$(touch ' + marker + ')');
assert.equal(core.label(''), '');

// A comma shifts the legacy bind line's own fields and a control character
// ends the line, so neither can be shown -- and the caller says so rather
// than binding a string Hyprland reads differently.
assert.equal(core.label('Reload, Acme'), '');
assert.equal(core.labelIssue('Reload, Acme'), 'it has a comma');
assert.equal(core.label('a\nb'), '');
assert.equal(core.labelIssue('a\nb'), 'it has a control character');
assert.equal(core.labelIssue("Player's shortcut"), '');

// --- the shell ----------------------------------------------------------

// Every manifest value the worker pastes into its `sh -c` line goes
// through shellQuote first. Through a real shell, each hostile value comes
// back byte for byte and none of it runs.
const hostile = [
    'SUPER + SHIFT + $(touch ' + marker + ')',
    '$(touch ' + marker + ')',
    '`touch ' + marker + '`',
    '"; /usr/bin/touch ' + marker + '; echo "',
    "'; /usr/bin/touch " + marker + "; echo '",
    'x\'; /usr/bin/touch ' + marker + '; : \'',
    'back\\slash',
    'new\nline',
    "quote'quote"
];
for (const value of hostile) {
    const out = execFileSync('sh', ['-c', `printf '%s' ${core.shellQuote(value)}`]).toString();
    assert.equal(out, value, `shell round trip changed ${JSON.stringify(value)}`);
}
assert.ok(!existsSync(marker), 'a quoted value must not run anything');

// The two lines the worker builds, exactly as it builds them: the legacy
// bind line is one argument whatever the description and the command
// contain, and the Lua payload is one argument with the value escaped
// inside the string literal rather than pasted into the source.
const bind = core.legacyBind(parsed('SUPER + SHIFT + R'), 'Reload, Acme', 'qs -c aphotic ipc call aphotic action acme.reload');
assert.equal(bind, 'SUPER SHIFT, R, , exec, qs -c aphotic ipc call aphotic action acme.reload');

const trap = core.legacyBind(parsed('SUPER + SHIFT + R'),
    'Reload"; /usr/bin/touch ' + marker + '; echo "',
    'qs -c aphotic ipc call aphotic action acme.reload$(/usr/bin/touch ' + marker + ')');
const through = execFileSync('sh', ['-c', `printf '%s' ${core.shellQuote(trap)}`]).toString();
assert.equal(through, trap);
assert.ok(!existsSync(marker), 'the built bind line must not run anything');

assert.equal(core.luaUnbind('SUPER + SHIFT + R'), 'hl.unbind("SUPER + SHIFT + R")');
assert.equal(core.luaString('a"b\\c'), 'a\\"b\\\\c');
assert.equal(core.luaString('a\nb'), 'a\\nb');
assert.equal(
    core.luaBind('SUPER + SHIFT + R', 'qs -c aphotic ipc call aphotic action acme.reload', 'Reload "Acme"'),
    'hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("qs -c aphotic ipc call aphotic action acme.reload"), { description = "Reload \\"Acme\\"" })');
assert.equal(
    core.luaBind('SUPER + SHIFT + R', 'cmd', 'Reload, Acme'),
    'hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("cmd"), { description = "" })');

console.log('PASS: plugin keybind core assertions');
