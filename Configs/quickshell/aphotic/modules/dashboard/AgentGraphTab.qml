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

    implicitWidth: 820
    implicitHeight: 520
    radius: Tokens.rounding.extraLarge
    color: Colours.tPalette.m3surfaceContainer

    Binding {
        target: AgentGraphService
        property: "surfaceVisible"
        value: root.visible
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
                text: AgentGraphService.liveSessionCount === 0
                    ? qsTr("idle")
                    : qsTr("%1 live · %2 nodes").arg(AgentGraphService.liveSessionCount).arg(AgentGraphService.nodeCount)
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledRect {
                implicitWidth: tierLabel.implicitWidth + Tokens.padding.medium
                implicitHeight: tierLabel.implicitHeight + Tokens.padding.extraSmall
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

        GraphView {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
