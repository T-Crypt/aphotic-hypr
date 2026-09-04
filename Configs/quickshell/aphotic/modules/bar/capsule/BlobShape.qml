pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

// Closed polar blob: r(t) = R * (1 + amplitude * cos(lobes * t + phase)),
// sampled into a polyline. amplitude 0 is an exact circle; raising it
// pushes `lobes` rounded petals out of the rim. Used as a mask source,
// so only the fill matters -- never stroked.
Shape {
    id: root

    property int lobes: 6
    property real amplitude: 0
    property real phase: 0
    property color fillColour: "white"

    readonly property int samples: 72

    readonly property var outline: {
        const cx = root.width / 2;
        const cy = root.height / 2;
        // Dividing by the peak factor keeps the petals' TIPS on the item's
        // bounds rather than the valleys, so a raised amplitude never
        // spills outside the mask texture it is rendered into.
        const r = Math.min(cx, cy) / (1 + Math.abs(root.amplitude));
        const pts = [];
        for (let i = 0; i <= root.samples; i++) {
            const t = (i % root.samples) / root.samples * Math.PI * 2;
            const rr = r * (1 + root.amplitude * Math.cos(root.lobes * t + root.phase));
            pts.push(Qt.point(cx + rr * Math.cos(t), cy + rr * Math.sin(t)));
        }
        return pts;
    }

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: 0
        strokeColor: "transparent"
        fillColor: root.fillColour

        PathPolyline {
            path: root.outline
        }
    }
}
