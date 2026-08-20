pragma Singleton
import QtQuick

// wallust-generated: real palette wired in for Task 8, replacing the
// Task 2 hand-hardcoded stand-in. wallust has no native Material You role
// generation (that's matugen's job, still optional/unused here per the
// roadmap), so ANSI-style color0-15 are mapped onto M3 role names by
// convention (color4=blue->primary, color1=red->error, color2=green->
// tertiary).
//
// "on" (text/foreground) roles are NOT derived by blindly darkening the
// accent color — some wallust palettes produce dark, desaturated accents,
// and darkening an already-dark color further produces near-invisible
// text (this was a real bug: illegible text on some themes). Instead
// `contrastOn()` below picks pure light or pure dark based on the actual
// luminance of whatever it's paired against, guaranteeing readable text
// regardless of what a given wallpaper's palette looks like.
QtObject {
    id: root

    readonly property bool light: false

    function luminance(c: color): real {
        return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
    }

    function contrastOn(c: color): color {
        return luminance(c) > 0.55 ? "#14120f" : "#f5f1ea";
    }

    readonly property QtObject palette: QtObject {
        readonly property color m3primary: "{{ color4 }}"
        readonly property color m3onPrimary: root.contrastOn(m3primary)
        readonly property color m3secondary: "{{ color7 }}"
        readonly property color m3tertiary: "{{ color2 }}"
        readonly property color m3onTertiary: root.contrastOn(m3tertiary)
        readonly property color m3error: "{{ color1 }}"
        readonly property color m3onError: root.contrastOn(m3error)
        readonly property color m3onSurface: root.contrastOn(m3surfaceContainer)
        readonly property color m3onSurfaceVariant: Qt.tint(m3onSurface, Qt.alpha(m3surfaceContainer, 0.35))
        readonly property color m3outlineVariant: "{{ color8 }}"
        readonly property color m3surfaceContainer: "{{ background | darken(0.05) }}"
        readonly property color m3surfaceContainerHigh: "{{ background | lighten(0.12) }}"
        readonly property color m3shadow: "#000000"
    }

    readonly property QtObject tPalette: QtObject {
        readonly property color m3surfaceContainer: root.layer(root.palette.m3surfaceContainer, 1)
    }

    // Real M3-style elevation: blend a small amount of the primary accent
    // into the base surface color, more at higher layerIndex. Previously a
    // no-op (`return c`) — the bar's surfaces all rendered at the exact
    // same flat tone as the raw wallust background, which is why they
    // barely stood out from the desktop behind them on some wallpapers.
    function layer(c: color, layerIndex: var): color {
        const amount = Math.min(0.16, (layerIndex ?? 1) * 0.05);
        return Qt.tint(c, Qt.alpha(palette.m3primary, amount));
    }
}
