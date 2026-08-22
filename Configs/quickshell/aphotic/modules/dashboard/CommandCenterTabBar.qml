pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

RowLayout {
    id: root

    required property string currentTab
    required property var tabs // [{ id, icon, label }]

    signal tabSelected(id: string)

    spacing: Tokens.spacing.small

    Repeater {
        model: root.tabs

        StyledRect {
            id: tabButton

            required property var modelData
            readonly property bool active: tabButton.modelData.id === root.currentTab

            Layout.preferredHeight: 40
            Layout.preferredWidth: label.implicitWidth + icon.implicitWidth + Tokens.padding.large * 2 + Tokens.spacing.small
            radius: Tokens.rounding.full
            color: tabButton.active ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer

            Behavior on color {
                CAnim {}
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: Tokens.spacing.small

                MaterialIcon {
                    id: icon
                    text: tabButton.modelData.icon
                    color: tabButton.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                    fill: tabButton.active ? 1 : 0
                }

                StyledText {
                    id: label
                    text: tabButton.modelData.label
                    color: tabButton.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
                }
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
                onClicked: root.tabSelected(tabButton.modelData.id)
            }
        }
    }
}
