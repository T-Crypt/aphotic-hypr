pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.components
import qs.config
import qs.services

// CPU history as a smooth ridge and network as a low band, inside a rounded,
// outlined well. The curves pass through every sample (Catmull-Rom turned
// into cubic segments), so the line reads as a signal rather than a
// staircase, and the Shape's curve renderer antialiases them.
Item {
    id: root

    readonly property int capacity: 48
    readonly property real netFlatBelow: 64 * 1024
    property var cpuTrail: []
    property var netTrail: []

    function pushCpu(value: real): void {
        const next = root.cpuTrail.concat([Math.max(0, Math.min(1, value))]);
        root.cpuTrail = next.length > root.capacity ? next.slice(next.length - root.capacity) : next;
    }

    function pushNet(value: real): void {
        const next = root.netTrail.concat([Math.max(0, value)]);
        root.netTrail = next.length > root.capacity ? next.slice(next.length - root.capacity) : next;
    }

    function seedForProbe(cpu: var, net: var): void {
        root.cpuTrail = cpu;
        root.netTrail = net;
    }

    Connections {
        target: SystemUsage

        function onCpuPercChanged(): void {
            root.pushCpu(SystemUsage.cpuPerc);
        }
    }

    Connections {
        target: NetworkUsage

        function onDownloadSpeedChanged(): void {
            root.pushNet(NetworkUsage.downloadSpeed);
        }
    }

    readonly property real inset: 10
    readonly property real floorY: root.height - root.inset

    function points(values: var, top: real, floor: real, peak: real): var {
        const w = root.width - root.inset * 2;
        const step = w / (root.capacity - 1);
        const count = values.length;
        return values.map((v, i) => Qt.point(root.inset + w - (count - 1 - i) * step, floor - (v / peak) * (floor - top)));
    }

    // Catmull-Rom through the points, as SVG cubic segments.
    function curve(pts: var): string {
        if (pts.length < 2)
            return "";
        let d = `M ${pts[0].x} ${pts[0].y}`;
        for (let i = 0; i < pts.length - 1; i++) {
            const p0 = pts[Math.max(0, i - 1)];
            const p1 = pts[i];
            const p2 = pts[i + 1];
            const p3 = pts[Math.min(pts.length - 1, i + 2)];
            d += ` C ${p1.x + (p2.x - p0.x) / 6} ${p1.y + (p2.y - p0.y) / 6} ${p2.x - (p3.x - p1.x) / 6} ${p2.y - (p3.y - p1.y) / 6} ${p2.x} ${p2.y}`;
        }
        return d;
    }

    function area(pts: var, floor: real): string {
        const line = root.curve(pts);
        if (!line)
            return "";
        return `${line} L ${pts[pts.length - 1].x} ${floor} L ${pts[0].x} ${floor} Z`;
    }

    readonly property var cpuPts: root.points(root.cpuTrail, root.inset + 6, root.floorY, 1)
    readonly property var netPts: {
        const peak = root.netTrail.reduce((m, v) => Math.max(m, v), root.netFlatBelow);
        return root.points(root.netTrail, root.floorY - root.height * 0.28, root.floorY, peak);
    }

    StyledClippingRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: Qt.alpha(Colours.signalStyle.surface, 0.35)

        // Faint guides at a quarter, half and three quarters.
        Repeater {
            model: [0.25, 0.5, 0.75]

            Rectangle {
                required property real modelData

                x: root.inset
                width: root.width - root.inset * 2
                y: root.floorY - (root.floorY - root.inset - 6) * modelData
                height: 1
                color: Qt.alpha(Colours.signalStyle.hairline, 0.5)
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillColor: Qt.alpha(Colours.signalSecondary, 0.1)

                PathSvg {
                    path: root.area(root.netPts, root.floorY)
                }
            }

            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: 0
                    y1: 0
                    x2: 0
                    y2: root.height

                    GradientStop {
                        position: 0
                        color: Qt.alpha(Colours.signalStyle.accentLine, 0.3)
                    }

                    GradientStop {
                        position: 1
                        color: Qt.alpha(Colours.signalStyle.accentLine, 0)
                    }
                }

                PathSvg {
                    path: root.area(root.cpuPts, root.floorY)
                }
            }

            ShapePath {
                strokeWidth: 2
                strokeColor: Colours.signalStyle.accentLine
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin

                PathSvg {
                    path: root.curve(root.cpuPts)
                }
            }
        }

        // The newest sample: a lit point the eye lands on.
        Rectangle {
            id: tip

            readonly property var at: root.cpuPts.length > 0 ? root.cpuPts[root.cpuPts.length - 1] : null

            visible: tip.at !== null
            x: (tip.at?.x ?? 0) - width / 2
            y: (tip.at?.y ?? 0) - height / 2
            width: 8
            height: 8
            radius: 4
            color: Colours.signalStyle.accentLine

            Rectangle {
                anchors.centerIn: parent
                width: 20
                height: 20
                radius: 10
                color: Qt.alpha(Colours.signalStyle.accentLine, 0.16)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: "transparent"
        border.width: 1
        border.color: Colours.signalStyle.hairline
    }
}
