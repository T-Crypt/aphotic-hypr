pragma Singleton
import QtQuick
import qs.config

// bar.* defaults below match caelestia-dots/shell's native plugin
// defaults (plugin/src/Caelestia/Config/barconfig.hpp at the pinned
// commit) except where noted — this repo has no config file/UI yet to
// override these, so matching upstream's own defaults is the safer
// choice absent a stated Noctis-specific preference. border.* keeps
// this repo's original (smaller) values from Task 2 rather than
// upstream's 10/2/25 — no border is actually rendered anywhere yet to
// visually justify swapping it; revisit when Task 7 wires BarWindow.qml.
QtObject {
    readonly property QtObject border: QtObject {
        readonly property int thickness: 2
        readonly property int minThickness: 1
        readonly property int rounding: 12
    }

    readonly property QtObject bar: QtObject {
        readonly property bool persistent: true
        readonly property bool showOnHover: true
        readonly property int dragThreshold: 20
        readonly property var excludedScreens: []

        readonly property QtObject tray: QtObject {
            readonly property bool background: false
            readonly property bool recolour: false
            readonly property bool compact: false
            readonly property var iconSubs: GlobalConfig.bar.tray.iconSubs
            readonly property var hiddenIcons: GlobalConfig.bar.tray.hiddenIcons
        }

        readonly property QtObject clock: QtObject {
            readonly property bool background: false
            readonly property bool showDate: false
            readonly property bool showIcon: true
        }

        readonly property QtObject popouts: QtObject {
            readonly property bool statusIcons: true
            readonly property bool tray: true
            readonly property bool activeWindow: true
        }

        readonly property QtObject activeWindow: QtObject {
            readonly property bool compact: false
            readonly property bool inverted: false
            readonly property bool showOnHover: true
        }

        readonly property QtObject scrollActions: QtObject {
            readonly property bool workspaces: true
            readonly property bool volume: true
            readonly property bool brightness: true
        }

        readonly property QtObject workspaces: QtObject {
            readonly property int shown: 5
            readonly property bool activeIndicator: true
            readonly property bool occupiedBg: false
            readonly property bool showWindows: true
            readonly property bool showWindowsOnSpecialWorkspaces: true
            readonly property int maxWindowIcons: 5
            readonly property bool activeTrail: false
            readonly property bool perMonitorWorkspaces: GlobalConfig.bar.workspaces.perMonitorWorkspaces
            readonly property string label: "  "
            readonly property string occupiedLabel: "󰮯"
            readonly property string activeLabel: "󰮯"
            readonly property string capitalisation: "preserve"
            readonly property var specialWorkspaceIcons: GlobalConfig.bar.workspaces.specialWorkspaceIcons
            readonly property var windowIcons: GlobalConfig.bar.workspaces.windowIcons
        }

        readonly property QtObject statusIcons: QtObject {
            readonly property var values: [
                { id: "lockStatus", enabled: true },
                { id: "audio", enabled: false },
                { id: "microphone", enabled: false },
                { id: "kbLayout", enabled: false },
                { id: "network", enabled: true },
                { id: "bluetooth", enabled: true },
                { id: "battery", enabled: true }
            ]
        }

        readonly property QtObject entries: QtObject {
            readonly property var values: [
                { id: "logo", enabled: true },
                { id: "workspaces", enabled: true },
                { id: "spacer", enabled: true },
                { id: "activeWindow", enabled: true },
                { id: "spacer", enabled: true },
                { id: "tray", enabled: true },
                { id: "clock", enabled: true },
                { id: "statusIcons", enabled: true },
                { id: "power", enabled: true }
            ]
        }
    }

    readonly property QtObject services: QtObject {
        readonly property real brightnessIncrement: GlobalConfig.services.brightnessIncrement
        readonly property bool useTwelveHourClock: GlobalConfig.services.useTwelveHourClock
    }

    // Matches caelestia-dots/shell's OsdConfig defaults
    // (plugin/src/Caelestia/Config/osdconfig.hpp).
    readonly property QtObject osd: QtObject {
        readonly property bool enabled: true
        readonly property int hideDelay: 2000
        readonly property bool enableBrightness: true
        readonly property bool enableMicrophone: false
    }
}
