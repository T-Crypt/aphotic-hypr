// A manifest's `[keybind] combo` is untrusted text on its way into two
// Hyprland grammars and one shell, so it is parsed, refused and quoted in
// one place rather than re-derived at each use: PluginRegistry.qml keys
// its dedupe on comboKey() and gives up on a combo with no key, and
// PluginKeybind.qml builds both bind forms from what parse() returns and
// never pastes a manifest value into a command line itself. Plain
// functions so tests/test_plugin_keybind_core.cjs runs them under node,
// the way PluginApiCore.js and PluginRegistryCore.js are tested.

// Hyprland's own modifier names and bits. The aliases are the ones its
// parsers accept for the same bit (WIN, LOGO and MOD4 are SUPER, MOD1 is
// ALT), so either spelling is one physical combo to the conflict check and
// to the registry's dedupe. HyprKeybinds.qml decodes the same bits for the
// cheatsheet. A modifier outside this table has no bit and no legacy
// spelling both parsers agree on, so a combo naming one is refused rather
// than bound under a modmask that matches no live bind.
var MODIFIERS = {
    SHIFT: 1,
    CAPS: 2,
    CTRL: 4,
    CONTROL: 4,
    ALT: 8,
    MOD1: 8,
    MOD2: 16,
    MOD3: 32,
    SUPER: 64,
    WIN: 64,
    LOGO: 64,
    MOD4: 64,
    MOD5: 128
};

// A key or a modifier name: no whitespace, no comma (the legacy bind
// syntax's own field separator), and no character a shell or a Lua string
// reads as syntax. cmd_plugin.sh's _aphotic_plugin_combo_error holds
// validate to the same shape before the shell ever sees the combo.
var TOKEN = /^[A-Za-z0-9_:.-]+$/;

// Spaces around a '+' are formatting. Anything else -- a tab, a newline --
// is a token's own character and fails TOKEN, because the declared combo is
// the string the Lua parser is handed as-is.
function trim(value) {
    return String(value).replace(/^ +| +$/g, '');
}

// "SUPER + SHIFT + R" -> {key: "R", modmask: 65, legacy: "SUPER SHIFT, R"},
// whatever the tokens' spelling or spacing. Anything else comes back as
// {error: "..."} naming what could not be represented, and the caller
// refuses the bind: a combo with no key, no bit or no legacy form would
// otherwise be derived into a string Hyprland rejects, under a modmask
// that matches nothing in the live bind table.
function parse(combo) {
    if (typeof combo !== 'string' || /^\s*$/.test(combo))
        return {error: 'it is empty'};
    var tokens = combo.split('+').map(trim);
    for (var i = 0; i < tokens.length; i++) {
        if (tokens[i] === '')
            return {error: 'it has an empty token'};
        if (!TOKEN.test(tokens[i]))
            return {error: `'${tokens[i]}' is not a key or a modifier name`};
    }
    var key = tokens[tokens.length - 1];
    var mods = tokens.slice(0, -1);
    var modmask = 0;
    for (var m = 0; m < mods.length; m++) {
        var bit = MODIFIERS[mods[m].toUpperCase()];
        if (bit === undefined)
            return {error: `'${mods[m]}' is not a modifier both parsers know`};
        modmask |= bit;
    }
    return {
        key: key,
        modmask: modmask,
        // The legacy parser takes the modifiers space-separated and the
        // key after a comma. A modless combo keeps that field empty --
        // without the comma the parser reads the key as a modifier.
        legacy: mods.map(m => m.toUpperCase()).join(' ') + ', ' + key
    };
}

// One physical combo spelled two ways -- "SUPER + shift + R" and
// "SUPER + SHIFT + r", "MOD4 + R" and "SUPER + R" -- is one key here, so
// the registry drops exactly what the conflict check would call the same
// combo. "" for a combo parse() refuses, which is never an identity.
function comboKey(combo) {
    var parsed = parse(combo);
    return parsed.error ? '' : `${parsed.modmask}|${parsed.key.toLowerCase()}`;
}

// A description rides inside the legacy bind line's third field, where a
// comma shifts every field after it, and inside a Lua string, where a
// control character truncates the line. "" when it cannot be shown, else
// why not -- quotes and substitutions are quoted below instead, because
// "Player's shortcut" is a label a plugin may legitimately want.
function labelIssue(value) {
    var text = typeof value === 'string' ? value : '';
    if (/[\x00-\x1f]/.test(text))
        return 'it has a control character';
    if (text.indexOf(',') >= 0)
        return 'it has a comma';
    return '';
}

function label(value) {
    var text = typeof value === 'string' ? value : '';
    return labelIssue(text) ? '' : text;
}

// The two ways a manifest value reaches a shell. Every one of them goes
// through shellQuote before it lands in the worker's `sh -c` line, and
// everything that lands inside the Lua payload on top of that goes
// through luaString first -- a combo, a description or an action id
// carrying `$(`, a quote or a backslash is text, not syntax.
function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

function luaString(value) {
    return String(value)
        .replace(/\\/g, '\\\\')
        .replace(/"/g, '\\"')
        .replace(/\n/g, '\\n')
        .replace(/\r/g, '\\r');
}

function luaUnbind(combo) {
    return `hl.unbind("${luaString(combo)}")`;
}

function luaBind(combo, command, description) {
    return `hl.bind("${luaString(combo)}", hl.dsp.exec_cmd("${luaString(command)}"), { description = "${luaString(label(description))}" })`;
}

function legacyBind(parsed, description, command) {
    return `${parsed.legacy}, ${label(description)}, exec, ${command}`;
}
