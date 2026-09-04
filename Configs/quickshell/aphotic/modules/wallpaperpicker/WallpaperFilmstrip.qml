pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property ScreenState screenState

    readonly property int cellWidth: 300
    readonly property int cellHeight: 169
    readonly property int cellSpacing: 20
    readonly property int slotPitch: cellWidth + cellSpacing
    readonly property real centerScale: 1.35
    readonly property int visibleSlots: 5
    readonly property real centerOffset: (slotPitch * visibleSlots - cellWidth) / 2

    readonly property real flickDeceleration: 1000
    readonly property real maxFlickVelocity: 4800
    readonly property real singleStepVelocity: Math.sqrt(2 * flickDeceleration * slotPitch)

    property string _originalWallpaper: ""
    property int _previewIndex: -1

    implicitWidth: slotPitch * visibleSlots + Tokens.padding.large * 2
    implicitHeight: cellHeight * centerScale + caption.implicitHeight + Tokens.spacing.large + Tokens.padding.large * 2

    focus: true

    // Themes.setTheme() writes ~/.local/state/aphotic/theme.json and queues
    // wallust + awww, which rewrites Colours.qml and so hot-reloads the whole
    // Quickshell scene graph. Firing that per scrolled-past index is what made
    // the strip stutter, so the live preview waits for the strip to come to
    // rest and _commit() flushes whatever is still pending.
    function _applyPreview(): void {
        previewDelay.stop();
        const index = root._previewIndex;
        root._previewIndex = -1;
        if (index < 0)
            return;
        const file = Themes.wallpapersInActiveTheme[index];
        if (file && file !== Themes.activeWallpaper)
            Themes.setWallpaperInActiveTheme(file);
    }

    function _cancelPreview(): void {
        previewDelay.stop();
        root._previewIndex = -1;
    }

    function _commit(): void {
        root._applyPreview();
        root.screenState.wallpaperPicker = false;
    }

    function _revertAndClose(): void {
        root._cancelPreview();
        Themes.setWallpaperInActiveTheme(root._originalWallpaper);
        root.screenState.wallpaperPicker = false;
    }

    function _clampVelocity(v: real): real {
        return Math.max(-root.maxFlickVelocity, Math.min(root.maxFlickVelocity, v));
    }

    function _indexAtCenter(): int {
        if (strip.count === 0)
            return -1;
        const slot = Math.round((strip.contentX + root.centerOffset) / root.slotPitch);
        return Math.max(0, Math.min(slot, strip.count - 1));
    }

    function _targetContentX(index: int): real {
        const clamped = Math.max(0, Math.min(index, strip.count - 1));
        return clamped * root.slotPitch - root.centerOffset;
    }

    function _settle(): void {
        settleAnim.to = root._targetContentX(strip.currentIndex);
        settleAnim.restart();
        root._previewIndex = strip.currentIndex;
        previewDelay.restart();
    }

    function _flickToIndex(targetIndex: int): void {
        const clamped = Math.max(0, Math.min(targetIndex, strip.count - 1));
        const deltaItems = clamped - strip.currentIndex;
        if (deltaItems === 0)
            return;
        const direction = Math.sign(deltaItems);
        const distance = Math.abs(deltaItems) * root.slotPitch;
        strip.flick(root._clampVelocity(-direction * Math.sqrt(2 * root.flickDeceleration * distance)), 0);
    }

    function _wheelImpulse(direction: int): void {
        const combined = -strip.horizontalVelocity + direction * root.singleStepVelocity;
        strip.flick(root._clampVelocity(-combined), 0);
    }

    Keys.onLeftPressed: root._flickToIndex(strip.currentIndex - 1)
    Keys.onRightPressed: root._flickToIndex(strip.currentIndex + 1)
    Keys.onReturnPressed: root._commit()
    Keys.onEscapePressed: root._revertAndClose()

    Connections {
        target: root.screenState
        function onWallpaperPickerChanged() {
            if (!root.screenState.wallpaperPicker)
                return;
            root._cancelPreview();
            root._originalWallpaper = Themes.activeWallpaper;
            const idx = Themes.wallpapersInActiveTheme.indexOf(Themes.activeWallpaper);
            if (idx !== -1) {
                strip.currentIndex = idx;
                strip.contentX = root._targetContentX(idx);
            }
            root.forceActiveFocus();
        }
    }

    Repeater {
        model: Themes.wallpapersInActiveTheme

        Item {
            id: preload

            required property string modelData

            visible: false

            Image {
                source: `file://${Themes.awwwDir}/${Themes.activeTheme}/${preload.modelData}`
                asynchronous: true
                cache: true
                sourceSize.width: root.cellWidth
                sourceSize.height: root.cellHeight
            }
        }
    }

    StyledClippingRect {
        id: filmstripSurface

        anchors.fill: parent
        radius: Tokens.rounding.extraLarge
        color: Colours.palette.m3surfaceContainerHigh
        border.width: Config.border.thickness
        border.color: Colours.palette.m3outlineVariant

        DepthLayer {
            anchors.fill: parent
            opacityScale: 0.7
        }

        DepthGradient {
            anchors.fill: parent
            radius: filmstripSurface.radius
            baseColour: filmstripSurface.color
        }

        Column {
            anchors.centerIn: parent
            spacing: Tokens.spacing.large

            ListView {
                id: strip

                width: root.slotPitch * root.visibleSlots
                height: root.cellHeight * root.centerScale
                orientation: ListView.Horizontal
                spacing: root.cellSpacing
                leftMargin: root.centerOffset
                rightMargin: root.centerOffset
                clip: true
                cacheBuffer: root.slotPitch * 2

                snapMode: ListView.NoSnap

                flickDeceleration: root.flickDeceleration
                maximumFlickVelocity: root.maxFlickVelocity
                boundsBehavior: Flickable.DragOverBounds

                model: Themes.wallpapersInActiveTheme

                onContentXChanged: {
                    // This filmstrip's item tree stays alive even while the
                    // picker window is hidden (only PanelWindow.visible
                    // toggles). Switching themes from Settings elsewhere
                    // reassigns Themes.wallpapersInActiveTheme, which resets
                    // this (currently invisible) ListView's model -- Qt resets
                    // contentX to 0 as part of that, re-entering this handler
                    // while QQuickItemView::setModel is still mid-update.
                    // None of this logic is meaningful while the picker isn't
                    // open, so skip it rather than let it run reentrantly.
                    // The margins below also nudge contentX during creation,
                    // before the required screenState is assigned.
                    if (!root.screenState?.wallpaperPicker)
                        return;
                    const idx = root._indexAtCenter();
                    if (idx !== -1 && idx !== strip.currentIndex)
                        strip.currentIndex = idx;
                }

                onMovementEnded: root._settle()

                Timer {
                    id: previewDelay

                    interval: Tokens.anim.durations.expressiveSlowEffects
                    onTriggered: root._applyPreview()
                }

                SpringAnimation {
                    id: settleAnim

                    target: strip
                    property: "contentX"
                    spring: 2.2
                    damping: 0.42
                }

                WheelHandler {
                    onWheel: event => root._wheelImpulse(event.angleDelta.y < 0 ? 1 : -1)
                }

                delegate: Item {
                    id: delegate

                    required property string modelData
                    required property int index

                    readonly property real itemCenterX: x + width / 2
                    readonly property real viewCenterX: strip.contentX + strip.width / 2
                    readonly property real distance: (itemCenterX - viewCenterX) / root.slotPitch
                    readonly property real closeness: Math.max(0, 1 - Math.abs(distance))

                    width: root.cellWidth
                    height: root.cellHeight
                    y: (strip.height - height) / 2
                    scale: Math.max(0.42, root.centerScale - Math.abs(distance) * 0.34)
                    opacity: Math.max(0.25, 1 - Math.abs(distance) * 0.26)

                    transform: Rotation {
                        origin.x: delegate.width / 2
                        origin.y: delegate.height / 2
                        axis {
                            x: 0
                            y: 1
                            z: 0
                        }
                        angle: Math.max(-32, Math.min(32, delegate.distance * -26))
                    }

                    StyledClippingRect {
                        anchors.fill: parent
                        radius: Tokens.rounding.large
                        color: Colours.tPalette.m3surfaceContainer

                        layer.enabled: Math.abs(delegate.distance) < 1.6
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: Qt.tint(Colours.palette.m3shadow, Qt.alpha(Colours.palette.m3primary, 0.55 * delegate.closeness))
                            shadowOpacity: 0.3 + 0.35 * delegate.closeness
                            shadowBlur: 0.5 + 0.3 * delegate.closeness
                            shadowVerticalOffset: 4
                        }

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
                        onClicked: delegate.index === strip.currentIndex ? root._commit() : root._flickToIndex(delegate.index)
                    }
                }
            }

            Column {
                id: caption

                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Themes.wallpapersInActiveTheme[strip.currentIndex] ?? Themes.activeWallpaper
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3onSurfaceVariant
                    animate: true
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: `${strip.currentIndex + 1} / ${strip.count}`
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                    opacity: 0.7
                }
            }
        }
    }
}
