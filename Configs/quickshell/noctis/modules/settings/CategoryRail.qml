pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property string currentCategory
    required property var categories // [{ id, icon, label }]

    signal categorySelected(id: string)

    readonly property var filteredCategories: {
        const q = searchInput.text.trim().toLowerCase();
        return q.length === 0 ? root.categories : root.categories.filter(c => c.label.toLowerCase().includes(q));
    }

    spacing: Tokens.spacing.small

    StyledRect {
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        Layout.bottomMargin: Tokens.spacing.small
        radius: Tokens.rounding.full
        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "search"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            TextInput {
                id: searchInput

                Layout.fillWidth: true
                clip: true
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurface

                Keys.onEscapePressed: searchInput.text = ""

                StyledText {
                    visible: searchInput.text.length === 0
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Search settings…")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }
        }
    }

    Repeater {
        model: ScriptModel {
            values: root.filteredCategories
        }

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

                    Behavior on fill {
                        CAnim {}
                    }
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

    StyledText {
        visible: root.filteredCategories.length === 0
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.medium
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: qsTr("No matches")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }
}
