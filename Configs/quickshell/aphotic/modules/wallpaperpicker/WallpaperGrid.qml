pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.services

// Every wallpaper across every theme, at a glance. This is the layout that
// earns its keep on a large library: the coverflow shows five entries and
// the dock a dozen, where this shows a screenful and pages by rows.
Item {
    id: root

    required property WallpaperPickerModel model

    readonly property int cellHeight: Math.max(110, Math.round(root.height * 0.16))
    readonly property int cellWidth: Math.round(cellHeight * 16 / 9)
    readonly property int cellGap: Tokens.spacing.medium

    readonly property int columns: Math.max(1, Math.floor((root.width * 0.86 + cellGap) / (cellWidth + cellGap)))

    readonly property string backdropSource: root.model.fullSizeFor(grid.currentIndex)

    // The grid fills the window, so its backdrop has to as well. The
    // window used to hand every layout the coverflow's band (63% of the
    // height, faded at the top), which left the rows below that point
    // sitting on unblurred wallpaper. No fade for the same reason: there
    // is no band edge to soften when the band is the whole screen.
    readonly property int bandHeight: root.height
    readonly property int bandFade: 0

    focus: true

    // The focus grab is load-bearing: without it the arrow keys land on
    // whatever had focus before and the grid cannot be driven from the
    // keyboard at all.
    function focusActive(): void {
        const idx = root.model.activeIndex;
        grid.currentIndex = idx >= 0 ? idx : 0;
        grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
        root.forceActiveFocus();
    }

    // Arrow keys move the selection and queue a preview; the preview itself
    // is deferred inside the model, so holding an arrow down scrolls freely
    // and only the entry it settles on is ever applied.
    function _step(delta: int): void {
        if (grid.count === 0)
            return;
        const next = Math.max(0, Math.min(grid.currentIndex + delta, grid.count - 1));
        if (next === grid.currentIndex)
            return;
        grid.currentIndex = next;
        grid.positionViewAtIndex(next, GridView.Contain);
        root.model.queuePreview(next);
    }

    Keys.onLeftPressed: root._step(-1)
    Keys.onRightPressed: root._step(1)
    Keys.onUpPressed: root._step(-root.columns)
    Keys.onDownPressed: root._step(root.columns)
    Keys.onReturnPressed: root.model.commit(grid.currentIndex)
    Keys.onEscapePressed: root.model.revertAndClose()

    Column {
        anchors.centerIn: parent
        spacing: Tokens.spacing.large

        GridView {
            id: grid

            width: root.columns * (root.cellWidth + root.cellGap)
            height: Math.min(root.height * 0.66, root.height - 160)
            cellWidth: root.cellWidth + root.cellGap
            cellHeight: root.cellHeight + root.cellGap
            clip: true
            cacheBuffer: root.cellHeight * 3

            model: root.model.count
            reuseItems: true

            // A wheel-only view is against the rule in this repo, so the
            // scrollbar beside it is a real draggable one rather than an
            // indicator.
            FlickScrollBar {
                anchors.left: parent.right
                anchors.leftMargin: Tokens.spacing.small
                height: parent.height
                flickable: grid
            }

            delegate: Item {
                id: cell

                required property int index

                property bool hovered: false

                // Recycled cells come back with whatever hover state they
                // were pooled with; everything else here derives from
                // index, which Qt re-evaluates on reuse.
                GridView.onReused: cell.hovered = false

                width: grid.cellWidth
                height: grid.cellHeight

                WallpaperCard {
                    anchors.centerIn: parent

                    width: root.cellWidth
                    height: root.cellHeight

                    source: root.model.previewFor(cell.index)
                    decodeWidth: root.cellWidth
                    decodeHeight: root.cellHeight
                    matteWidth: 64
                    matteHeight: 36
                    distance: 0
                    hovered: cell.hovered
                    active: cell.index === grid.currentIndex
                    locked: cell.index === root.model.activeIndex
                }

                MaterialIcon {
                    visible: root.model.entries[cell.index]?.isVideo ?? false
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: Tokens.padding.medium
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
                        if (cell.index === grid.currentIndex) {
                            root.model.commit(cell.index);
                        } else {
                            grid.currentIndex = cell.index;
                            root.model.queuePreview(cell.index);
                        }
                    }
                }
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Tokens.spacing.extraSmall

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.model.entries[grid.currentIndex]?.file ?? ""
                font: Tokens.font.title.large
                color: Colours.palette.m3onSurface
                animate: true
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.model.entries[grid.currentIndex]?.theme ?? ""
                font: Tokens.font.label.medium
                color: Colours.palette.m3onSurfaceVariant
                animate: true
            }
        }
    }
}
