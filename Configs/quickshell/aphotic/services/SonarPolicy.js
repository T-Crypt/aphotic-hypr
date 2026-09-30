// Pure session rules for the Sonar ping. Plain functions over plain data
// so tests/test_sonar_policy.cjs runs them under node exactly as QML runs
// them; services/Sonar.qml is the reactive wrapper.

// The ring finishes expanding at 60% of the session; the rest is reading
// time with the fade folded into the tail, so one progress value drives
// the whole composition and teardown is one moment, not a chain.
var LIFETIME_MS = 2000;
var SWEEP_FRACTION = 0.6;
var FADE_AT = 0.75;

// Whether a ping may start at all. Locks and blocking prompts take
// precedence by never answering; the enable check runs here so the
// keybind and IPC routes cannot drift apart.
function canPing(enabled, blocking, locked) {
    return enabled && !blocking && !locked;
}

// `hyprctl cursorpos` prints "x, y". Anything else -- transient
// hyprctl failure, empty output -- is the fallback path, not an error:
// the focused output's center still gives a real origin.
function parseCursorPos(text) {
    var m = /^\s*(-?\d+)\s*,\s*(-?\d+)\s*$/.exec(text || '');
    return m ? {x: parseInt(m[1], 10), y: parseInt(m[2], 10)} : null;
}

function originFallback(output) {
    if (!output)
        return {x: 0, y: 0};
    return {x: output.x + output.width / 2, y: output.y + output.height / 2};
}

// Ring radius as a fraction of the session's maximum, from the shared
// progress value. Reduced motion skips the sweep: the ring is already
// at full size and the two-second timeout does the rest.
function radiusFraction(progress, reduced) {
    if (reduced)
        return 1;
    return Math.min(progress / SWEEP_FRACTION, 1);
}

function opacityAt(progress, reduced) {
    if (reduced)
        return 1;
    if (progress < FADE_AT)
        return 1;
    return Math.max(0, 1 - (progress - FADE_AT) / (1 - FADE_AT));
}

// A target answers once the ring reaches the nearest point of its
// rectangle. Global logical coordinates throughout: the same circle
// crosses every output, gaps included.
function reached(point, rect, radius) {
    var dx = Math.max(rect.x - point.x, 0, point.x - rect.x - rect.width);
    var dy = Math.max(rect.y - point.y, 0, point.y - rect.y - rect.height);
    return dx * dx + dy * dy <= radius * radius;
}

// SUPER's modmask bit in `hyprctl binds -j` is 1 << 6. A conflict is a
// non-mouse bind on the same key with the same modifiers that is not
// ours -- our own re-assertion must not read as one. The low byte is
// compared so Hyprland's state flag bits never mask a real conflict.
function superBindConflict(binds) {
    return (binds || []).some(function (b) {
        return b && !b.mouse && b.key === 'grave'
            && (b.modmask & 0xff) === 64
            && b.description !== 'Ping Sonar discovery';
    });
}

function dismissKey(key, autoRepeat) {
    return !(key === 96 && autoRepeat);
}
