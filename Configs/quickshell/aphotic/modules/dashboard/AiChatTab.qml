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
        AiProviders.sendMessage("dashboard", AiConfig.activeProvider, AiConfig.ollamaModel, text);
    }

    // Bubbles carry only role and text, so the assistant side resolves the
    // current provider's label instead of a stored name.
    function _senderLabel(role) {
        if (role === "user")
            return qsTr("You");
        const provider = AiProviders.providers.find(p => p.id === AiConfig.activeProvider);
        return provider ? provider.label : qsTr("Assistant");
    }

    Connections {
        target: AiProviders
        function onResponseReceived(requestId, text) {
            if (requestId === "dashboard")
                root._appendMessage("assistant", text);
        }
        function onErrorReceived(requestId, message) {
            if (requestId === "dashboard")
                root._appendMessage("assistant", `⚠ ${message}`);
        }
    }

    // First Command Center open after the Assistant is installed: pre-select
    // it and greet with a system-authored message instead of a live model
    // call, so there's no cold-start latency on the very first thing the
    // user sees. assistantWelcomeShown makes this a once-ever trigger, not
    // once-per-tab-open. Checked both on mount AND on assistantEnabled
    // changing -- AiConfig's own FileView loads asynchronously, so
    // assistantEnabled can still be at its false default the instant this
    // tab mounts, before ai-config.json has actually finished loading.
    function _maybeShowAssistantWelcome() {
        if (AiConfig.assistantEnabled && !Settings.assistantWelcomeShown) {
            AiConfig.activeProvider = "assistant";
            root._appendMessage("assistant", qsTr("Hi, I'm the Aphotic Assistant — I run locally and know this specific install (your profile, layers, and theme). Ask me about theming, the launcher's prefix modes, keybinds, or setting up the gaming/dev layers."));
            Settings.assistantWelcomeShown = true;
        }
    }

    Component.onCompleted: root._maybeShowAssistantWelcome()

    Connections {
        target: AiConfig
        function onAssistantEnabledChanged() {
            root._maybeShowAssistantWelcome();
        }
    }

    // A Flow rather than a fixed RowLayout -- the provider list (plus the
    // conditional Aphotic Assistant pill and Ollama model pill) can exceed
    // the tab's width, and this tab's width in turn governs the Command
    // Center frame's size (DashboardContent.qml sizes tabFrame off the
    // active tab's implicit size). Wrapping instead of overflowing keeps
    // every pill visible and keeps the frame sized to what's actually
    // rendered, however many providers are configured.
    //
    // Layout.preferredWidth is required here, not just Layout.fillWidth:
    // a Flow's own implicitWidth is its *unwrapped* natural width (as wide
    // as needed to fit every pill on one line), and with nothing else
    // pinning this column's width, that unwrapped width would win the
    // ColumnLayout's own implicit-size calculation and get fed straight
    // back down to the Flow -- so it always received exactly enough room
    // to never wrap. Matching the chat list's width below breaks that
    // loop and gives both a shared, stable column width.
    Flow {
        Layout.fillWidth: true
        Layout.preferredWidth: 480
        spacing: Tokens.spacing.small

        Repeater {
            model: AiProviders.providers

            StyledRect {
                id: providerPill

                required property var modelData
                readonly property bool active: providerPill.modelData.id === AiConfig.activeProvider
                readonly property bool available: AiProviders.isAvailable(providerPill.modelData.id)

                height: 32
                width: pillLabel.implicitWidth + Tokens.padding.large * 2
                radius: Tokens.rounding.full
                opacity: providerPill.available ? 1 : 0.4
                // Signal: quiet hairline capsule; the accent border is the
                // only thing that marks the active provider.
                color: Settings.barSignal ? "transparent"
                       : (providerPill.active ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer)
                border.width: Settings.barSignal ? (providerPill.active ? 2 : 1) : 0
                border.color: Settings.barSignal ? (providerPill.active ? Colours.signalStyle.accentLine : Colours.signalStyle.hairline)
                                : "transparent"

                Behavior on color {
                    CAnim {}
                }

                Behavior on border.color {
                    CAnim {}
                }

                StyledText {
                    id: pillLabel
                    anchors.centerIn: parent
                    text: Settings.barSignal ? providerPill.modelData.label.toUpperCase() : providerPill.modelData.label
                    color: Settings.barSignal
                           ? (providerPill.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant)
                           : (providerPill.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant)
                    font: Settings.barSignal
                          ? Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build()
                          : Tokens.font.label.small
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    showHoverBackground: providerPill.available
                    stateOpacity: Settings.barSignal
                                  ? (containsMouse && !providerPill.active ? 1 : 0)
                                  : (containsMouse ? 0.08 : 0)
                    color: Settings.barSignal ? Colours.signalStyle.hover : Colours.palette.m3onSurface
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

        StyledRect {
            id: modelPill

            visible: AiConfig.activeProvider === "ollama"
            height: 32
            width: modelLabel.implicitWidth + Tokens.padding.large * 2
            radius: Tokens.rounding.full
            color: Settings.barSignal ? "transparent" : Colours.tPalette.m3surfaceContainer
            border.width: Settings.barSignal ? 1 : 0
            border.color: Colours.signalStyle.hairline

            StyledText {
                id: modelLabel
                anchors.centerIn: parent
                text: {
                    const t = AiConfig.ollamaHostConfigured
                              ? (AiConfig.ollamaModel || qsTr("Select model"))
                              : qsTr("Set host…");
                    return Settings.barSignal ? t.toUpperCase() : t;
                }
                color: Colours.palette.m3onSurfaceVariant
                font: Settings.barSignal
                      ? Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build()
                      : Tokens.font.label.small
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
                stateOpacity: Settings.barSignal ? (containsMouse ? 1 : 0) : (containsMouse ? 0.08 : 0)
                color: Settings.barSignal ? Colours.signalStyle.hover : Colours.palette.m3onSurface
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
        id: chatPanel

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 480
        Layout.preferredHeight: 300
        radius: Tokens.rounding.large
        color: Settings.barSignal ? Colours.signalStyle.surface : Colours.tPalette.m3surfaceContainer
        border.width: Settings.barSignal ? 1 : 0
        border.color: Colours.signalStyle.hairline

        Elevation {
            visible: Settings.barSignal
            target: chatPanel
            level: 1
        }

        Rectangle {
            visible: Settings.barSignal
            x: chatPanel.radius
            width: chatPanel.width - chatPanel.radius * 2
            height: 1
            color: Colours.signalStyle.edgeLight
        }

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

            delegate: Item {
                id: bubble

                required property var modelData
                readonly property bool fromUser: bubble.modelData.role === "user"

                width: list.width
                implicitHeight: Settings.barSignal
                               ? senderLabel.implicitHeight + Tokens.spacing.extraSmall + bubbleBody.implicitHeight
                               : bubbleBody.implicitHeight

                ColumnLayout {
                    anchors.fill: parent
                    spacing: Settings.barSignal ? Tokens.spacing.extraSmall : 0

                    StyledText {
                        id: senderLabel

                        visible: Settings.barSignal
                        Layout.alignment: bubble.fromUser ? Qt.AlignRight : Qt.AlignLeft
                        Layout.maximumWidth: bubbleBody.implicitWidth
                        elide: Text.ElideRight
                        text: root._senderLabel(bubble.modelData.role).toUpperCase()
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build()
                    }

                    StyledRect {
                        id: bubbleBody

                        // Bubbles hug their text up to 80% of the list.
                        readonly property real maxBubbleWidth: list.width * 0.8

                        Layout.fillWidth: !Settings.barSignal
                        Layout.alignment: Settings.barSignal ? (bubble.fromUser ? Qt.AlignRight : Qt.AlignLeft) : Qt.AlignLeft
                        Layout.maximumWidth: Settings.barSignal ? bubbleBody.maxBubbleWidth : -1
                        implicitWidth: bubbleText.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: bubbleText.implicitHeight + Tokens.padding.medium * 2
                        radius: Settings.barSignal ? Tokens.rounding.large : Tokens.rounding.medium
                        bottomRightRadius: Settings.barSignal && bubble.fromUser ? Tokens.rounding.small : bubbleBody.radius
                        bottomLeftRadius: Settings.barSignal && !bubble.fromUser ? Tokens.rounding.small : bubbleBody.radius
                        color: Settings.barSignal
                               ? (bubble.fromUser ? Qt.alpha(Colours.palette.m3primary, 0.14) : Colours.signalStyle.raised)
                               : (bubble.fromUser ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHigh)
                        border.width: Settings.barSignal ? 1 : 0
                        border.color: Settings.barSignal
                                      ? (bubble.fromUser ? Qt.alpha(Colours.palette.m3primary, 0.4) : Colours.signalStyle.hairline)
                                      : "transparent"

                        Rectangle {
                            visible: Settings.barSignal && !bubble.fromUser
                            x: Math.min(bubbleBody.radius, bubbleBody.width / 2)
                            width: Math.max(bubbleBody.width - Math.min(bubbleBody.radius, bubbleBody.width / 2) * 2, 0)
                            height: 1
                            color: Colours.signalStyle.edgeLight
                        }

                        StyledText {
                            id: bubbleText
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: Tokens.padding.medium
                            anchors.verticalCenter: parent.verticalCenter
                            wrapMode: Text.Wrap
                            text: bubble.modelData.text
                            color: Settings.barSignal
                                   ? Colours.palette.m3onSurface
                                   : (bubble.fromUser ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurface)
                            font: Tokens.font.body.medium
                        }
                    }
                }
            }

            ColumnLayout {
                visible: list.count === 0
                anchors.centerIn: parent
                spacing: Settings.barSignal ? Tokens.spacing.small : 0

                MaterialIcon {
                    visible: Settings.barSignal
                    Layout.alignment: Qt.AlignHCenter
                    text: "smart_toy"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.large
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Ask anything")
                    color: Settings.barSignal ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                    font: Settings.barSignal
                          ? Tokens.font.title.builders.medium.weight(Font.DemiBold).build()
                          : Tokens.font.body.medium
                }

                StyledText {
                    visible: Settings.barSignal
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Type below to start a conversation")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build()
                }
            }
        }
    }

    StyledRect {
        id: inputBar

        Layout.fillWidth: true
        Layout.preferredHeight: 48
        radius: Tokens.rounding.full
        color: Settings.barSignal ? Colours.signalStyle.raised : Colours.palette.m3surfaceContainerHigh
        border.width: Settings.barSignal ? 1 : 0
        border.color: Settings.barSignal && (input.activeFocus || input.text.length > 0)
                     ? Qt.alpha(Colours.palette.m3primary, 0.7)
                     : Colours.signalStyle.hairline

        Behavior on border.color {
            CAnim {}
        }

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
                // Tinted at rest, solid only while a reply streams.
                color: AiProviders.busy || !Settings.barSignal
                       ? Colours.palette.m3primary
                       : Qt.alpha(Colours.palette.m3primary, 0.18)
                opacity: AiProviders.busy ? 0.5 : 1

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "send"
                    color: AiProviders.busy || !Settings.barSignal
                           ? Colours.contrastOn(Colours.palette.m3primary)
                           : Colours.palette.m3primaryOnSurface
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
