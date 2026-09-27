pragma Singleton

import QtQuick
import Quickshell
import "ContextPolicy.js" as Policy

// What the user is doing right now. Set by hand -- `aphotic context set
// <name>`, `qs -c aphotic ipc call context set <name>` or a keybind --
// and never by detection: a suggestion may come later, a switch never
// happens behind the user's back. services/ContextPolicy.js declares what
// each context changes and which consumer reads each key.
//
// Not persisted. A context is a session state like DND-for-a-meeting, and
// a restart landing back in `default` is the safe direction to fail.
Singleton {
    id: root

    readonly property string current: root._current
    readonly property string previous: root._previous
    readonly property var policy: Policy.policy(root._current)
    readonly property var contexts: Policy.list()
    readonly property bool reducesMotion: Policy.reducesMotion(root._current)
    readonly property string resourceThreshold: Policy.resourceThreshold(root._current)
    readonly property bool hidesOverlays: Policy.hidesOverlays(root._current)

    signal switched(from: string, to: string)

    property string _current: "default"
    property string _previous: "default"

    function has(name: string): bool {
        return Policy.has(name);
    }

    function set(name: string): bool {
        if (!Policy.has(name))
            return false;
        if (name === root._current)
            return true;
        const from = root._current;
        root._previous = from;
        root._current = name;
        root.switched(from, name);
        return true;
    }

    // Back to whatever was active before the last switch.
    function revert(): bool {
        return root.set(root._previous);
    }

    function allowsPopup(urgency: int): bool {
        return Policy.allowsPopup(root._current, urgency);
    }
}
