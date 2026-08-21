pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property string currentCategory
    required property var categories // [{ id, icon, label }]

    signal categorySelected(id: string)

    spacing: Tokens.spacing.small

    Repeater {
        model: root.categories

        StyledRect {
            id: categoryButton

            required property var modelData
            readonly property bool active: categoryButton.modelData.id === root.currentCategory

            Layout.fillWidth: true
            Layout.preferredHeight: 40
            radius: Tokens.rounding.medium
            color: categoryButton.active ? Colours.palette.m3primary : "transparent"

            Behavior on color {
                CAnim {}
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: categoryButton.modelData.icon
                    color: categoryButton.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                    fill: categoryButton.active ? 1 : 0
                }

                StyledText {
                    text: categoryButton.modelData.label
                    color: categoryButton.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
                }
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
                showHoverBackground: !categoryButton.active
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.categorySelected(categoryButton.modelData.id)
            }
        }
    }
}
