pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

RowLayout {
    id: root

    required property string label
    required property bool checked
    property string icon: "tune"

    signal toggled(state: bool)

    Layout.fillWidth: true
    spacing: Tokens.spacing.medium

    MaterialIcon {
        text: root.icon
        color: Colours.palette.m3onSurfaceVariant
        fontStyle: Tokens.font.icon.medium
    }

    StyledText {
        Layout.fillWidth: true
        text: root.label
        font: Tokens.font.body.medium
        elide: Text.ElideRight
    }

    Item {
        id: switchTrack

        implicitWidth: 40
        implicitHeight: 22

        StyledRect {
            anchors.fill: parent
            radius: height / 2
            color: root.checked ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

            Behavior on color {
                CAnim {}
            }
        }

        StyledRect {
            width: 16
            height: 16
            radius: 8
            color: Colours.palette.m3surfaceContainerHigh
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - 3 : 3

            Behavior on x {
                Anim {}
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggled(!root.checked)
        }
    }
}
