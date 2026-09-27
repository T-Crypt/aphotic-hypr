import QtQuick
import QtQuick.Shapes

// Concave fillet that lets a surface's side edge curve into the edge it grows from.
// corner: 0 topLeft, 1 topRight, 2 bottomLeft, 3 bottomRight.
Item {
    id: root

    property int corner: 0
    property real radius: 0
    property color color: "transparent"

    width: root.radius
    height: root.radius

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Scale {
            origin.x: root.radius / 2
            origin.y: root.radius / 2
            xScale: root.corner === 1 || root.corner === 3 ? -1 : 1
            yScale: root.corner >= 2 ? -1 : 1
        }

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: root.color

            startX: 0
            startY: 0
            PathLine {
                x: root.radius
                y: 0
            }
            PathLine {
                x: root.radius
                y: root.radius
            }
            PathArc {
                x: 0
                y: 0
                radiusX: root.radius
                radiusY: root.radius
                direction: PathArc.Counterclockwise
            }
        }
    }
}
