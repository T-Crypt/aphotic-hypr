pragma Singleton

import QtQuick
import Quickshell
import qs.services

// Suppresses notification popups (services/Notifs.qml sets popup: false
// while this is enabled -- notifications still land in history, never
// discarded). Persisted via Settings.dndEnabled, not a separate state
// file, since it's a single flag alongside every other bar-icon-adjacent
// toggle already living there.
Singleton {
    id: root

    readonly property bool enabled: Settings.dndEnabled
    property bool _pomodoroForced: false

    function toggle(): void {
        Settings.dndEnabled = !Settings.dndEnabled;
    }

    // Pomodoro's focus phase auto-engages DND and auto-releases it when
    // focus ends -- _pomodoroForced tracks whether THIS connection was the
    // one that turned it on, so ending a focus session never clobbers DND
    // the user had already turned on manually beforehand. Focus Mode
    // (roadmap, not yet built) should hook in the same way once it
    // exists: watch its own active-and-not-paused signal, engage/release
    // through Settings.dndEnabled, with its own forced-tracking flag
    // (don't share _pomodoroForced -- Focus Mode and Pomodoro can be
    // active independently of each other).
    readonly property bool pomodoroFocusActive: Pomodoro.running && !Pomodoro.isBreak

    onPomodoroFocusActiveChanged: {
        if (root.pomodoroFocusActive) {
            if (!Settings.dndEnabled) {
                Settings.dndEnabled = true;
                root._pomodoroForced = true;
            }
        } else if (root._pomodoroForced) {
            Settings.dndEnabled = false;
            root._pomodoroForced = false;
        }
    }
}
