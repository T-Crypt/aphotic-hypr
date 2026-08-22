pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.modules.settings

ColumnLayout {
    id: root

    signal back

    readonly property var wallpapers: {
        const result = [];
        for (const theme of Themes.themes) {
            for (const file of theme.wallpapers ?? [])
                result.push({ theme: theme.name, file });
        }
        return result;
    }

    spacing: Tokens.spacing.medium

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        StyledRect {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: Tokens.rounding.full
            color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)

            MaterialIcon {
                anchors.centerIn: parent
                text: "arrow_back"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.back()
            }
        }

        StyledText {
            text: qsTr("All wallpapers")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
        }
    }

    Flickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: width
        contentHeight: grid.implicitHeight
        clip: true

        GridLayout {
            id: grid

            width: parent.width
            columns: Math.max(1, Math.floor(width / (120 + Tokens.spacing.medium)))
            columnSpacing: Tokens.spacing.medium
            rowSpacing: Tokens.spacing.medium

            Repeater {
                model: ScriptModel {
                    values: root.wallpapers
                }

                WallpaperTile {}
            }
        }
    }
}
