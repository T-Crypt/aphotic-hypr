pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.services

// The Signal skin's base surface: the raised bar tone, a hairline border,
// and a 1px edge-light line along the top (inset by the radius, like the
// cards in FlowScene.qml). Depth comes from those two lines, never a shadow.
Rectangle {
    id: root

    // Override to re-tint a specific surface (e.g. Minimal's translucent
    // bar); leave unset for the default signal tone.
    property color tone: Colours.signalStyle.bar
    // The one edge a stacked SignalLine draws instead. It leaves that edge
    // bare so the line can open there across a gap such as the notch span,
    // and keeps the hairline on the other three. "start" is the top or left
    // edge, "end" the bottom or right; "" draws every edge here.
    property bool horizontal: true
    property string openEdge: ""
    readonly property bool borderOpen: root.openEdge !== ""

    color: root.tone
    border.width: root.borderOpen ? 0 : 1
    border.color: Colours.signalStyle.hairline

    // The hairline with the open edge left out: one rounded-rect stroke
    // traced so the straight side that is missing is the open one. The
    // corner arcs stay, so a SignalLine drawn over the open side meets them.
    Shape {
        anchors.fill: parent
        visible: root.borderOpen && root.width > 0 && root.height > 0
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 1
            strokeColor: Colours.signalStyle.hairline
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: root.hairlinePath()
            }
        }
    }

    // The rounded-rect outline as SVG, minus the straight side of the open
    // edge. Traced clockwise from the corner after that side, so the two
    // arcs at the open edge meet the SignalLine's halves.
    function hairlinePath(): string {
        const inset = 0.5;
        const w = Math.max(0, root.width - 1);
        const h = Math.max(0, root.height - 1);
        const r = Math.max(0, Math.min(root.radius, w / 2, h / 2));
        const physical = root.horizontal
            ? (root.openEdge === "start" ? "top" : "bottom")
            : (root.openEdge === "start" ? "left" : "right");
        const pts = [
            [inset + r, inset],
            [inset + w - r, inset],
            [inset + w, inset + r],
            [inset + w, inset + h - r],
            [inset + w - r, inset + h],
            [inset + r, inset + h],
            [inset, inset + h - r],
            [inset, inset + r]
        ];
        const segs = [["L", 1], ["A", 2], ["L", 3], ["A", 4], ["L", 5], ["A", 6], ["L", 7], ["A", 0]];
        const openIndex = { top: 0, right: 2, bottom: 4, left: 6 }[physical];
        const start = (openIndex + 1) % 8;
        let d = "M " + pts[start][0] + " " + pts[start][1];
        for (let k = 0; k < 7; k++) {
            const s = segs[(start + k) % 8];
            const p = pts[s[1]];
            d += s[0] === "L" ? " L " + p[0] + " " + p[1]
                : " A " + r + " " + r + " 0 0 1 " + p[0] + " " + p[1];
        }
        return d;
    }

    Rectangle {
        x: parent.radius
        width: parent.width - parent.radius * 2
        height: 1
        color: Colours.signalStyle.edgeLight
    }
}
