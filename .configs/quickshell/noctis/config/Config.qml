pragma Singleton
import QtQuick

QtObject {
    readonly property QtObject border: QtObject {
        readonly property int thickness: 2
        readonly property int minThickness: 1
        readonly property int rounding: 12
    }

    readonly property QtObject bar: QtObject {
        readonly property bool persistent: true
        readonly property var excludedScreens: []

        readonly property QtObject tray: QtObject {
            readonly property bool compact: true
        }

        readonly property QtObject popouts: QtObject {
            readonly property bool statusIcons: true
            readonly property bool tray: true
            readonly property bool activeWindow: false
        }

        readonly property QtObject activeWindow: QtObject {
            readonly property bool showOnHover: false
        }

        readonly property QtObject scrollActions: QtObject {
            readonly property bool workspaces: true
            readonly property bool volume: true
            readonly property bool brightness: true
        }

        readonly property QtObject entries: QtObject {
            readonly property var values: [
                { id: "logo", enabled: true },
                { id: "workspaces", enabled: true },
                { id: "spacer", enabled: true },
                { id: "activeWindow", enabled: true },
                { id: "tray", enabled: true },
                { id: "clock", enabled: true },
                { id: "statusIcons", enabled: true },
                { id: "power", enabled: true }
            ]
        }
    }
}
