pragma Singleton
import QtQuick

// wallust-generated: real palette wired in for Task 8, replacing the
// Task 2 hand-hardcoded stand-in. wallust has no native Material You role
// generation (that's matugen's job, still optional/unused here per the
// roadmap), so ANSI-style color0-15 are mapped onto M3 role names by
// convention (color4=blue->primary, color1=red->error, color2=green->
// tertiary) with lighten/darken filters standing in for M3 tonal steps.
QtObject {
    id: root

    readonly property bool light: false

    readonly property QtObject palette: QtObject {
        readonly property color m3primary: "#2C849A"
        readonly property color m3onPrimary: "#091A1F"
        readonly property color m3secondary: "#F4F1EC"
        readonly property color m3tertiary: "#16486A"
        readonly property color m3onTertiary: "#040E15"
        readonly property color m3error: "#321D33"
        readonly property color m3onSurface: "#F4F1EC"
        readonly property color m3onSurfaceVariant: "#C3C1BD"
        readonly property color m3outlineVariant: "#1F2027"
        readonly property color m3surfaceContainer: "#1F212B"
        readonly property color m3surfaceContainerHigh: "#383942"
        readonly property color m3shadow: "#000000"
    }

    readonly property QtObject tPalette: QtObject {
        readonly property color m3surfaceContainer: root.layer(root.palette.m3surfaceContainer)
    }

    function layer(c: color, layerIndex: var): color {
        return c;
    }
}
