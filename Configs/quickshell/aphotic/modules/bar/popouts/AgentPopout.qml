import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property ScreenState screenState

    spacing: Tokens.spacing.medium

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Agents").toUpperCase()
            color: Colours.inkMuted
            font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build()
        }

        MaterialIcon {
            text: "close"
            fontStyle: Tokens.font.icon.small

            MouseArea {
                anchors.fill: parent
                anchors.margins: -Tokens.padding.small
                cursorShape: Qt.PointingHandCursor
                onClicked: root.screenState.agentPanel = false
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small / 2

        Repeater {
            model: AgentProviders.providers

            StyledRect {
                id: tabRect

                required property var modelData

                readonly property bool isSelected: modelData.id === AgentProviders.selected

                Layout.fillWidth: true
                implicitWidth: tabRow.implicitWidth + Tokens.padding.small * 2
                implicitHeight: tabRow.implicitHeight + Tokens.padding.small * 2
                radius: Tokens.rounding.medium
                color: "transparent"

                Rectangle {
                    visible: tabRect.isSelected
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: Tokens.rounding.medium
                    anchors.rightMargin: Tokens.rounding.medium
                    height: 2
                    radius: Tokens.rounding.full
                    color: Colours.signalStyle.accentLine
                }

                Interact {
                    anchors.fill: parent
                    color: Colours.signalStyle.hover
                    stateOpacity: (containsMouse ? 1 : 0)
                    onClicked: Settings.agentSelectedProvider = tabRect.modelData.id
                }

                RowLayout {
                    id: tabRow

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        text: tabRect.modelData.icon
                        color: tabRect.isSelected ? Colours.ink : Colours.inkMuted
                        fontStyle: Tokens.font.icon.small
                        fill: tabRect.isSelected ? 1 : 0
                    }

                    StyledText {
                        text: tabRect.modelData.label
                        color: tabRect.isSelected ? Colours.ink : Colours.inkMuted
                        font: Tokens.font.label.medium
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: detail

        readonly property int index: AgentProviders.selectedIndex
        readonly property var stat: AgentProviders.stats[index] ?? ({})
        readonly property string harnessId: AgentProviders.providers[index]?.id ?? ""
        readonly property var sessions: AgentProviders.liveSessionsOf(detail.harnessId)

        Layout.fillWidth: true
        spacing: Tokens.spacing.small / 2

        StyledText {
            text: qsTr("%1 session(s) open").arg(AgentProviders.sessionCountOf(detail.harnessId))
            font: Tokens.font.title.builders.medium.weight(Font.DemiBold).build()
        }

        // One row per open session, labelled by the status AgentEvents
        // tracks for it, not by the name of its last event.
        Repeater {
            model: detail.sessions

            RowLayout {
                required property var modelData

                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.extraSmall
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: {
                        switch (parent.modelData.status) {
                        case "running": return "sync";
                        case "waiting": return "notifications";
                        case "compacting": return "compress";
                        default: return "circle";
                        }
                    }
                    fontStyle: Tokens.font.icon.small
                    color: parent.modelData.status === "idle" ? Colours.inkMuted : Colours.signal
                }

                StyledText {
                    Layout.fillWidth: true
                    text: parent.modelData.tool || parent.modelData.model || qsTr("Session %1").arg(parent.modelData.id.slice(0, 8))
                    font: Tokens.font.label.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    text: {
                        switch (parent.modelData.status) {
                        case "running": return qsTr("running");
                        case "waiting": return qsTr("waiting on you");
                        case "compacting": return qsTr("compacting");
                        default: return qsTr("idle");
                        }
                    }
                    color: Colours.inkMuted
                    font: Tokens.font.label.small
                }
            }
        }

        StyledText {
            visible: detail.stat.availability === "unavailable"
            text: qsTr("No usage data yet")
            color: Colours.inkMuted
            font: Tokens.font.body.small
        }

        StyledText {
            visible: detail.stat.availability === "unsupported"
            text: qsTr("Usage tracking not supported for this version")
            color: Colours.inkMuted
            font: Tokens.font.body.small
        }

        StyledText {
            visible: detail.stat.availability === "available"
            text: qsTr("Today: %1 tokens").arg(detail.stat.todayTokens ?? 0)
            color: Colours.inkMuted
            font: Tokens.font.body.small
        }

        Repeater {
            model: detail.stat.availability === "available" ? (detail.stat.tokensByModel ?? []) : []

            RowLayout {
                required property var modelData

                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: parent.modelData.model
                    color: Colours.inkMuted
                    font: Tokens.font.label.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    text: qsTr("%1 tokens").arg(parent.modelData.tokens)
                    font: Tokens.font.label.medium
                }
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Right-click the bar icon to launch · middle-click to switch provider")
        color: Colours.inkMuted
        font: Tokens.font.body.small
        wrapMode: Text.Wrap
    }
}
