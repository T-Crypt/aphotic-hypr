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
    // Wide enough for every slot it draws, even when that overruns the
    // screen. The strip does not clip, so the outermost cards were already
    // painted out there; capping the width only stopped them receiving
    // clicks, and a click on one fell through to the dismiss handler behind.
    readonly property int stripWidth: slotPitch * visibleSlots
    readonly property real centerOffset: (stripWidth - slotPitch) / 2

    readonly property int heroHeight: Math.round(cellHeight * centerScale)
    readonly property int stripHeight: heroHeight + Math.round(cellHeight * 0.5)

    readonly property int matteWidth: 64
    readonly property int matteHeight: 36

    readonly property int bandHeight: Math.max(320, Math.round(root.height * 0.63))
    readonly property int bandFade: Math.round(bandHeight * 0.15)

    readonly property real flickDeceleration: 1000
    readonly property real maxFlickVelocity: 4800
    readonly property real singleStepVelocity: Math.sqrt(2 * flickDeceleration * slotPitch)

    readonly property string backdropSource: root._pathFor(strip.currentIndex)

    // The strip runs endlessly in both directions by giving the ListView the
    // wallpaper list repeated an odd number of times and living in the middle
    // copy. A "slot" is an index into that repeated space; the wallpaper it
    // shows is slot modulo the real list length.
    readonly property int wallpaperCount: Themes.wallpapersInActiveTheme.length
    readonly property int reps: 21
    readonly property int slotCount: wallpaperCount > 0 ? wallpaperCount * reps : 0
    readonly property int anchorBase: wallpaperCount * Math.floor(reps / 2)

    property string _originalWallpaper: ""
    property int _previewIndex: -1
    property int settledIndex: -1
    property int _pendingIndex: -1

    readonly property int _focusIndex: root._pendingIndex >= 0 ? root._pendingIndex : strip.currentIndex

    focus: true

    function _logical(slot: int): int {
        const n = root.wallpaperCount;
        return n > 0 ? ((slot % n) + n) % n : -1;
    }

    function _fileFor(slot: int): string {
        return Themes.wallpapersInActiveTheme[root._logical(slot)] ?? "";
    }

    function _pathFor(slot: int): string {
        const file = root._fileFor(slot);
        return file ? `file://${Themes.awwwDir}/${Themes.activeTheme}/${file}` : "";
    }

    // Sliding back to the middle copy once the strip is at rest keeps either
    // end out of reach. The content is periodic, so moving contentX by a whole
    // number of copies lands on the same picture and shows nothing.
    function _reanchor(): void {
        if (root.wallpaperCount <= 0 || glideAnim.running)
            return;
        const want = root.anchorBase + root._logical(strip.currentIndex);
        const shift = want - strip.currentIndex;
        if (shift === 0)
            return;
        strip.contentX += shift * root.slotPitch;
        strip.currentIndex = want;
        if (root.settledIndex >= 0)
            root.settledIndex += shift;
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

    // Escaping without having moved used to re-apply the wallpaper that was
    // already active, spending a full wallust + awww + sddm-sync run to
    // arrive back where it started.
    function _revertAndClose(): void {
        root._cancelPreview();
        if (root._originalWallpaper && root._originalWallpaper !== Themes.activeWallpaper)
            Themes.setWallpaperInActiveTheme(root._originalWallpaper);
        root.screenState.wallpaperPicker = false;
    }

    function _clampVelocity(v: real): real {
        return Math.max(-root.maxFlickVelocity, Math.min(root.maxFlickVelocity, v));
    }

    // Both conversions go through originX. A ListView shifts its content
    // origin once the model is long enough, and a delegate then sits at
    // originX + index * slotPitch. Reading it as index * slotPitch put every
    // index-to-position conversion out by however many slots originX had
    // grown to, so a click resolved to a delegate tens of slots away from the
    // one under the pointer. The short unrepeated model never moved originX
    // off zero, which is why this only appeared once the strip started
    // wrapping.
    function _indexAtCenter(): int {
        if (strip.count === 0)
            return -1;
        const slot = Math.round((strip.contentX - strip.originX + root.centerOffset) / root.slotPitch);
        return Math.max(0, Math.min(slot, strip.count - 1));
    }

    function _targetContentX(index: int): real {
        const clamped = Math.max(0, Math.min(index, strip.count - 1));
        return strip.originX + clamped * root.slotPitch - root.centerOffset;
    }

    // Anchor into the middle copy rather than wherever the view happens to
    // sit. Slot 0 is the very edge of the repeated model, where stepping left
    // hits the clamp instead of wrapping, and that is exactly where an open
    // lands if the theme scan has not produced a list yet -- so this runs
    // again when one arrives.
    function _anchorToActive(): void {
        if (!root.screenState?.wallpaperPicker || root.wallpaperCount <= 0)
            return;
        const idx = Themes.wallpapersInActiveTheme.indexOf(Themes.activeWallpaper);
        const slot = root.anchorBase + (idx !== -1 ? idx : root._logical(strip.currentIndex));
        strip.currentIndex = slot;
        strip.contentX = root._targetContentX(slot);
    }

    onWallpaperCountChanged: Qt.callLater(root._anchorToActive)

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
        root._reanchor();
        settleAnim.to = root._targetContentX(strip.currentIndex);
        settleAnim.restart();
        root._previewIndex = root._logical(strip.currentIndex);
        previewDelay.restart();
        root.settledIndex = strip.currentIndex;
    }

    // A keyed step used to be a flick() sized to coast exactly one slot,
    // which fought both the settle spring still writing contentX and the
    // next keypress reading a currentIndex that was mid-flight. _pendingIndex
    // holds the target across an in-flight glide so presses accumulate
    // instead of each restarting from wherever the strip happens to be.
    function _goToIndex(targetIndex: int): void {
        if (strip.count === 0)
            return;
        const clamped = Math.max(0, Math.min(targetIndex, strip.count - 1));
        if (clamped === root._focusIndex)
            return;

        root._cancelPreview();
        root.settledIndex = -1;
        root._pendingIndex = clamped;

        settleAnim.stop();
        glideAnim.stop();
        strip.cancelFlick();

        const steps = Math.max(1, Math.abs(clamped - root._indexAtCenter()));
        glideAnim.duration = Math.min(Tokens.anim.durations.expressiveDefaultSpatial, Tokens.anim.durations.small + 40 * steps);
        glideAnim.from = strip.contentX;
        glideAnim.to = root._targetContentX(clamped);
        glideAnim.start();
    }

    function _step(delta: int): void {
        root._goToIndex(root._focusIndex + delta);
    }

    function _abortGlide(): void {
        glideAnim.stop();
        root._pendingIndex = -1;
    }

    function _wheelImpulse(direction: int): void {
        root._abortGlide();
        const combined = -strip.horizontalVelocity + direction * root.singleStepVelocity;
        strip.flick(root._clampVelocity(-combined), 0);
    }

    Keys.onLeftPressed: root._step(-1)
    Keys.onRightPressed: root._step(1)
    Keys.onReturnPressed: root._commit()
    Keys.onEscapePressed: root._revertAndClose()

    Connections {
        target: root.screenState
        function onWallpaperPickerChanged() {
            if (!root.screenState.wallpaperPicker)
                return;
            root._cancelPreview();
            root._abortGlide();
            root._originalWallpaper = Themes.activeWallpaper;
            root._anchorToActive();
            Qt.callLater(root._recenter);
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
            spacing: 0
            leftMargin: root.centerOffset
            rightMargin: root.centerOffset
            cacheBuffer: root.slotPitch * 2

            snapMode: ListView.NoSnap

            flickDeceleration: root.flickDeceleration
            maximumFlickVelocity: root.maxFlickVelocity
            boundsBehavior: Flickable.DragOverBounds

            model: root.slotCount

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
            onMovementEnded: {
                if (glideAnim.running)
                    return;
                root._settle();
            }
            onDragStarted: root._abortGlide()

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

            NumberAnimation {
                id: glideAnim

                target: strip
                property: "contentX"
                easing: Tokens.anim.emphasizedDecel

                onFinished: {
                    const landed = root._pendingIndex;
                    root._pendingIndex = -1;
                    if (landed < 0)
                        return;
                    strip.currentIndex = landed;
                    root._reanchor();
                    root._previewIndex = root._logical(strip.currentIndex);
                    previewDelay.restart();
                    root.settledIndex = strip.currentIndex;
                }
            }

            WheelHandler {
                onWheel: event => root._wheelImpulse(event.angleDelta.y < 0 ? 1 : -1)
            }

            // The delegate is exactly one slot wide and carries no transform
            // of its own, so the hit areas tile the strip with no gaps and no
            // overlap however far the artwork inside is scaled up. Clicking
            // anywhere in a slot's column picks that wallpaper. Scaling the
            // delegate itself made the enlarged centre card cover its
            // neighbours, and the outermost cards fell outside every hit area
            // and dismissed the picker instead of selecting anything.
            delegate: Item {
                id: delegate

                required property int index

                property bool hovered: false

                readonly property real itemCenterX: x + width / 2
                readonly property real viewCenterX: strip.contentX + strip.width / 2
                readonly property real distance: (itemCenterX - viewCenterX) / root.slotPitch

                width: root.slotPitch
                height: strip.height

                Item {
                    id: art

                    anchors.fill: parent

                    scale: Math.max(0.42, root.centerScale - Math.abs(delegate.distance) * 0.34)
                    opacity: Math.max(0, 1 - Math.abs(delegate.distance) * 0.38)

                    transform: Rotation {
                        origin.x: art.width / 2
                        origin.y: art.height / 2
                        axis {
                            x: 0
                            y: 1
                            z: 0
                        }
                        angle: Math.max(-32, Math.min(32, delegate.distance * -26))
                    }

                    WallpaperCard {
                        anchors.centerIn: parent

                        width: root.cellWidth
                        height: root.cellHeight

                        source: root._pathFor(delegate.index)
                        decodeWidth: root.cellWidth
                        decodeHeight: root.cellHeight
                        matteWidth: root.matteWidth
                        matteHeight: root.matteHeight
                        distance: delegate.distance
                        hovered: delegate.hovered
                        active: delegate.index === strip.currentIndex
                        locked: delegate.index === root.settledIndex
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: delegate.hovered = true
                    onExited: delegate.hovered = false
                    onClicked: delegate.index === strip.currentIndex ? root._commit() : root._goToIndex(delegate.index)
                }
            }
        }

        Column {
            id: hud

            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Tokens.spacing.small

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root._fileFor(strip.currentIndex) || Themes.activeWallpaper
                font: Tokens.font.title.large
                color: Colours.palette.m3onSurface
                animate: true
            }

            Row {
                id: rail

                // Five dots that rotate with the strip rather than one per
                // wallpaper: the middle dot is always where you are, and the
                // rest read as how far a click will travel. A per-wallpaper
                // rail cannot show position in an endless list, and stopped
                // being readable past a couple of dozen wallpapers anyway.
                readonly property int span: Math.min(5, root.wallpaperCount)
                readonly property int half: Math.floor(rail.span / 2)

                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Tokens.spacing.extraSmall

                Repeater {
                    model: rail.span

                    Item {
                        id: dot

                        required property int index

                        readonly property int offset: dot.index - rail.half
                        readonly property bool current: dot.offset === 0

                        implicitWidth: Tokens.spacing.large
                        implicitHeight: Tokens.spacing.large

                        Rectangle {
                            anchors.centerIn: parent

                            implicitWidth: dot.current ? 9 : 6
                            implicitHeight: implicitWidth
                            radius: implicitWidth / 2
                            color: dot.current ? Colours.palette.m3primary : Colours.palette.m3onSurface
                            opacity: dot.current ? 0.55 + 0.45 * DepthFx.pulse : 0.4 - 0.09 * Math.abs(dot.offset)

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
                            onClicked: root._step(dot.offset)
                        }
                    }
                }
            }
        }
    }
}
