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
            radius: Tokens.rounding.full
            color: root.checked ? Colours.signal : Colours.layer(Colours.surface, 3)
            border.width: root.checked ? 0 : 1
            border.color: Colours.outline

            Behavior on color {
                CAnim {}
            }
        }

        StyledRect {
            width: root.checked ? 16 : 12
            height: width
            radius: Tokens.rounding.full
            color: root.checked ? Colours.contrastOn(Colours.signal) : Colours.inkMuted
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - 3 : 5

            Behavior on width {
                Anim {}
            }

            Behavior on x {
                Anim {}
            }
        }

        Interact {
            anchors.fill: parent
            onClicked: root.toggled(!root.checked)
        }
    }
}
