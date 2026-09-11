pragma Singleton

import QtQuick
import Quickshell
import qs.services

// Whether decorative motion is worth drawing right now.
//
// Every breathing, pulsing or drifting element in the shell repaints the
// whole window that holds it, whether or not a person can see it. When a
// fullscreen window covers every monitor the shell's chrome is behind it,
// so that repaint buys nothing and costs the same GPU time as always --
// during a game or a film, which is exactly when it is least affordable.
//
// Core surfaces read `decorative` before starting anything that animates
// on its own. Plugins should do the same: one gate for the whole shell
// scales, fifty plugins each with their own idea of "is anyone looking"
// does not.
Singleton {
    id: root

    // Every monitor's active workspace has a fullscreen window on it.
    // Conservative on purpose: one visible monitor without one and the
    // shell keeps animating, because the chrome on that monitor is
    // genuinely on screen.
    readonly property bool covered: {
        const mons = Hypr.monitors?.values ?? [];
        if (mons.length === 0)
            return false;
        return mons.every(m => m.activeWorkspace?.lastIpcObject?.hasfullscreen === true);
    }

    readonly property bool decorative: !root.covered
}
