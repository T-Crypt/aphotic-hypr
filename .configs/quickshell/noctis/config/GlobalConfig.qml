pragma Singleton
import QtQuick

QtObject {
    readonly property QtObject bar: QtObject {
        readonly property QtObject workspaces: QtObject {
            readonly property bool perMonitorWorkspaces: false
        }
    }

    readonly property QtObject services: QtObject {
        readonly property int brightnessIncrement: 5
    }
}
