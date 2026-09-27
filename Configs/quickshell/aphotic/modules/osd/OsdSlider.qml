import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property string icon
    required property real value
    property real to: 1
    property real reveal: 1
    readonly property real fraction: Math.min(1, root.to > 0 ? root.value / root.to : 0)

    signal moved(value: real)
    signal wheelUp()
    signal wheelDown()

    implicitWidth: Tokens.sizes.osd.sliderWidth
    implicitHeight: Tokens.sizes.osd.sliderHeight

    opacity: root.reveal
    transform: Translate {
        x: (1 - root.reveal) * Tokens.spacing.large
    }

    StyledRect {
        anchors.fill: parent
        radius: height / 2
        color: Colours.tPalette.m3surfaceContainer
    }

    StyledRect {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        radius: parent.height / 2
        width: Math.max(height, parent.width * root.fraction)
        color: Colours.palette.m3primary

        Behavior on width {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }

    MaterialIcon {
        anchors.left: parent.left
        anchors.leftMargin: Tokens.padding.medium
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon
        color: Colours.palette.m3onPrimary
        scale: 0.9 + 0.25 * root.fraction

        Behavior on scale {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }

    StyledText {
        anchors.right: parent.right
        anchors.rightMargin: Tokens.padding.large
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(root.value * 100) + "%"
        font: Tokens.font.label.medium
        color: root.fraction > 0.85 ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
    }

    MouseArea {
        anchors.fill: parent

        function setFromX(x: real): void {
            root.moved(Math.min(1, Math.max(0, x / width)) * root.to);
        }

        onWheel: event => {
            if (event.angleDelta.y > 0)
                root.wheelUp();
            else if (event.angleDelta.y < 0)
                root.wheelDown();
        }
        onPressed: mouse => setFromX(mouse.x)
        onPositionChanged: mouse => {
            if (pressed)
                setFromX(mouse.x);
        }
    }
}
