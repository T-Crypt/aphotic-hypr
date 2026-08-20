pragma Singleton
import QtQuick

// Interim hand-hardcoded stand-in for caelestia's real wallust/Material-You
// Colours service (services/Colours.qml upstream) — placed in qs.services,
// NOT qs.config, because already-vendored files (StyledText.qml,
// MaterialIcon.qml) import qs.services to reach it. Only the palette roles
// actually referenced by vendored code (grepped, not guessed) are modeled.
// Task 8 replaces this with a real wallust-generated version — when it
// does, keep it in services/, not config/ as originally planned.
QtObject {
    id: root

    readonly property bool light: false

    readonly property QtObject palette: QtObject {
        readonly property color m3primary: "#8ab4f8"
        readonly property color m3onPrimary: "#062e6f"
        readonly property color m3secondary: "#c2c6dd"
        readonly property color m3tertiary: "#a3c9a8"
        readonly property color m3onTertiary: "#0a3818"
        readonly property color m3error: "#f2b8b5"
        readonly property color m3onSurface: "#e3e2e6"
        readonly property color m3onSurfaceVariant: "#c4c6d0"
        readonly property color m3outlineVariant: "#44474e"
        readonly property color m3surfaceContainer: "#211f26"
        readonly property color m3surfaceContainerHigh: "#2b2930"
        readonly property color m3shadow: "#000000"
    }

    readonly property QtObject tPalette: QtObject {
        readonly property color m3surfaceContainer: root.layer(root.palette.m3surfaceContainer)
    }

    function layer(c: color, layerIndex: var): color {
        return c;
    }
}
