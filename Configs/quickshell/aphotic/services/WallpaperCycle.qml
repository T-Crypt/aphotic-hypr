pragma Singleton

import QtQuick
import Quickshell
import qs.services

// Advances the wallpaper on a Timer via the same `aphotic wallpaper
// --random` path SUPER+W and the launcher's "~" mode already use --
// stays within the active theme's own wallpaper pool since that's what
// wallswitcher.py (which --random delegates to) already does, not a
// second implementation. Paused (not stopped) while Settings' Appearance/
// Theme Creator pane is open (UiPickerState) or the session is
// locked/idle (SessionLockState) -- pausing just skips ticks rather than
// resetting the interval, so re-enabling either condition resumes on
// roughly the same cadence instead of restarting the countdown.
Singleton {
    id: root

    Timer {
        interval: Settings.wallpaperAutoCycleInterval * 60 * 1000
        running: Settings.wallpaperAutoCycleEnabled
        repeat: true
        triggeredOnStart: false
        onTriggered: {
            if (UiPickerState.active || SessionLockState.locked)
                return;
            Quickshell.execDetached(["aphotic", "wallpaper", "--random"]);
        }
    }
}
