pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    implicitWidth: 940
    implicitHeight: 620
    color: background
    radius: 24
    property color background: "#10171c"
    property color surface: "#192329"
    property color accent: "#89dfca"
    property color secondary: "#b5c8e7"
    property color ink: "#e0ebe8"
    property color muted: "#9bafad"
    property color warning: "#f4bd72"
    property var flow: ({resources:[],workloads:[],edges:[],planes:[],claimCount:0,contentionCount:0})
    property var metrics: []
    property var pending: null
    property var events: []
    property bool motion: true
    property string selectionKind: "resource"
    property string selectionKey: "gpu-vram"
    property real travel: 1
    readonly property var selected: (selectionKind === "resource" ? flow.resources : selectionKind === "plane" ? (flow.planes || []) : flow.workloads).find(n => n.key === selectionKey) || null
    signal decide(int negotiationId, string decision)

    // The map only changes when the model's signature changes. Metric
    // ticks and palette changes rebuild `flow` every second without
    // moving a node, and a settled map must not repaint or replay the
    // pulse on those.
    property string _signature: "-"

    Behavior on background { enabled: root.motion; ColorAnimation { duration: 180 } }
    Behavior on surface { enabled: root.motion; ColorAnimation { duration: 180 } }

    onFlowChanged: {
        const next = flow.signature || "";
        if (next === root._signature)
            return;
        root._signature = next;
        paths.requestPaint();
        if (motion && visible && !pulse.running) pulse.restart();
    }
    onAccentChanged: paths.requestPaint()
    onWarningChanged: paths.requestPaint()
    onMotionChanged: if (!motion) pulse.stop()
    onVisibleChanged: if (!visible) pulse.stop()
    NumberAnimation { id: pulse; objectName: "flowPulse"; target: root; property: "travel"; from: 0; to: 1; duration: 850 }

    component Copy: Text {
        color: root.ink
        font.pixelSize: 13
        textFormat: Text.PlainText
        elide: Text.ElideRight
    }
    component Action: Button {
        id: control
        property bool chosen: false
        contentItem: Copy {
            text: control.text
            color: control.enabled ? (control.chosen ? root.accent : root.ink) : root.muted
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 10
            color: control.down ? Qt.alpha(root.accent,0.2) : root.surface
            border.width: 1
            border.color: control.activeFocus || control.chosen ? root.accent : Qt.alpha(root.muted,0.22)
            opacity: control.enabled ? 1 : 0.5
        }
        implicitHeight: 34
        leftPadding: 12
        rightPadding: 12
    }

    component DecisionAction: Action {
        id: action
        property string decision
        property int pressedId: -1
        onPressed: pressedId = root.pending ? root.pending.id : -1
        onClicked: {
            if (root.pending && root.pending.id === pressedId)
                root.decide(pressedId, decision);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                spacing: 3
                Copy { text: "A P H O T I C   /   F L O W"; color: root.accent; font.pixelSize: 11; font.letterSpacing: 2 }
                Copy { text: "Your system, in concert."; font.pixelSize: 26; font.weight: Font.DemiBold }
            }
            Item { Layout.fillWidth: true }
            Copy { text: root.flow.contentionCount ? root.flow.contentionCount + (root.flow.contentionCount === 1 ? " resource contended" : " resources contended") : "Room to breathe"; color: root.flow.contentionCount ? root.warning : root.accent }
            Action { text: root.motion ? "Motion on" : "Motion off"; onClicked: root.motion = !root.motion }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: root.flow.planes
                Rectangle {
                    id: plane
                    required property var modelData
                    readonly property bool chosen: root.selectionKind === "plane" && root.selectionKey === plane.modelData.key
                    objectName: "plane-" + modelData.key
                    Layout.fillWidth: true
                    implicitHeight: 58
                    radius: 12
                    enabled: plane.modelData.installed
                    opacity: plane.enabled ? 1 : 0.55
                    color: plane.chosen ? Qt.alpha(root.accent,0.12) : root.surface
                    border.width: 1
                    border.color: plane.chosen ? root.accent : plane.modelData.active ? Qt.alpha(root.accent,0.7) : Qt.alpha(root.muted,0.15)
                    Column {
                        anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 24
                        spacing: 3
                        Copy {
                            width: parent.width
                            text: plane.modelData.label + "  /  " + plane.modelData.phase
                            color: plane.modelData.active ? root.accent : root.muted
                            font.pixelSize: 12
                        }
                        Copy {
                            width: parent.width
                            text: plane.modelData.detail.split("\n")[0]
                            color: root.muted
                            font.pixelSize: 10
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: plane.enabled
                        onClicked: { root.selectionKind = "plane"; root.selectionKey = plane.modelData.key; }
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: root.metrics.length
                Rectangle {
                    id: metric
                    objectName: "metric-" + metric.index
                    required property int index
                    readonly property var modelData: root.metrics[metric.index] || ({label:"", value:""})
                    Layout.fillWidth: true
                    implicitHeight: 56
                    radius: 12
                    color: Qt.alpha(root.surface,0.65)
                    Column {
                        anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 24
                        spacing: 4
                        Copy { width: parent.width; text: metric.modelData.label; color: root.muted; font.pixelSize: 10 }
                        Copy { width: parent.width; text: metric.modelData.value; font.pixelSize: 15 }
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Qt.alpha(root.surface,0.5)
                radius: 18
                Copy { x: 16; y: 14; text: "RESERVOIRS"; color: root.muted; font.pixelSize: 10; font.letterSpacing: 1.5 }
                Copy { anchors.right: parent.right; anchors.rightMargin: 16; y: 14; text: "WORKLOADS"; color: root.muted; font.pixelSize: 10; font.letterSpacing: 1.5 }
                Item {
                    id: map
                    anchors.fill: parent
                    anchors.topMargin: 42
                    anchors.bottomMargin: 30
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    readonly property real leftWidth: 135
                    readonly property real rightWidth: 155
                    function ry(i: int): real { return (i + 0.5) * height / Math.max(1,root.flow.resources.length); }
                    function wy(i: int): real { return (i + 0.5) * height / Math.max(1,root.flow.workloads.length); }
                    Canvas {
                        id: paths
                        anchors.fill: parent
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        onPaint: {
                            const c = getContext("2d");
                            c.reset();
                            for (const edge of root.flow.edges) {
                                const x1 = map.leftWidth, x2 = width-map.rightWidth;
                                c.beginPath();
                                c.moveTo(x1,map.ry(edge.resource));
                                c.bezierCurveTo(x1+(x2-x1)*0.45,map.ry(edge.resource),x2-(x2-x1)*0.45,map.wy(edge.workload),x2,map.wy(edge.workload));
                                c.strokeStyle = edge.contended ? root.warning : root.accent;
                                c.globalAlpha = edge.contended ? 0.7 : edge.foreground ? 0.5 : 0.2;
                                c.lineWidth = edge.contended ? 2 : 1.2;
                                c.stroke();
                            }
                        }
                    }
                    Repeater {
                        model: root.motion ? root.flow.edges : []
                        Rectangle {
                            id: spark
                            required property var modelData
                            readonly property real t: root.travel
                            readonly property real dx: map.width-map.leftWidth-map.rightWidth
                            width: 5; height: 5; radius: 3
                            visible: pulse.running
                            color: spark.modelData.contended ? root.warning : root.accent
                            opacity: spark.modelData.foreground ? 1 : 0.4
                            x: map.leftWidth + dx*(3*(1-t)*(1-t)*t*0.45+3*(1-t)*t*t*0.55+t*t*t)-2.5
                            y: map.ry(spark.modelData.resource)+(map.wy(spark.modelData.workload)-map.ry(spark.modelData.resource))*(3*t*t-2*t*t*t)-2.5
                        }
                    }
                    Repeater {
                        model: root.flow.resources
                        Action {
                            id: reservoir
                            objectName: "resource-" + modelData.key
                            required property var modelData
                            required property int index
                            x: 0; y: map.ry(index)-22
                            width: map.leftWidth; height: 44
                            chosen: root.selectionKind === "resource" && root.selectionKey === modelData.key
                            text: modelData.label + (modelData.contended ? "  !" : "")
                            onClicked: { root.selectionKind = "resource"; root.selectionKey = modelData.key; }
                            ToolTip.visible: hovered
                            ToolTip.text: modelData.summary + " · " + modelData.detail
                        }
                    }
                    Repeater {
                        model: root.flow.workloads
                        Action {
                            id: workload
                            objectName: "workload-" + modelData.key
                            required property var modelData
                            required property int index
                            x: map.width-width; y: map.wy(index)-16
                            width: map.rightWidth; height: 32
                            opacity: modelData.foreground || chosen ? 1 : 0.65
                            chosen: root.selectionKind === "workload" && root.selectionKey === modelData.key
                            text: modelData.label
                            onClicked: { root.selectionKind = "workload"; root.selectionKey = modelData.key; }
                            ToolTip.visible: hovered
                            ToolTip.text: modelData.summary
                        }
                    }
                    Copy {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        width: map.rightWidth
                        visible: root.flow.workloads.length === 0
                        text: "Quiet waters.\nNo active claims or profiles."
                        wrapMode: Text.WordWrap
                        color: root.muted
                    }
                }
                Copy {
                    x: 16; anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                    width: parent.width-32
                    text: root.flow.claimCount + " claims · dim = background priority" + ((root.flow.hiddenWorkloads || root.flow.hiddenResources || root.flow.hiddenEdges) ? " · map truncated (+" + root.flow.hiddenWorkloads + " workloads / " + root.flow.hiddenResources + " resources / " + root.flow.hiddenEdges + " links)" : "")
                    color: root.muted; font.pixelSize: 10
                }
            }
            Rectangle {
                Layout.preferredWidth: 270
                Layout.fillHeight: true
                color: root.surface
                radius: 18
                ScrollView {
                    anchors.fill: parent; anchors.margins: 16
                    clip: true
                    contentWidth: availableWidth
                    Column {
                        width: parent.width
                        spacing: 10
                        Copy { text: "CLAIM LENS"; color: root.accent; font.pixelSize: 10; font.letterSpacing: 1.5 }
                        Copy { width: parent.width; text: root.selected ? root.selected.label : "Select a node"; font.pixelSize: 20 }
                        Copy { width: parent.width; text: root.selected ? root.selected.detail : "Inspect a resource or workload to see what it requests and why."; wrapMode: Text.WordWrap; color: root.muted }
                        Copy { width: parent.width; text: root.selected ? root.selected.summary : ""; wrapMode: Text.WordWrap; color: root.selected && root.selected.contended ? root.warning : root.accent }
                        Repeater {
                            model: root.selected ? root.selected.claims.slice(0,64) : []
                            Column {
                                id: claim
                                required property var modelData
                                width: parent.width
                                spacing: 4
                                Rectangle { width: parent.width; height: 1; color: Qt.alpha(root.muted,0.15) }
                                Copy { width: parent.width; text: claim.modelData.label; wrapMode: Text.WordWrap }
                                Copy { width: parent.width; text: claim.modelData.owner + " → " + claim.modelData.resource; color: root.muted; wrapMode: Text.WordWrap; font.pixelSize: 11 }
                                Copy { width: parent.width; text: claim.modelData.amount + " " + (claim.modelData.unit || "") + " · " + claim.modelData.priority + " · " + claim.modelData.origin; color: root.secondary; wrapMode: Text.WordWrap; font.pixelSize: 11 }
                            }
                        }
                        Copy { width: parent.width; visible: root.selected && root.selected.claims.length > 64; text: "Inspector limited to 64 claims."; color: root.warning; wrapMode: Text.WordWrap }
                        Copy { width: parent.width; text: "ACTION TRUTH\nLifecycle phase is reported by the engine. Individual applied-action receipts are not yet available. Dimming does not change process scheduling."; wrapMode: Text.WordWrap; color: root.muted; font.pixelSize: 11 }
                    }
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: root.pending ? 82 : 46
            radius: 14
            color: root.pending ? Qt.alpha(root.warning,0.09) : root.surface
            border.color: root.pending ? Qt.alpha(root.warning,0.4) : "transparent"
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 10; spacing: 5
                Copy {
                    Layout.fillWidth: true
                    text: root.pending ? "NEGOTIATION · " + root.pending.resourceLabel + " · " + root.pending.claimant.owner + " ↔ " + root.pending.requestor.owner : (root.events.length ? root.events[0] : "Listening while visible · no additional process scanner")
                    color: root.pending ? root.warning : root.muted
                }
                RowLayout {
                    visible: !!root.pending
                    DecisionAction { objectName: "keepAction"; text: "Keep both"; decision: "keep" }
                    DecisionAction { objectName: "suspendAction"; text: "Request graceful stop"; decision: "suspend"; enabled: !!root.pending && root.pending.claimantSuspendable }
                    DecisionAction { text: "Ignore this pair"; decision: "ignore" }
                    Copy { Layout.fillWidth: true; text: root.pending && !root.pending.claimantSuspendable ? "No graceful-stop hook" : "Owner confirms release"; color: root.muted; font.pixelSize: 10 }
                }
            }
        }
    }
}
