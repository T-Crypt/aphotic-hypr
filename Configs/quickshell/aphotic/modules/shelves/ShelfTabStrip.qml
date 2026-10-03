pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components
import qs.services

// The tab handles for one shelf edge. Visible whenever the edge has any
// tab at all, so closing one is a click rather than a second gesture.
// Clicking the shown tab closes it, which is what an inside click on the
// shelf's own tab is supposed to do.
Item {
    id: root

    required property string output
    required property string edge
    readonly property var tabs: ShelfTabs.forEdge(edge)
    readonly property var current: Shelves.tabFor(output,edge)
    readonly property real chip: Tokens.sizes.bar.innerWidth

    function select(id: string): void {
        if (id === (root.current?.id ?? ""))
            Shelves.closeTab(output,edge);
        else
            Shelves.openTab(output,edge,id);
    }

    implicitHeight: Math.min(200, root.tabs.length * (root.chip + Tokens.spacing.extraSmall))

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: handles.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: handles
            width: parent.width
            spacing: Tokens.spacing.extraSmall

        Repeater {
            model: root.tabs
            delegate: Item {
                id: chip

                required property var modelData
                readonly property string output: root.output
                readonly property string edge: root.edge
                readonly property bool current: root.current !== null && root.current.id === modelData.id

                anchors.horizontalCenter: parent.horizontalCenter
                width: root.chip
                height: root.chip
                objectName: "shelf-tab-" + modelData.id

                // Tab acknowledgement: one finite trace of the selected
                // handle per ready panel. A finite animation where motion
                // is allowed, the same hold without it when it is not.
                Rectangle {
                    id: traceRing
                    objectName: "shelf-tab-trace"

                    anchors.fill: parent
                    radius: Tokens.rounding.full
                    color: "transparent"
                    border.width: 1
                    border.color: Colours.palette.m3primary
                    opacity: 0

                    property int seen: 0

                    Timer {
                        id: staticHold
                        interval: 600
                        onTriggered: traceRing.opacity = 0
                    }

                    SequentialAnimation {
                        id: trace
                        NumberAnimation { target: traceRing; property: "opacity"; to: 1; duration: 120 }
                        PauseAnimation { duration: 240 }
                        NumberAnimation { target: traceRing; property: "opacity"; to: 0; duration: 300 }
                    }
                }

                // Off unless the user asked for it. The effect has no
                // lifetime of its own: a panel that reports ready bumps
                // the counter, and the selected handle traces once.
                Connections {
                    target: Shelves
                    function onAcksChanged() {
                        chip.syncAck();
                    }
                }

                function stopTrace() {
                    trace.stop(); staticHold.stop(); traceRing.opacity = 0;
                }
                function syncAck() {
                    const count = Shelves.ackCount(chip.output,chip.edge);
                    if (count <= traceRing.seen) return;
                    traceRing.seen = count;
                    if (!Settings.shelfTabAcknowledge || !chip.current) return;
                    if (RenderGate.decorative) trace.restart();
                    else { traceRing.opacity = 1; staticHold.restart(); }
                }
                onCurrentChanged: if (!current) stopTrace()
                Component.onCompleted: traceRing.seen = Shelves.ackCount(chip.output,chip.edge)

                StateLayer {
                    radius: Tokens.rounding.full
                    onClicked: root.select(chip.modelData.id)
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: chip.modelData.icon
                    fontStyle: Tokens.font.icon.large
                    color: chip.current ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }
    }
}
