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
    readonly property int slotPitch: cellWidth + cellGap

    readonly property string backdropSource: root.model.fullSizeFor(strip.currentIndex)

    // Unused while the dock renders its backdrop lossless (the wallpaper
    // is the whole screen), stated so the window never has to fall back
    // to another layout's geometry on this one's behalf.
    readonly property int bandHeight: root.height
    readonly property int bandFade: 0

    // Proximity magnification, the same quadratic falloff DockBar uses for
    // app icons so the two docks in this shell feel like one idea.
    readonly property real magnifyRadius: root.cellWidth * 1.3
    readonly property real magnifyExtra: 0.3

    // Hover fades in and out rather than snapping, so the deck settles when
    // the pointer leaves instead of every card dropping at once. The
    // falloff below tracks the pointer live; this only scales how much of
    // it applies.
    property real hoverStrength: hover.hovered ? 1 : 0

    Behavior on hoverStrength {
        NumberAnimation {
            duration: Tokens.anim.durations.expressiveDefaultEffects
            easing: Tokens.anim.emphasizedDecel
        }
    }

    function magnifyFalloff(centerX: real): real {
        if (root.hoverStrength <= 0)
            return 1;
        const dist = Math.abs(centerX - hover.point.position.x);
        if (dist >= root.magnifyRadius)
            return 1;
        const t = 1 - dist / root.magnifyRadius;
        return 1 + root.magnifyExtra * t * t * root.hoverStrength;
    }

    focus: true

    // Called by the window when this layout becomes the visible one. The
    // focus grab is the whole reason it exists: without it the arrow keys
    // land on whatever had focus before and the deck cannot be driven from
    // the keyboard at all.
    function focusActive(): void {
        const idx = root.model.activeIndex;
        strip.currentIndex = idx >= 0 ? idx : 0;
        strip.contentX = root._centeredContentX(strip.currentIndex);
        root.forceActiveFocus();
    }

    // Only while nothing else owns contentX: recentring mid-glide or
    // mid-drag would fight whoever is driving it.
    function _recenterIfIdle(): void {
        if (glide.running || strip.moving || strip.count === 0)
            return;
        strip.contentX = root._centeredContentX(strip.currentIndex);
    }

    function _maxContentX(): real {
        return Math.max(0, strip.contentWidth - strip.width);
    }

    function _centeredContentX(index: int): real {
        const raw = index * root.slotPitch + root.cellWidth / 2 - strip.width / 2;
        return Math.max(0, Math.min(raw, root._maxContentX()));
    }

    // One path for the wheel and the arrow keys both. Scrolling used to
    // pan contentX without touching currentIndex, so the deck slid under a
    // selection that never moved and nothing ever previewed -- you could
    // only apply whatever happened to be selected when the picker opened.
    function _step(delta: int): void {
        if (strip.count === 0)
            return;
        const next = Math.max(0, Math.min(strip.currentIndex + delta, strip.count - 1));
        if (next === strip.currentIndex)
            return;
        strip.currentIndex = next;
        glide.to = root._centeredContentX(next);
        glide.restart();
        root.model.queuePreview(next);
    }

    function _select(index: int): void {
        if (index === strip.currentIndex)
            return;
        strip.currentIndex = index;
        glide.to = root._centeredContentX(index);
        glide.restart();
        root.model.queuePreview(index);
    }

    Keys.onLeftPressed: root._step(-1)
    Keys.onRightPressed: root._step(1)
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Home)
            root._select(0);
        else if (event.key === Qt.Key_End)
            root._select(strip.count - 1);
        else
            return;
        event.accepted = true;
    }
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
            id: tray

            anchors.horizontalCenter: parent.horizontalCenter

            // Sized to the screen rather than to the content, so the deck
            // neither jitters as cards magnify nor stretches to the full
            // width of a hundred-wallpaper library.
            implicitWidth: Math.min(root.width * 0.9, strip.contentWidth + Tokens.padding.large * 2)
            // Headroom for the tallest a magnified card can grow to, so a
            // card near the edge is never clipped by its own tray.
            implicitHeight: root.cellHeight * (1 + root.magnifyExtra) + Tokens.padding.large * 2
            radius: Tokens.rounding.extraLarge
            color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.55)

            ListView {
                id: strip

                anchors.centerIn: parent
                width: tray.implicitWidth - Tokens.padding.large * 2
                height: parent.height
                orientation: ListView.Horizontal
                spacing: root.cellGap
                clip: false
                cacheBuffer: root.cellWidth * 4
                boundsBehavior: Flickable.StopAtBounds

                model: root.model.count
                reuseItems: true

                onWidthChanged: Qt.callLater(root._recenterIfIdle)
                onContentWidthChanged: Qt.callLater(root._recenterIfIdle)

                // Dragging the deck by hand moves the selection to whatever
                // ends up nearest the middle, so a drag and a wheel step
                // leave the picker in the same state.
                onMovementEnded: {
                    if (glide.running || strip.count === 0)
                        return;
                    const nearest = Math.round((strip.contentX + strip.width / 2 - root.cellWidth / 2) / root.slotPitch);
                    root._select(Math.max(0, Math.min(nearest, strip.count - 1)));
                }

                NumberAnimation {
                    id: glide

                    target: strip
                    property: "contentX"
                    duration: Tokens.anim.durations.expressiveFastSpatial
                    easing: Tokens.anim.emphasizedDecel
                }

                // A moving highlight rather than one drawn per card: it
                // slides between selections instead of blinking from one to
                // the next, which is what makes stepping through the deck
                // read as one continuous motion.
                Rectangle {
                    id: highlight

                    readonly property real slotX: strip.currentIndex * root.slotPitch

                    x: highlight.slotX - Tokens.padding.small
                    y: strip.height - Tokens.padding.large - root.cellHeight - Tokens.padding.small
                    // Under the selected card, which draws over the ring's
                    // middle, but above every neighbour so a magnified one
                    // beside it cannot paint over the border.
                    z: 199
                    width: root.cellWidth + Tokens.padding.small * 2
                    height: root.cellHeight + Tokens.padding.small * 2
                    radius: Tokens.rounding.large
                    visible: strip.count > 0
                    color: "transparent"
                    border.width: 2
                    border.color: Colours.palette.m3primary
                    opacity: 0.55 + 0.45 * DepthFx.pulse

                    Behavior on x {
                        NumberAnimation {
                            duration: Tokens.anim.durations.expressiveFastSpatial
                            easing: Tokens.anim.emphasizedDecel
                        }
                    }

                    Behavior on border.color {
                        CAnim {}
                    }
                }

                WheelHandler {
                    // A horizontal deck gets scrolled with a vertical wheel
                    // far more often than a horizontal one. Both are folded
                    // into one axis, then accumulated: a trackpad sends many
                    // small deltas where a mouse notch sends one large one,
                    // and stepping per event would make a trackpad race.
                    property real accumulated: 0

                    onWheel: event => {
                        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                        accumulated += delta;
                        while (Math.abs(accumulated) >= 120) {
                            root._step(accumulated > 0 ? -1 : 1);
                            accumulated += accumulated > 0 ? -120 : 120;
                        }
                    }
                }

                delegate: Item {
                    id: cell

                    required property int index

                    property bool hovered: false

                    ListView.onReused: cell.hovered = false

                    readonly property real centerX: cell.x - strip.contentX + cell.width / 2
                    readonly property real magnify: root.magnifyFalloff(cell.centerX)

                    width: root.cellWidth
                    height: strip.height

                    // magnifyFalloff returns 1 at rest, so every unmagnified
                    // neighbour sits at 100 and a hovered one climbs to 130.
                    // The selected cell was given 2, which put it and the
                    // highlight ring behind its own neighbours rather than
                    // on top of them -- the selection read as landing on the
                    // wrong card. Above the whole magnify range instead.
                    z: cell.index === strip.currentIndex ? 200 : Math.round(cell.magnify * 100)

                    // Scaling a wrapper rather than the card's own width and
                    // height keeps every cell the same size, so the deck
                    // never reflows as the wave passes along it -- only what
                    // is painted changes. The Behavior is what makes the
                    // zoom trail the pointer instead of snapping to it.
                    Item {
                        id: art

                        anchors.fill: parent

                        scale: cell.magnify
                        transformOrigin: Item.Bottom

                        Behavior on scale {
                            NumberAnimation {
                                duration: Tokens.anim.durations.expressiveFastEffects
                                easing: Tokens.anim.emphasizedDecel
                            }
                        }

                        WallpaperCard {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Tokens.padding.large

                            width: root.cellWidth
                            height: root.cellHeight

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
                            if (cell.index === strip.currentIndex)
                                root.model.commit(cell.index);
                            else
                                root._select(cell.index);
                        }
                    }
                }
            }
        }
    }
}
