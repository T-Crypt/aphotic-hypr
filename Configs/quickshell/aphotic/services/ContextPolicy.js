// Runtime contexts: what the user is doing right now, as opposed to what
// is installed (InstallProfile layers) or what a domain workload is doing
// (ProfileEngine phases). A context installs nothing and starts nothing.
// It only changes how already-running surfaces behave, and switching back
// to `default` undoes all of it because nothing here writes user settings.
//
// Each context is a declaration, read by the consumers that own the
// behaviour. Keys, and who reads them:
//
//   notifications  popup floor: all | normal | critical | none.
//                  Notifs.qml; everything still lands in history.
//   motion         full | reduced. RenderGate.decorative goes false on
//                  reduced, so every self-running animation gated on it
//                  stops.
//   resources      the least ResourcePosture level the ambient shell
//                  (bar, notch) surfaces: pressure | contention |
//                  negotiating. A negotiation always opens its prompt.
//
// Plain functions so tests/test_runtime_context.cjs runs them under node.

var ORDER = ['default', 'focus', 'dev', 'game', 'present'];

var CONTEXTS = {
    default: {label: 'Default', icon: 'desktop_windows',
        description: 'Everything behaves as configured.',
        notifications: 'all', motion: 'full', resources: 'pressure'},
    focus: {label: 'Focus', icon: 'center_focus_strong',
        description: 'Only critical popups, calmer motion, resources shown once contended.',
        notifications: 'critical', motion: 'reduced', resources: 'contention'},
    dev: {label: 'Dev', icon: 'code',
        description: 'Low-priority popups held back; resource pressure shown early.',
        notifications: 'normal', motion: 'full', resources: 'pressure'},
    game: {label: 'Game', icon: 'sports_esports',
        description: 'Only critical popups, no decorative motion, resource pressure shown early.',
        notifications: 'critical', motion: 'reduced', resources: 'pressure'},
    present: {label: 'Present', icon: 'present_to_all',
        description: 'No popups, no decorative motion, resources shown only when a decision is needed.',
        notifications: 'none', motion: 'reduced', resources: 'negotiating'}
};

// Popup floors against freedesktop urgency: 0 low, 1 normal, 2 critical.
var FLOORS = {all: 0, normal: 1, critical: 2, none: 3};

function has(name) {
    return Object.prototype.hasOwnProperty.call(CONTEXTS, name);
}

function policy(name) {
    return CONTEXTS[has(name) ? name : 'default'];
}

function list() {
    return ORDER.map(function (id) {
        var c = CONTEXTS[id];
        return {id: id, label: c.label, icon: c.icon, description: c.description};
    });
}

function allowsPopup(name, urgency) {
    var floor = FLOORS[policy(name).notifications];
    return (typeof urgency === 'number' ? urgency : 1) >= (floor === undefined ? 0 : floor);
}

function reducesMotion(name) {
    return policy(name).motion === 'reduced';
}

function resourceThreshold(name) {
    return policy(name).resources;
}
