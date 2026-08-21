import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property string icon
    required property real value
    property real to: 1

    signal moved(value: real)
    signal wheelUp()
    signal wheelDown()

    implicitWidth: Tokens.sizes.osd.sliderWidth
    implicitHeight: Tokens.sizes.osd.sliderHeight

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
        width: Math.max(height, parent.width * Math.min(1, root.to > 0 ? root.value / root.to : 0))
        color: Colours.palette.m3primary

        Behavior on width {
            Anim {}
        }
    }

    MaterialIcon {
        anchors.left: parent.left
        anchors.leftMargin: Tokens.padding.medium
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon
        color: Colours.palette.m3onPrimary
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
