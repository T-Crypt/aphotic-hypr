import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    readonly property var timeoutPresets: [
        { value: 1000, label: qsTr("1s") },
        { value: 2000, label: qsTr("2s") },
        { value: 3000, label: qsTr("3s") },
        { value: 5000, label: qsTr("5s") }
    ]

    spacing: Tokens.spacing.largeIncreased

    StyledText {
        text: qsTr("OSD / Notifications")
        font: Tokens.font.title.large
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("On-screen display")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsToggleRow {
                icon: "picture_in_picture"
                label: qsTr("Show OSD")
                checked: Settings.osdEnabled
                onToggled: state => Settings.osdEnabled = state
            }

            SettingsToggleRow {
                icon: "brightness_6"
                label: qsTr("Brightness slider")
                checked: Settings.osdEnableBrightness
                onToggled: state => Settings.osdEnableBrightness = state
            }

            SettingsToggleRow {
                icon: "mic"
                label: qsTr("Microphone slider")
                checked: Settings.osdEnableMicrophone
                onToggled: state => Settings.osdEnableMicrophone = state
            }

            SettingsPresetRow {
                icon: "timer"
                label: qsTr("OSD hide delay")
                presets: root.timeoutPresets
                value: Settings.osdHideDelay
                onSelected: value => Settings.osdHideDelay = value
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.leftMargin: Tokens.padding.small
            text: qsTr("Notifications")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsPresetRow {
                icon: "notifications_active"
                label: qsTr("Notification timeout")
                presets: root.timeoutPresets
                value: Settings.notifExpireTimeout
                onSelected: value => Settings.notifExpireTimeout = value
            }
        }
    }
}
