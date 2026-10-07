pragma ComponentBehavior: Bound

import QtQuick
import qs.services

// The Signal edge line every bar layout shares: a 1px hairline along one of
// the parent's edges (optionally opened by a centered gap), a soft hover
// segment, and a 2px accent segment marking the active entry. All segment
// coordinates are in the line's own space, measured along its length from
// its start end.
Item {
    id: root

    // true:  the line runs along x (full parent width, 1px tall)
    // false: it runs along y (full parent height, 1px wide)
    property bool horizontal: true
    // Which side of the parent the 1px line sits on: "start" is the top
    // (horizontal) or left (vertical) edge, "end" the bottom or right.
    property string edge: "start"
    // Centered gap along the line the hairline halves open around (e.g. a
    // notch span), 0 for no gap.
    property real gapLength: 0
    property real activeStart: 0
    property real activeLength: 0
    property real hoverStart: 0
    property real hoverLength: 0
    property bool hoverVisible: false
    // "idle" | "active" | "warn": which tone the base hairline uses.
    property string level: "idle"

    x: root.horizontal ? 0 : (root.edge === "end" ? parent.width - 1 : 0)
    y: root.horizontal ? (root.edge === "end" ? parent.height - 1 : 0) : 0
    width: root.horizontal ? parent.width : 1
    height: root.horizontal ? 1 : parent.height

    readonly property real length: root.horizontal ? root.width : root.height
    readonly property real half: Math.max(0, (root.length - root.gapLength) / 2)
    readonly property color baseColor: root.level === "warn" ? Colours.status.warning
        : (root.level === "active" ? Qt.alpha(Colours.signalStyle.accentLine, 0.5) : Colours.signalStyle.hairline)
    readonly property color accentColor: root.level === "warn" ? Colours.status.warning : Colours.signalStyle.accentLine

    // The base hairline in two halves that open around the gap, so the line
    // flows into whatever outline the gap carries.
    Rectangle {
        width: root.horizontal ? root.half : 1
        height: root.horizontal ? 1 : root.half
        color: root.baseColor
    }

    Rectangle {
        x: root.horizontal ? root.length - root.half : 0
        y: root.horizontal ? 0 : root.length - root.half
        width: root.horizontal ? root.half : 1
        height: root.horizontal ? 1 : root.half
        color: root.baseColor
    }

    Rectangle {
        x: root.horizontal ? root.hoverStart : 0
        y: root.horizontal ? 0 : root.hoverStart
        width: root.horizontal ? root.hoverLength : 1
        height: root.horizontal ? 1 : root.hoverLength
        color: Colours.palette.m3onSurface
        opacity: root.hoverVisible ? 0.45 : 0

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }
    }

    // On the "end" edge the 2px accent sits 1px inboard of the hairline so
    // it stays fully inside the parent; on the "start" edge it overlaps the
    // hairline and spills 1px into the parent.
    Rectangle {
        readonly property real thickness: 2
        x: root.horizontal ? root.activeStart : (root.edge === "end" ? 1 - thickness : 0)
        y: root.horizontal ? (root.edge === "end" ? 1 - thickness : 0) : root.activeStart
        width: root.horizontal ? root.activeLength : thickness
        height: root.horizontal ? thickness : root.activeLength
        radius: thickness / 2
        color: root.accentColor
        visible: root.activeLength > 0
    }
}
