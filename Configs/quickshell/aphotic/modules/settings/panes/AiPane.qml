pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services
import qs.services.ai

ColumnLayout {
    id: root

    spacing: Tokens.spacing.largeIncreased

    StyledText {
        text: qsTr("AI")
        font: Tokens.font.title.large
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Provider")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsRow {
                icon: "smart_toy"
                label: qsTr("Active")
                description: qsTr("Used when AI Chat opens")

                RowLayout {
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: AiProviders.providers

                        StyledRect {
                            id: providerPill

                            required property var modelData
                            readonly property bool active: providerPill.modelData.id === AiConfig.activeProvider
                            readonly property bool available: AiProviders.isAvailable(providerPill.modelData.id)

                            Layout.preferredHeight: 28
                            Layout.preferredWidth: pillLabel.implicitWidth + Tokens.padding.medium * 2
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

                            // A disabled StateLayer's own MouseArea stops
                            // accepting clicks, letting them fall through
                            // to whatever is behind it -- the dashboard's
                            // click-outside-to-dismiss MouseArea, in this
                            // overlay family. This plain MouseArea stays
                            // enabled regardless of availability so it
                            // always absorbs the click; it only acts when
                            // the provider is actually usable.
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (providerPill.available)
                                        AiConfig.activeProvider = providerPill.modelData.id;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Ollama")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsRow {
                icon: "dns"
                label: qsTr("Host")
                description: AiConfig.ollamaHostConfigured ? AiConfig.ollamaHost : qsTr("Not set -- Ollama provider unavailable")

                StyledRect {
                    Layout.preferredWidth: 200
                    Layout.preferredHeight: 32
                    radius: Tokens.rounding.full
                    color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                    TextInput {
                        id: hostInput

                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurface
                        text: AiConfig.ollamaHost

                        Keys.onReturnPressed: {
                            const value = hostInput.text.trim();
                            if (value.length > 0) {
                                AiConfig.ollamaHost = value;
                                AiProviders.refreshOllamaModels();
                            }
                        }

                        StyledText {
                            visible: hostInput.text.length === 0
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("http://host:11434")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }
                    }
                }
            }

            SettingsRow {
                icon: "memory"
                label: qsTr("Model")
                description: AiConfig.ollamaModel.length > 0 ? AiConfig.ollamaModel : qsTr("None selected")

                StyledRect {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: Tokens.rounding.full
                    color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "refresh"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: AiProviders.refreshOllamaModels()
                    }
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.extraSmall
            visible: AiProviders.ollamaModels.length > 0
            spacing: Tokens.spacing.small

            Repeater {
                model: AiProviders.ollamaModels

                StyledRect {
                    id: modelPill

                    required property string modelData
                    readonly property bool active: modelPill.modelData === AiConfig.ollamaModel

                    implicitHeight: 28
                    implicitWidth: modelLabel.implicitWidth + Tokens.padding.medium * 2
                    radius: Tokens.rounding.full
                    color: modelPill.active ? Colours.palette.m3primary : Colours.layer(Colours.tPalette.m3surfaceContainer, 2)

                    StyledText {
                        id: modelLabel
                        anchors.centerIn: parent
                        text: modelPill.modelData
                        color: modelPill.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        showHoverBackground: !modelPill.active
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: AiConfig.ollamaModel = modelPill.modelData
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: ollamaModelsSection

        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
        visible: AiConfig.activeProvider === "ollama" && AiConfig.ollamaHostConfigured

        function formatVram(bytes: real): string {
            return qsTr("%1 GB").arg((bytes / 1073741824).toFixed(1));
        }

        function runningInfo(name: string): var {
            return AiProviders.ollamaRunningModels.find(m => m.name === name) ?? null;
        }

        Component.onCompleted: AiProviders.refreshRunningModels()

        onVisibleChanged: {
            if (ollamaModelsSection.visible)
                AiProviders.refreshRunningModels();
        }

        Timer {
            interval: 5000
            running: ollamaModelsSection.visible
            repeat: true
            onTriggered: AiProviders.refreshRunningModels()
        }

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Ollama Models")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true
            visible: AiProviders.ollamaModels.length > 0

            Repeater {
                model: AiProviders.ollamaModels

                SettingsRow {
                    id: modelRow

                    required property string modelData
                    readonly property var running: ollamaModelsSection.runningInfo(modelRow.modelData)
                    readonly property bool active: modelRow.modelData === AiConfig.ollamaModel

                    icon: "memory"
                    label: modelRow.modelData
                    description: modelRow.running ? qsTr("Running -- %1 VRAM").arg(ollamaModelsSection.formatVram(modelRow.running.size_vram)) : qsTr("Idle")

                    RowLayout {
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: "check_circle"
                            fill: modelRow.active ? 1 : 0
                            color: modelRow.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.small

                            StateLayer {
                                anchors.fill: parent
                                anchors.margins: -Tokens.padding.small
                                radius: Tokens.rounding.full
                                onClicked: AiConfig.ollamaModel = modelRow.modelData
                            }
                        }

                        MaterialIcon {
                            text: "delete"
                            color: Colours.palette.m3error
                            fontStyle: Tokens.font.icon.small

                            StateLayer {
                                anchors.fill: parent
                                anchors.margins: -Tokens.padding.small
                                radius: Tokens.rounding.full
                                onClicked: AiProviders.deleteModel(modelRow.modelData)
                            }
                        }
                    }
                }
            }
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsRow {
                icon: "download"
                label: qsTr("Pull new model")
                description: qsTr("Downloads a model onto the Ollama host")

                RowLayout {
                    spacing: Tokens.spacing.small

                    StyledRect {
                        Layout.preferredWidth: 160
                        Layout.preferredHeight: 32
                        radius: Tokens.rounding.full
                        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                        TextInput {
                            id: pullInput

                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.medium
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            enabled: !AiProviders.pulling
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurface

                            Keys.onReturnPressed: {
                                if (pullInput.text.trim().length > 0) {
                                    AiProviders.pullModel(pullInput.text);
                                    pullInput.text = "";
                                }
                            }

                            StyledText {
                                visible: pullInput.text.length === 0
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("llama3.2")
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }
                        }
                    }

                    StyledRect {
                        Layout.preferredWidth: pullLabel.implicitWidth + Tokens.padding.large * 2
                        Layout.preferredHeight: 32
                        radius: Tokens.rounding.full
                        opacity: AiProviders.pulling ? 0.5 : 1
                        color: Colours.palette.m3primary

                        StyledText {
                            id: pullLabel
                            anchors.centerIn: parent
                            text: AiProviders.pulling ? qsTr("Pulling…") : qsTr("Pull")
                            color: Colours.contrastOn(Colours.palette.m3primary)
                            font: Tokens.font.label.small
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            showHoverBackground: !AiProviders.pulling
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !AiProviders.pulling
                            onClicked: {
                                if (pullInput.text.trim().length > 0) {
                                    AiProviders.pullModel(pullInput.text);
                                    pullInput.text = "";
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("API Keys")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            ApiKeyRow {
                icon: "key"
                label: qsTr("Claude (Anthropic)")
                hasKey: AiKeys.hasAnthropicKey
                onKeySubmitted: value => AiKeys.anthropicApiKey = value
                onKeyCleared: AiKeys.anthropicApiKey = ""
            }

            ApiKeyRow {
                icon: "key"
                label: qsTr("Gemini")
                hasKey: AiKeys.hasGeminiKey
                onKeySubmitted: value => AiKeys.geminiApiKey = value
                onKeyCleared: AiKeys.geminiApiKey = ""
            }

            ApiKeyRow {
                icon: "key"
                label: qsTr("ChatGPT")
                hasKey: AiKeys.hasOpenaiKey
                onKeySubmitted: value => AiKeys.openaiApiKey = value
                onKeyCleared: AiKeys.openaiApiKey = ""
            }
        }
    }

    component ApiKeyRow: SettingsRow {
        id: keyRow

        required property bool hasKey

        signal keySubmitted(value: string)
        signal keyCleared

        description: keyRow.hasKey ? qsTr("Key configured") : qsTr("No key set")

        RowLayout {
            spacing: Tokens.spacing.small

            StyledRect {
                visible: !keyRow.hasKey
                Layout.preferredWidth: 170
                Layout.preferredHeight: 32
                radius: Tokens.rounding.full
                color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                TextInput {
                    id: keyInput

                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.medium
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    echoMode: TextInput.Password
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface

                    Keys.onReturnPressed: {
                        const value = keyInput.text.trim();
                        if (value.length > 0) {
                            keyRow.keySubmitted(value);
                            keyInput.text = "";
                        }
                    }

                    StyledText {
                        visible: keyInput.text.length === 0
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Paste key, Enter")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }

            StyledRect {
                visible: keyRow.hasKey
                Layout.preferredWidth: clearLabel.implicitWidth + Tokens.padding.large * 2
                Layout.preferredHeight: 32
                radius: Tokens.rounding.full
                color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                StyledText {
                    id: clearLabel
                    anchors.centerIn: parent
                    text: qsTr("Clear")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: keyRow.keyCleared()
                }
            }
        }
    }
}
