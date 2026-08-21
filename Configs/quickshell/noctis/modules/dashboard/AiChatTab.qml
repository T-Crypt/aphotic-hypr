pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.services.ai

ColumnLayout {
    id: root

    width: 520
    height: 420

    spacing: Tokens.spacing.medium

    readonly property var messages: []

    function _appendMessage(role, text) {
        root.messages.push({ role, text });
        messageModel.values = root.messages.slice();
        Qt.callLater(() => list.positionViewAtEnd());
    }

    function _send() {
        const text = input.text.trim();
        if (text.length === 0 || AiProviders.busy)
            return;
        root._appendMessage("user", text);
        input.text = "";
        AiProviders.sendMessage(text);
    }

    Connections {
        target: AiProviders
        function onResponseReceived(text) {
            root._appendMessage("assistant", text);
        }
        function onErrorReceived(message) {
            root._appendMessage("assistant", `⚠ ${message}`);
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        Repeater {
            model: AiProviders.providers

            StyledRect {
                id: providerPill

                required property var modelData
                readonly property bool active: providerPill.modelData.id === AiConfig.activeProvider
                readonly property bool available: AiProviders.isAvailable(providerPill.modelData.id)

                Layout.preferredHeight: 32
                Layout.preferredWidth: pillLabel.implicitWidth + Tokens.padding.large * 2
                radius: Tokens.rounding.full
                opacity: providerPill.available ? 1 : 0.4
                color: providerPill.active ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer

                Behavior on color {
                    CAnim {}
                }

                StyledText {
                    id: pillLabel
                    anchors.centerIn: parent
                    text: providerPill.modelData.label
                    color: providerPill.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    disabled: !providerPill.available
                    onClicked: AiConfig.activeProvider = providerPill.modelData.id
                }
            }
        }

        Item {
            Layout.fillWidth: true
        }

        StyledRect {
            visible: AiConfig.activeProvider === "ollama"
            Layout.preferredHeight: 32
            Layout.preferredWidth: modelLabel.implicitWidth + Tokens.padding.large * 2
            radius: Tokens.rounding.full
            color: Colours.tPalette.m3surfaceContainer

            StyledText {
                id: modelLabel
                anchors.centerIn: parent
                text: AiConfig.ollamaModel
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }
        }
    }

    StyledRect {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        ListView {
            id: list

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            clip: true
            spacing: Tokens.spacing.small

            model: ScriptModel {
                id: messageModel
                values: []
            }

            delegate: StyledRect {
                id: bubble

                required property var modelData
                readonly property bool fromUser: bubble.modelData.role === "user"

                width: list.width
                implicitHeight: bubbleText.implicitHeight + Tokens.padding.medium * 2
                radius: Tokens.rounding.medium
                color: bubble.fromUser ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh

                StyledText {
                    id: bubbleText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: Tokens.padding.medium
                    anchors.verticalCenter: parent.verticalCenter
                    wrapMode: Text.Wrap
                    text: bubble.modelData.text
                    color: bubble.fromUser ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurface
                    font: Tokens.font.body.medium
                }
            }

            StyledText {
                visible: list.count === 0
                anchors.centerIn: parent
                text: qsTr("Ask anything")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
            }
        }
    }

    StyledRect {
        Layout.fillWidth: true
        Layout.preferredHeight: 48
        radius: Tokens.rounding.full
        color: Colours.palette.m3surfaceContainerHigh

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.small
            spacing: Tokens.spacing.small

            TextInput {
                id: input

                Layout.fillWidth: true
                clip: true
                enabled: !AiProviders.busy
                font: Tokens.font.body.medium
                color: Colours.palette.m3onSurface

                Keys.onReturnPressed: root._send()

                StyledText {
                    visible: input.text.length === 0
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: AiProviders.busy ? qsTr("Thinking…") : qsTr("Message…")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                }
            }

            StyledRect {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: Tokens.rounding.full
                color: Colours.palette.m3primary
                opacity: AiProviders.busy ? 0.5 : 1

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "send"
                    color: Colours.contrastOn(Colours.palette.m3primary)
                    fontStyle: Tokens.font.icon.small
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    disabled: AiProviders.busy
                    onClicked: root._send()
                }
            }
        }
    }
}
