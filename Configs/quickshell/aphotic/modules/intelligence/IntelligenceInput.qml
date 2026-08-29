pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.services.ai

ColumnLayout {
    id: root

    spacing: Tokens.spacing.extraSmall

    readonly property var activeSession: IntelligenceSessions.activeSession
    readonly property string effectiveProvider: root.activeSession?.provider ?? (Settings.intelligenceDefaultProvider || AiConfig.activeProvider)
    readonly property bool ollamaHostMissing: root.effectiveProvider === "ollama" && !AiConfig.ollamaHostConfigured
    readonly property bool providerAvailable: AiProviders.isAvailable(root.effectiveProvider)

    function send(): void {
        const text = textEdit.text.trim();
        if (text.length === 0 || AiProviders.busy || root.ollamaHostMissing || !root.providerAvailable)
            return;
        const provider = root.effectiveProvider;
        const model = root.activeSession?.model ?? (Settings.intelligenceDefaultModel || AiConfig.ollamaModel);
        textEdit.text = "";
        IntelligenceSessions.sendUserMessage(text, provider, model);
    }

    StyledText {
        visible: root.ollamaHostMissing
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("⚠ No Ollama host configured. Set one in Settings → AI, or set OLLAMA_BASE_URL.")
        color: Colours.palette.m3error
        font: Tokens.font.label.small
    }

    StyledText {
        visible: !root.ollamaHostMissing && !root.providerAvailable && root.effectiveProvider === "claude"
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        // Claude doesn't need an API key (see AiProviders.claudeAvailable's
        // comment) -- a real login-session check instead, so this warning
        // needs its own accurate text rather than the generic "set an env
        // var" one below, which would be actively wrong for this provider.
        text: !AiProviders.claudeCliPresent ? qsTr("⚠ The claude CLI isn't installed.") : qsTr("⚠ Not logged in to Claude. Run `claude login` in a terminal, then refresh.")
        color: Colours.palette.m3error
        font: Tokens.font.label.small
    }

    StyledText {
        visible: !root.ollamaHostMissing && !root.providerAvailable && root.effectiveProvider !== "claude"
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("⚠ No API key configured for %1. Set %2 to enable.").arg(AiProviders.providers.find(p => p.id === root.effectiveProvider)?.label ?? root.effectiveProvider).arg(AiProviders.requiredEnvVar(root.effectiveProvider))
        color: Colours.palette.m3error
        font: Tokens.font.label.small
    }

    StyledRect {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(Math.max(48, inputFlick.contentHeight + Tokens.padding.medium * 2), 160)
        radius: Tokens.rounding.large
        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.small
            anchors.topMargin: Tokens.padding.small
            anchors.bottomMargin: Tokens.padding.small
            spacing: Tokens.spacing.small

            Flickable {
                id: inputFlick

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: textEdit.contentHeight
                boundsBehavior: Flickable.StopAtBounds

                TextEdit {
                    id: textEdit

                    width: inputFlick.width
                    enabled: !AiProviders.busy
                    wrapMode: TextEdit.Wrap
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3onSurface
                    selectByMouse: true

                    Keys.onPressed: event => {
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                            event.accepted = true;
                            root.send();
                        }
                    }

                    StyledText {
                        visible: textEdit.text.length === 0
                        anchors.left: parent.left
                        anchors.top: parent.top
                        text: AiProviders.busy ? qsTr("Thinking…") : qsTr("Message…")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.medium
                    }
                }
            }

            StyledRect {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                Layout.alignment: Qt.AlignBottom
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
                    onClicked: root.send()
                }
            }
        }
    }
}
