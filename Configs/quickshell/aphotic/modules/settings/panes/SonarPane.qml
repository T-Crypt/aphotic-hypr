import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property var screenState
    property bool showLabels: false
    property string output: screenState?.modelData?.name ?? ""
    readonly property var outputChoices: [...new Set(Quickshell.screens.map(s => s.name).concat(Object.keys(Settings.shelfOutputs)))].map(n => ({value:n,label:n}))


    spacing: Tokens.spacing.largeIncreased

    StyledText {
        text: qsTr("Sonar & Shelves")
        font: Tokens.font.title.large
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Sonar")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsToggleRow {
                icon: "radar"
                label: qsTr("Enable Sonar")
                checked: Settings.sonarEnabled
                onToggled: state => Settings.sonarEnabled = state
            }

            SettingsToggleRow {
                icon: "visibility"
                label: qsTr("Show disabled-feature ghosts")
                checked: Settings.sonarGhosts
                onToggled: state => Settings.sonarGhosts = state
            }

            SettingsRow {
                icon: "keyboard_command_key"
                label: qsTr("Ping shortcut")
                description: Sonar.conflictReason.length > 0
                    ? Sonar.conflictReason
                    : qsTr("Or run qs -c aphotic ipc call sonar ping")
            }

            SettingsRow {
                icon: "play_arrow"
                label: qsTr("Preview ping")
                activatable: true
                onActivated: Sonar.ping(root.screenState)
            }
        }
    }

    SettingsGroup {
        Layout.fillWidth: true
        SettingsRow {
            icon: "label"
            label: qsTr("Labels from the last ping")
            activatable: true
            onActivated: root.showLabels = !root.showLabels
        }
        Repeater {
            model: root.showLabels ? Sonar.lastTargets : []
            SettingsRow {
                required property var modelData
                label: modelData.label
                description: modelData.output + " · " + modelData.shortcut + (modelData.reason ? " · " + modelData.reason : "")
            }
        }
    }

    SettingsGroup {
        Layout.fillWidth: true
        SettingsPresetRow {
            icon: "monitor"
            label: qsTr("Shelf output")
            presets: root.outputChoices
            value: root.output
            onSelected: value => root.output = value
        }
        SettingsRow {
            icon: "info"
            label: root.output
            description: Shelves.config(root.output).description
        }
    }
    Repeater {
        model: ["left","right"]
        delegate: ColumnLayout {
            id: edgeGroup
            required property string modelData
            readonly property var config: Shelves.config(root.output)[modelData]
            Layout.fillWidth: true
            StyledText { text: edgeGroup.modelData === "left" ? qsTr("Left shelf") : qsTr("Right shelf"); font: Tokens.font.title.medium }
            SettingsGroup {
                Layout.fillWidth: true
                SettingsToggleRow {
                    icon: "dock_to_left"; label: qsTr("Enable dock")
                    checked: edgeGroup.config.enabled
                    onToggled: state => Shelves.update(root.output,edgeGroup.modelData,{enabled:state})
                }
                SettingsToggleRow {
                    icon: "monitor"; label: qsTr("Running apps from all outputs")
                    checked: edgeGroup.config.allOutputs
                    onToggled: state => Shelves.update(root.output,edgeGroup.modelData,{allOutputs:state})
                }
                SettingsToggleRow {
                    icon: "zoom_in"; label: qsTr("Magnify icons")
                    checked: edgeGroup.config.magnify
                    onToggled: state => Shelves.update(root.output,edgeGroup.modelData,{magnify:state})
                }
                SettingsRow {
                    icon: "keyboard"; label: edgeGroup.modelData === "left" ? "Super + [" : "Super + ]"
                    description: edgeGroup.modelData === "left" ? ShelfKeybinds.leftReason : ShelfKeybinds.rightReason
                }
                SettingsRow {
                    icon: "apps"; label: qsTr("Pinned desktop IDs")
                    description: qsTr("Comma-separated desktop IDs; press Enter to save")
                    StyledRect {
                        implicitWidth: 180; implicitHeight: 32; radius: Tokens.rounding.full
                        color: Colours.palette.m3surfaceContainerHigh
                        TextInput {
                            anchors.fill: parent; anchors.margins: Tokens.padding.small
                            clip: true; color: Colours.palette.m3onSurface; font: Tokens.font.label.small
                            text: edgeGroup.config.pinned.join(", ")
                            onAccepted: Shelves.update(root.output,edgeGroup.modelData,{pinned:text.split(",").map(s => s.trim()).filter(Boolean)})
                        }
                    }
                }
                SettingsRow {
                    icon: "play_arrow"; label: qsTr("Toggle shelf"); activatable: edgeGroup.config.enabled
                    onActivated: Shelves.toggle(root.output,edgeGroup.modelData)
                }
            }
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
