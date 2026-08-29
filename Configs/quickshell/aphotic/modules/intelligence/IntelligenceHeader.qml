pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.services.ai

ColumnLayout {
    id: root

    required property bool historyOpen

    signal historyToggled
    signal newSessionRequested

    spacing: Tokens.spacing.small

    readonly property var activeSession: IntelligenceSessions.activeSession
    readonly property string effectiveProvider: root.activeSession?.provider ?? (Settings.intelligenceDefaultProvider || AiConfig.activeProvider)
    readonly property string effectiveModel: root.activeSession?.model ?? (Settings.intelligenceDefaultModel || AiConfig.ollamaModel)

    function _selectProvider(providerId: string): void {
        const model = providerId === "ollama" ? root.effectiveModel : "";
        if (root.activeSession)
            IntelligenceSessions.setSessionProvider(root.activeSession.id, providerId, model);
        else
            IntelligenceSessions.createSession(providerId, model);
    }

    function _selectModel(model: string): void {
        if (root.activeSession)
            IntelligenceSessions.setSessionProvider(root.activeSession.id, root.effectiveProvider, model);
        else
            IntelligenceSessions.createSession(root.effectiveProvider, model);
    }

    // The two action buttons get their own pinned row -- previously they
    // trailed the provider-pill row and scrolled out of reach whenever the
    // pills overflowed. Keeping them on a fixed top-right row means they're
    // always in the same spot regardless of how many providers are
    // configured or how long the active Ollama model name is.
    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        Item {
            Layout.fillWidth: true
        }

        StyledRect {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            radius: Tokens.rounding.full
            color: "transparent"

            MaterialIcon {
                anchors.centerIn: parent
                text: "add_comment"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.newSessionRequested()
            }
        }

        StyledRect {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            radius: Tokens.rounding.full
            color: root.historyOpen ? Colours.palette.m3primary : "transparent"

            Behavior on color {
                CAnim {}
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: "history"
                color: root.historyOpen ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
                showHoverBackground: !root.historyOpen
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.historyToggled()
            }
        }
    }

    // Fixed-width provider labels + an unbounded Ollama model name can
    // together exceed the panel's width. This used to scroll horizontally
    // with no visible affordance, so pills like "Codex" silently ended up
    // off-screen with no hint they existed. Wrapping onto additional lines
    // instead keeps every pill visible and reachable with a plain click --
    // the card has vertical room to spare for it.
    Flow {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        Repeater {
            model: AiProviders.providers

            StyledRect {
                id: providerPill

                required property var modelData
                readonly property bool active: providerPill.modelData.id === root.effectiveProvider
                readonly property bool available: AiProviders.isAvailable(providerPill.modelData.id)

                height: 26
                width: pillLabel.implicitWidth + Tokens.padding.medium * 2
                radius: Tokens.rounding.full
                opacity: providerPill.available ? 1 : 0.4
                color: providerPill.active ? Colours.palette.m3primary : Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

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

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (providerPill.available)
                            root._selectProvider(providerPill.modelData.id);
                    }
                }
            }
        }

        StyledRect {
            id: modelPill

            visible: root.effectiveProvider === "ollama"
            height: 26
            width: Math.min(modelLabel.implicitWidth, 120) + Tokens.padding.medium * 2
            radius: Tokens.rounding.full
            color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

            StyledText {
                id: modelLabel
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: AiConfig.ollamaHostConfigured ? (root.effectiveModel || qsTr("Select model")) : qsTr("Set host…")
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
                width: 200
                padding: Tokens.padding.small
                background: StyledRect {
                    radius: Tokens.rounding.medium
                    color: Colours.tPalette.m3surfaceContainer
                }

                contentItem: ColumnLayout {
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        visible: AiProviders.ollamaModels.length === 0
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
                            Layout.preferredHeight: 30
                            radius: Tokens.rounding.small
                            color: modelOption.modelData === root.effectiveModel ? Colours.palette.m3primary : "transparent"

                            StyledText {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: Tokens.padding.small
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: modelOption.modelData
                                color: modelOption.modelData === root.effectiveModel ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurface
                                font: Tokens.font.label.small
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root._selectModel(modelOption.modelData);
                                    modelMenu.close();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
