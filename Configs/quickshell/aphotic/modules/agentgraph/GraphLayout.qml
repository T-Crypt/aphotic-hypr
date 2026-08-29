pragma ComponentBehavior: Bound

import QtQuick

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

    onSessionsChanged: root.rebuild()
    onAreaWidthChanged: root.rebuild()
    onAreaHeightChanged: root.rebuild()

    function rebuild(): void {
        const nodes = [];
        const edges = [];
        const list = root.sessions ?? [];

        for (let s = 0; s < list.length; s++) {
            const session = list[s];
            const rootIndex = nodes.length;
            nodes.push({
                key: session.id,
                kind: "session",
                sessionIndex: s,
                sessionId: session.id,
                label: session.model || session.id.slice(0, 8),
                tool: "",
                status: session.status,
                parent: -1,
                startedAt: session.startedAt ?? 0
            });

            const visible = session.nodes.slice(-root.maxNodesPerSession);
            const indexByNode = ({});
            for (const node of visible) {
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
                    parent: -1,
                    parentId: node.parentId,
                    startedAt: node.startedAt ?? 0
                });
            }

            for (let i = rootIndex + 1; i < nodes.length; i++) {
                const node = nodes[i];
                const parent = node.parentId ? indexByNode[node.parentId] : undefined;
                node.parent = parent === undefined ? rootIndex : parent;
                edges.push({ a: node.parent, b: i, status: node.status, key: node.key });
            }
        }

        root._nodes = nodes;
        root._edges = edges;
        root._seed();
        root._radial();
    }

    // Positions survive a rebuild by node key: sessions are replaced
    // wholesale on every hook event, so seeding from scratch each time would
    // make every node jump on every tool call.
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

    // Radial: a call tree, laid out as one. Session roots ring the centre,
    // each session's own calls fan out into the wedge pointing away from it,
    // and a subagent's calls fan around the Agent node that spawned them.
    // Deterministic and one-pass -- there is no steady-state cost at all once
    // it has run, and an arriving node doesn't disturb the ones already
    // placed the way a relaxing force layout does.
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

    // Pills are a fixed pixel size but the graph's own extent isn't, so the
    // placed result is normalised into the available area rather than
    // trusting the radii to happen to fit. This is also what makes the
    // surface size-agnostic -- a tab, a full overlay and a small popout all
    // get a graph that fills them.
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
        const scale = Math.min(1.35, Math.min(usableW / spanX, usableH / spanY));
        const offsetX = root._centreX - ((minX + maxX) / 2) * scale;
        const offsetY = root._centreY - ((minY + maxY) / 2) * scale;

        for (let i = 0; i < positions.length; i++)
            positions[i] = { x: positions[i].x * scale + offsetX, y: positions[i].y * scale + offsetY };
    }

    // Ring radius grows with how many children have to fit on it, so a
    // session with thirty tool calls spaces them out instead of stacking
    // them on top of each other at a fixed distance.
    function _place(index, childrenOf, positions, facing, spread, radius, isRoot): void {
        const children = childrenOf[index];
        if (!children || children.length === 0)
            return;

        const origin = positions[index];
        const needed = (children.length * 46) / Math.max(0.6, spread);
        const ring = Math.max(radius, needed);
        const step = children.length === 1 ? 0 : spread / (children.length - 1);
        const start = facing - spread / 2;

        for (let c = 0; c < children.length; c++) {
            const angle = children.length === 1 ? facing : start + step * c;
            positions[children[c]] = { x: origin.x + Math.cos(angle) * ring, y: origin.y + Math.sin(angle) * ring };
            root._place(children[c], childrenOf, positions, angle, Math.PI * 0.8, root._subRadius, false);
        }
    }

    function _commit(): void {
        const held = ({});
        for (let i = 0; i < root._nodes.length; i++)
            held[root._nodes[i].key] = root._positions[i];
        root._held = held;
    }
}
