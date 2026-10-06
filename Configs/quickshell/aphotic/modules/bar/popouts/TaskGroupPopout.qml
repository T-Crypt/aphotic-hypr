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
        text: (root.group?.appClass ?? "").toUpperCase()
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build()
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
            color: (row.modelData.focused ? Qt.alpha(Colours.palette.m3primary, 0.14) : "transparent")

            Rectangle {
                visible: row.modelData.focused
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 2
                height: parent.height - Tokens.padding.small * 2
                radius: Tokens.rounding.full
                color: Colours.signalStyle.accentLine
            }

            StyledText {
                id: label
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.small
                text: row.modelData.title || root.group?.appClass || qsTr("Window")
                color: row.modelData.focused ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
                color: Colours.signalStyle.hover
                stateOpacity: (containsMouse ? 1 : 0)
                onClicked: WindowList.focus(row.modelData.address)
            }
        }
    }
}
