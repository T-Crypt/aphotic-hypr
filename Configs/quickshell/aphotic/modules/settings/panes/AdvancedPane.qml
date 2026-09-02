pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    spacing: Tokens.spacing.largeIncreased

    StyledText {
        text: qsTr("Advanced")
        font: Tokens.font.title.large
    }

    StyledText {
        text: qsTr("Keyboard")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Deep XKB options for your keyboard. Leave empty to use the system default — they are written to ~/.config/hypr/custom.lua alongside the Language pane's layout.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsRow {
            icon: "model_training"
            label: qsTr("Keyboard model")
            description: qsTr("e.g. pc105 — empty uses the system default")

            KbCodeField {
                text: Settings.kbModel
                Layout.preferredWidth: 200
                onSubmitted: value => Settings.kbModel = value
            }
        }

        SettingsRow {
            icon: "rule"
            label: qsTr("XKB rules")
            description: qsTr("Empty uses the system default")

            KbCodeField {
                text: Settings.kbRules
                Layout.preferredWidth: 200
                onSubmitted: value => Settings.kbRules = value
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("These, along with the Language pane's keyboard layout, are written to ~/.config/hypr/custom.lua — the override file install.sh never overwrites — and applied immediately via the compositor's live config API.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }
}
