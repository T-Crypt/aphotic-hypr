import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property var group

    spacing: Tokens.spacing.small / 2

    StyledText {
        Layout.maximumWidth: 260
        text: root.group?.appClass ?? ""
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    Repeater {
        model: root.group?.windows ?? []

        StyledRect {
            id: row

            required property var modelData

            Layout.fillWidth: true
            Layout.preferredWidth: 260
            implicitHeight: label.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.medium
            color: row.modelData.focused ? Colours.palette.m3secondaryContainer : "transparent"

            StyledText {
                id: label
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.small
                text: row.modelData.title || root.group?.appClass || qsTr("Window")
                elide: Text.ElideRight
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
                onClicked: WindowList.focus(row.modelData.address)
            }
        }
    }
}
