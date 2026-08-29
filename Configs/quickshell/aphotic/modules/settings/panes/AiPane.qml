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
                icon: AiProviders.ollamaReachable ? "check_circle" : "power_settings_new"
                label: qsTr("Status")
                description: {
                    if (AiProviders.startingOllama)
                        return qsTr("Starting…");
                    if (AiProviders.ollamaReachable)
                        return qsTr("Running at %1").arg(AiConfig.ollamaHost);
                    return qsTr("Not reachable at %1").arg(AiConfig.ollamaHost);
                }

                StyledRect {
                    Layout.preferredHeight: 32
                    Layout.preferredWidth: startLabel.implicitWidth + Tokens.padding.large * 2
                    radius: Tokens.rounding.full
                    visible: !AiProviders.ollamaReachable
                    opacity: AiProviders.startingOllama ? 0.5 : 1
                    color: Colours.palette.m3primary

                    StyledText {
                        id: startLabel
                        anchors.centerIn: parent
                        text: AiProviders.startingOllama ? qsTr("Starting…") : qsTr("Start Ollama")
                        color: Colours.contrastOn(Colours.palette.m3primary)
                        font: Tokens.font.label.small
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        disabled: AiProviders.startingOllama
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !AiProviders.startingOllama
                        onClicked: AiProviders.startOllama()
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

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Hardware Advisor")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        StyledText {
            visible: LlmFit.checked && !LlmFit.available
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: qsTr("⚠ llmfit not found. Add it via the 'ai' profile layer, or run: curl -fsSL https://llmfit.axjns.dev/install.sh | sh")
            color: Colours.palette.m3error
            font: Tokens.font.label.small
        }

        SettingsGroup {
            Layout.fillWidth: true
            visible: LlmFit.available

            SettingsRow {
                icon: "insights"
                label: qsTr("Recommended model for this system")
                description: LlmFit.scanning ? qsTr("Scanning CPU/GPU…") : qsTr("Runs llmfit against your detected hardware")

                StyledRect {
                    Layout.preferredWidth: scanLabel.implicitWidth + Tokens.padding.large * 2
                    Layout.preferredHeight: 32
                    radius: Tokens.rounding.full
                    opacity: LlmFit.scanning ? 0.5 : 1
                    color: Colours.palette.m3primary

                    StyledText {
                        id: scanLabel
                        anchors.centerIn: parent
                        text: LlmFit.scanning ? qsTr("Scanning…") : qsTr("Scan")
                        color: Colours.contrastOn(Colours.palette.m3primary)
                        font: Tokens.font.label.small
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        showHoverBackground: !LlmFit.scanning
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !LlmFit.scanning
                        onClicked: LlmFit.scan()
                    }
                }
            }
        }

        StyledText {
            visible: LlmFit.available && LlmFit.errorText.length > 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: `⚠ ${LlmFit.errorText}`
            color: Colours.palette.m3error
            font: Tokens.font.label.small
        }

        StyledText {
            visible: LlmFit.available && LlmFit.systemInfo !== null
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: LlmFit.systemInfo ? qsTr("%1 · %2 cores · %3 GB RAM · %4").arg(LlmFit.systemInfo.cpu_name).arg(LlmFit.systemInfo.cpu_cores).arg(LlmFit.systemInfo.total_ram_gb).arg(LlmFit.systemInfo.has_gpu ? `${LlmFit.systemInfo.gpu_name} (${LlmFit.systemInfo.gpu_vram_gb} GB)` : qsTr("no GPU detected")) : ""
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }

        SettingsGroup {
            Layout.fillWidth: true
            visible: LlmFit.available && LlmFit.recommendations.length > 0

            Repeater {
                model: LlmFit.recommendations

                SettingsRow {
                    id: recRow

                    required property var modelData
                    readonly property string tag: LlmFit.guessOllamaTag(recRow.modelData)

                    icon: "smart_toy"
                    label: `${recRow.modelData.name} (${recRow.modelData.best_quant})`
                    description: qsTr("%1 fit · ~%2 tok/s · %3 params · score %4/100").arg(recRow.modelData.fit_level).arg(Math.round(recRow.modelData.estimated_tps)).arg(recRow.modelData.parameter_count).arg(Math.round(recRow.modelData.score))

                    StyledRect {
                        Layout.preferredWidth: pullLabel.implicitWidth + Tokens.padding.large * 2
                        Layout.preferredHeight: 32
                        radius: Tokens.rounding.full
                        visible: recRow.tag.length > 0
                        opacity: AiProviders.pulling ? 0.5 : 1
                        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                        StyledText {
                            id: pullLabel
                            anchors.centerIn: parent
                            text: qsTr("Pull \"%1\"").arg(recRow.tag)
                            color: Colours.palette.m3onSurfaceVariant
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
                            onClicked: AiProviders.pullModel(recRow.tag)
                        }
                    }
                }
            }
        }

        StyledText {
            visible: LlmFit.available && LlmFit.recommendations.length > 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: qsTr("Pull tags are a best-effort guess from the model name, not a lookup -- verify against Ollama Models above if a pull doesn't find a match.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Model Storage")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsRow {
                icon: "folder"
                label: qsTr("Ollama models")
                description: ModelStorage.ollamaDirExists ? qsTr("%1 -- %2 used").arg(ModelStorage.ollamaDir).arg(ModelStorage.ollamaDirSize) : qsTr("%1 -- not created yet").arg(ModelStorage.ollamaDir)

                RowLayout {
                    spacing: Tokens.spacing.small

                    StyledRect {
                        visible: !ModelStorage.ollamaDirExists
                        Layout.preferredWidth: createOllamaLabel.implicitWidth + Tokens.padding.large * 2
                        Layout.preferredHeight: 32
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        StyledText {
                            id: createOllamaLabel
                            anchors.centerIn: parent
                            text: qsTr("Create")
                            color: Colours.contrastOn(Colours.palette.m3primary)
                            font: Tokens.font.label.small
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: ModelStorage.createOllamaDir()
                        }
                    }

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
                            onClicked: ModelStorage.refreshOllama()
                        }
                    }
                }
            }

            SettingsRow {
                icon: "folder_open"
                label: qsTr("GGUF directory")
                description: ModelStorage.ggufDirExists ? qsTr("%1 -- %2 used").arg(ModelStorage.ggufDir).arg(ModelStorage.ggufDirSize) : qsTr("%1 -- not created yet").arg(ModelStorage.ggufDir)

                RowLayout {
                    spacing: Tokens.spacing.small

                    StyledRect {
                        Layout.preferredWidth: 200
                        Layout.preferredHeight: 32
                        radius: Tokens.rounding.full
                        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                        TextInput {
                            id: ggufDirInput

                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.medium
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurface
                            text: Settings.ggufModelsDir

                            Component.onCompleted: ggufDirInput.cursorPosition = 0

                            Keys.onReturnPressed: {
                                const value = ggufDirInput.text.trim();
                                if (value.length > 0)
                                    Settings.ggufModelsDir = value;
                            }
                        }
                    }

                    StyledRect {
                        visible: !ModelStorage.ggufDirExists
                        Layout.preferredWidth: createGgufLabel.implicitWidth + Tokens.padding.large * 2
                        Layout.preferredHeight: 32
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        StyledText {
                            id: createGgufLabel
                            anchors.centerIn: parent
                            text: qsTr("Create")
                            color: Colours.contrastOn(Colours.palette.m3primary)
                            font: Tokens.font.label.small
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: ModelStorage.createGgufDir()
                        }
                    }

                    StyledRect {
                        visible: ModelStorage.ggufDirExists
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
                            onClicked: ModelStorage.refreshGguf()
                        }
                    }
                }
            }
        }

        StyledText {
            visible: ModelStorage.ggufDirExists && ModelStorage.ggufFiles.length === 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: qsTr("No .gguf files in this directory yet.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }

        SettingsGroup {
            Layout.fillWidth: true
            visible: ModelStorage.ggufDirExists && ModelStorage.ggufFiles.length > 0

            Repeater {
                model: ModelStorage.ggufFiles

                SettingsRow {
                    id: ggufRow

                    required property var modelData

                    icon: "description"
                    label: ggufRow.modelData.name
                    description: ggufRow.modelData.sizeText

                    MaterialIcon {
                        text: "delete"
                        color: Colours.palette.m3error
                        fontStyle: Tokens.font.icon.small

                        StateLayer {
                            anchors.fill: parent
                            anchors.margins: -Tokens.padding.small
                            radius: Tokens.rounding.full
                            onClicked: ModelStorage.deleteGgufFile(ggufRow.modelData.name)
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
            text: qsTr("Intelligence")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsToggleRow {
                label: qsTr("Quick-chat popout")
                description: qsTr("SUPER+Shift+A — a fast overlay separate from the AI Chat tab above")
                checked: Settings.intelligenceEnabled
                onToggled: state => Settings.intelligenceEnabled = state
            }

            SettingsRow {
                icon: "smart_toy"
                label: qsTr("Default provider")
                description: qsTr("Used for new Intelligence sessions — blank follows Active above")

                RowLayout {
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: [{ id: "", label: qsTr("Same as Active") }, ...AiProviders.providers]

                        StyledRect {
                            id: defaultProviderPill

                            required property var modelData
                            readonly property bool active: defaultProviderPill.modelData.id === Settings.intelligenceDefaultProvider

                            Layout.preferredHeight: 28
                            Layout.preferredWidth: defaultProviderLabel.implicitWidth + Tokens.padding.medium * 2
                            radius: Tokens.rounding.full
                            color: defaultProviderPill.active ? Colours.palette.m3primary : Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                            StyledText {
                                id: defaultProviderLabel
                                anchors.centerIn: parent
                                text: defaultProviderPill.modelData.label
                                color: defaultProviderPill.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.small
                            }

                            StateLayer {
                                anchors.fill: parent
                                radius: parent.radius
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: Settings.intelligenceDefaultProvider = defaultProviderPill.modelData.id
                            }
                        }
                    }
                }
            }

            SettingsRow {
                icon: "memory"
                label: qsTr("Default model")
                description: qsTr("Ollama-only — blank follows the Active model above")

                StyledRect {
                    Layout.preferredWidth: 160
                    Layout.preferredHeight: 32
                    radius: Tokens.rounding.full
                    color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                    TextInput {
                        id: defaultModelInput

                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurface
                        text: Settings.intelligenceDefaultModel

                        Keys.onReturnPressed: Settings.intelligenceDefaultModel = defaultModelInput.text.trim()

                        StyledText {
                            visible: defaultModelInput.text.length === 0
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Same as Active")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }
                    }
                }
            }

            SettingsRow {
                icon: "auto_delete"
                label: qsTr("Session limits")
                description: qsTr("Older or excess sessions are pruned automatically — 0 disables a limit")

                RowLayout {
                    spacing: Tokens.spacing.small

                    StyledRect {
                        Layout.preferredWidth: 60
                        Layout.preferredHeight: 32
                        radius: Tokens.rounding.full
                        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                        TextInput {
                            id: maxSessionsInput

                            anchors.fill: parent
                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter
                            validator: IntValidator {
                                bottom: 0
                                top: 999
                            }
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurface
                            text: Settings.intelligenceMaxSessions.toString()

                            Keys.onReturnPressed: {
                                const value = parseInt(maxSessionsInput.text, 10);
                                if (!isNaN(value))
                                    Settings.intelligenceMaxSessions = value;
                            }
                        }
                    }

                    StyledText {
                        text: qsTr("max sessions")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }

                    StyledRect {
                        Layout.preferredWidth: 60
                        Layout.preferredHeight: 32
                        radius: Tokens.rounding.full
                        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                        TextInput {
                            id: autoPruneInput

                            anchors.fill: parent
                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter
                            validator: IntValidator {
                                bottom: 0
                                top: 999
                            }
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurface
                            text: Settings.intelligenceAutoPruneDays.toString()

                            Keys.onReturnPressed: {
                                const value = parseInt(autoPruneInput.text, 10);
                                if (!isNaN(value))
                                    Settings.intelligenceAutoPruneDays = value;
                            }
                        }
                    }

                    StyledText {
                        text: qsTr("days old")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall
        visible: AiConfig.assistantEnabled

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Aphotic Assistant")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsRow {
                icon: "smart_toy"
                label: qsTr("Installed model")
                description: AiConfig.assistantModel.length > 0 ? AiConfig.assistantModel : qsTr("Unknown")

                RowLayout {
                    spacing: Tokens.spacing.small

                    StyledRect {
                        Layout.preferredWidth: reinstallLabel.implicitWidth + Tokens.padding.large * 2
                        Layout.preferredHeight: 32
                        radius: Tokens.rounding.full
                        opacity: AiProviders.pulling ? 0.5 : 1
                        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                        StyledText {
                            id: reinstallLabel
                            anchors.centerIn: parent
                            text: AiProviders.pulling ? qsTr("Pulling…") : qsTr("Reinstall")
                            color: Colours.palette.m3onSurfaceVariant
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
                            onClicked: AiProviders.pullModel(AiConfig.assistantModel)
                        }
                    }

                    StyledRect {
                        id: uninstallButton

                        property bool confirming: false

                        Layout.preferredWidth: uninstallLabel.implicitWidth + Tokens.padding.large * 2
                        Layout.preferredHeight: 32
                        radius: Tokens.rounding.full
                        color: uninstallButton.confirming ? Colours.palette.m3error : Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                        Behavior on color {
                            CAnim {}
                        }

                        StyledText {
                            id: uninstallLabel
                            anchors.centerIn: parent
                            text: uninstallButton.confirming ? qsTr("Confirm remove?") : qsTr("Uninstall")
                            color: uninstallButton.confirming ? Colours.contrastOn(Colours.palette.m3error) : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (uninstallButton.confirming) {
                                    AiProviders.deleteModel(AiConfig.assistantModel);
                                    if (AiConfig.activeProvider === "assistant")
                                        AiConfig.activeProvider = "ollama";
                                    AiConfig.assistantEnabled = false;
                                    AiConfig.assistantModel = "";
                                    AiConfig.assistantInstalledAt = "";
                                    uninstallButton.confirming = false;
                                } else {
                                    uninstallButton.confirming = true;
                                    uninstallResetTimer.restart();
                                }
                            }
                        }

                        Timer {
                            id: uninstallResetTimer
                            interval: 4000
                            onTriggered: uninstallButton.confirming = false
                        }
                    }
                }
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
