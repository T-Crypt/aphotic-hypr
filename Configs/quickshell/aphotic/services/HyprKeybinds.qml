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

    // Categorization for the SUPER+K cheatsheet (modules/keybinds/) --
    // keybinds.lua is a sequence of imperative hl.bind() calls, not a
    // table with a category field (see this file's own header comment
    // and docs/LEDGER.md's queued-items note on why this reads live from
    // hyprctl instead of parsing that file), and Hyprland's bind schema
    // has no room for a custom field of our own to survive the round
    // trip through `hyprctl binds -j` even if one were added there. So
    // this buckets by keyword match against the same `description` text
    // the launcher's "!" mode already displays -- one heuristic instead
    // of a second, driftable source of truth. Order matters: earlier
    // rules must be more specific than later ones (e.g. "move window to
    // workspace N" needs to land in Workspaces, not Windows, so the
    // workspace check runs first).
    readonly property var _categoryOrder: ["Aphotic Shell", "Windows", "Workspaces", "Apps & System", "Capture", "Media & Hardware"]

    function _categoryFor(description: string): string {
        const d = description.toLowerCase();
        if (d.includes("to workspace") || d.includes("switch to workspace") || /^(next|previous) (special )?workspace$/.test(d) || d.includes("empty workspace"))
            return "Workspaces";
        if (/window|floating|pseudotile|split direction|\bgroup\b|fullscreen|\bpin\b/.test(d))
            return "Windows";
        if (d.includes("screenshot") || d.includes("color from screen"))
            return "Capture";
        if (/volume|brightness|microphone|\btrack\b|\bmedia\b|\baudio\b/.test(d))
            return "Media & Hardware";
        if (d.startsWith("open ") || d.includes("lock screen") || d.includes("power/logout"))
            return "Apps & System";
        return "Aphotic Shell";
    }

    // Grouped for the cheatsheet -- each group's items stay in the same
    // alphabetical-by-description order `entries` is already sorted in,
    // since filtering preserves relative order. Empty groups are omitted
    // rather than rendered as a header with nothing under it.
    readonly property var categorizedEntries: root._categoryOrder.map(cat => ({
                category: cat,
                items: root.entries.filter(e => root._categoryFor(e.description) === cat)
            })).filter(g => g.items.length > 0)

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
