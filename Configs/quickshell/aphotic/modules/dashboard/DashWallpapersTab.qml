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

    readonly property var themeInfo: Themes.activeThemeInfo
    readonly property list<string> wallpapers: Themes.wallpapersInActiveTheme
    readonly property int currentIndex: root.wallpapers.indexOf(Themes.activeWallpaper)
    readonly property string themeFolder: `${Themes.awwwDir}/${Themes.activeTheme}`

    // WallpaperTile expects { theme, file } -- every entry here shares the
    // current theme since this tab only cycles within it (switching themes
    // entirely stays in Appearance).
    readonly property var tileModel: {
        const theme = Themes.activeTheme;
        return root.wallpapers.map(file => ({ theme, file }));
    }

    spacing: Tokens.spacing.medium

    component IconButton: Item {
        id: btn

        required property string icon
        property bool enabled_: true
        signal clicked

        implicitWidth: icon_.implicitHeight + Tokens.padding.medium * 2
        implicitHeight: btn.implicitWidth
        opacity: btn.enabled_ ? 1 : 0.4

        StateLayer {
            anchors.fill: parent
            radius: Tokens.rounding.full
            disabled: !btn.enabled_
            onClicked: btn.clicked()
        }

        MaterialIcon {
            id: icon_
            anchors.centerIn: parent
            text: btn.icon
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.medium
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        ColumnLayout {
            spacing: Tokens.spacing.extraSmall

            StyledText {
                Layout.maximumWidth: 220
                text: root.themeInfo?.displayName ?? Themes.activeTheme
                color: Colours.palette.m3onSurface
                font: Tokens.font.title.builders.medium.weight(Font.Medium).build()
                elide: Text.ElideRight
            }

            StyledText {
                Layout.maximumWidth: 220
                text: Themes.activeWallpaper
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }

        Item {
            Layout.fillWidth: true
        }

        StyledText {
            visible: root.wallpapers.length > 0
            text: qsTr("%1 of %2").arg(Math.max(0, root.currentIndex) + 1).arg(root.wallpapers.length)
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }

        IconButton {
            icon: "folder_open"
            onClicked: Quickshell.execDetached(["thunar", root.themeFolder])
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Tokens.spacing.medium
        visible: root.wallpapers.length > 0

        IconButton {
            icon: "chevron_left"
            enabled_: root.wallpapers.length > 1
            onClicked: Themes.previousWallpaper()
        }

        GridLayout {
            id: grid

            columns: Math.max(1, Math.min(4, root.wallpapers.length))
            columnSpacing: Tokens.spacing.medium
            rowSpacing: Tokens.spacing.medium

            Repeater {
                model: ScriptModel {
                    values: root.tileModel
                }

                WallpaperTile {}
            }
        }

        IconButton {
            icon: "chevron_right"
            enabled_: root.wallpapers.length > 1
            onClicked: Themes.nextWallpaper()
        }
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        visible: root.wallpapers.length === 0
        text: qsTr("No wallpapers found")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.medium
    }
}
