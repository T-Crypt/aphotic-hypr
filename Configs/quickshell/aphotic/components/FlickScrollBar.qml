pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.services

// A grabbable vertical scrollbar for a Flickable.
//
// The drag math sets contentY directly from the mouse delta rather than
// binding drag.target to the thumb: QML's drag mechanics overwrite a bound
// `y` with a plain value on press, which permanently breaks the one-way
// position binding after the first drag. SettingsPanel.qml learned that the
// hard way and this keeps its conclusion.
Item {
    id: root

    required property Flickable flickable

    // Narrow enough to stay out of the way, with the press band widened
    // past it below so it is still easy to grab.
    readonly property int thumbWidth: 8
    readonly property int minThumbHeight: 24

    implicitWidth: root.thumbWidth
    visible: root.flickable.contentHeight > root.flickable.height

    StyledRect {
        id: thumb

        x: 0
        y: root.flickable.visibleArea.yPosition * root.height
        width: root.thumbWidth
        height: Math.max(root.minThumbHeight, root.flickable.visibleArea.heightRatio * root.height)
        radius: Tokens.rounding.full
        color: Colours.palette.m3onSurfaceVariant
        opacity: dragArea.pressed ? 0.7 : dragArea.containsMouse ? 0.55 : 0.35

        Behavior on opacity {
            Anim {
                type: Anim.StandardSmall
            }
        }

        MouseArea {
            id: dragArea

            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            preventStealing: true

            property real pressY: 0
            property real pressContentY: 0

            onPressed: mouse => {
                pressY = mapToItem(root, mouse.x, mouse.y).y;
                pressContentY = root.flickable.contentY;
            }
            onPositionChanged: mouse => {
                if (!pressed)
                    return;
                const trackHeight = root.height - thumb.height;
                if (trackHeight <= 0)
                    return;
                const scrollable = root.flickable.contentHeight - root.flickable.height;
                const deltaY = mapToItem(root, mouse.x, mouse.y).y - pressY;
                root.flickable.contentY = Math.max(0, Math.min(scrollable, pressContentY + deltaY / trackHeight * scrollable));
            }
        }
    }
}
