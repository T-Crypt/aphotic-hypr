// DesktopContextMenu.qml -- right-click menu on the desktop background.
// Deliberately flat (no nested submenus) and reuses existing entry
// points rather than building its own wallpaper browser: "Wallpapers &
// Themes" is the exact same action SUPER+CTRL+W already triggers
// (launcher opened pre-filled with "~", which browses themes and drills
// into a theme's own wallpapers -- see shell.qml's openWallpapers()).
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property ScreenState screenState
    required property real menuX
    required property real menuY

    signal dismissed

    readonly property var items: [
        { icon: "wallpaper", label: qsTr("Wallpapers & Themes"), action: () => root._openWallpapers() },
        { icon: "settings", label: qsTr("Settings"), action: () => { root.screenState.settings = true; } }
    ]

    function _openWallpapers(): void {
        if (!root.screenState.launcher)
            root.screenState.launcherPrefill = "~";
        root.screenState.launcher = true;
    }

    x: Math.min(menuX, (parent?.width ?? menuX) - width - Tokens.padding.small)
    y: Math.min(menuY, (parent?.height ?? menuY) - height - Tokens.padding.small)
    implicitWidth: 220
    implicitHeight: column.implicitHeight + Tokens.padding.small * 2

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainerHigh
        border.width: Config.border.thickness
        border.color: Colours.palette.m3outlineVariant

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colours.palette.m3shadow
            shadowOpacity: 0.5
            shadowBlur: 0.5
            shadowVerticalOffset: 2
        }
    }

    Column {
        id: column

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.small

        Repeater {
            model: root.items

            Item {
                id: menuItem

                required property var modelData

                width: column.width
                implicitHeight: Tokens.sizes.launcher.itemHeight * 0.7

                StateLayer {
                    radius: Tokens.rounding.medium
                    onClicked: {
                        menuItem.modelData.action();
                        root.dismissed();
                    }
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.medium
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: menuItem.modelData.icon
                        fontStyle: Tokens.font.icon.medium
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: menuItem.modelData.label
                        font: Tokens.font.body.medium
                    }
                }
            }
        }
    }
}
