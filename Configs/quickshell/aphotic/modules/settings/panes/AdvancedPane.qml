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
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("The rest of the xkb keyboard description, for hardware the defaults get wrong. Leave these empty unless you know you need them -- they are written to ~/.config/hypr/keyboard.lua alongside the Language pane's layout.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Keyboard")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsRow {
                icon: "keyboard_alt"
                label: qsTr("Keyboard model")
                description: qsTr("Empty uses the system default")

                KbCodeField {
                    text: Settings.kbModel
                    placeholderText: qsTr("e.g. pc105")
                    onSubmitted: value => Settings.kbModel = value
                }
            }

            SettingsRow {
                icon: "rule"
                label: qsTr("XKB rules")
                description: qsTr("Empty uses the system default")

                KbCodeField {
                    text: Settings.kbRules
                    placeholderText: qsTr("e.g. evdev")
                    onSubmitted: value => Settings.kbRules = value
                }
            }
        }
    }
}
