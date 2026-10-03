pragma Singleton
import QtQuick
import Quickshell
Singleton {
    readonly property string leftReason: left.reason
    readonly property string rightReason: right.reason
    readonly property bool running: left.busy || right.busy
    ShelfShortcut { id: left; edge: "left" }
    ShelfShortcut { id: right; edge: "right" }
}
