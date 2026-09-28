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
        text: Settings.barSignal ? (root.group?.appClass ?? "").toUpperCase() : (root.group?.appClass ?? "")
        color: Colours.palette.m3onSurfaceVariant
        font: Settings.barSignal ? Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build() : Tokens.font.label.medium
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
            color: Settings.barSignal ? (row.modelData.focused ? Qt.alpha(Colours.palette.m3primary, 0.14) : "transparent") : (row.modelData.focused ? Colours.palette.m3secondaryContainer : "transparent")

            Rectangle {
                visible: Settings.barSignal && row.modelData.focused
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
                color: Settings.barSignal ? (row.modelData.focused ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant) : Colours.palette.m3onSurface
                elide: Text.ElideRight
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
                color: Settings.barSignal ? Colours.signalStyle.hover : Colours.palette.m3onSurface
                stateOpacity: Settings.barSignal ? (containsMouse ? 1 : 0) : (containsMouse ? 0.08 : 0)
                onClicked: WindowList.focus(row.modelData.address)
            }
        }
    }
}
