import QtQuick
import QtQuick.Effects

// Trimmed copy of the live shell's qs.components.effects/Colouriser.qml --
// same MultiEffect re-tint approach, minus the Tokens-driven CAnim (this
// tree deliberately carries no dependency on the main shell's design-token
// singleton; see this directory's Colours.qml header for why).
MultiEffect {
    property color sourceColor: "black"

    colorization: 1
    brightness: 1 - sourceColor.hslLightness

    Behavior on colorizationColor {
        ColorAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }
}
