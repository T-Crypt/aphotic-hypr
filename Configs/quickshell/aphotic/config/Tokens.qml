pragma Singleton
import QtQuick

// Values below match caelestia-dots/shell's native plugin defaults
// (plugin/src/Caelestia/Config/tokens.cpp at the pinned commit) where a
// real default exists, so this hand-written singleton renders the same
// as upstream out of the box. `rounding` (not `radius`) matches the real
// vendored QML's own naming — confirmed via grep, nothing here uses
// "radius".
QtObject {
    readonly property QtObject padding: QtObject {
        readonly property int extraSmall: 4
        readonly property int small: 8
        readonly property int medium: 12
        readonly property int large: 16
        readonly property int largeIncreased: 20
        readonly property int extraLarge: 28
        readonly property int extraLargeIncreased: 32
        readonly property int extraExtraLarge: 48
    }

    readonly property QtObject spacing: QtObject {
        readonly property int extraSmall: 4
        readonly property int small: 8
        readonly property int medium: 12
        readonly property int large: 16
        readonly property int largeIncreased: 20
        readonly property int extraLarge: 28
        readonly property int extraLargeIncreased: 32
        readonly property int extraExtraLarge: 48
    }

    readonly property QtObject rounding: QtObject {
        readonly property int extraSmall: 4
        readonly property int small: 8
        readonly property int medium: 12
        readonly property int large: 16
        readonly property int largeIncreased: 20
        readonly property int extraLarge: 28
        readonly property int extraLargeIncreased: 32
        readonly property int extraExtraLarge: 48
        readonly property int full: 999999
    }

    readonly property QtObject sizes: QtObject {
        readonly property QtObject bar: QtObject {
            readonly property int innerWidth: 48
        }

        readonly property QtObject launcher: QtObject {
            readonly property int width: 640
            readonly property int itemHeight: 56
            readonly property int maxShown: 8
        }

        readonly property QtObject notifs: QtObject {
            readonly property int width: 380
            readonly property int image: 40
        }

        readonly property QtObject osd: QtObject {
            readonly property int sliderWidth: 260
            readonly property int sliderHeight: 44
        }

        readonly property QtObject session: QtObject {
            readonly property int button: 96
        }
    }

    readonly property QtObject fontSize: QtObject {
        readonly property int small: 11
        readonly property int smaller: 12
        readonly property int normal: 13
        readonly property int larger: 15
        readonly property int large: 18
        readonly property int extraLarge: 28
    }

    readonly property QtObject anim: QtObject {
        readonly property QtObject durations: QtObject {
            readonly property int small: 200
            readonly property int normal: 400
            readonly property int large: 600
            readonly property int extraLarge: 1000
            readonly property int expressiveFastSpatial: 350
            readonly property int expressiveDefaultSpatial: 500
            readonly property int expressiveSlowSpatial: 650
            readonly property int expressiveFastEffects: 150
            readonly property int expressiveDefaultEffects: 200
            readonly property int expressiveSlowEffects: 300
        }

        readonly property var emphasized: ({
            type: Easing.BezierSpline,
            bezierCurve: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]
        })
        readonly property var emphasizedAccel: ({ type: Easing.BezierSpline, bezierCurve: [0.3, 0, 0.8, 0.15, 1, 1] })
        readonly property var emphasizedDecel: ({ type: Easing.BezierSpline, bezierCurve: [0.05, 0.7, 0.1, 1, 1, 1] })
        readonly property var standard: ({ type: Easing.BezierSpline, bezierCurve: [0.2, 0, 0, 1, 1, 1] })
        readonly property var standardAccel: ({ type: Easing.BezierSpline, bezierCurve: [0.3, 0, 1, 1, 1, 1] })
        readonly property var standardDecel: ({ type: Easing.BezierSpline, bezierCurve: [0, 0, 0, 1, 1, 1] })
        readonly property var expressiveFastSpatial: ({ type: Easing.BezierSpline, bezierCurve: [0.42, 1.67, 0.21, 0.9, 1, 1] })
        readonly property var expressiveDefaultSpatial: ({ type: Easing.BezierSpline, bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1] })
        readonly property var expressiveSlowSpatial: ({ type: Easing.BezierSpline, bezierCurve: [0.39, 1.29, 0.35, 0.98, 1, 1] })
        readonly property var expressiveFastEffects: ({ type: Easing.BezierSpline, bezierCurve: [0.31, 0.94, 0.34, 1, 1, 1] })
        readonly property var expressiveDefaultEffects: ({ type: Easing.BezierSpline, bezierCurve: [0.34, 0.8, 0.34, 1, 1, 1] })
        readonly property var expressiveSlowEffects: ({ type: Easing.BezierSpline, bezierCurve: [0.34, 0.88, 0.34, 1, 1, 1] })
    }

    // Simplified stand-in for the native FontBuilder/QFont variable-axis
    // system (plugin/src/Caelestia/Config/fontbuilder.cpp) -- still no
    // real variable-font axis plumbing (vaxes()/fill()/grade()/width()
    // remain harmless no-ops), but body/title/label now resolve to a
    // real installed UI face (Inter, ttf inter-font) instead of falling
    // back to whatever the system default sans happens to be, so
    // font.weight actually selects a real designed weight face rather
    // than relying on synthetic bolding. Material Symbols Rounded IS
    // installed (ttf-material-symbols-variable) and set as the icon
    // font's family below; only the specific sizes actually read by
    // vendored bar components are populated with real point sizes.
    // Each mutator returns a BRAND NEW builder over a copy of state, rather
    // than mutating shared closure state in place. This matters because
    // `_fontStyle`'s `builders.*` entries are `readonly property` objects
    // created once and shared across every consumer -- if a mutator like
    // `scale()` mutated shared state instead, every re-evaluation of a
    // binding that calls it (e.g. driven by Time.hourStr ticking every
    // second) would compound the mutation forever on the same shared
    // object, permanently ballooning that property for every other
    // consumer too. This was a real bug: DashDateTime.qml's clock digits
    // grew without bound because they called
    // `Tokens.font.headline.builders.large.scale(1.3)...` every second.
    function _fontBuilder(pointSize, weight, family, italic, letterSpacing) {
        const state = {
            family: family ?? "Inter",
            pointSize: pointSize ?? 13,
            weight: weight ?? Font.Normal,
            italic: italic ?? false,
            letterSpacing: letterSpacing ?? 0
        };
        const next = patch => _fontBuilder(patch.pointSize ?? state.pointSize, patch.weight ?? state.weight, patch.family ?? state.family, patch.italic ?? state.italic, patch.letterSpacing ?? state.letterSpacing);
        return {
            family: f => next({ family: f }),
            size: pt => next({ pointSize: pt }),
            weight: w => next({ weight: w }),
            italic: on => next({ italic: on }),
            stretch: () => next({}),
            letterSpacing: amt => next({ letterSpacing: amt }),
            capitalisation: () => next({}),
            vaxis: () => next({}),
            vaxes: () => next({}),
            fill: () => next({}),
            grade: () => next({}),
            width: () => next({}),
            scale: factor => next({ pointSize: Math.max(1, Math.round(state.pointSize * factor)) }),
            build: () => ({ family: state.family, pointSize: state.pointSize, weight: state.weight, italic: state.italic, letterSpacing: state.letterSpacing })
        };
    }

    function _fontStyle(smallPt, mediumPt, largePt, family) {
        return {
            small: _fontBuilder(smallPt, undefined, family).build(),
            medium: _fontBuilder(mediumPt, undefined, family).build(),
            large: _fontBuilder(largePt, undefined, family).build(),
            builders: {
                small: _fontBuilder(smallPt, undefined, family),
                medium: _fontBuilder(mediumPt, undefined, family),
                large: _fontBuilder(largePt, undefined, family)
            }
        };
    }

    readonly property QtObject font: QtObject {
        readonly property var headline: _fontStyle(fontSize.larger, fontSize.large, fontSize.extraLarge)
        readonly property var title: _fontStyle(fontSize.normal, fontSize.larger, fontSize.large)
        readonly property var body: _fontStyle(fontSize.small, fontSize.normal, fontSize.larger)
        readonly property var label: _fontStyle(fontSize.small, fontSize.smaller, fontSize.normal)
        // Real monospace family (JetBrainsMono Nerd Font Mono, already
        // installed for terminal use) -- previously fell through to the
        // same default as body/title/label, so "mono" wasn't actually
        // monospace.
        readonly property var mono: _fontStyle(fontSize.small, fontSize.normal, fontSize.larger, "JetBrainsMono Nerd Font Mono")
        readonly property var icon: {
            // Matches caelestia's real default (appearanceconfig.hpp:
            // `m_icon->setDefaultFamily(QStringLiteral("Material Symbols
            // Rounded"))`) — now installed on this system
            // (ttf-material-symbols-variable), so icon glyph names render
            // as real glyphs instead of literal fallback text.
            const iconFamily = "Material Symbols Rounded";
            const b = _fontBuilder(fontSize.normal, undefined, iconFamily);
            b.small = _fontBuilder(fontSize.small, undefined, iconFamily).build();
            b.medium = _fontBuilder(fontSize.normal, undefined, iconFamily).build();
            b.large = _fontBuilder(fontSize.larger, undefined, iconFamily).build();
            b.extraLarge = _fontBuilder(fontSize.extraLarge, undefined, iconFamily).build();
            b.builders = {
                small: _fontBuilder(fontSize.small, undefined, iconFamily),
                medium: _fontBuilder(fontSize.normal, undefined, iconFamily),
                large: _fontBuilder(fontSize.larger, undefined, iconFamily),
                extraLarge: _fontBuilder(fontSize.extraLarge, undefined, iconFamily)
            };
            return b;
        }
        readonly property string workspaces: ""
    }
}
