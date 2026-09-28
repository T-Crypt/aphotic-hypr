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

    readonly property bool signalSkin: Settings.barSignal
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
        border.width: root.signalSkin ? 1 : 0
        border.color: root.signalSkin ? Colours.signalStyle.hairline : "transparent"
        color: root.signalSkin ? Colours.signalStyle.glass : Colours.tPalette.m3surfaceContainer
    }

    StyledRect {
        anchors.left: parent.left
        anchors.leftMargin: root.signalSkin ? 3 : 0
        anchors.top: parent.top
        anchors.topMargin: root.signalSkin ? 3 : 0
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.signalSkin ? 3 : 0
        radius: height / 2
        width: Math.max(height, (parent.width - (root.signalSkin ? 6 : 0)) * root.fraction)
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
        visible: root.signalSkin
        color: Qt.alpha(root.tint, 0.18)
    }

    Item {
        id: iconHost

        x: root.signalSkin ? (root.height - 32) / 2 : Tokens.padding.medium
        y: (root.height - icon.implicitHeight) / 2
        width: root.signalSkin ? 32 : icon.implicitWidth
        height: icon.implicitHeight

        MaterialIcon {
            id: icon

            anchors.centerIn: parent
            text: root.icon
            color: root.signalSkin ? Colours.legibleAccent(root.tint, Colours.signalStyle.surface) : Colours.palette.m3onPrimary
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
        font: root.signalSkin ? Tokens.font.label.builders.medium.weight(Font.DemiBold).build() : Tokens.font.label.medium
        color: root.fraction > 0.85 ? Colours.palette.m3onPrimary
              : (root.signalSkin ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant)
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
