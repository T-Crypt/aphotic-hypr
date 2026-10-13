// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

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
// Not a singleton: one instance per registration, made by
// services/PluginKeybinds.qml.
Scope {
    id: root

    required property string combo
    required property string command
    required property string description
    required property bool wanted

    // "SUPER + SHIFT + R" -> "SUPER SHIFT, R": the legacy parser wants the
    // key after a comma and the modifiers space-separated. Derived from the
    // one combo the manifest declares, not declared a second time; a combo
    // with no separator passes through as it is.
    readonly property string legacyCombo: {
        const at = root.combo.lastIndexOf(" + ");
        if (at < 0)
            return root.combo;
        return root.combo.slice(0, at).split(" + ").join(" ") + ", " + root.combo.slice(at + 3);
    }

    // "", "lua" or "legacy". A property rather than a branch inside
    // _sync() because `wanted` and `Hypr.usingLua` settle independently --
    // the registry loading, the Hyprland connection coming up -- and
    // reading the parser once, at whatever moment the registry finished,
    // emitted the refused form on a Lua install and left the combo
    // silently unbound. Same reasoning and shape as WorkspaceKeybind's.
    // A conflict or an unresolved reading also means "", so a bind is
    // never asserted over a key somebody else holds.
    readonly property string desiredForm: !root.wanted || !root._checked || root._conflict ? "" : (Hypr.usingLua ? "lua" : "legacy")
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

    // Hyprland's own modifier bits, the same ones HyprKeybinds decodes the
    // cheatsheet with. A combo naming anything outside this table matches
    // no live bind rather than a wrong one.
    readonly property var _modBits: ({ "SUPER": 64, "ALT": 8, "CTRL": 4, "CONTROL": 4, "SHIFT": 1 })

    readonly property var _target: {
        const tokens = root.combo.split(" + ").map(t => t.trim()).filter(t => t.length > 0);
        const key = (tokens.pop() ?? "").toLowerCase();
        let modmask = 0;
        for (const token of tokens)
            modmask |= root._modBits[token.toUpperCase()] ?? 0;
        return { key: key, modmask: modmask };
    }

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
    function _assertScript(form: string): string {
        let script = `hyprctl eval 'hl.unbind("${root.combo}")' 2>/dev/null || true; `
            + `hyprctl keyword unbind "${root.legacyCombo}" 2>/dev/null || true`;
        if (form === "lua")
            script += `; hyprctl eval 'hl.bind("${root.combo}", hl.dsp.exec_cmd("${root.command}"), { description = "${root.description}" })' 2>/dev/null || true`;
        else if (form === "legacy")
            script += `; hyprctl keyword bindd "${root.legacyCombo}, ${root.description}, exec, ${root.command}" 2>/dev/null || true`;
        return script;
    }

    function refresh(): void {
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
        if (want.length > 0)
            binder.command = ["sh", "-c", root._assertScript(want)];
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
