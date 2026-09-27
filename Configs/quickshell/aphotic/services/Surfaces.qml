pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "SurfacePolicy.js" as Policy

// The one place that decides how surfaces coexist. Every window still
// owns its own flag on its screen's ScreenState -- IPC, keybinds and the
// launcher keep setting those exactly as before -- and ScreenState
// reports each change here. This answers what the change does to the
// rest of the screen (services/SurfacePolicy.js holds the rules) and
// closes whatever it displaces through the same flags, so no window ever
// has to know another one exists.
//
// No timer, no process, no polling: every state change here is a flag
// flip or a hold/release call.
Singleton {
    id: root

    // Held by a blocking modal for as long as its window exists -- the
    // negotiation prompt today, anything that must own the keyboard on
    // every screen tomorrow. Newest holder wins; empty when none.
    readonly property string blocking: root._holders.length > 0 ? root._holders[root._holders.length - 1] : ""

    // Windows AND this into their `visible`: a blocking modal hides
    // them without touching their flags, so they come back as they were
    // once it releases.
    readonly property bool suppressed: root.blocking !== ""

    // Surfaces a plugin or a later module declares at runtime, keyed by
    // name. Same shape as SurfacePolicy.SURFACES. A declared surface has
    // no flag on ScreenState, so it reports its own opens and closes with
    // track() and closes itself on closeRequested -- the same contract a
    // core flag gets for free.
    readonly property var declared: root._declared

    signal changed(screenState: var, name: string, open: bool)
    signal closeRequested(screenState: var, name: string)

    property var _holders: []
    property var _declared: ({})

    function roleOf(name: string): string {
        return Policy.roleOf(name, root._declared);
    }

    function declare(name: string, role: string): bool {
        if (!name || Policy.ROLES.indexOf(role) < 0 || Policy.SURFACES[name])
            return false;
        const next = Object.assign({}, root._declared);
        next[name] = {
            role: role
        };
        root._declared = next;
        return true;
    }

    function undeclare(name: string): void {
        if (!Object.prototype.hasOwnProperty.call(root._declared, name))
            return;
        const next = Object.assign({}, root._declared);
        delete next[name];
        root._declared = next;
    }

    function hold(owner: string): void {
        if (!owner || root._holders.includes(owner))
            return;
        root._holders = root._holders.concat([owner]);
    }

    function release(owner: string): void {
        if (!root._holders.includes(owner))
            return;
        root._holders = root._holders.filter(h => h !== owner);
    }

    // Called by ScreenState on every flag change. The stack is assigned
    // before any displaced flag is cleared, so the re-entrant call each
    // clear makes finds its name already gone and does nothing.
    function track(screenState: var, name: string, open: bool): void {
        if (!screenState)
            return;
        const next = Policy.transition(screenState.surfaceStack ?? [], name, open, root._declared);
        screenState.surfaceStack = next.stack;
        for (const displaced of next.close)
            root._close(screenState, displaced);
        root.changed(screenState, name, open);
    }

    function describe(stack: var): var {
        return Policy.describe(stack ?? [], root.blocking, root._declared);
    }

    function engaged(stack: var): bool {
        return Policy.engaged(stack ?? [], root.blocking, root._declared);
    }

    // Closes whatever owns the keyboard on this screen. Returns the name
    // it closed, or "" when there was nothing it may close.
    function back(screenState: var): string {
        if (!screenState)
            return "";
        const name = Policy.back(screenState.surfaceStack ?? [], root.blocking, root._declared);
        if (name) {
            root._close(screenState, name);
            if ((screenState.surfaceStack ?? []).includes(name))
                root.track(screenState, name, false);
        }
        return name;
    }

    function _close(screenState: var, name: string): void {
        if (typeof screenState[name] === "boolean")
            screenState[name] = false;
        else
            root.closeRequested(screenState, name);
    }
}
