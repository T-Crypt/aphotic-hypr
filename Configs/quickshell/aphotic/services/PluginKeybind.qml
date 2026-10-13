// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "PluginKeybindCore.js" as KeybindCore

// One plugin's declared combo, bound while that plugin is enabled and the
// combo is free.
//
// WorkspaceKeybind.qml's plumbing generalised from one hardcoded combo to
// whatever a manifest declares, plus the one thing an arbitrary combo
// needs and a core one did not: the assert clears both parser tables on
// its combo first, which on a combo the user had already bound would
// unbind their bind. So the tables are only cleared once `hyprctl binds
// -j` says every bind on the combo is ours -- Sonar's and ShelfShortcut's
// rule. A foreign bind wins; our own is not a conflict, so re-asserting
// after a compositor reload still works.
//
// A plugin's combo, command and description are a manifest's own text and
// this worker's assert is one shell line. services/PluginKeybindCore.js
// parses the combo and quotes all three on the way in; a combo it cannot
// represent refuses the bind rather than deriving a string Hyprland would
// reject under a modmask that matches no live bind.
//
// Not a singleton: one instance per registration, made by
// services/PluginKeybinds.qml.
Scope {
    id: root

    required property string combo
    required property string command
    required property string description
    required property bool wanted

    // {key, modmask, legacy}, or {error}. One reading of the combo feeds
    // the legacy string the one legacy parser wants, the key and modmask
    // the conflict check compares, and the refusal above.
    readonly property var _parsed: KeybindCore.parse(root.combo)
    readonly property string _comboIssue: root._parsed.error ?? ""

    readonly property string legacyCombo: root._parsed.legacy ?? ""

    // "", "lua" or "legacy". A property rather than a branch inside
    // _sync() because `wanted` and `Hypr.usingLua` settle independently --
    // the registry loading, the Hyprland connection coming up -- and
    // reading the parser once, at whatever moment the registry finished,
    // emitted the refused form on a Lua install and left the combo
    // silently unbound. Same reasoning and shape as WorkspaceKeybind's.
    // A conflict or an unresolved reading also means "", so a bind is
    // never asserted over a key somebody else holds.
    readonly property string desiredForm: !root.wanted || root._comboIssue.length > 0 || !root._checked || root._conflict ? "" : (Hypr.usingLua ? "lua" : "legacy")
    readonly property string appliedForm: root._applied

    property string _applied: ""
    property bool _checked: false
    property bool _conflict: false
    property bool _checking: false
    property bool _checkAgain: false
    property bool _owns: false
    property bool _exited: false
    property bool _collected: false
    property int _exitCode: -1

    // A refused combo counts as no bind at all: no key to look for, and a
    // modmask no live bind can carry, so the check can never call one of
    // them ours.
    readonly property var _target: root._parsed.error
        ? { key: "", modmask: -1 }
        : { key: String(root._parsed.key).toLowerCase(), modmask: root._parsed.modmask }

    function _bindsOnCombo(binds: var): var {
        return (binds || []).filter(b => b && !b.mouse
            && String(b.key).toLowerCase() === root._target.key
            && (b.modmask & 0xff) === root._target.modmask);
    }

    function _isOurs(bind: var): bool {
        return bind.dispatcher === "exec" && bind.arg === root.command;
    }

    // The clear-then-assert sequence, through one shell. Clearing both
    // parser tables is what makes the combo idempotent across restarts and
    // parser switches: Hyprland outlives the shell, the on-exit unbind is
    // fire-and-forget, and a bind a previous start left behind would stack
    // a second binding that runs the action twice on one press. Each clear
    // is a refusal or a no-op on the parser it does not apply to. Nothing
    // is written to the user's config. Quiet on a box with no Hyprland.
    //
    // Every manifest-supplied value is quoted by KeybindCore before it is
    // interpolated here, so the line is the same line whatever the manifest
    // says: nothing in it can end the quote it sits in.
    function _assertScript(form: string): string {
        let script = `hyprctl eval ${KeybindCore.shellQuote(KeybindCore.luaUnbind(root.combo))} 2>/dev/null || true; `
            + `hyprctl keyword unbind ${KeybindCore.shellQuote(root.legacyCombo)} 2>/dev/null || true`;
        if (form === "lua")
            script += `; hyprctl eval ${KeybindCore.shellQuote(KeybindCore.luaBind(root.combo, root.command, root.description))} 2>/dev/null || true`;
        else if (form === "legacy")
            script += `; hyprctl keyword bindd ${KeybindCore.shellQuote(KeybindCore.legacyBind(root._parsed, root.description, root.command))} 2>/dev/null || true`;
        return script;
    }

    function refresh(): void {
        if (root._comboIssue.length > 0) {
            // Nothing is read and nothing is written: the conflict check has
            // no key to compare, so it cannot see the user's bind on the
            // combo the manifest meant, and the clear-then-assert would
            // derive a string Hyprland refuses.
            console.warn(`aphotic keybind: refusing '${root.combo}': ${root._comboIssue}`);
            root._checking = false;
            root._checkAgain = false;
            root._checked = false;
            root._conflict = false;
            root._owns = false;
            root._applied = "";
            return;
        }
        if (root._checking) {
            root._checkAgain = true;
            return;
        }
        root._checking = true;
        root._checkAgain = false;
        root._exited = false;
        root._collected = false;
        check.running = false;
        check.running = true;
    }

    function _finishCheck(): void {
        if (!root._exited || !root._collected)
            return;
        root._checking = false;
        if (root._checkAgain) {
            root._checkAgain = false;
            Qt.callLater(root.refresh);
            return;
        }
        let binds = null;
        if (root._exitCode === 0) {
            try {
                binds = JSON.parse(bindsOut.text);
            } catch (e) {
                binds = null;
            }
        }
        if (!Array.isArray(binds)) {
            // An unresolved reading is not "no conflict": never assert, and
            // never clear a combo that cannot be proven ours.
            root._checked = false;
            root._conflict = false;
            root._owns = false;
            root._sync();
            return;
        }
        const onCombo = root._bindsOnCombo(binds);
        root._conflict = onCombo.some(b => !root._isOurs(b));
        root._owns = onCombo.length > 0 && !root._conflict;
        root._checked = true;
        root._sync();
    }

    function _sync(): void {
        const want = root.desiredForm;
        if (want === root._applied)
            return;
        const had = root._applied;
        root._applied = want;
        if (want.length > 0) {
            const issue = KeybindCore.labelIssue(root.description);
            if (issue.length > 0)
                console.warn(`aphotic keybind: '${root.combo}' is bound without a description: ${issue}`);
            binder.command = ["sh", "-c", root._assertScript(want)];
        }
        else if (had.length > 0 && root._owns)
            binder.command = ["sh", "-c", root._assertScript("")];
        else
            return;
        binder.running = false;
        binder.running = true;
    }

    onDesiredFormChanged: {
        // The parser can resolve after the check did, so a form that only
        // exists once it has is asserted here. A form going away is left to
        // refresh(): clearing a combo on a reading older than the bind table
        // is exactly what would take a user's bind with it.
        if (root.wanted)
            root._sync();
    }
    onWantedChanged: root.refresh()
    Component.onCompleted: root.refresh()

    Connections {
        // A combo this worker passed over as somebody else's stays
        // unbound until the bind table is read again. HyprKeybinds reads
        // it for the cheatsheet and Sonar pings it, so a combo freed out
        // of band is picked up then rather than only at the next start --
        // the same re-check ShelfShortcut.qml hangs off this signal.
        target: HyprKeybinds

        function onEntriesChanged(): void {
            if (root.wanted)
                root.refresh();
        }
    }

    Connections {
        target: Hypr

        function onConfigReloaded(): void {
            // A reload discards runtime binds. Forgetting ownership is what
            // makes the re-check re-assert rather than skip as applied.
            root._applied = "";
            root._checked = false;
            root._conflict = false;
            root._owns = false;
            root.refresh();
        }
    }

    // Hyprland outlives the shell, so a bind left behind points at an IPC
    // target that has gone. Ownership is inspected again rather than
    // unbinding a combo the user has bound over since. Best-effort: a
    // kill -9 skips it, and the next start's clear-then-assert is what
    // actually guarantees a clean combo.
    Component.onDestruction: {
        if (root._applied.length === 0)
            return;
        Quickshell.execDetached(["python3", "-c",
            "import json,subprocess,sys; b=json.loads(subprocess.check_output(['hyprctl','-j','binds'])); k,mm,cmd=sys.argv[1],int(sys.argv[2]),sys.argv[3]; own=[x for x in b if str(x.get('key','')).lower()==k and (x.get('modmask',0)&255)==mm and not x.get('mouse')]; subprocess.run(sys.argv[4:]) if own and all(x.get('dispatcher')=='exec' and x.get('arg')==cmd for x in own) else None",
            root._target.key, String(root._target.modmask), root.command, "sh", "-c", root._assertScript("")]);
    }

    Process {
        id: binder
    }

    Process {
        id: check

        command: ["hyprctl", "-j", "binds"]
        stdout: StdioCollector {
            id: bindsOut

            onStreamFinished: {
                root._collected = true;
                root._finishCheck();
            }
        }

        onExited: (code, status) => {
            root._exitCode = code;
            root._exited = true;
            root._finishCheck();
        }
    }
}
