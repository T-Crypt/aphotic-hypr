pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Static file, NOT wallust-templated -- it used to be regenerated
// wholesale on every theme apply (Task 8), which made a *tracked git
// source file* something ordinary desktop use rewrote constantly: it was
// dirty in the working tree after every theme switch, and `aphotic update`
// (`git pull`) hit a real checkout conflict against that machine-local
// drift. The raw palette now lives in ~/.local/state/aphotic/palette.json
// (wallust's plugin_palette template, see Configs/wallust/wallust.toml and
// colors-plugin-palette.json) -- the same file the plugin system already
// reads -- and this file just reads it too, at runtime, via the FileView
// below. See docs/IN_FLIGHT.md item 3 for the full writeup.
//
// wallust has no native Material You role generation (that's matugen's
// job, still optional/unused here per the roadmap), so ANSI-style
// color0-15 are mapped onto M3 role names by convention (color4=blue->
// primary, color1=red->error, color2=green->tertiary) -- same mapping the
// old per-theme template used, just resolved here instead of at
// template-render time.
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
Singleton {
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

    // Raw resolved palette, read once at load and again on every future
    // theme apply (watchChanges catches wallust's rewrite of the target
    // file). Empty object until the first successful load -- the ?? "..."
    // fallbacks below are the same literal defaults the old Task 2
    // hand-hardcoded stand-in used, so a fresh install with no theme
    // applied yet still renders something coherent instead of black.
    property var _raw: ({})

    FileView {
        id: paletteFile

        path: `${Quickshell.env("HOME")}/.local/state/aphotic/palette.json`
        watchChanges: true
        onLoaded: {
            try {
                root._raw = JSON.parse(text());
            } catch (e) {
                root._raw = {};
            }
        }
        onLoadFailed: root._raw = {}
    }

    // watchChanges alone does not reliably re-fire when wallust rewrites
    // this file on every theme apply (confirmed live: instrumented
    // onLoaded/onLoadFailed with console.log, applied several themes in a
    // row via `aphotic theme set`, only the shell-startup load ever
    // logged -- every subsequent external rewrite produced zero reload,
    // leaving the whole shell frozen on whatever palette was active at
    // launch). Same root cause and same fix as Themes.qml's statePath
    // polling Timer (see its own comment) -- polling is the only
    // mechanism this repo controls that survives repeated external
    // rewrites of the same path. The file is a few hundred bytes, so
    // re-reading it every second is free, and reload() on unchanged
    // content is a no-op (same values back into the same properties).
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: paletteFile.reload()
    }

    function _rawColor(key: string, fallback: string): color {
        return root._raw?.colors?.[key] ?? fallback;
    }

    readonly property QtObject palette: QtObject {
        // Settings' Personalization pane can override just the primary
        // accent -- purely additive on top of the wallust-derived value,
        // never touches the wallust pipeline itself, and (unlike when
        // this whole file was regenerated per-theme) nothing can silently
        // discard this check anymore since Colours.qml itself is no
        // longer template output.
        readonly property color m3primary: Settings.accentColorOverride.length > 0 ? Settings.accentColorOverride : root._rawColor("color4", "#5A6089")
        readonly property color m3onPrimary: root.contrastOn(m3primary)
        readonly property color m3primaryOnSurface: root.legibleAccent(m3primary, m3surfaceContainerHigh)
        readonly property color m3secondary: root._rawColor("color7", "#F9EEDA")
        readonly property color m3secondaryOnSurface: root.legibleAccent(m3secondary, m3surfaceContainerHigh)
        readonly property color m3secondaryContainer: Qt.tint(m3surfaceContainerHigh, Qt.alpha(m3secondary, 0.24))
        readonly property color m3onSecondaryContainer: root.legibleAccent(m3secondary, m3secondaryContainer)
        readonly property color m3tertiary: root._rawColor("color2", "#4B836F")
        readonly property color m3onTertiary: root.contrastOn(m3tertiary)
        readonly property color m3tertiaryOnSurface: root.legibleAccent(m3tertiary, m3surfaceContainerHigh)
        readonly property color m3error: root._rawColor("color1", "#BC7541")
        readonly property color m3onError: root.contrastOn(m3error)
        readonly property color m3onSurface: root.contrastOn(m3surfaceContainer)
        readonly property color m3onSurfaceVariant: root.mutedOn(m3surfaceContainer, m3onSurface, 0.35)
        readonly property color m3outlineVariant: root._rawColor("color8", "#535355")
        // surfaceContainer/surfaceContainerHigh aren't ANSI slots -- they're
        // background darken(0.05)/lighten(0.12), computed wallust-side (see
        // colors-plugin-palette.json) so there's one color-math
        // implementation instead of a second one ported into QML/JS.
        readonly property color m3surfaceContainer: root._raw?.surfaceContainer ?? "#000000"
        readonly property color m3surfaceContainerHigh: root._raw?.surfaceContainerHigh ?? "#1F1F1F"
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
