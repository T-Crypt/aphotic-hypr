// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// The ALT+Tab switcher's state, and the only thing that moves focus.
//
// The rule this file exists to keep: cycling never touches the
// compositor. Every window, workspace and monitor rectangle is copied
// into plain JS on open and nothing re-reads Hyprland until the overlay
// closes, so walking the list cannot reorder the list being walked.
// Hyprland's own `hl.dsp.window.cycle_next` focuses on every press,
// which rewrites focus history under the cursor -- press Tab twice and
// you are back where you started. One `WindowList.focus()` fires, from
// commit(), and only if the selection actually moved.
//
// Nothing here reads the keyboard. `Configs/hypr/keybinds.lua` puts
// Hyprland into an `aphotic-switcher` submap for as long as the overlay
// is up and every key in it calls one of the IPC functions at the
// bottom, which is what makes releasing ALT a commit rather than a
// guess: Hyprland tells us, we don't poll for it.
//
// This singleton acts on its own rather than answering a reader, so it
// needs a construction site in `shell.qml`'s `_residentSingletons` or
// its IpcHandler never exists and every keybind below is a silent
// no-op. See CLAUDE.md.
Singleton {
    id: root

    // Home row, left index finger outwards. Ten keys, ten workspaces,
    // in the order they sit under the hand.
    readonly property var homeRow: ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";"]

    // Beyond this the cards are too narrow to read a window outline in,
    // and the home row has run out of keys anyway.
    readonly property int maxWorkspaces: 10

    property bool open: false

    // Which monitor the overlay draws on, captured at open. Not read
    // live: the pointer moving across a monitor edge mid-cycle should
    // not teleport the surface being cycled.
    property string monitorName: ""

    // The frozen snapshot. `windows` is in most-recently-used order,
    // `cards` is one per workspace in id order with the windows that
    // live on it. Both are plain arrays of plain objects, deliberately:
    // a HyprlandToplevel is live and would defeat the whole point.
    property var windows: []
    property var cards: []

    // Index into `windows`, or -1 when the selection is a workspace with
    // nothing on it. Exactly one of these two is meaningful at a time.
    property int selected: -1
    property int selectedWorkspace: 0

    readonly property var current: root.selected >= 0 ? root.windows[root.selected] ?? null : null

    readonly property int currentWorkspace: root.current ? root.current.workspaceId : root.selectedWorkspace

    // Hyprland numbers focus history 0-first, so ascending order is
    // most-recent-first: index 0 is the window in front of you right
    // now, index 1 is the one ALT+Tab is expected to land on. A window
    // the compositor did not report an id for sorts to the back rather
    // than to the front, where it would displace the real answer.
    function _snapshotWindows(): var {
        return WindowList.windows.filter(w => !w.workspaceName.startsWith("special:")).map(w => {
            const ipc = w.toplevel?.lastIpcObject ?? {};
            const at = ipc.at ?? [0, 0];
            const size = ipc.size ?? [0, 0];
            return {
                address: w.address,
                title: w.title,
                appClass: w.appClass,
                workspaceId: w.workspaceId,
                floating: w.floating,
                focused: w.focused,
                x: at[0],
                y: at[1],
                width: size[0],
                height: size[1],
                order: ipc.focusHistoryID ?? 9999
            };
        }).sort((a, b) => a.order - b.order);
    }

    function _monitorRects(): var {
        const rects = {};
        for (const m of Hypr.monitors.values) {
            const ipc = m.lastIpcObject ?? {};
            rects[m.name] = {
                x: ipc.x ?? m.x ?? 0,
                y: ipc.y ?? m.y ?? 0,
                width: ipc.width ?? m.width ?? 1920,
                height: ipc.height ?? m.height ?? 1080
            };
        }
        return rects;
    }

    // Cards run 1..N with no gaps, so an empty desktop between two busy
    // ones is still somewhere the home row can land. N is one past the
    // last workspace in use, which is how "jump to a fresh desktop and
    // let go" works without the card list growing every time you do it.
    function _snapshotCards(windows: var): var {
        const rects = root._monitorRects();
        const focusedWs = Hypr.focusedWorkspace?.id ?? 1;

        let last = Math.max(focusedWs, 1);
        for (const w of windows)
            if (w.workspaceId > last)
                last = w.workspaceId;
        const count = Math.min(root.maxWorkspaces, last + 1);

        const monitorOf = {};
        for (const ws of Hypr.workspaces.values)
            monitorOf[ws.id] = ws.monitor?.name ?? "";

        const fallback = rects[root.monitorName] ?? Object.values(rects)[0] ?? {
            x: 0,
            y: 0,
            width: 1920,
            height: 1080
        };

        const cards = [];
        for (let id = 1; id <= count; id++) {
            const rect = rects[monitorOf[id]] ?? fallback;
            cards.push({
                id,
                key: root.homeRow[id - 1] ?? "",
                rect,
                windows: windows.filter(w => w.workspaceId === id)
                    // Cards read spatially, so their windows are ordered
                    // the way they sit on screen rather than by recency.
                    // The 1-9 badges number this order.
                    .sort((a, b) => (a.y - b.y) || (a.x - b.x))
            });
        }
        return cards;
    }

    function _snapshot(): void {
        root.monitorName = Hypr.focusedMonitor?.name ?? "";
        const windows = root._snapshotWindows();
        root.windows = windows;
        root.cards = root._snapshotCards(windows);
        root.selected = windows.length > 0 ? 0 : -1;
        root.selectedWorkspace = Hypr.focusedWorkspace?.id ?? 1;
    }

    // First press opens on the snapshot and steps once, so ALT+Tab lands
    // on the previous window the way it does everywhere else. Every
    // press after that is one more step through the same frozen list.
    function step(delta: int): void {
        if (!root.open) {
            root._snapshot();
            root.open = true;
        }
        if (root.windows.length === 0)
            return;
        const from = root.selected >= 0 ? root.selected : -1;
        root.selected = (from + delta + root.windows.length * 2) % root.windows.length;
        root.selectedWorkspace = 0;
    }

    function _cardAt(id: int): var {
        return root.cards.find(c => c.id === id) ?? null;
    }

    // Landing on a workspace selects its first window, or the workspace
    // itself when there is none -- which is the whole reason an empty
    // card is drawn at all.
    function selectWorkspace(id: int): void {
        if (!root.open)
            return;
        const card = root._cardAt(id);
        if (!card)
            return;
        if (card.windows.length > 0) {
            root.selected = root.windows.indexOf(card.windows[0]);
            root.selectedWorkspace = 0;
        } else {
            root.selected = -1;
            root.selectedWorkspace = id;
        }
    }

    // The 1-9 badges, numbered within whichever card the selection is on.
    function selectWindow(n: int): void {
        if (!root.open)
            return;
        const card = root._cardAt(root.currentWorkspace);
        const win = card?.windows[n - 1];
        if (!win)
            return;
        root.selected = root.windows.indexOf(win);
        root.selectedWorkspace = 0;
    }

    function selectAddress(address: string): void {
        const at = root.windows.findIndex(w => w.address === address);
        if (at < 0)
            return;
        root.selected = at;
        root.selectedWorkspace = 0;
    }

    // Left/right walk the cards, up/down walk the windows inside the one
    // the selection is on. Two axes, two meanings, so neither ever
    // silently does the other's job.
    function move(direction: string): void {
        if (!root.open || root.cards.length === 0)
            return;

        if (direction === "left" || direction === "right") {
            const at = root.cards.findIndex(c => c.id === root.currentWorkspace);
            const delta = direction === "right" ? 1 : -1;
            const next = (Math.max(at, 0) + delta + root.cards.length) % root.cards.length;
            root.selectWorkspace(root.cards[next].id);
            return;
        }

        const card = root._cardAt(root.currentWorkspace);
        if (!card || card.windows.length === 0)
            return;
        const at = card.windows.indexOf(root.current);
        const delta = direction === "down" ? 1 : -1;
        const next = (Math.max(at, 0) + delta + card.windows.length) % card.windows.length;
        root.selected = root.windows.indexOf(card.windows[next]);
        root.selectedWorkspace = 0;
    }

    // The one place focus moves. A selection that never left the window
    // already in front dispatches nothing at all, so tapping ALT+Tab and
    // changing your mind costs the compositor nothing.
    function commit(): void {
        const win = root.current;
        const workspace = root.selectedWorkspace;
        root.close();

        if (win) {
            if (!win.focused)
                WindowList.focus(win.address);
            return;
        }
        if (workspace > 0)
            Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = ${workspace} })` : `workspace ${workspace}`);
    }

    function close(): void {
        root.open = false;
        root.selected = -1;
        root.selectedWorkspace = 0;
        root.windows = [];
        root.cards = [];
    }

    // A window closing while the overlay is up would leave the selection
    // pointing at a dead address, and committing it dispatches a focus
    // Hyprland answers with nothing. Cheaper to drop the surface than to
    // re-derive a snapshot the user is halfway through reading.
    Connections {
        function onRawEvent(name: string): void {
            if (root.open && name === "closewindow")
                root.close();
        }

        target: Hypr
    }

    IpcHandler {
        target: "switcher"

        function next(): void {
            root.step(1);
        }

        function prev(): void {
            root.step(-1);
        }

        function move(direction: string): void {
            root.move(direction);
        }

        function workspace(key: string): void {
            const at = root.homeRow.indexOf(key);
            if (at >= 0)
                root.selectWorkspace(at + 1);
        }

        function window(n: string): void {
            root.selectWindow(parseInt(n, 10));
        }

        function commit(): void {
            root.commit();
        }

        function cancel(): void {
            root.close();
        }

        function state(): string {
            return JSON.stringify({
                open: root.open,
                monitor: root.monitorName,
                selected: root.selected,
                selectedWorkspace: root.selectedWorkspace,
                windows: root.windows.length,
                cards: root.cards.length
            });
        }
    }
}
