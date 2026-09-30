import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    required property var screenState

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

    Item {
        Layout.fillHeight: true
    }
}
