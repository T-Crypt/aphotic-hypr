pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.modules.agentgraph
import qs.services.ai

StyledRect {
    id: root

    property bool replayMode: false

    implicitWidth: 820
    implicitHeight: root.replayMode ? 620 : 520
    radius: Tokens.rounding.extraLarge
    color: Colours.tPalette.m3surfaceContainer

    Behavior on implicitHeight {
        Anim { type: Anim.EmphasizedSmall }
    }

    Binding {
        target: AgentGraphService
        property: "surfaceVisible"
        value: root.visible
    }

    GraphReplay {
        id: replay
        events: AgentGraphService.replayEvents
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                text: qsTr("Agent graph")
                font: Tokens.font.title.small
                color: Colours.palette.m3onSurface
            }

            StyledText {
                Layout.fillWidth: true
                text: root.replayMode
                    ? (replay.loaded ? qsTr("replaying %1 events").arg(replay.events.length) : qsTr("pick a run"))
                    : AgentGraphService.liveSessionCount === 0
                        ? qsTr("idle")
                        : qsTr("%1 live · %2 nodes").arg(AgentGraphService.liveSessionCount).arg(AgentGraphService.nodeCount)
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledRect {
                implicitWidth: replayLabel.implicitWidth + Tokens.padding.medium
                implicitHeight: 24
                radius: Tokens.rounding.full
                color: root.replayMode ? Colours.palette.m3primary : Qt.alpha(Colours.tPalette.m3surfaceContainerHigh, 0.9)
                border.width: 1
                border.color: root.replayMode ? "transparent" : Colours.palette.m3outlineVariant

                RowLayout {
                    id: replayLabel

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        text: "history"
                        fontStyle: Tokens.font.icon.small
                        color: root.replayMode ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        text: qsTr("Replay")
                        font: Tokens.font.label.small
                        color: root.replayMode ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                    }
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                }

                TapHandler {
                    onTapped: {
                        root.replayMode = !root.replayMode;
                        if (root.replayMode)
                            AgentGraphService.refreshRuns();
                        else
                            replay.pause();
                    }
                }
            }

            StyledRect {
                implicitWidth: tierLabel.implicitWidth + Tokens.padding.medium
                implicitHeight: 24
                radius: Tokens.rounding.full
                color: Qt.alpha(Colours.palette.m3primary, 0.16)

                StyledText {
                    id: tierLabel

                    anchors.centerIn: parent
                    text: AgentGraphService.tier
                    font: Tokens.font.label.small
                    color: Colours.palette.m3primary
                }
            }
        }

        // Replay is a different clock over the same renderer, never a second
        // view -- the only thing that changes is where `sessions` comes from.
        GraphView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            sessions: root.replayMode ? replay.sessions : AgentGraphService.sessions
        }

        Loader {
            Layout.fillWidth: true
            active: root.replayMode
            visible: active

            sourceComponent: ReplayBar {
                replay: replay
                onExited: {
                    root.replayMode = false;
                    replay.pause();
                }
            }
        }
    }
}
