import QtQuick
import qs.config
import qs.services

SettingsRow {
    id: root

    required property bool checked
    icon: "tune"
    activatable: true
    onActivated: root.toggled(!root.checked)

    signal toggled(state: bool)

    Item {
        id: switchTrack

        implicitWidth: 40
        implicitHeight: 22

        StyledRect {
            anchors.fill: parent
            radius: height / 2
            color: root.checked ? Colours.palette.m3primary : Colours.layer(Colours.tPalette.m3surfaceContainer, 3)
            border.width: root.checked ? 0 : 1
            border.color: Colours.palette.m3outlineVariant

            Behavior on color {
                CAnim {}
            }
        }

        StyledRect {
            width: root.checked ? 16 : 12
            height: width
            radius: width / 2
            color: root.checked ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - 3 : 5

            Behavior on width {
                Anim {}
            }

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
