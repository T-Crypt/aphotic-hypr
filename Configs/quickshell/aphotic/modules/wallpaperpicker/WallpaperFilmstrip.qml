pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property ScreenState screenState

    readonly property int cellWidth: 340
    readonly property int cellHeight: 210
    readonly property int cellSpacing: 24

    property string _originalWallpaper: ""

    implicitWidth: cellWidth * 3 + cellSpacing * 4 + Tokens.padding.large * 2
    implicitHeight: cellHeight + label.implicitHeight + Tokens.spacing.large + Tokens.padding.large * 2

    focus: true

    function _commit(): void {
        root.screenState.wallpaperPicker = false;
    }

    // Live-preview scrolling already applied the real wallpaper on every
    // step (see strip.onCurrentIndexChanged) -- Escape has to explicitly
    // put the original one back, not just close, or "cancel" wouldn't
    // actually cancel anything.
    function _revertAndClose(): void {
        Themes.setWallpaperInActiveTheme(root._originalWallpaper);
        root.screenState.wallpaperPicker = false;
    }

    Keys.onLeftPressed: strip.decrementCurrentIndex()
    Keys.onRightPressed: strip.incrementCurrentIndex()
    Keys.onReturnPressed: root._commit()
    Keys.onEscapePressed: root._revertAndClose()

    Connections {
        target: root.screenState
        function onWallpaperPickerChanged() {
            if (!root.screenState.wallpaperPicker)
                return;
            root._originalWallpaper = Themes.activeWallpaper;
            strip.currentIndex = Themes.wallpapersInActiveTheme.indexOf(Themes.activeWallpaper);
            root.forceActiveFocus();
        }
    }

    StyledClippingRect {
        anchors.fill: parent
        radius: Tokens.rounding.extraLarge
        color: Colours.palette.m3surfaceContainerHigh
        border.width: Config.border.thickness
        border.color: Colours.palette.m3outlineVariant

        Column {
            anchors.centerIn: parent
            spacing: Tokens.spacing.large

            ListView {
                id: strip

                width: root.cellWidth * 3 + root.cellSpacing * 2
                height: root.cellHeight
                orientation: ListView.Horizontal
                spacing: root.cellSpacing
                clip: true
                snapMode: ListView.SnapOneItem
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: width / 2 - root.cellWidth / 2
                preferredHighlightEnd: width / 2 - root.cellWidth / 2

                model: Themes.wallpapersInActiveTheme

                onCurrentIndexChanged: {
                    if (currentIndex >= 0 && currentIndex < model.length)
                        Themes.setWallpaperInActiveTheme(model[currentIndex]);
                }

                WheelHandler {
                    onWheel: event => event.angleDelta.y < 0 ? strip.incrementCurrentIndex() : strip.decrementCurrentIndex()
                }

                delegate: Item {
                    id: delegate

                    required property string modelData
                    required property int index

                    readonly property int distance: Math.abs(index - strip.currentIndex)

                    width: root.cellWidth
                    height: root.cellHeight
                    scale: Math.max(0.5, 1 - distance * 0.28)
                    opacity: Math.max(0.35, 1 - distance * 0.3)

                    Behavior on scale {
                        Anim {}
                    }
                    Behavior on opacity {
                        Anim {}
                    }

                    StyledClippingRect {
                        anchors.fill: parent
                        radius: Tokens.rounding.large
                        color: Colours.tPalette.m3surfaceContainer

                        Image {
                            anchors.fill: parent
                            source: `file://${Themes.awwwDir}/${Themes.activeTheme}/${delegate.modelData}`
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize.width: root.cellWidth
                            sourceSize.height: root.cellHeight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: delegate.index === strip.currentIndex ? root._commit() : strip.currentIndex = delegate.index
                    }
                }
            }

            StyledText {
                id: label

                anchors.horizontalCenter: parent.horizontalCenter
                text: Themes.activeWallpaper
                font: Tokens.font.body.medium
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }
}
