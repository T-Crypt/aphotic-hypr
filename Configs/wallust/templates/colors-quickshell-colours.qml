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
        readonly property color m3primary: "{{ color4 }}"
        readonly property color m3onPrimary: "{{ color4 | darken(0.8) }}"
        readonly property color m3secondary: "{{ color7 }}"
        readonly property color m3tertiary: "{{ color2 }}"
        readonly property color m3onTertiary: "{{ color2 | darken(0.8) }}"
        readonly property color m3error: "{{ color1 }}"
        readonly property color m3onSurface: "{{ foreground }}"
        readonly property color m3onSurfaceVariant: "{{ foreground | darken(0.2) }}"
        readonly property color m3outlineVariant: "{{ color8 }}"
        readonly property color m3surfaceContainer: "{{ background | lighten(0.1) }}"
        readonly property color m3surfaceContainerHigh: "{{ background | lighten(0.2) }}"
        readonly property color m3shadow: "#000000"
    }

    readonly property QtObject tPalette: QtObject {
        readonly property color m3surfaceContainer: root.layer(root.palette.m3surfaceContainer)
    }

    function layer(c: color, layerIndex: var): color {
        return c;
    }
}
