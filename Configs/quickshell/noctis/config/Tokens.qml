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
    // system (plugin/src/Caelestia/Config/fontbuilder.cpp) — no real
    // variable font is vendored (Google Sans Flex isn't installed on this
    // system, so body/title/etc. still fall back to system default sans),
    // so vaxes()/fill()/grade()/width() are harmless no-ops here rather
    // than real variable-axis writes. Material Symbols Rounded IS
    // installed (ttf-material-symbols-variable) and set as the icon
    // font's family below; only the specific sizes actually read by
    // vendored bar components are populated with real point sizes.
    function _fontBuilder(pointSize, weight, family) {
        const state = {
            family: family ?? "",
            pointSize: pointSize ?? 13,
            weight: weight ?? Font.Normal,
            italic: false,
            letterSpacing: 0
        };
        const builder = {
            family: f => { state.family = f; return builder; },
            size: pt => { state.pointSize = pt; return builder; },
            weight: w => { state.weight = w; return builder; },
            italic: on => { state.italic = on; return builder; },
            stretch: () => builder,
            letterSpacing: amt => { state.letterSpacing = amt; return builder; },
            capitalisation: () => builder,
            vaxis: () => builder,
            vaxes: () => builder,
            fill: () => builder,
            grade: () => builder,
            width: () => builder,
            scale: factor => { state.pointSize = Math.max(1, Math.round(state.pointSize * factor)); return builder; },
            build: () => ({ family: state.family, pointSize: state.pointSize, weight: state.weight, italic: state.italic, letterSpacing: state.letterSpacing })
        };
        return builder;
    }

    function _fontStyle(smallPt, mediumPt, largePt) {
        return {
            small: _fontBuilder(smallPt).build(),
            medium: _fontBuilder(mediumPt).build(),
            large: _fontBuilder(largePt).build(),
            builders: {
                small: _fontBuilder(smallPt),
                medium: _fontBuilder(mediumPt),
                large: _fontBuilder(largePt)
            }
        };
    }

    readonly property QtObject font: QtObject {
        readonly property var headline: _fontStyle(fontSize.larger, fontSize.large, fontSize.extraLarge)
        readonly property var title: _fontStyle(fontSize.normal, fontSize.larger, fontSize.large)
        readonly property var body: _fontStyle(fontSize.small, fontSize.normal, fontSize.larger)
        readonly property var label: _fontStyle(fontSize.small, fontSize.smaller, fontSize.normal)
        readonly property var mono: _fontStyle(fontSize.small, fontSize.normal, fontSize.larger)
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
