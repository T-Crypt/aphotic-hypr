pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.services

// A smooth line through `values` with a soft fill under it and a lit point
// on the newest sample. `peak` sets the top of the scale; 0 scales to the
// largest value seen.
Item {
    id: root

    property var values: []
    property real peak: 1
    property int capacity: 40
    property color colour: Colours.signal
    property bool fill: true
    property real lineWidth: 2

    readonly property real scaleTop: root.peak > 0 ? root.peak : Math.max(1, root.values.reduce((m, v) => Math.max(m, v), 0))
    readonly property var pts: {
        const n = root.values.length;
        const step = root.width / Math.max(1, root.capacity - 1);
        const h = root.height - root.lineWidth * 2;
        return root.values.map((v, i) => Qt.point(root.width - (n - 1 - i) * step, root.lineWidth + h - Math.min(1, v / root.scaleTop) * h));
    }

    function curve(p: var): string {
        if (p.length < 2)
            return "";
        let d = `M ${p[0].x} ${p[0].y}`;
        for (let i = 0; i < p.length - 1; i++) {
            const a = p[Math.max(0, i - 1)], b = p[i], c = p[i + 1], e = p[Math.min(p.length - 1, i + 2)];
            d += ` C ${b.x + (c.x - a.x) / 6} ${b.y + (c.y - a.y) / 6} ${c.x - (e.x - b.x) / 6} ${c.y - (e.y - b.y) / 6} ${c.x} ${c.y}`;
        }
        return d;
    }

    readonly property string line: root.curve(root.pts)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: 0
                y2: root.height

                GradientStop {
                    position: 0
                    color: Qt.alpha(root.colour, root.fill ? 0.28 : 0)
                }

                GradientStop {
                    position: 1
                    color: Qt.alpha(root.colour, 0)
                }
            }

            PathSvg {
                path: root.line ? `${root.line} L ${root.pts[root.pts.length - 1].x} ${root.height} L ${root.pts[0].x} ${root.height} Z` : ""
            }
        }

        ShapePath {
            strokeWidth: root.lineWidth
            strokeColor: root.colour
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: root.line
            }
        }
    }

    Rectangle {
        readonly property var at: root.pts.length > 0 ? root.pts[root.pts.length - 1] : null

        visible: at !== null
        x: (at?.x ?? 0) - width / 2
        y: (at?.y ?? 0) - height / 2
        width: 7
        height: 7
        radius: Math.min(width, height) / 2
        color: root.colour

        Rectangle {
            anchors.centerIn: parent
            width: 18
            height: 18
            radius: Math.min(width, height) / 2
            color: Qt.alpha(root.colour, 0.18)
        }
    }
}
