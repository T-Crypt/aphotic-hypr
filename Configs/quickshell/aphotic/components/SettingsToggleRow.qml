import QtQuick
import qs.config
import qs.services

SettingsRow {
    id: root

    required property bool checked
    icon: "tune"

    signal toggled(state: bool)

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
