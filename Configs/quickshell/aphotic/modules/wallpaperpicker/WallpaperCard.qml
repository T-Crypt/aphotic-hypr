pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.config
import qs.components
import qs.components.effects
import qs.services

Item {
    id: root

    required property string source
    required property int decodeWidth
    required property int decodeHeight
    required property int matteWidth
    required property int matteHeight
    required property int textureWidth
    required property int textureHeight

    property real distance: 0
    property bool active: false
    property bool locked: false

    readonly property real closeness: Math.max(0, 1 - Math.abs(root.distance))
    readonly property real dofAmount: DepthFx.enabled ? Math.min(1, Math.abs(root.distance) * 0.5) : 0

    readonly property int chamfer: Math.max(10, Math.round(root.height * 0.14))
    readonly property int corner: Math.max(4, Math.round(root.height * 0.04))

    property real _punch: 0
    property bool _hovered: false
    property real _lift: root.active ? -root.height * 0.07 : 0

    signal activated
    signal requested

    scale: (root._hovered && !root.active ? 1.05 : 1) * (1 + 0.06 * root._punch)

    onLockedChanged: {
        if (root.locked)
            punch.restart();
    }

    transform: Translate {
        y: root._lift
    }

    Behavior on scale {
        Anim {
            type: Anim.FastEffects
        }
    }

    Behavior on _lift {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    SequentialAnimation {
        id: punch

        NumberAnimation {
            target: root
            property: "_punch"
            to: 1
            duration: Tokens.anim.durations.expressiveFastEffects
            easing: Tokens.anim.expressiveDefaultSpatial
        }
        NumberAnimation {
            target: root
            property: "_punch"
            to: 0
            duration: Tokens.anim.durations.expressiveFastEffects
            easing: Tokens.anim.expressiveDefaultSpatial
        }
    }

    BioluminescentGlow {
        target: body
        radius: Tokens.rounding.large
        glowColour: Colours.palette.m3primary
        glowBlur: 40
        glowSpread: 0.1
        intensity: root.active ? DepthFx.glowIntensity : 0
    }

    Item {
        id: body

        anchors.fill: parent

        layer.enabled: true
        layer.smooth: true
        layer.effect: Mask {
            maskSource: silhouette
            maskThresholdMin: 0
            maskSpreadAtMin: 0
            blurEnabled: root.dofAmount > 0.04
            blur: root.dofAmount
            blurMax: DepthFx.full ? 24 : 12
            autoPaddingEnabled: false
        }

        Rectangle {
            anchors.fill: parent
            color: Colours.tPalette.m3surfaceContainer
        }

        Image {
            anchors.fill: parent
            source: root.source
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            opacity: 0.55
            sourceSize.width: root.matteWidth
            sourceSize.height: root.matteHeight
        }

        Image {
            anchors.fill: parent
            source: root.source
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            sourceSize.width: root.decodeWidth
            sourceSize.height: root.decodeHeight
        }
    }

    BevelPath {
        id: silhouette

        anchors.fill: parent
        visible: false
        layer.enabled: true
        fillColour: "white"
        strokeColour: "transparent"
        strokeWidth: 0
        chamfer: root.chamfer
        corner: root.corner
    }

    BevelPath {
        anchors.fill: parent
        fillColour: "transparent"
        strokeColour: Qt.tint(Colours.palette.m3outlineVariant, Qt.alpha(Colours.palette.m3primary, 0.5 * root.closeness))
        strokeWidth: 1.5
        opacity: 0.25 + 0.35 * root.closeness
        chamfer: root.chamfer
        corner: root.corner
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root._hovered = true
        onExited: root._hovered = false
        onClicked: root.active ? root.activated() : root.requested()
    }

    component BevelPath: Shape {
        id: bevel

        property color fillColour: "transparent"
        property color strokeColour: "transparent"
        property real strokeWidth: 0
        property int chamfer: 44
        property int corner: Tokens.rounding.medium

        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: bevel.fillColour
            strokeColor: bevel.strokeColour
            strokeWidth: bevel.strokeWidth
            joinStyle: ShapePath.MiterJoin

            startX: bevel.chamfer
            startY: 0

            PathLine {
                x: bevel.width - bevel.corner
                y: 0
            }
            PathArc {
                x: bevel.width
                y: bevel.corner
                radiusX: bevel.corner
                radiusY: bevel.corner
            }
            PathLine {
                x: bevel.width
                y: bevel.height - bevel.chamfer
            }
            PathLine {
                x: bevel.width - bevel.chamfer
                y: bevel.height
            }
            PathLine {
                x: bevel.corner
                y: bevel.height
            }
            PathArc {
                x: 0
                y: bevel.height - bevel.corner
                radiusX: bevel.corner
                radiusY: bevel.corner
            }
            PathLine {
                x: 0
                y: bevel.chamfer
            }
            PathLine {
                x: bevel.chamfer
                y: 0
            }
        }
    }
}
