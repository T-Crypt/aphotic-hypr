pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
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
                    showHoverBackground: providerPill.available
                }

                // A StateLayer's own MouseArea goes `enabled: false` when
                // disabled (so the hover/ripple visuals correctly turn
                // off), and a disabled MouseArea does not accept the
                // click -- it falls through to whatever is behind it,
                // which here is DashboardWindow's full-screen click-
                // outside-to-dismiss MouseArea. That silently closed the
                // whole dashboard instead of just no-opping on an
                // unavailable pill. This plain MouseArea stays enabled
                // regardless of availability so it always absorbs the
                // click; it only acts on it when the provider is usable.
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (providerPill.available)
                            AiConfig.activeProvider = providerPill.modelData.id;
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
        }

        StyledRect {
            id: modelPill

            visible: AiConfig.activeProvider === "ollama"
            Layout.preferredHeight: 32
            Layout.preferredWidth: modelLabel.implicitWidth + Tokens.padding.large * 2
            radius: Tokens.rounding.full
            color: Colours.tPalette.m3surfaceContainer

            StyledText {
                id: modelLabel
                anchors.centerIn: parent
                text: AiConfig.ollamaHostConfigured ? (AiConfig.ollamaModel || qsTr("Select model")) : qsTr("Set host…")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
            }

            MouseArea {
                anchors.fill: parent
                onClicked: modelMenu.open()
            }

            Popup {
                id: modelMenu

                y: modelPill.height + Tokens.spacing.small
                width: 220
                padding: Tokens.padding.small
                background: StyledRect {
                    radius: Tokens.rounding.medium
                    color: Colours.tPalette.m3surfaceContainer
                }

                contentItem: ColumnLayout {
                    spacing: Tokens.spacing.extraSmall

                    // Host isn't configured yet -- let the user type one
                    // in directly rather than only pointing them at a
                    // config file. AiConfig persists whatever is entered.
                    RowLayout {
                        visible: !AiConfig.ollamaHostConfigured
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall

                        StyledRect {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            radius: Tokens.rounding.small
                            color: Colours.palette.m3surfaceContainerHigh

                            TextInput {
                                id: hostInput
                                anchors.fill: parent
                                anchors.margins: Tokens.padding.small
                                font: Tokens.font.label.small
                                color: Colours.palette.m3onSurface
                                clip: true

                                StyledText {
                                    visible: hostInput.text.length === 0
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    text: qsTr("http://host:11434")
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                }

                                Keys.onReturnPressed: {
                                    if (hostInput.text.trim().length > 0) {
                                        AiConfig.ollamaHost = hostInput.text.trim();
                                        AiProviders.refreshOllamaModels();
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        visible: AiConfig.ollamaHostConfigured && AiProviders.ollamaModels.length === 0
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: qsTr("No models found on this host")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }

                    Repeater {
                        model: AiProviders.ollamaModels

                        StyledRect {
                            id: modelOption

                            required property string modelData

                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            radius: Tokens.rounding.small
                            color: modelOption.modelData === AiConfig.ollamaModel ? Colours.palette.m3primary : "transparent"

                            StyledText {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: Tokens.padding.small
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: modelOption.modelData
                                color: modelOption.modelData === AiConfig.ollamaModel ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurface
                                font: Tokens.font.label.small
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    AiConfig.ollamaModel = modelOption.modelData;
                                    modelMenu.close();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    StyledText {
        visible: AiConfig.activeProvider === "ollama" && !AiConfig.ollamaHostConfigured
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("⚠ No Ollama host configured. Click the pill above to set one, or set OLLAMA_BASE_URL.")
        color: Colours.palette.m3error
        font: Tokens.font.label.small
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
                    showHoverBackground: !AiProviders.busy
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root._send()
                }
            }
        }
    }
}
