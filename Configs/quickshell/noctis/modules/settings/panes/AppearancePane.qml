pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services

ColumnLayout {
    spacing: Tokens.spacing.medium

    StyledText {
        text: qsTr("Theme")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 3
        columnSpacing: Tokens.spacing.medium
        rowSpacing: Tokens.spacing.medium

        Repeater {
            model: ScriptModel {
                values: Themes.themes
            }

            StyledRect {
                id: themeCard

                required property var modelData
                readonly property bool active: themeCard.modelData.name === Themes.activeTheme

                Layout.preferredWidth: 140
                Layout.preferredHeight: 56
                radius: Tokens.rounding.medium
                color: themeCard.active ? Colours.layer(Colours.tPalette.m3surfaceContainer, 2) : Colours.tPalette.m3surfaceContainer
                border.width: themeCard.active ? 2 : 0
                border.color: Colours.palette.m3primary

                Behavior on color {
                    CAnim {}
                }

                StyledText {
                    anchors.centerIn: parent
                    anchors.margins: Tokens.padding.small
                    width: parent.width - Tokens.padding.small * 2
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: themeCard.modelData.displayName
                    color: themeCard.active ? Colours.palette.m3primary : Colours.palette.m3onSurface
                    font: Tokens.font.body.medium
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    showHoverBackground: !themeCard.active
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (!themeCard.active)
                            Themes.setTheme(themeCard.modelData.name, themeCard.modelData.defaultWallpaper);
                    }
                }
            }
        }
    }

    StyledText {
        visible: Themes.wallpapersInActiveTheme.length > 1
        Layout.topMargin: Tokens.spacing.medium
        text: qsTr("Wallpaper")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
    }

    RowLayout {
        visible: Themes.wallpapersInActiveTheme.length > 1
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        Repeater {
            model: ScriptModel {
                values: Themes.wallpapersInActiveTheme
            }

            StyledRect {
                id: wallpaperPill

                required property string modelData
                readonly property bool active: wallpaperPill.modelData === Themes.activeWallpaper

                Layout.preferredHeight: 32
                Layout.preferredWidth: wallpaperLabel.implicitWidth + Tokens.padding.large * 2
                radius: Tokens.rounding.full
                color: wallpaperPill.active ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer

                StyledText {
                    id: wallpaperLabel
                    anchors.centerIn: parent
                    elide: Text.ElideMiddle
                    text: wallpaperPill.modelData
                    color: wallpaperPill.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    showHoverBackground: !wallpaperPill.active
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Themes.setWallpaperInActiveTheme(wallpaperPill.modelData)
                }
            }
        }
    }
}
