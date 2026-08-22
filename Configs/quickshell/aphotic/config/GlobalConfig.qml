pragma Singleton
import QtQuick

// Matches caelestia-dots/shell's ServiceConfig defaults
// (plugin/src/Caelestia/Config/serviceconfig.hpp) where applicable.
// brightnessIncrement fixed from Task 2's int 5 to the real qreal 0.1 —
// Brightness is a 0-1 fraction (same shape as Audio's audioIncrement),
// so 5 was a step-count/fraction unit mismatch, not a deliberate choice.
QtObject {
    readonly property QtObject bar: QtObject {
        readonly property QtObject workspaces: QtObject {
            readonly property bool perMonitorWorkspaces: false
            readonly property var specialWorkspaceIcons: []
            readonly property var windowIcons: [
                { regex: "steam(_app_(default|[0-9]+))?", icon: "sports_esports" }
            ]
        }
        readonly property QtObject tray: QtObject {
            readonly property var iconSubs: []
            readonly property var hiddenIcons: []
        }
    }

    readonly property QtObject notifs: QtObject {
        readonly property real defaultExpireTimeout: 5000
    }

    // NetworkUsage.qml (vendored under Task 4) has always read
    // GlobalConfig.dashboard.resourceUpdateInterval, but nothing wired
    // the dashboard in until tonight, so this gap went unnoticed until
    // Dashboard.qml's first real load surfaced it live.
    readonly property QtObject dashboard: QtObject {
        readonly property int resourceUpdateInterval: 2000
    }

    readonly property QtObject services: QtObject {
        readonly property real brightnessIncrement: 0.1
        readonly property real audioIncrement: 0.1
        readonly property real maxVolume: 1.0
        readonly property bool useTwelveHourClock: false
        readonly property int visualiserBars: 60
        readonly property string defaultPlayer: "Spotify"
        readonly property var playerAliases: []
    }
}
