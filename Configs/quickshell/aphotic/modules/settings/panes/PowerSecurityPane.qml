pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    spacing: Tokens.spacing.largeIncreased

    function formatMinutes(seconds: int): string {
        const m = Math.round(seconds / 60);
        return qsTr("%1 min").arg(m);
    }

    StyledText {
        text: qsTr("Power & Security")
        font: Tokens.font.title.large
    }

    StyledText {
        text: qsTr("Power profile")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        Repeater {
            model: [
                {
                    profile: PowerProfile.PowerSaver,
                    icon: "energy_savings_leaf",
                    label: qsTr("Saver")
                },
                {
                    profile: PowerProfile.Balanced,
                    icon: "balance",
                    label: qsTr("Balanced")
                },
                {
                    profile: PowerProfile.Performance,
                    icon: "rocket_launch",
                    label: qsTr("Performance")
                }
            ]

            StyledRect {
                id: profileBtn

                required property var modelData
                readonly property bool active: PowerProfiles.profile === profileBtn.modelData.profile

                Layout.fillWidth: true
                implicitHeight: profileCol.implicitHeight + Tokens.padding.medium * 2
                radius: Tokens.rounding.medium
                color: profileBtn.active ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer

                ColumnLayout {
                    id: profileCol
                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small / 2

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: profileBtn.modelData.icon
                        color: profileBtn.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: profileBtn.modelData.label
                        color: profileBtn.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.medium
                    }
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    showHoverBackground: !profileBtn.active
                    disabled: profileBtn.modelData.profile === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile
                    onClicked: PowerProfiles.profile = profileBtn.modelData.profile
                }
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Idle & lock")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsToggleRow {
            icon: "lock_clock"
            label: qsTr("Lock when idle")
            description: root.formatMinutes(Settings.idleLockTimeout)
            checked: Settings.idleLockEnabled
            onToggled: state => Settings.idleLockEnabled = state
        }

        SettingsRow {
            icon: "timer"
            label: qsTr("Lock after")
            description: root.formatMinutes(Settings.idleLockTimeout)
            enabled: Settings.idleLockEnabled
            opacity: enabled ? 1 : 0.4

            RowLayout {
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "remove"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small

                    StateLayer {
                        anchors.fill: parent
                        anchors.margins: -Tokens.padding.small
                        radius: Tokens.rounding.full
                        onClicked: Settings.idleLockTimeout = Math.max(60, Settings.idleLockTimeout - 60)
                    }
                }

                MaterialIcon {
                    text: "add"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small

                    StateLayer {
                        anchors.fill: parent
                        anchors.margins: -Tokens.padding.small
                        radius: Tokens.rounding.full
                        onClicked: Settings.idleLockTimeout = Math.min(3600, Settings.idleLockTimeout + 60)
                    }
                }
            }
        }

        SettingsToggleRow {
            icon: "bedtime"
            label: qsTr("Suspend when idle")
            description: root.formatMinutes(Settings.idleSuspendTimeout)
            checked: Settings.idleSuspendEnabled
            onToggled: state => Settings.idleSuspendEnabled = state
        }

        SettingsRow {
            icon: "timer"
            label: qsTr("Suspend after")
            description: root.formatMinutes(Settings.idleSuspendTimeout)
            enabled: Settings.idleSuspendEnabled
            opacity: enabled ? 1 : 0.4

            RowLayout {
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "remove"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small

                    StateLayer {
                        anchors.fill: parent
                        anchors.margins: -Tokens.padding.small
                        radius: Tokens.rounding.full
                        onClicked: Settings.idleSuspendTimeout = Math.max(300, Settings.idleSuspendTimeout - 300)
                    }
                }

                MaterialIcon {
                    text: "add"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small

                    StateLayer {
                        anchors.fill: parent
                        anchors.margins: -Tokens.padding.small
                        radius: Tokens.rounding.full
                        onClicked: Settings.idleSuspendTimeout = Math.min(7200, Settings.idleSuspendTimeout + 300)
                    }
                }
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Lockout")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Failed unlock attempts are handled by your system's PAM/faillock policy, the same as any other login prompt — Aphotic doesn't layer its own attempt counter on top of it.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }
}
