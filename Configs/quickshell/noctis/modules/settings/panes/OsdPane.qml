import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    readonly property var timeoutPresets: [1000, 2000, 3000, 5000]

    spacing: Tokens.spacing.medium

    StyledText {
        text: qsTr("On-screen display")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
    }

    SettingsToggleRow {
        Layout.fillWidth: true
        icon: "picture_in_picture"
        label: qsTr("Show OSD")
        checked: Settings.osdEnabled
        onToggled: state => Settings.osdEnabled = state
    }

    SettingsToggleRow {
        Layout.fillWidth: true
        icon: "brightness_6"
        label: qsTr("Brightness slider")
        checked: Settings.osdEnableBrightness
        onToggled: state => Settings.osdEnableBrightness = state
    }

    SettingsToggleRow {
        Layout.fillWidth: true
        icon: "mic"
        label: qsTr("Microphone slider")
        checked: Settings.osdEnableMicrophone
        onToggled: state => Settings.osdEnableMicrophone = state
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        StyledText {
            Layout.fillWidth: true
            text: qsTr("OSD hide delay")
            font: Tokens.font.body.medium
        }

        RowLayout {
            spacing: Tokens.spacing.small

            Repeater {
                model: root.timeoutPresets

                StyledRect {
                    id: presetPill

                    required property int modelData
                    readonly property bool active: presetPill.modelData === Settings.osdHideDelay

                    Layout.preferredHeight: 28
                    Layout.preferredWidth: presetLabel.implicitWidth + Tokens.padding.medium * 2
                    radius: Tokens.rounding.full
                    color: presetPill.active ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer

                    StyledText {
                        id: presetLabel
                        anchors.centerIn: parent
                        text: qsTr("%1s").arg(presetPill.modelData / 1000)
                        color: presetPill.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: Settings.osdHideDelay = presetPill.modelData
                    }
                }
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.medium
        text: qsTr("Notifications")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        StyledText {
            Layout.fillWidth: true
            text: qsTr("Notification timeout")
            font: Tokens.font.body.medium
        }

        RowLayout {
            spacing: Tokens.spacing.small

            Repeater {
                model: root.timeoutPresets

                StyledRect {
                    id: notifPresetPill

                    required property int modelData
                    readonly property bool active: notifPresetPill.modelData === Settings.notifExpireTimeout

                    Layout.preferredHeight: 28
                    Layout.preferredWidth: notifPresetLabel.implicitWidth + Tokens.padding.medium * 2
                    radius: Tokens.rounding.full
                    color: notifPresetPill.active ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer

                    StyledText {
                        id: notifPresetLabel
                        anchors.centerIn: parent
                        text: qsTr("%1s").arg(notifPresetPill.modelData / 1000)
                        color: notifPresetPill.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: Settings.notifExpireTimeout = notifPresetPill.modelData
                    }
                }
            }
        }
    }
}
