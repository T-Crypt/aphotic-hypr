// How Aphotic's surfaces coexist on one screen. Plain functions over plain
// data so the rules run under node (tests/test_surface_policy.cjs) exactly
// as QML runs them; services/Surfaces.qml is the thin reactive wrapper.
//
// A surface has one role. The role, not the surface, decides what an open
// does to everything else already on screen:
//
//   transient  bar popouts and similar hover/click-away panels
//   workspace  the plugin Workspace plane: stays behind a primary
//   primary    launcher, dashboard, settings, ... -- one at a time
//   modal      a screen-covering choice (the session menu)
//
// A blocking modal (the Resource Engine's negotiation prompt) is not in
// any screen's stack. It is held globally while its window exists and
// hides every other interactive surface without closing it, so the
// answer can't be taken by whichever window happened to have keyboard
// focus, and everything comes back once the answer is in.

var ROLES = ['transient', 'workspace', 'primary', 'modal', 'sonar'];

var SURFACES = {
    sonar: {role: 'sonar'},
    shelf: {role: 'transient'},
    agentPanel: {role: 'transient'},
    workspace: {role: 'workspace'},
    launcher: {role: 'primary'},
    dashboard: {role: 'primary'},
    settings: {role: 'primary'},
    intelligence: {role: 'primary'},
    notificationCenter: {role: 'primary'},
    pkgInstall: {role: 'primary'},
    wallpaperPicker: {role: 'primary'},
    keybindsCheatsheet: {role: 'primary'},
    session: {role: 'modal'}
};

// Which existing roles an incoming role closes. Workspace survives a
// primary on purpose: it is the plane a launcher opens over, not a rival.
var DISPLACES = {
    transient: ['transient', 'sonar'],
    workspace: ['transient', 'primary', 'modal', 'sonar'],
    primary: ['transient', 'primary', 'modal', 'sonar'],
    modal: ['transient', 'primary', 'sonar'],
    sonar: []
};

// Focus precedence when more than one surface is open at once.
var RANK = {transient: 1, workspace: 2, primary: 3, modal: 4, sonar: 5};

function roleOf(name, extra) {
    var entry = (extra && extra[name]) || SURFACES[name];
    return entry && ROLES.indexOf(entry.role) >= 0 ? entry.role : '';
}

function names(extra) {
    return Object.keys(Object.assign({}, SURFACES, extra || {}));
}

// Opening or closing `name` against `stack` (open order, oldest first).
// Returns the new stack and the surfaces the caller must close. An
// unknown surface is tracked with no role: it neither closes nor is
// closed, which is the old behaviour of every flag.
function transition(stack, name, open, extra) {
    var rest = (stack || []).filter(function (n) { return n !== name; });
    if (!open)
        return {stack: rest, close: []};

    var displaces = DISPLACES[roleOf(name, extra)] || [];
    var keep = [];
    var close = [];
    rest.forEach(function (n) {
        if (displaces.indexOf(roleOf(n, extra)) >= 0)
            close.push(n);
        else
            keep.push(n);
    });
    keep.push(name);
    return {stack: keep, close: close};
}

// The surface that owns the keyboard: the blocking modal if one is held,
// else the highest-ranked open surface, newest first among equals.
function focusOwner(stack, blocking, extra) {
    if (blocking)
        return blocking;
    var best = '';
    var bestRank = 0;
    (stack || []).forEach(function (n) {
        var rank = RANK[roleOf(n, extra)] || 0;
        if (rank >= bestRank && rank > 0) {
            best = n;
            bestRank = rank;
        }
    });
    return best;
}

// What the screen is doing, in one word a visual layer can style against.
function mode(stack, blocking, extra) {
    if (blocking)
        return 'blocked';
    var owner = focusOwner(stack, '', extra);
    return owner ? roleOf(owner, extra) : 'ambient';
}

function describe(stack, blocking, extra) {
    stack = stack || [];
    return {
        stack: stack.slice(),
        focusOwner: focusOwner(stack, blocking, extra),
        mode: mode(stack, blocking, extra),
        blocking: blocking || ''
    };
}

// What Escape/back should close. Never the blocking modal: backing out
// of a negotiation would be a decision, and that prompt answers its own
// Escape with the choice that stops nothing.
function back(stack, blocking, extra) {
    if (blocking)
        return '';
    return focusOwner(stack, '', extra);
}

// The ambient surfaces (bar popouts, the notch's expanded tile) settle
// whenever something takes the keyboard. They are not in the stack, so
// this is the one question they ask.
function engaged(stack, blocking, extra) {
    var m = mode((stack || []).filter(function (n) { return roleOf(n, extra) !== 'sonar'; }), blocking, extra);
    return m !== 'ambient' && m !== 'transient';
}
