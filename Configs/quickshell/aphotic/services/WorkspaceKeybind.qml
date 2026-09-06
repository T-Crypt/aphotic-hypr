// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// The Workspace surface's keybind, bound only while something is there
// to open.
//
// Every other bind this shell ships is a line in `Configs/hypr/
// keybinds.lua`, because every other surface exists on every install.
// The Workspace plane does not: `ui.workspace` is a plugin capability,
// and with no enabled plugin registering one there is no window, no
// action and nothing for a key to do. A static line would still be
// listed in the SUPER+K cheatsheet and would still swallow the combo,
// promising a surface the install does not have.
//
// So the bind is made at runtime and removed the moment the last
// workspace plugin goes. `HyprKeybinds` reads `hyprctl binds -j` rather
// than parsing keybinds.lua, so the cheatsheet picks this up and drops
// it with no help from here.
//
// Nothing is written to the user's config. This is a live compositor
// keyword and it dies with the Hyprland session, which is what makes it
// safe to assert on every shell start.
//
// This singleton acts on its own rather than answering a reader, so it
// needs a construction site in `shell.qml`'s `_residentSingletons` or
// none of the below ever runs. See CLAUDE.md.
Singleton {
    id: root

    // Free on a stock install: SUPER+W is the wallpaper picker and
    // SUPER+CTRL+W browses every theme's wallpapers, so the third W is
    // the one still going spare and keeps the surface openers together.
    readonly property string combo: "SUPER + SHIFT + W"
    readonly property string legacyCombo: "SUPER SHIFT, W"

    // Read back by the cheatsheet, so it has to bucket into "Aphotic
    // Shell" under HyprKeybinds' own `_categoryFor` heuristic. Anything
    // starting "Open " lands in Apps & System instead.
    readonly property string description: "Toggle plugin workspace"
    readonly property string command: "qs -c aphotic ipc call workspace toggle"

    readonly property bool wanted: PluginRegistry.surfacesFor("workspace").length > 0

    // "", "lua" or "legacy". Which form the bind should be in right now,
    // and the reason this is a property rather than a branch inside
    // _sync(): `wanted` and `Hypr.usingLua` settle independently, one on
    // the plugin registry loading and one on the Hyprland connection
    // coming up. Reading the parser once, at whatever moment the
    // registry happened to finish, silently emitted the refused form on
    // a Lua install and left the combo unbound with nothing logged.
    // Watching both means the wrong guess corrects itself.
    readonly property string desiredForm: !root.wanted ? "" : (Hypr.usingLua ? "lua" : "legacy")
    readonly property string appliedForm: root._applied
    readonly property bool bound: root._applied.length > 0

    property string _applied: ""

    // The two config parsers take this differently, the same split
    // `StateSnapshot.monitorCommand()` already documents: `hyprctl
    // keyword` is refused outright under the Lua parser ("keyword can't
    // work with non-legacy parsers"), where the runtime equivalent is
    // `hl.bind` through `hyprctl eval`. Both forms verified live,
    // including that `hyprctl binds -j` echoes the description back so
    // the cheatsheet can read it.
    function _bindArgs(form: string): var {
        if (form === "lua")
            return ["hyprctl", "eval", `hl.bind("${root.combo}", hl.dsp.exec_cmd("${root.command}"), { description = "${root.description}" })`];
        return ["hyprctl", "keyword", "bindd", `${root.legacyCombo}, ${root.description}, exec, ${root.command}`];
    }

    function _unbindArgs(form: string): var {
        if (form === "lua")
            return ["hyprctl", "eval", `hl.unbind("${root.combo}")`];
        return ["hyprctl", "keyword", "unbind", root.legacyCombo];
    }

    // Binding a combo replaces whatever held it, so switching form needs
    // no unbind of its own. Only going back to nothing does.
    function _sync(): void {
        const want = root.desiredForm;
        const had = root._applied;
        if (want === had)
            return;
        root._applied = want;
        binder.command = want.length > 0 ? root._bindArgs(want) : root._unbindArgs(had);
        binder.running = false;
        binder.running = true;
    }

    onDesiredFormChanged: root._sync()
    Component.onCompleted: root._sync()

    // A shell that exits leaves the bind pointing at an IPC target that
    // has gone. Hyprland outlives the shell, so this is the one moment
    // worth cleaning up at; a kill -9 skips it and the next start
    // re-asserts the same combo over the stale one.
    Component.onDestruction: {
        if (root._applied.length > 0)
            Quickshell.execDetached(root._unbindArgs(root._applied));
    }

    Process {
        id: binder
    }
}
