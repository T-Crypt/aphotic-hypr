pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.services

// A card deck along the bottom edge, with the full-resolution wallpaper
// filling the screen behind it. Where the coverflow asks you to judge a
// wallpaper from a 1.35x card, this gets out of the way and lets the actual
// image be the preview -- WallpaperPickerWindow puts the backdrop in
// lossless mode for this layout.
Item {
    id: root

    required property WallpaperPickerModel model

    readonly property int cellHeight: Math.max(96, Math.round(root.height * 0.13))
    readonly property int cellWidth: Math.round(cellHeight * 16 / 9)
    readonly property int cellGap: Tokens.spacing.small

    readonly property string backdropSource: root.model.fullSizeFor(strip.currentIndex)

    // Proximity magnification, the same quadratic falloff DockBar uses for
    // app icons so the two docks in this shell feel like one idea.
    readonly property real magnifyRadius: root.cellWidth * 1.2
    readonly property real magnifyExtra: 0.34

    function magnifyFalloff(centerX: real): real {
        if (!hover.hovered)
            return 1;
        const dist = Math.abs(centerX - hover.point.position.x);
        if (dist >= root.magnifyRadius)
            return 1;
        const t = 1 - dist / root.magnifyRadius;
        return 1 + root.magnifyExtra * t * t;
    }

    focus: true

    function focusActive(): void {
        const idx = root.model.activeIndex;
        strip.currentIndex = idx >= 0 ? idx : 0;
        strip.positionViewAtIndex(strip.currentIndex, ListView.Center);
    }

    function _step(delta: int): void {
        if (strip.count === 0)
            return;
        const next = Math.max(0, Math.min(strip.currentIndex + delta, strip.count - 1));
        if (next === strip.currentIndex)
            return;
        strip.currentIndex = next;
        strip.positionViewAtIndex(next, ListView.Center);
        root.model.queuePreview(next);
    }

    Keys.onLeftPressed: root._step(-1)
    Keys.onRightPressed: root._step(1)
    Keys.onReturnPressed: root.model.commit(strip.currentIndex)
    Keys.onEscapePressed: root.model.revertAndClose()

    HoverHandler {
        id: hover
    }

    Column {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: Tokens.padding.large * 2
        spacing: Tokens.spacing.medium

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Tokens.spacing.extraSmall

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.model.entries[strip.currentIndex]?.file ?? ""
                font: Tokens.font.title.large
                color: Colours.palette.m3onSurface
                animate: true
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.model.entries[strip.currentIndex]?.theme ?? ""
                font: Tokens.font.label.medium
                color: Colours.palette.m3onSurfaceVariant
                animate: true
            }
        }

        StyledRect {
            anchors.horizontalCenter: parent.horizontalCenter

            // The tray is sized to the screen, not to the content, so the
            // deck neither jitters as cards magnify nor stretches to the
            // full width of a hundred-wallpaper library.
            implicitWidth: Math.min(root.width * 0.9, strip.contentWidth + Tokens.padding.large * 2)
            // Headroom for the tallest a magnified card can grow to, so a
            // card near the edge is never clipped by its own tray.
            implicitHeight: root.cellHeight * (1 + root.magnifyExtra) + Tokens.padding.large * 2
            radius: Tokens.rounding.extraLarge
            color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.55)

            ListView {
                id: strip

                anchors.centerIn: parent
                width: Math.min(parent.implicitWidth - Tokens.padding.large * 2, strip.contentWidth)
                height: parent.height
                orientation: ListView.Horizontal
                spacing: root.cellGap
                clip: false
                cacheBuffer: root.cellWidth * 4
                boundsBehavior: Flickable.StopAtBounds

                model: root.model.count

                WheelHandler {
                    // A horizontal deck is scrolled with a vertical wheel
                    // far more often than a horizontal one.
                    onWheel: event => strip.contentX = Math.max(0, Math.min(strip.contentWidth - strip.width, strip.contentX - (event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x)))
                }

                delegate: Item {
                    id: cell

                    required property int index

                    property bool hovered: false

                    readonly property real centerX: cell.x - strip.contentX + cell.width / 2
                    readonly property real magnify: root.magnifyFalloff(cell.centerX)

                    width: root.cellWidth
                    height: strip.height

                    // Cards grow from their bottom edge so the deck keeps a
                    // flat baseline as the wave passes along it. magnify is
                    // a binding on the pointer position rather than an
                    // animated property, which is what makes the wave track
                    // the cursor instead of chasing it -- same as DockBar.
                    z: cell.index === strip.currentIndex ? 2 : Math.round(cell.magnify * 100)

                    WallpaperCard {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Tokens.padding.large

                        width: root.cellWidth * cell.magnify
                        height: root.cellHeight * cell.magnify

                        source: root.model.previewFor(cell.index)
                        decodeWidth: Math.round(root.cellWidth * (1 + root.magnifyExtra))
                        decodeHeight: Math.round(root.cellHeight * (1 + root.magnifyExtra))
                        matteWidth: 64
                        matteHeight: 36
                        distance: 0
                        hovered: cell.hovered
                        active: cell.index === strip.currentIndex
                        locked: cell.index === root.model.activeIndex
                    }

                    MaterialIcon {
                        visible: root.model.entries[cell.index]?.isVideo ?? false
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.margins: Tokens.padding.large + Tokens.padding.small
                        text: "movie"
                        fill: 1
                        color: Colours.palette.m3onSurface
                        fontStyle: Tokens.font.icon.small
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: cell.hovered = true
                        onExited: cell.hovered = false
                        onClicked: {
                            if (cell.index === strip.currentIndex) {
                                root.model.commit(cell.index);
                            } else {
                                strip.currentIndex = cell.index;
                                root.model.queuePreview(cell.index);
                            }
                        }
                    }
                }
            }
        }
    }
}
