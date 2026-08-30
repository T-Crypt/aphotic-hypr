// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import qs.services

QtObject {
    id: root

    property var sessions: []
    property real areaWidth: 800
    property real areaHeight: 500
    property int maxNodesPerSession: 150

    readonly property var nodes: root._nodes
    readonly property var edges: root._edges
    readonly property var positions: root._positions

    property var _nodes: []
    property var _edges: []
    property var _positions: []
    property var _held: ({})

    readonly property real _centreX: root.areaWidth / 2
    readonly property real _centreY: root.areaHeight / 2
    readonly property real _sessionRadius: Math.min(root.areaWidth, root.areaHeight) * 0.3
    readonly property real _toolRadius: Math.min(root.areaWidth, root.areaHeight) * 0.19
    readonly property real _subRadius: Math.min(root.areaWidth, root.areaHeight) * 0.11

    readonly property real fadeFloor: 0.35
    readonly property real fadeHalfLifeMs: 900000

    function fadeFor(node, nowMs: real): real {
        if (!node || node.status === "running")
            return 1;
        if (node.kind === "session" && node.status !== "ended")
            return 1;
        const endedAt = node.endedAt || node.startedAt;
        if (!endedAt)
            return 1;
        const age = Math.max(0, nowMs - endedAt);
        const halved = Math.pow(0.5, age / root.fadeHalfLifeMs);
        return root.fadeFloor + (1 - root.fadeFloor) * halved;
    }

    function categoryFor(tool: string): string {
        switch (tool) {
        case "Read":
        case "Write":
        case "Edit":
        case "Glob":
        case "Grep":
        case "NotebookEdit":
            return "file";
        case "Bash":
            return "shell";
        case "WebFetch":
        case "WebSearch":
            return "web";
        case "Agent":
        case "Task":
            return "agent";
        default:
            return "other";
        }
    }

    function categoryColor(category: string): color {
        switch (category) {
        case "file":
            return Colours.palette.m3secondary;
        case "shell":
            return Colours.palette.m3tertiary;
        case "web":
            return Colours.palette.m3primary;
        case "agent":
            return Qt.tint(Colours.palette.m3secondary, Qt.alpha(Colours.palette.m3tertiary, 0.5));
        default:
            return Colours.palette.m3surfaceContainerHigh;
        }
    }

    function sessionColor(hue: real): color {
        return Qt.hsla(((hue % 360) + 360) % 360 / 360, 0.5, 0.62, 1);
    }

    function _hueForKey(key: string): int {
        let hash = 0;
        for (let i = 0; i < key.length; i++)
            hash = (hash * 31 + key.charCodeAt(i)) | 0;
        return Math.abs(hash) % 360;
    }

    function groupColorFor(sessionHue: real, agentId: string): color {
        if (!Settings.agentGraphGroupByParent || !agentId)
            return root.sessionColor(sessionHue);
        return root.sessionColor(root._hueForKey(agentId));
    }

    property bool liveEnabled: Settings.agentGraphEnabled

    onSessionsChanged: {
        if (root.liveEnabled)
            root.rebuild();
    }
    onAreaWidthChanged: root.rebuild()
    onAreaHeightChanged: root.rebuild()
    onLiveEnabledChanged: {
        if (root.liveEnabled)
            root.rebuild();
    }

    function rebuild(): void {
        const nodes = [];
        const edges = [];
        const list = root.sessions ?? [];

        for (let s = 0; s < list.length; s++) {
            const session = list[s];
            const rootIndex = nodes.length;
            const sessionColor = root.sessionColor(session.hue ?? 0);
            nodes.push({
                key: session.id,
                kind: "session",
                sessionIndex: s,
                sessionId: session.id,
                label: session.modelInfo?.label || session.id.slice(0, 8),
                tool: "",
                status: session.status,
                parent: -1,
                startedAt: session.startedAt ?? 0,
                endedAt: session.endedAt ?? 0,
                cwd: session.cwd ?? "",
                callCount: session.nodes.length,
                provider: session.modelInfo?.provider ?? "",
                locality: session.modelInfo?.locality ?? "",
                quant: session.modelInfo?.quant ?? "",
                modelRaw: session.modelInfo?.raw ?? session.model ?? "",
                sessionColor: sessionColor,
                groupColor: sessionColor
            });

            const visible = session.nodes.slice(-root.maxNodesPerSession);
            const indexByNode = ({});
            for (const node of visible) {
                const category = root.categoryFor(node.tool);
                indexByNode[node.id] = nodes.length;
                nodes.push({
                    key: `${session.id}|${node.id}`,
                    kind: node.agentId ? "subagent" : "tool",
                    sessionIndex: s,
                    sessionId: session.id,
                    label: node.tool,
                    tool: node.tool,
                    status: node.status,
                    agentType: node.agentType,
                    agentId: node.agentId,
                    parent: -1,
                    parentId: node.parentId,
                    startedAt: node.startedAt ?? 0,
                    endedAt: node.endedAt ?? 0,
                    durationMs: node.durationMs ?? 0,
                    category: category,
                    categoryColor: root.categoryColor(category),
                    sessionColor: sessionColor,
                    groupColor: root.groupColorFor(session.hue ?? 0, node.agentId)
                });
            }

            for (let i = rootIndex + 1; i < nodes.length; i++) {
                const node = nodes[i];
                const parent = node.parentId ? indexByNode[node.parentId] : undefined;
                node.parent = parent === undefined ? rootIndex : parent;
                edges.push({ a: node.parent, b: i, status: node.status, key: node.key, startedAt: node.startedAt });
            }
        }

        root._nodes = nodes;
        root._edges = edges;
        root._seed();
        root._radial();
    }

    function _seed(): void {
        const positions = [];
        const held = root._held;
        const next = ({});

        for (let i = 0; i < root._nodes.length; i++) {
            const node = root._nodes[i];
            const prior = held[node.key];
            const parent = node.parent >= 0 && node.parent < positions.length ? positions[node.parent] : null;
            const fallback = parent
                ? { x: parent.x + (i % 7 - 3) * 18, y: parent.y + (i % 5 - 2) * 18 }
                : { x: root._centreX, y: root._centreY };
            const point = prior ?? fallback;
            positions.push({ x: point.x, y: point.y });
            next[node.key] = point;
        }

        root._held = next;
        root._positions = positions;
    }

    function _radial(): void {
        const nodes = root._nodes;
        const positions = root._positions;
        const sessionCount = root.sessions?.length ?? 0;
        const childrenOf = ({});

        for (let i = 0; i < nodes.length; i++) {
            const parent = nodes[i].parent;
            if (parent < 0)
                continue;
            (childrenOf[parent] = childrenOf[parent] ?? []).push(i);
        }

        for (let i = 0; i < nodes.length; i++) {
            const node = nodes[i];
            if (node.kind !== "session")
                continue;
            const angle = sessionCount <= 1 ? 0 : (node.sessionIndex / sessionCount) * Math.PI * 2 - Math.PI / 2;
            const radius = sessionCount <= 1 ? 0 : root._sessionRadius;
            positions[i] = {
                x: root._centreX + Math.cos(angle) * radius * (root.areaWidth / Math.min(root.areaWidth, root.areaHeight)) * 0.75,
                y: root._centreY + Math.sin(angle) * radius
            };
            root._place(i, childrenOf, positions, angle, sessionCount <= 1 ? Math.PI * 2 : Math.PI * 1.25, root._toolRadius, true);
        }

        root._fit(positions);
        root._positions = positions.slice();
        root._commit();
    }

    function _fit(positions): void {
        if (positions.length === 0 || root.areaWidth <= 0 || root.areaHeight <= 0)
            return;

        let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
        for (const point of positions) {
            minX = Math.min(minX, point.x);
            maxX = Math.max(maxX, point.x);
            minY = Math.min(minY, point.y);
            maxY = Math.max(maxY, point.y);
        }

        const inset = 78;
        const usableW = Math.max(80, root.areaWidth - inset * 2);
        const usableH = Math.max(80, root.areaHeight - inset * 2);
        const spanX = Math.max(1, maxX - minX);
        const spanY = Math.max(1, maxY - minY);
        const scale = Math.max(0.75, Math.min(1.35, Math.min(usableW / spanX, usableH / spanY)));
        const offsetX = root._centreX - ((minX + maxX) / 2) * scale;
        const offsetY = root._centreY - ((minY + maxY) / 2) * scale;

        for (let i = 0; i < positions.length; i++)
            positions[i] = { x: positions[i].x * scale + offsetX, y: positions[i].y * scale + offsetY };
    }

    function _place(index, childrenOf, positions, facing, spread, radius, isRoot): void {
        const children = childrenOf[index];
        if (!children || children.length === 0)
            return;

        const origin = positions[index];
        const spacing = 96;
        const gap = 84;
        let ring = Math.max(radius, isRoot ? 160 : 96, spacing / Math.max(0.4, spread));
        let placed = 0;

        while (placed < children.length) {
            const capacity = Math.max(3, Math.floor((spread * ring) / spacing));
            const count = Math.min(capacity, children.length - placed);
            const step = count === 1 ? 0 : spread / (count - 1);
            const start = facing - spread / 2;

            for (let c = 0; c < count; c++) {
                const angle = count === 1 ? facing : start + step * c;
                const child = children[placed + c];
                positions[child] = { x: origin.x + Math.cos(angle) * ring, y: origin.y + Math.sin(angle) * ring };
                root._place(child, childrenOf, positions, angle, Math.PI * 0.8, root._subRadius, false);
            }

            placed += count;
            ring += gap;
        }
    }

    function _commit(): void {
        const held = ({});
        for (let i = 0; i < root._nodes.length; i++)
            held[root._nodes[i].key] = root._positions[i];
        root._held = held;
    }
}
