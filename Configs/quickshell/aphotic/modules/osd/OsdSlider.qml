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

    readonly property color tint: Colours.signalStyle.tint(0)

    implicitWidth: Tokens.sizes.osd.sliderWidth
    implicitHeight: Tokens.sizes.osd.sliderHeight

    opacity: root.reveal
    transform: Translate {
        x: (1 - root.reveal) * Tokens.spacing.large
    }

    StyledRect {
        anchors.fill: parent
        radius: height / 2
        border.width: 1
        border.color: Colours.signalStyle.hairline
        color: Colours.signalStyle.glass
    }

    StyledRect {
        anchors.left: parent.left
        anchors.leftMargin: 3
        anchors.top: parent.top
        anchors.topMargin: 3
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 3
        radius: height / 2
        width: Math.max(height, (parent.width - 6) * root.fraction)
        color: Colours.palette.m3primary

        Behavior on width {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }

    // Signal: 32px icon chip at the leading end, above the fill.
    StyledRect {
        id: iconChip

        anchors.left: parent.left
        anchors.leftMargin: (root.height - 32) / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 32
        height: 32
        radius: 16
        color: Qt.alpha(root.tint, 0.18)
    }

    Item {
        id: iconHost

        x: (root.height - 32) / 2
        y: (root.height - icon.implicitHeight) / 2
        width: 32
        height: icon.implicitHeight

        MaterialIcon {
            id: icon

            anchors.centerIn: parent
            text: root.icon
            color: Colours.legibleAccent(root.tint, Colours.signalStyle.surface)
            scale: 0.9 + 0.25 * root.fraction

            Behavior on scale {
                Anim {
                    type: Anim.FastSpatial
                }
            }
        }
    }

    StyledText {
        anchors.right: parent.right
        anchors.rightMargin: Tokens.padding.large
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(root.value * 100) + "%"
        font: Tokens.font.label.builders.medium.weight(Font.DemiBold).build()
        color: root.fraction > 0.85 ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
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
