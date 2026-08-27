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
                icon: Quickshell.iconPath(t.lastIpcObject?.class, "application-x-executable"),
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

    function focus(address: string): void {
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ address = "${address}" })` : `focuswindow address:${address}`);
    }
}
