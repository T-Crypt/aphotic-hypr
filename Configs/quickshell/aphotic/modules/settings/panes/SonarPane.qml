import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property var screenState
    property bool showLabels: false

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

    Item {
        Layout.fillHeight: true
    }
}
