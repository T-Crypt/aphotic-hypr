// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.config
import qs.components
import qs.components.effects
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

    readonly property color accent: Settings.agentGraphAccent ? Settings.agentGraphAccent : Colours.palette.m3primary

    property int hoveredIndex: -1
    property int selectedIndex: -1
    property real nowMs: 0

    property real zoom: 1
    property real panX: 0
    property real panY: 0
    property bool interacting: false

    readonly property bool showLabels: root.zoom > 0.72
    readonly property bool showIcons: root.zoom > 0.42

    function zoomAt(px: real, py: real, factor: real): void {
        const next = Math.max(0.3, Math.min(4, root.zoom * factor));
        if (next === root.zoom)
            return;
        root.interacting = true;
        root.panX = px - (px - root.panX) * (next / root.zoom);
        root.panY = py - (py - root.panY) * (next / root.zoom);
        root.zoom = next;
        root.interacting = false;
    }

    function zoomToFit(): void {
        root.zoom = 1;
        root.panX = 0;
        root.panY = 0;
    }

    function frameNode(index: int): void {
        const point = graphLayout.positions[index];
        if (!point)
            return;
        root.zoom = Math.max(root.zoom, 1.6);
        root.panX = root.width / 2 - point.x * root.zoom;
        root.panY = root.height / 2 - point.y * root.zoom;
    }

    function _onScreen(point): bool {
        if (!point)
            return false;
        const x = point.x * root.zoom + root.panX;
        const y = point.y * root.zoom + root.panY;
        return x > -80 && x < root.width + 80 && y > -60 && y < root.height + 60;
    }

    function focusSession(index: int): void {
        const node = graphLayout.nodes[index];
        if (!node || node.kind !== "session" || !node.cwd)
            return;
        const leaf = node.cwd.slice(node.cwd.lastIndexOf("/") + 1);
        if (!leaf)
            return;
        const match = WindowList.windows.find(w => w.title.includes(leaf));
        if (match)
            WindowList.focus(match.address);
    }

    function _durationText(node): string {
        const ms = node.status === "running"
            ? Math.max(0, root.nowMs - (node.startedAt ?? 0))
            : (node.durationMs ?? 0);
        if (!ms || !node.startedAt)
            return "";
        if (ms < 1000)
            return qsTr("%1 ms").arg(Math.round(ms));
        if (ms < 60000)
            return qsTr("%1 s").arg((ms / 1000).toFixed(1));
        return qsTr("%1 m %2 s").arg(Math.floor(ms / 60000)).arg(Math.round((ms % 60000) / 1000));
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root.nowMs = Date.now()
    }

    property real flowClock: 0

    implicitWidth: 760
    implicitHeight: 460

    NumberAnimation on flowClock {
        running: root.visible && root.anyFlowing && Settings.agentGraphEnabled
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

    Item {
        id: viewport

        anchors.fill: parent
        clip: true

        Item {
            id: canvas

            width: viewport.width
            height: viewport.height
            transformOrigin: Item.TopLeft
            scale: root.zoom
            x: root.panX
            y: root.panY

            Behavior on scale {
                enabled: !root.interacting
                Anim { type: Anim.EmphasizedSmall }
            }

            Behavior on x {
                enabled: !root.interacting
                Anim { type: Anim.EmphasizedSmall }
            }

            Behavior on y {
                enabled: !root.interacting
                Anim { type: Anim.EmphasizedSmall }
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
                    strokeColor: Qt.alpha(root.accent, 0.9)
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin

                    PathMultiline {
                        paths: root._polylines("running")
                    }
                }
            }

            Repeater {
                model: root.empty ? [] : graphLayout.edges

                Item {
                    id: flow

                    required property var modelData

                    readonly property var from: graphLayout.positions[flow.modelData.a] ?? { x: 0, y: 0 }
                    readonly property var to: graphLayout.positions[flow.modelData.b] ?? { x: 0, y: 0 }
                    readonly property bool flowing: flow.modelData.status === "running"

                    readonly property int speed: {
                        const elapsed = root.nowMs - (flow.modelData.startedAt ?? 0);
                        if (!flow.modelData.startedAt || elapsed > 20000)
                            return 1;
                        return elapsed > 5000 ? 2 : 3;
                    }

                    visible: flow.flowing && (root._onScreen(flow.from) || root._onScreen(flow.to))

                    Repeater {
                        model: flow.flowing ? root.edgeParticles : 0

                        Rectangle {
                            id: packet

                            required property int index

                            readonly property real progress: (root.flowClock * flow.speed + packet.index / Math.max(1, root.edgeParticles)) % 1
                            readonly property real eased: packet.progress * packet.progress * (3 - 2 * packet.progress)

                            width: 6
                            height: 6
                            radius: width / 2
                            color: root.accent
                            opacity: 0.35 + packet.progress * 0.65
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
                    readonly property bool waiting: node.modelData.status === "waiting"
                    readonly property bool ended: node.modelData.status === "ended"
                    readonly property bool hovered: root.hoveredIndex === node.index
                    readonly property bool selected: root.selectedIndex === node.index
                    readonly property color stateColour: node.errored ? Colours.palette.m3error : root.accent
                    readonly property real fade: graphLayout.fadeFor(node.modelData, root.nowMs)
                    readonly property real fadeScale: 0.9 + 0.1 * node.fade

                    opacity: node.fade

                    Behavior on opacity {
                        Anim { type: Anim.DefaultEffects }
                    }

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

                    BioluminescentGlow {
                        target: pill
                        glowColour: node.stateColour
                        breathing: node.running || node.isSession && node.modelData.status === "running"
                        visible: node.running || node.errored || node.waiting || node.hovered || node.selected
                        glowBlur: node.selected ? 26 : 18
                    }

                    StyledRect {
                        id: pill

                        anchors.centerIn: parent
                        implicitWidth: Math.max(node.isSession ? 26 : 20, content.implicitWidth + (node.isSession ? Tokens.padding.large : Tokens.padding.medium))
                        implicitHeight: node.isSession ? 32 : 26
                        radius: Tokens.rounding.full
                        scale: node.fadeScale * (node.selected ? 1.12 : node.hovered ? 1.09 : node.running ? 1.06 : 1)
                        color: node.isSession
                            ? Qt.alpha(root.accent, node.ended ? 0.3 : 0.85)
                            : node.running
                                ? Qt.alpha(root.accent, 0.8)
                                : node.errored
                                    ? Qt.alpha(Colours.palette.m3error, 0.85)
                                    : Qt.alpha(node.modelData.categoryColor ?? Colours.palette.m3surfaceContainerHigh, 0.92)
                        border.width: pill.grouped ? 2.5 : 1.5
                        border.color: Qt.alpha(node.modelData.groupColor ?? Colours.palette.m3outlineVariant, node.isSession ? 0.85 : (pill.grouped ? 0.9 : 0.55))

                        readonly property bool grouped: Settings.agentGraphGroupByParent && node.modelData.kind === "subagent"
                        readonly property color ink: Colours.contrastOn(pill.color)

                        Behavior on scale {
                            Anim { type: Anim.EmphasizedSmall }
                        }

                        HoverHandler {
                            onHoveredChanged: root.hoveredIndex = hovered ? node.index : (root.hoveredIndex === node.index ? -1 : root.hoveredIndex)
                        }

                        TapHandler {
                            onTapped: {
                                root.selectedIndex = root.selectedIndex === node.index ? -1 : node.index;
                                if (node.isSession)
                                    root.focusSession(node.index);
                            }
                        }

                        Row {
                            id: content

                            anchors.centerIn: parent
                            spacing: Tokens.spacing.extraSmall

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.showIcons
                                text: node.isSession ? "hub" : root._iconFor(node.modelData.tool)
                                color: pill.ink
                                fontStyle: Tokens.font.icon.small
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: node.isSession ? root.showIcons : root.showLabels
                                text: node.isSession ? node.modelData.label : node.modelData.tool
                                font: node.isSession ? Tokens.font.body.small : Tokens.font.label.small
                                color: pill.ink
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: node.modelData.kind === "subagent" && root.showLabels
                                width: 5
                                height: 5
                                radius: 2.5
                                color: Qt.alpha(pill.ink, 0.7)
                            }

                            StyledRect {
                                id: modelBadge

                                anchors.verticalCenter: parent.verticalCenter
                                visible: node.isSession && root.showLabels && (node.modelData.locality || node.modelData.quant)
                                radius: Tokens.rounding.small
                                color: Qt.alpha(pill.ink, 0.16)
                                implicitWidth: badgeText.implicitWidth + Tokens.padding.small
                                implicitHeight: badgeText.implicitHeight + Tokens.padding.extraSmall

                                StyledText {
                                    id: badgeText

                                    anchors.centerIn: parent
                                    text: [node.modelData.locality, node.modelData.quant].filter(Boolean).join(" · ")
                                    font: Tokens.font.label.small
                                    color: pill.ink
                                }
                            }
                        }
                    }
                }
            }
        }

        PinchHandler {
            target: null
            onActiveChanged: root.interacting = active
            onScaleChanged: root.zoomAt(centroid.position.x, centroid.position.y, activeScale > 1 ? 1.03 : 0.97)
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => root.zoomAt(event.x, event.y, event.angleDelta.y > 0 ? 1.12 : 1 / 1.12)
        }

        DragHandler {
            target: null
            cursorShape: Qt.ClosedHandCursor
            onActiveChanged: root.interacting = active
            onTranslationChanged: {
                root.panX += translation.x - dragState.x;
                root.panY += translation.y - dragState.y;
                dragState = Qt.point(translation.x, translation.y);
            }
            onGrabChanged: dragState = Qt.point(0, 0)

            property point dragState: Qt.point(0, 0)
        }
    }

    StyledRect {
        id: tip

        readonly property int target: root.selectedIndex >= 0 ? root.selectedIndex : root.hoveredIndex
        readonly property var node: tip.target >= 0 ? graphLayout.nodes[tip.target] ?? null : null
        readonly property var point: tip.target >= 0 ? graphLayout.positions[tip.target] ?? null : null

        visible: opacity > 0
        opacity: tip.node ? 1 : 0
        implicitWidth: tipContent.implicitWidth + Tokens.padding.large * 2
        implicitHeight: tipContent.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.large
        color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.97)
        border.width: 1
        border.color: Colours.palette.m3outlineVariant
        z: 10

        readonly property real screenX: (tip.point?.x ?? 0) * root.zoom + root.panX
        readonly property real screenY: (tip.point?.y ?? 0) * root.zoom + root.panY

        x: Math.max(0, Math.min(root.width - width, tip.screenX - width / 2))
        y: tip.screenY + 46 + height > root.height ? Math.max(0, tip.screenY - height - 30) : tip.screenY + 30

        Behavior on opacity {
            Anim { type: Anim.DefaultEffects }
        }

        Column {
            id: tipContent

            anchors.centerIn: parent
            spacing: Tokens.spacing.extraSmall

            StyledText {
                text: tip.node ? (tip.node.kind === "session" ? tip.node.label : tip.node.tool) : ""
                font: Tokens.font.body.medium
                color: Colours.palette.m3onSurface
            }

            StyledText {
                visible: text.length > 0
                text: {
                    if (!tip.node)
                        return "";
                    const bits = [tip.node.status];
                    const duration = root._durationText(tip.node);
                    if (duration)
                        bits.push(duration);
                    if (tip.node.agentType)
                        bits.push(tip.node.agentType);
                    if (tip.node.kind === "session" && tip.node.callCount)
                        bits.push(qsTr("%1 calls").arg(tip.node.callCount));
                    return bits.join(" · ");
                }
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                visible: text.length > 0
                text: tip.node && tip.node.kind === "session" ? tip.node.cwd : ""
                font: Tokens.font.label.small
                color: Colours.palette.m3outlineVariant
                elide: Text.ElideLeft
                maximumLineCount: 1
                width: Math.min(implicitWidth, 260)
            }

            StyledText {
                visible: text.length > 0
                text: tip.node && tip.node.kind === "session" ? tip.node.modelRaw : ""
                font: Tokens.font.label.small
                color: Colours.palette.m3outlineVariant
                elide: Text.ElideRight
                maximumLineCount: 1
                width: Math.min(implicitWidth, 260)
            }
        }
    }

    GraphEmptyState {
        anchors.centerIn: parent
        visible: root.empty
    }

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: Tokens.spacing.extraSmall
        visible: !root.empty
        opacity: 0.85

        component ZoomButton: StyledRect {
            required property string glyph
            signal activated

            implicitWidth: 28
            implicitHeight: 28
            radius: Tokens.rounding.full
            color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.9)
            border.width: 1
            border.color: Colours.palette.m3outlineVariant

            MaterialIcon {
                anchors.centerIn: parent
                text: parent.glyph
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
                onClicked: parent.activated()
            }
        }

        ZoomButton {
            glyph: "remove"
            onActivated: root.zoomAt(root.width / 2, root.height / 2, 1 / 1.25)
        }

        ZoomButton {
            glyph: "fit_screen"
            onActivated: root.zoomToFit()
        }

        ZoomButton {
            glyph: "add"
            onActivated: root.zoomAt(root.width / 2, root.height / 2, 1.25)
        }
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
