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
// text (this was a real bug: illegible text on some themes). contrastOn()
// picks whichever fixed text color gives the higher real WCAG contrast
// ratio against whatever it's paired with (relLuminance/contrastRatio
// below), not a brightness-threshold guess -- a plain luminance-vs-0.55
// check can rate a saturated mid-tone color (a purple wallpaper's accent,
// for example) as "light enough" for dark text while the pairing is
// still hard to read. mutedOn() applies the same real-ratio check to the
// secondary/muted text blend so it never drops below WCAG AA (4.5:1)
// regardless of wallpaper.
QtObject {
    id: root

    readonly property bool light: false

    // WCAG relative luminance (not the old 0.299/0.587/0.114 "perceptual"
    // weights) -- linearizes each sRGB channel with the real gamma curve
    // before weighting, which is what an actual contrast-ratio calculation
    // requires. The old formula was a brightness estimate, not a contrast
    // measure, so it could rate a color as "light enough" for dark text
    // while that pairing was still hard to read -- e.g. a saturated
    // mid-tone purple wallpaper accent, exactly the case that prompted
    // this rewrite.
    function relLuminance(c: color): real {
        function chan(v) {
            return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        }
        return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b);
    }

    // WCAG contrast ratio between two colors, 1 (identical) to 21 (black
    // on white).
    function contrastRatio(a: color, b: color): real {
        const la = relLuminance(a);
        const lb = relLuminance(b);
        const lighter = Math.max(la, lb);
        const darker = Math.min(la, lb);
        return (lighter + 0.05) / (darker + 0.05);
    }

    readonly property color _lightText: "#f5f1ea"
    readonly property color _darkText: "#14120f"

    // Picks whichever of the two fixed text colors gives the higher real
    // contrast ratio against c, instead of guessing from c's own
    // brightness alone -- guarantees the winner is the actually-more-
    // readable option for any hue/saturation, not just bright-vs-dark.
    function contrastOn(c: color): color {
        const lightRatio = contrastRatio(c, _lightText);
        const darkRatio = contrastRatio(c, _darkText);
        return lightRatio >= darkRatio ? _lightText : _darkText;
    }

    // Same pick as contrastOn, but only used once the ratio against onC
    // (the "full contrast" text color already chosen for this surface)
    // drops below the WCAG AA floor for normal text -- keeps the muted/
    // secondary look everywhere it's already legible, and only steps in
    // where blending would have made it fail outright.
    readonly property real minBodyContrast: 4.5

    function mutedOn(surface: color, onSurface: color, amount: real): color {
        const blended = Qt.tint(onSurface, Qt.alpha(surface, amount));
        return contrastRatio(surface, blended) >= minBodyContrast ? blended : contrastOn(surface);
    }

    // Several bar modules (Clock, Media, StatusIcons, ActiveWindow) use a
    // raw accent role (m3primary/m3secondary/m3tertiary) directly as their
    // icon+text colour, for per-module visual variety rather than flat
    // neutral text everywhere. That's fine as long as the accent itself
    // reads clearly against the dark pill it sits on -- but wallust can
    // hand back a dark, desaturated accent for some wallpapers (this was a
    // real bug: near-illegible dark-green title text on the HackTheBox
    // theme), and unlike onPrimary/onTertiary/onSurface, nothing was
    // contrast-checking the accent against the surface it's actually
    // rendered on. legibleAccent leaves already-legible accents untouched
    // (preserving the intended per-module hue) and only pulls a failing
    // one toward the winning contrastOn() text colour, just enough to
    // clear the same WCAG AA floor mutedOn() already enforces elsewhere.
    function legibleAccent(accent: color, surface: color): color {
        if (contrastRatio(accent, surface) >= minBodyContrast)
            return accent;
        return Qt.tint(accent, Qt.alpha(contrastOn(surface), 0.6));
    }

    readonly property QtObject palette: QtObject {
        readonly property color m3primary: "#4A5A52"
        readonly property color m3onPrimary: root.contrastOn(m3primary)
        readonly property color m3primaryOnSurface: root.legibleAccent(m3primary, m3surfaceContainerHigh)
        readonly property color m3secondary: "#669B04"
        readonly property color m3secondaryOnSurface: root.legibleAccent(m3secondary, m3surfaceContainerHigh)
        readonly property color m3tertiary: "#474E42"
        readonly property color m3onTertiary: root.contrastOn(m3tertiary)
        readonly property color m3tertiaryOnSurface: root.legibleAccent(m3tertiary, m3surfaceContainerHigh)
        readonly property color m3error: "#3E413F"
        readonly property color m3onError: root.contrastOn(m3error)
        readonly property color m3onSurface: root.contrastOn(m3surfaceContainer)
        readonly property color m3onSurfaceVariant: root.mutedOn(m3surfaceContainer, m3onSurface, 0.35)
        readonly property color m3outlineVariant: "#1F201F"
        readonly property color m3surfaceContainer: "#050806"
        readonly property color m3surfaceContainerHigh: "#232624"
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
