import QtQuick
import qs.config
import qs.services

// The hover, press and keyboard focus treatment for Signal surfaces: a
// tone wash on hover, a short inset with a soft accent edge on press,
// and the accent line on keyboard focus. Disabled takes none of the three.
MouseArea {
    id: root

    property bool disabled
    property bool showHoverBackground: true
    property bool manualPressOverride
    property bool manualHoverOverride

    property color color: Colours.signalStyle.hover
    // A caller tone washes at layer weight; the default hover tone
    // already carries its own weight and draws at full strength.
    property real stateOpacity: root.hoverActive ? (root._callerTone ? 0.08 : 1) : 0

    property alias radius: hover.radius
    property alias topLeftRadius: hover.topLeftRadius
    property alias topRightRadius: hover.topRightRadius
    property alias bottomLeftRadius: hover.bottomLeftRadius
    property alias bottomRightRadius: hover.bottomRightRadius
    readonly property alias rect: hover

    readonly property bool _callerTone: !Qt.colorEqual(root.color, Colours.signalStyle.hover)
    readonly property bool hoverActive: (containsMouse || root.manualHoverOverride) && root.showHoverBackground && !root.disabled
    readonly property bool pressActive: (pressed || root.manualPressOverride) && !root.disabled
    property real pressInset: root.pressActive ? Tokens.padding.extraSmall : 0

    anchors.fill: parent
    enabled: !root.disabled
    focus: !root.disabled
    cursorShape: root.disabled ? undefined : Qt.PointingHandCursor
    hoverEnabled: true

    StyledRect {
        id: hover

        anchors.fill: parent
        opacity: root.stateOpacity
        color: root.color
        // Pick up radius from parent if it has one (parent can be anything with radius props)
        // qmllint disable missing-property
        radius: root.parent?.radius ?? 0
        topLeftRadius: root.parent?.topLeftRadius ?? radius ?? 0
        topRightRadius: root.parent?.topRightRadius ?? radius ?? 0
        bottomLeftRadius: root.parent?.bottomLeftRadius ?? radius ?? 0
        bottomRightRadius: root.parent?.bottomRightRadius ?? radius ?? 0
        // qmllint enable missing-property
    }

    StyledRect {
        id: press

        x: root.pressInset
        y: root.pressInset
        width: Math.max(0, root.width - root.pressInset * 2)
        height: Math.max(0, root.height - root.pressInset * 2)
        opacity: root.pressActive ? 1 : 0
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(Colours.signalStyle.accentLine, 0.6)
        radius: Math.max(0, hover.radius - root.pressInset)
        topLeftRadius: Math.max(0, hover.topLeftRadius - root.pressInset)
        topRightRadius: Math.max(0, hover.topRightRadius - root.pressInset)
        bottomLeftRadius: Math.max(0, hover.bottomLeftRadius - root.pressInset)
        bottomRightRadius: Math.max(0, hover.bottomRightRadius - root.pressInset)

        Behavior on opacity {
            enabled: RenderGate.decorative && !Motion.reducedMotion
            Anim {
                type: Anim.FastEffects
            }
        }
    }

    StyledRect {
        id: focusLine

        anchors.fill: parent
        visible: root.activeFocus && !root.disabled
        color: "transparent"
        border.width: 2
        border.color: Colours.signalStyle.accentLine
        radius: hover.radius
        topLeftRadius: hover.topLeftRadius
        topRightRadius: hover.topRightRadius
        bottomLeftRadius: hover.bottomLeftRadius
        bottomRightRadius: hover.bottomRightRadius
    }

    Behavior on stateOpacity {
        enabled: RenderGate.decorative && !Motion.reducedMotion
        Anim {
            type: Anim.DefaultEffects
        }
    }

    Behavior on pressInset {
        enabled: RenderGate.decorative && !Motion.reducedMotion
        Anim {
            type: Anim.FastEffects
        }
    }
}
