pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Keybinds cheatsheet backing data for the launcher's "!" mode
// (modules/launcher/Launcher.qml / KeybindItem.qml). Reads straight from
// `hyprctl binds -j` -- Hyprland's own live bind table -- rather than
// parsing Configs/hypr/keybinds.lua by hand: that file is a sequence of
// imperative `hl.bind(...)` calls (including a `for i = 1, 10` loop
// generating 20 binds at runtime), not a flat table, so a from-scratch
// parser would be real, ongoing-maintenance work for something
// `hyprctl` already resolves correctly. This is also correct for a user
// who has edited their own binds -- it reflects what's actually bound,
// not what this repo's copy of the file says.
//
// Requires each `hl.bind()` call to pass a `description` in its options
// table (`{ description = "..." }`) -- confirmed live that hyprlua's
// bind function accepts this and `hyprctl binds -j` faithfully echoes it
// back via `description`/`has_description`. Binds with no description
// are filtered out here rather than shown with a blank/placeholder label
// -- keybinds.lua currently gives one to every real bind, so this should
// only ever exclude something deliberately left undescribed later.
Singleton {
    id: root

    property var entries: []

    // Hyprland's own modmask bit values (shared with X11/xkbcommon) --
    // SUPER (64), SHIFT (1), CTRL (4), ALT (8) are the only ones this
    // repo's own binds ever use; CAPS/MOD2/MOD3/MOD5 are decoded too
    // (falls back to a generic MODn label) so an unexpected modmask
    // degrades to something readable instead of silently dropping bits.
    readonly property var _modBits: [
        { bit: 64, label: "SUPER" },
        { bit: 8, label: "ALT" },
        { bit: 4, label: "CTRL" },
        { bit: 1, label: "SHIFT" },
        { bit: 2, label: "CAPS" },
        { bit: 16, label: "MOD2" },
        { bit: 32, label: "MOD3" },
        { bit: 128, label: "MOD5" }
    ]

    function _modsFor(modmask: int): string {
        return root._modBits.filter(m => (modmask & m.bit) !== 0).map(m => m.label).join("+");
    }

    // hyprctl's own key names are already mostly readable (single
    // letters, "left"/"right"/"Tab", XF86 media-key names) -- this only
    // prettifies the handful that read awkwardly as-is.
    readonly property var _keyLabels: ({
        "backspace": "Backspace",
        "space": "Space",
        "comma": ",",
        "period": ".",
        "left": "←",
        "right": "→",
        "up": "↑",
        "down": "↓",
        "mouse_down": "Scroll Down",
        "mouse_up": "Scroll Up",
        "mouse:272": "Left Click",
        "mouse:273": "Right Click"
    })

    function _keyLabelFor(key: string): string {
        if (root._keyLabels[key] !== undefined)
            return root._keyLabels[key];
        // "XF86AudioPlay" -> "Audio Play", "XF86MonBrightnessUp" -> "Mon Brightness Up"
        if (key.startsWith("XF86"))
            return key.slice(4).replace(/([a-z])([A-Z])/g, "$1 $2");
        return key;
    }

    function refresh(): void {
        proc.running = true;
    }

    Process {
        id: proc

        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const raw = JSON.parse(text);
                    root.entries = raw.filter(b => b.has_description && b.description).map(b => {
                                const mods = root._modsFor(b.modmask);
                                const keyLabel = root._keyLabelFor(b.key);
                                return {
                                    combo: mods ? `${mods}+${keyLabel}` : keyLabel,
                                    description: b.description
                                };
                            }).sort((a, b) => a.description.localeCompare(b.description));
                } catch (e) {
                    root.entries = [];
                }
            }
        }
    }

    Component.onCompleted: root.refresh()
}
