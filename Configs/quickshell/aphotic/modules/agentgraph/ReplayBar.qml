pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services
import qs.services.ai

ColumnLayout {
    id: root

    required property GraphReplay replay
    property string runId: ""

    signal exited

    spacing: Tokens.spacing.small

    Component.onCompleted: AgentGraphService.refreshRuns()

    // Blocks are laid out on the replay's own compressed clock, not on wall
    // time, so a run with a four-minute pause in it still reads as a dense
    // strip rather than one block and a lot of empty space.
    readonly property var lanes: {
        const events = root.replay.events;
        const stamps = root.replay.stamps;
        const open = ({});
        const rows = ({});
        const order = [];

        for (let i = 0; i < events.length; i++) {
            const e = events[i];
            if (!e.toolId)
                continue;
            const lane = `${e.sessionId}|${e.agentId ?? ""}`;
            if (!rows[lane]) {
                rows[lane] = [];
                order.push(lane);
            }
            if (e.event === "pre_tool_use") {
                open[e.toolId] = { lane: lane, tool: e.tool ?? "", start: stamps[i] ?? 0, index: i, status: "running" };
                rows[lane].push(open[e.toolId]);
            } else if (open[e.toolId]) {
                open[e.toolId].end = stamps[i] ?? 0;
                open[e.toolId].status = e.event === "post_tool_use_failure" ? "errored" : "completed";
            }
        }

        return order.map(lane => ({
            key: lane,
            agent: lane.split("|")[1],
            blocks: rows[lane].map(b => ({
                tool: b.tool,
                index: b.index,
                status: b.status,
                start: b.start,
                end: b.end ?? (root.replay.durationMs || b.start + 1)
            }))
        }));
    }

    function _time(ms: real): string {
        const total = Math.max(0, Math.round(ms / 1000));
        return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
    }

    Process {
        id: exporter
        onExited: code => Toaster.toast(code === 0 ? qsTr("Run exported") : qsTr("Export failed"), code === 0 ? `~/agent-run-${root.runId}.jsonl` : qsTr("Could not copy the run archive"), code === 0 ? "download_done" : "error")
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        MaterialIcon {
            text: "history"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.small
        }

        StyledText {
            text: qsTr("Runs")
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
        }

        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            contentWidth: runRow.implicitWidth
            flickableDirection: Flickable.HorizontalFlick
            clip: true

            Row {
                id: runRow
                spacing: Tokens.spacing.extraSmall

                Repeater {
                    model: AgentGraphService.runs

                    StyledRect {
                        id: chip

                        required property var modelData
                        readonly property bool active: chip.modelData.id === root.runId

                        implicitWidth: chipLabel.implicitWidth + Tokens.padding.medium
                        implicitHeight: 24
                        radius: Tokens.rounding.full
                        color: chip.active ? Colours.palette.m3primary : Qt.alpha(Colours.tPalette.m3surfaceContainerHigh, 0.9)
                        border.width: 1
                        border.color: chip.active ? "transparent" : Colours.palette.m3outlineVariant

                        StyledText {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: chip.modelData.id.slice(0, 8)
                            font: Tokens.font.label.small
                            color: chip.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                        }

                        TapHandler {
                            onTapped: {
                                root.runId = chip.modelData.id;
                                AgentGraphService.loadRun(chip.modelData.id);
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            visible: AgentGraphService.runs.length === 0
            text: qsTr("No recorded runs yet")
            font: Tokens.font.label.small
            color: Colours.palette.m3outlineVariant
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        component TransportButton: StyledRect {
            required property string glyph
            property bool accented: false
            signal activated

            implicitWidth: 28
            implicitHeight: 28
            radius: Tokens.rounding.full
            color: accented ? Colours.palette.m3primary : Qt.alpha(Colours.tPalette.m3surfaceContainerHigh, 0.9)
            border.width: 1
            border.color: accented ? "transparent" : Colours.palette.m3outlineVariant

            MaterialIcon {
                anchors.centerIn: parent
                text: parent.glyph
                color: parent.accented ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
            }

            TapHandler {
                onTapped: parent.activated()
            }
        }

        TransportButton {
            glyph: "replay"
            onActivated: root.replay.seekTo(0)
        }

        TransportButton {
            glyph: "skip_previous"
            onActivated: root.replay.step(-1)
        }

        TransportButton {
            glyph: root.replay.playing ? "pause" : "play_arrow"
            accented: true
            onActivated: root.replay.toggle()
        }

        TransportButton {
            glyph: "skip_next"
            onActivated: root.replay.step(1)
        }

        StyledRect {
            implicitWidth: speedLabel.implicitWidth + Tokens.padding.medium
            implicitHeight: 26
            radius: Tokens.rounding.full
            color: Qt.alpha(Colours.tPalette.m3surfaceContainerHigh, 0.9)
            border.width: 1
            border.color: Colours.palette.m3outlineVariant

            StyledText {
                id: speedLabel
                anchors.centerIn: parent
                text: `${root.replay.speed}x`
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
            }

            TapHandler {
                onTapped: root.replay.speed = root.replay.speed >= 8 ? 1 : root.replay.speed * 2
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: `${root._time(root.replay.positionMs)} / ${root._time(root.replay.durationMs)} · ${root.replay.cursor}/${root.replay.events.length}`
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
        }

        TransportButton {
            glyph: "download"
            onActivated: {
                if (!root.runId)
                    return;
                const home = Quickshell.env("HOME");
                exporter.command = ["cp", `${home}/.local/state/aphotic/agent-runs/${root.runId}.jsonl`, `${home}/agent-run-${root.runId}.jsonl`];
                exporter.running = true;
            }
        }

        TransportButton {
            glyph: "close"
            onActivated: root.exited()
        }
    }

    StyledRect {
        id: scrubber

        Layout.fillWidth: true
        implicitHeight: 6
        radius: Tokens.rounding.full
        color: Qt.alpha(Colours.palette.m3outlineVariant, 0.5)

        StyledRect {
            width: parent.width * root.replay.progress
            height: parent.height
            radius: parent.radius
            color: Colours.palette.m3primary
        }

        TapHandler {
            onTapped: point => root.replay.seekTo(point.position.x / scrubber.width * root.replay.durationMs)
        }

        DragHandler {
            target: null
            yAxis.enabled: false
            onCentroidChanged: if (active) root.replay.seekTo(centroid.position.x / scrubber.width * root.replay.durationMs)
        }
    }

    Column {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.extraSmall
        spacing: 3

        Repeater {
            model: root.lanes

            Item {
                id: lane

                required property var modelData

                width: parent.width
                height: 14

                StyledText {
                    id: laneLabel
                    anchors.verticalCenter: parent.verticalCenter
                    width: 66
                    text: lane.modelData.agent ? qsTr("subagent") : qsTr("main")
                    font: Tokens.font.label.small
                    color: Colours.palette.m3outlineVariant
                    elide: Text.ElideRight
                }

                Item {
                    anchors.left: laneLabel.right
                    anchors.leftMargin: Tokens.spacing.extraSmall
                    anchors.right: parent.right
                    height: parent.height

                    Repeater {
                        model: lane.modelData.blocks

                        StyledRect {
                            id: block

                            required property var modelData
                            readonly property real span: Math.max(1, root.replay.durationMs)

                            x: parent.width * (block.modelData.start / block.span)
                            width: Math.max(3, parent.width * ((block.modelData.end - block.modelData.start) / block.span))
                            height: 10
                            anchors.verticalCenter: parent.verticalCenter
                            radius: Tokens.rounding.extraSmall
                            color: block.modelData.status === "errored"
                                ? Colours.palette.m3error
                                : block.modelData.index < root.replay.cursor
                                    ? Colours.palette.m3primary
                                    : Qt.alpha(Colours.palette.m3outlineVariant, 0.7)

                            StateLayer {
                                anchors.fill: parent
                                radius: parent.radius
                            }

                            TapHandler {
                                onTapped: root.replay.seekToIndex(block.modelData.index)
                            }
                        }
                    }
                }
            }
        }
    }
}
