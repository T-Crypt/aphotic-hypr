pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.config
import qs.components
import qs.services
import qs.services.ai

Item {
    id: root

    property var sessions: AgentGraphService.sessions
    property int maxNodesPerSession: AgentGraphService.maxNodesPerSession
    property int edgeParticles: AgentGraphService.edgeParticles

    readonly property alias layout: graphLayout
    readonly property bool empty: root.sessions.length === 0
    readonly property bool anyFlowing: graphLayout.edges.some(e => e.status === "running")

    // One clock for every packet on every edge instead of an animation per
    // packet: phase comes from the packet's index, so N particles cost one
    // running animation, and it stops entirely when nothing is in flight.
    property real flowClock: 0

    implicitWidth: 760
    implicitHeight: 460

    NumberAnimation on flowClock {
        running: root.visible && root.anyFlowing
        loops: Animation.Infinite
        from: 0
        to: 1
        duration: 1600
    }

    GraphLayout {
        id: graphLayout

        sessions: root.sessions
        areaWidth: root.width
        areaHeight: root.height
        maxNodesPerSession: root.maxNodesPerSession
    }

    // Repeater delegates must be Items, and ShapePath is not one -- a
    // Repeater of ShapePath silently draws nothing. All edges of a given
    // status therefore share one ShapePath fed by a PathMultiline, which is
    // also three geometry nodes for the whole graph instead of one per edge.
    function _iconFor(tool: string): string {
        switch (tool) {
        case "Read":
            return "description";
        case "Write":
            return "note_add";
        case "Edit":
            return "edit";
        case "Bash":
            return "terminal";
        case "Grep":
            return "search";
        case "Glob":
            return "folder_open";
        case "WebFetch":
        case "WebSearch":
            return "language";
        case "Agent":
        case "Task":
            return "smart_toy";
        case "TodoWrite":
            return "checklist";
        case "NotebookEdit":
            return "menu_book";
        default:
            return "bolt";
        }
    }

    function _polylines(status: string): var {
        const positions = graphLayout.positions;
        const lines = [];
        for (const edge of graphLayout.edges) {
            if (edge.status !== status)
                continue;
            const a = positions[edge.a];
            const b = positions[edge.b];
            if (!a || !b)
                continue;
            const mx = (a.x + b.x) / 2 + (b.y - a.y) * 0.09;
            const my = (a.y + b.y) / 2 - (b.x - a.x) * 0.09;
            lines.push([Qt.point(a.x, a.y), Qt.point(mx, my), Qt.point(b.x, b.y)]);
        }
        return lines;
    }

    Shape {
        anchors.fill: parent
        opacity: root.empty ? 0 : 1
        preferredRendererType: Shape.CurveRenderer

        Behavior on opacity {
            Anim { type: Anim.DefaultEffects }
        }

        ShapePath {
            strokeWidth: 1.2
            strokeColor: Qt.alpha(Colours.palette.m3outlineVariant, 0.8)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathMultiline {
                paths: root._polylines("completed").concat(root._polylines("idle"))
            }
        }

        ShapePath {
            strokeWidth: 1.5
            strokeColor: Qt.alpha(Colours.palette.m3error, 0.65)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathMultiline {
                paths: root._polylines("errored")
            }
        }

        ShapePath {
            strokeWidth: 2.5
            strokeColor: Qt.alpha(Colours.palette.m3primary, 0.9)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathMultiline {
                paths: root._polylines("running")
            }
        }
    }

    // The graph reads as alive or it reads as a diagram. Packets travel the
    // edge of a call that is actually in flight; nothing moves on an edge
    // that has already finished. Density comes from the hardware tier and is
    // thinned, never switched off -- see AgentGraphService.edgeParticles.
    Repeater {
        model: root.empty ? [] : graphLayout.edges

        Item {
            id: flow

            required property var modelData

            readonly property var from: graphLayout.positions[flow.modelData.a] ?? { x: 0, y: 0 }
            readonly property var to: graphLayout.positions[flow.modelData.b] ?? { x: 0, y: 0 }
            readonly property bool flowing: flow.modelData.status === "running"

            visible: flow.flowing

            Repeater {
                model: flow.flowing ? root.edgeParticles : 0

                Rectangle {
                    id: packet

                    required property int index

                    readonly property real progress: (root.flowClock + packet.index / Math.max(1, root.edgeParticles)) % 1
                    readonly property real eased: packet.progress * packet.progress * (3 - 2 * packet.progress)

                    width: 6
                    height: 6
                    radius: width / 2
                    color: Colours.palette.m3primary
                    opacity: 1 - Math.abs(packet.progress - 0.5) * 0.5
                    x: flow.from.x + (flow.to.x - flow.from.x) * packet.eased - width / 2
                    y: flow.from.y + (flow.to.y - flow.from.y) * packet.eased - height / 2
                }
            }
        }
    }

    Repeater {
        model: graphLayout.nodes

        Item {
            id: node

            required property int index
            required property var modelData

            readonly property var point: graphLayout.positions[node.index] ?? { x: 0, y: 0 }
            readonly property bool isSession: node.modelData.kind === "session"
            readonly property bool running: node.modelData.status === "running"
            readonly property bool errored: node.modelData.status === "errored"

            x: node.point.x - width / 2
            y: node.point.y - height / 2
            width: pill.width
            height: pill.height
            z: node.isSession ? 2 : 1

            Behavior on x {
                Anim { type: Anim.EmphasizedSmall }
            }

            Behavior on y {
                Anim { type: Anim.EmphasizedSmall }
            }

            Rectangle {
                id: halo

                property real pulse: 0.1

                anchors.centerIn: pill
                width: pill.width + Tokens.padding.medium
                height: pill.height + Tokens.padding.medium
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: node.errored ? Colours.palette.m3error : Colours.palette.m3primary
                opacity: node.running ? halo.pulse : node.errored ? 0.6 : 0

                SequentialAnimation on pulse {
                    running: node.running && root.visible
                    loops: Animation.Infinite
                    Anim {
                        to: 0.5
                        type: Anim.SlowEffects
                    }
                    Anim {
                        to: 0.08
                        type: Anim.SlowEffects
                    }
                }

                Behavior on opacity {
                    Anim { type: Anim.DefaultEffects }
                }
            }

            StyledRect {
                id: pill

                anchors.centerIn: parent
                implicitWidth: content.implicitWidth + (node.isSession ? Tokens.padding.large : Tokens.padding.medium)
                implicitHeight: node.isSession ? 32 : 26
                radius: Tokens.rounding.full
                scale: node.running ? 1.06 : 1
                color: node.isSession
                    ? Qt.alpha(Colours.palette.m3primary, node.modelData.status === "ended" ? 0.3 : 0.85)
                    : node.running
                        ? Qt.alpha(Colours.palette.m3primary, 0.8)
                        : node.errored
                            ? Qt.alpha(Colours.palette.m3error, 0.85)
                            : Qt.alpha(Colours.tPalette.m3surfaceContainerHigh, 0.92)
                border.width: 1
                border.color: node.isSession || node.running || node.errored
                    ? "transparent"
                    : Qt.alpha(Colours.palette.m3outlineVariant, 0.8)

                readonly property color ink: node.isSession || node.running || node.errored
                    ? Colours.contrastOn(pill.color)
                    : Colours.palette.m3onSurfaceVariant

                Behavior on scale {
                    Anim { type: Anim.EmphasizedSmall }
                }

                Row {
                    id: content

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: node.isSession ? "hub" : root._iconFor(node.modelData.tool)
                        color: pill.ink
                        fontStyle: Tokens.font.icon.small
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: node.isSession ? node.modelData.label : node.modelData.tool
                        font: node.isSession ? Tokens.font.body.small : Tokens.font.label.small
                        color: pill.ink
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: node.modelData.kind === "subagent"
                        width: 5
                        height: 5
                        radius: 2.5
                        color: Qt.alpha(pill.ink, 0.7)
                    }
                }
            }
        }
    }

    GraphEmptyState {
        anchors.centerIn: parent
        visible: root.empty
    }

    component GraphEmptyState: Column {
        spacing: Tokens.spacing.small

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 64
            height: 64
            radius: width / 2
            color: Qt.alpha(Colours.palette.m3primary, 0.12)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3primary, 0.25)

            MaterialIcon {
                anchors.centerIn: parent
                text: "hub"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.extraLarge
            }
        }

        Item {
            width: 1
            height: Tokens.spacing.small
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("No agent sessions")
            color: Colours.palette.m3onSurface
            font: Tokens.font.body.medium
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Claude Code sessions appear here as they run")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }
}
