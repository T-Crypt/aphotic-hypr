pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

Singleton {
    id: root

    readonly property var windows: Hypr.toplevels.values.map(t => ({
                address: t.address,
                title: t.title || t.lastIpcObject?.class || "",
                appClass: t.lastIpcObject?.class ?? "",
                workspaceId: t.workspace?.id ?? 0,
                workspaceName: t.workspace?.name ?? "",
                focused: t.address === Hypr.activeToplevel?.address,
                floating: !!t.lastIpcObject?.floating,
                toplevel: t
            }))

    // Groups windows by app class, preserving first-seen order -- the
    // shape Taskbar's grouped task list and Dock's running-indicator both
    // need (one entry per app, with its member windows for a flyout/click
    // list) without either building its own grouping logic.
    function grouped(): var {
        const order = [];
        const groups = {};
        for (const w of root.windows) {
            if (!groups[w.appClass]) {
                groups[w.appClass] = [];
                order.push(w.appClass);
            }
            groups[w.appClass].push(w);
        }
        return order.map(appClass => ({ appClass, windows: groups[appClass] }));
    }

    function windowsForClass(appClass: string): var {
        return root.windows.filter(w => w.appClass === appClass);
    }

    // One entry per app class, first-seen order, without the per-window
    // grouping payload -- Settings scans this to find classes whose icon
    // does not resolve.
    function classes(): var {
        const seen = [];
        for (const w of root.windows)
            if (w.appClass && !seen.some(e => e.appClass === w.appClass))
                seen.push({ appClass: w.appClass, title: w.title });
        return seen;
    }

    // Quickshell reports an address with no `0x`, Hyprland's `address:`
    // selector requires one, and the Lua dispatcher takes a window
    // selector string rather than an address key. Getting any of the
    // three wrong fails silently: Hyprland.dispatch() reports nothing
    // back. Every focus-a-window path goes through here for that reason.
    function focus(address: string): void {
        if (!address)
            return;
        const selector = `address:${address.startsWith("0x") ? address : "0x" + address}`;
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ window = "${selector}" })` : `focuswindow ${selector}`);
    }

    // Walk one app's windows a click at a time, wherever they live. The
    // focused window is the anchor, so a second click moves on rather
    // than bouncing back to the first; with none of them focused the
    // walk starts at the top. Order is `Hypr.toplevels`' own, which is
    // stable while no window opens or closes.
    function cycleWindows(windows: var): void {
        if (!windows?.length)
            return;
        const at = windows.findIndex(w => w.focused);
        root.focus(windows[(at + 1) % windows.length].address);
    }

    function cycle(appClass: string): void {
        root.cycleWindows(root.windowsForClass(appClass));
    }
}
