pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property ScreenState screenState

    readonly property int cellHeight: Math.max(120, Math.round(root.height * 0.219))
    readonly property int cellWidth: Math.round(cellHeight * 16 / 9)
    readonly property int cellSpacing: Math.max(8, Math.round(root.width * 0.007))
    readonly property int slotPitch: cellWidth + cellSpacing
    readonly property real centerScale: 1.35
    readonly property int visibleSlots: 5
    readonly property int stripWidth: Math.min(slotPitch * visibleSlots, Math.max(cellWidth, Math.round(root.width * 0.86)))
    readonly property real centerOffset: (stripWidth - cellWidth) / 2

    // The strip clips horizontally, so its height has to clear the tallest a
    // card ever gets -- centre scale times the hover and settle-punch bumps --
    // plus the glow's bleed, or the clip edge slices the top of the card the
    // moment it grows.
    readonly property int stripHeight: Math.round(cellHeight * centerScale * 1.18) + Math.round(cellHeight * 0.28)

    readonly property int textureWidth: Math.round(cellWidth * centerScale)
    readonly property int textureHeight: Math.round(cellHeight * centerScale)
    readonly property int matteWidth: 64
    readonly property int matteHeight: 36

    readonly property int bandHeight: Math.max(320, Math.round(root.height * 0.63))
    readonly property int bandFade: Math.round(bandHeight * 0.15)

    readonly property real flickDeceleration: 1000
    readonly property real maxFlickVelocity: 4800
    readonly property real singleStepVelocity: Math.sqrt(2 * flickDeceleration * slotPitch)

    readonly property string backdropSource: root._pathFor(strip.currentIndex)

    property string _originalWallpaper: ""
    property int _previewIndex: -1
    property int settledIndex: -1

    focus: true

    function _pathFor(index: int): string {
        const file = Themes.wallpapersInActiveTheme[index];
        return file ? `file://${Themes.awwwDir}/${Themes.activeTheme}/${file}` : "";
    }

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

    // centerOffset is derived from the window's width, which is still
    // unresolved when the picker is first shown, so the contentX set on open
    // is computed against the wrong offset and leaves the strip parked
    // between two slots. Re-anchoring whenever the offset changes is what
    // keeps the selected card actually centred.
    function _recenter(): void {
        if (!root.screenState?.wallpaperPicker)
            return;
        strip.contentX = root._targetContentX(strip.currentIndex);
    }

    onCenterOffsetChanged: Qt.callLater(root._recenter)
    onSlotPitchChanged: Qt.callLater(root._recenter)

    function _settle(): void {
        settleAnim.to = root._targetContentX(strip.currentIndex);
        settleAnim.restart();
        root._previewIndex = strip.currentIndex;
        previewDelay.restart();
        root.settledIndex = strip.currentIndex;
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
                Qt.callLater(root._recenter);
            }
            root.settledIndex = -1;
            root.settledIndex = strip.currentIndex;
            root.forceActiveFocus();
        }
    }

    Repeater {
        model: Themes.wallpapersInActiveTheme

        Item {
            id: preload

            required property string modelData

            visible: false

            readonly property string path: `file://${Themes.awwwDir}/${Themes.activeTheme}/${preload.modelData}`

            Image {
                source: preload.path
                asynchronous: true
                cache: true
                sourceSize.width: root.cellWidth
                sourceSize.height: root.cellHeight
            }

            Image {
                source: preload.path
                asynchronous: true
                cache: true
                sourceSize.width: root.matteWidth
                sourceSize.height: root.matteHeight
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: Tokens.spacing.large

        ListView {
            id: strip

            width: root.stripWidth
            height: root.stripHeight
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

            onMovementStarted: root.settledIndex = -1
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

                width: root.cellWidth
                height: root.cellHeight
                y: (strip.height - height) / 2
                scale: Math.max(0.42, root.centerScale - Math.abs(distance) * 0.34)
                opacity: Math.max(0, 1 - Math.abs(distance) * 0.38)

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

                WallpaperCard {
                    anchors.fill: parent

                    source: `file://${Themes.awwwDir}/${Themes.activeTheme}/${delegate.modelData}`
                    decodeWidth: root.cellWidth
                    decodeHeight: root.cellHeight
                    matteWidth: root.matteWidth
                    matteHeight: root.matteHeight
                    textureWidth: root.textureWidth
                    textureHeight: root.textureHeight
                    distance: delegate.distance
                    active: delegate.index === strip.currentIndex
                    locked: delegate.index === root.settledIndex

                    onActivated: root._commit()
                    onRequested: root._flickToIndex(delegate.index)
                }
            }
        }

        Column {
            id: hud

            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Tokens.spacing.small

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Themes.wallpapersInActiveTheme[strip.currentIndex] ?? Themes.activeWallpaper
                font: Tokens.font.title.large
                color: Colours.palette.m3onSurface
                animate: true
            }

            Row {
                id: rail

                readonly property int capacity: 25
                readonly property int shown: Math.min(strip.count, capacity)
                readonly property int start: Math.max(0, Math.min(strip.currentIndex - Math.floor(capacity / 2), strip.count - shown))
                readonly property bool windowed: strip.count > capacity

                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Tokens.spacing.extraSmall

                Repeater {
                    model: rail.shown

                    Item {
                        id: dot

                        required property int index

                        readonly property int wallpaperIndex: rail.start + dot.index
                        readonly property bool current: dot.wallpaperIndex === strip.currentIndex
                        readonly property real edgeFade: rail.windowed ? Math.min(1, (Math.min(dot.index, rail.shown - 1 - dot.index) + 1) / 3) : 1

                        implicitWidth: Tokens.spacing.large
                        implicitHeight: Tokens.spacing.large

                        Rectangle {
                            anchors.centerIn: parent

                            implicitWidth: dot.current ? 9 : 6
                            implicitHeight: implicitWidth
                            radius: implicitWidth / 2
                            color: dot.current ? Colours.palette.m3primary : Colours.palette.m3onSurface
                            opacity: dot.current ? 0.55 + 0.45 * DepthFx.pulse : 0.4 * dot.edgeFade

                            Behavior on implicitWidth {
                                Anim {
                                    type: Anim.FastEffects
                                }
                            }

                            Behavior on color {
                                CAnim {}
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root._flickToIndex(dot.wallpaperIndex)
                        }
                    }
                }
            }
        }
    }
}
