pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components
import qs.services

// The echo ring drawn around a dock icon whose launch produced a window.
// One finite animation where motion is allowed; the same outline held for
// the same time with no movement where it is not. It exists only while the
// echo is running, so an icon that is not echoing costs one invisible item.
Item {
    id: root

    required property string key

    property bool echoing: false

    // Off when the echo is not running, so nothing draws for a launch that
    // never produced a window.
    visible: root.echoing

    Rectangle {
        id: ring

        anchors.fill: parent
        anchors.margins: -Tokens.spacing.extraSmall
        radius: Tokens.rounding.full
        color: "transparent"
        border.width: 2
        border.color: Colours.palette.m3primary
        opacity: 0

        SequentialAnimation {
            id: sweep
            NumberAnimation { target: ring; property: "opacity"; to: 1; duration: 120 }
            PauseAnimation { duration: 200 }
            NumberAnimation { target: ring; property: "opacity"; to: 0; duration: 400 }
        }

        Timer {
            id: hold
            interval: 600
            onTriggered: ring.opacity = 0
        }
    }

    onEchoingChanged: {
        if (!root.echoing)
            return;
        if (RenderGate.decorative) {
            sweep.restart();
        } else {
            ring.opacity = 1;
            hold.restart();
        }
    }
}