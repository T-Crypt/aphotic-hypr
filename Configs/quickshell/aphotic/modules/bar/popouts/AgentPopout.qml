import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property ScreenState screenState

    implicitWidth: 300
    spacing: Tokens.spacing.medium

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Agents")
            font: Tokens.font.title.medium
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
                implicitHeight: tabRow.implicitHeight + Tokens.padding.small * 2
                radius: Tokens.rounding.normal
                color: isSelected ? Colours.palette.m3secondaryContainer : "transparent"

                StateLayer {
                    anchors.fill: parent
                    onClicked: Settings.agentSelectedProvider = tabRect.modelData.id
                }

                RowLayout {
                    id: tabRow

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        text: tabRect.modelData.icon
                        color: tabRect.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                        fill: tabRect.isSelected ? 1 : 0
                    }

                    StyledText {
                        text: tabRect.modelData.label
                        color: tabRect.isSelected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
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
        readonly property bool isOllama: AgentProviders.selected === "ollama"

        Layout.fillWidth: true
        spacing: Tokens.spacing.small / 2

        StyledText {
            visible: !detail.isOllama
            text: qsTr("%1 session(s) running").arg(detail.stat.sessionCount ?? 0)
            font: Tokens.font.title.medium
        }

        StyledText {
            visible: !detail.isOllama && detail.stat.availability === "unavailable"
            text: qsTr("No usage data yet")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }

        StyledText {
            visible: !detail.isOllama && detail.stat.availability === "unsupported"
            text: qsTr("Usage tracking not supported for this CLI version")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }

        StyledText {
            visible: !detail.isOllama && detail.stat.availability === "available"
            text: qsTr("Today: %1 tokens").arg(detail.stat.todayTokens ?? 0)
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }

        Repeater {
            model: !detail.isOllama && detail.stat.availability === "available" ? (detail.stat.tokensByModel ?? []) : []

            RowLayout {
                required property var modelData

                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: parent.modelData.model
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    text: qsTr("%1 tok").arg(parent.modelData.tokens)
                    font: Tokens.font.label.medium
                }
            }
        }

        StyledText {
            visible: detail.isOllama
            text: (detail.stat.loadedModels ?? []).length > 0 ? (detail.stat.loadedModels ?? []).join(", ") : qsTr("No models loaded")
            font: Tokens.font.title.medium
            wrapMode: Text.Wrap
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Right-click the bar icon to launch · middle-click to switch provider")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
        wrapMode: Text.Wrap
    }
}
