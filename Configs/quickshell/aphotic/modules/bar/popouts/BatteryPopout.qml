import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.config
import qs.components
import qs.services
import qs.utils

ColumnLayout {
    id: root

    spacing: Tokens.spacing.medium

    readonly property bool charging: [UPowerDeviceState.Charging, UPowerDeviceState.PendingCharge].includes(UPower.displayDevice.state)

    function formatTime(seconds: real): string {
        if (!seconds || seconds <= 0)
            return "";
        const h = Math.floor(seconds / 3600);
        const m = Math.round((seconds % 3600) / 60);
        return h > 0 ? qsTr("%1h %2m").arg(h).arg(m) : qsTr("%1m").arg(m);
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small
        visible: UPower.displayDevice.isLaptopBattery

        MaterialIcon {
            text: Icons.getBatteryIcon(UPower.displayDevice.percentage, root.charging)
            color: !UPower.onBattery || UPower.displayDevice.percentage > 0.2 ? Colours.palette.m3onSurface : Colours.palette.m3error
            fill: 1
        }

        StyledText {
            text: `${Math.round(UPower.displayDevice.percentage * 100)}%`
            font: Tokens.font.title.medium
        }

        StyledText {
            Layout.fillWidth: true
            text: {
                if (UPower.displayDevice.state === UPowerDeviceState.FullyCharged)
                    return qsTr("Fully charged");
                if (root.charging) {
                    const t = root.formatTime(UPower.displayDevice.timeToFull);
                    return t ? qsTr("Charging — %1 until full").arg(t) : qsTr("Charging");
                }
                const t = root.formatTime(UPower.displayDevice.timeToEmpty);
                return t ? qsTr("%1 remaining").arg(t) : qsTr("On battery");
            }
            color: Colours.palette.m3onSurfaceVariant
            horizontalAlignment: Text.AlignRight
        }
    }

    StyledText {
        visible: !UPower.displayDevice.isLaptopBattery
        text: qsTr("No battery")
        color: Colours.palette.m3onSurfaceVariant
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

            Item {
                id: profileBtn

                required property var modelData

                Layout.preferredWidth: profileCol.implicitWidth + Tokens.padding.medium * 2
                Layout.preferredHeight: profileCol.implicitHeight + Tokens.padding.small * 2

                StateLayer {
                    radius: Tokens.rounding.small
                    color: PowerProfiles.profile === profileBtn.modelData.profile ? Colours.palette.m3primary : "transparent"
                    disabled: profileBtn.modelData.profile === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile
                    onClicked: PowerProfiles.profile = profileBtn.modelData.profile
                }

                ColumnLayout {
                    id: profileCol
                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small / 2

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: profileBtn.modelData.icon
                        color: PowerProfiles.profile === profileBtn.modelData.profile ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: profileBtn.modelData.label
                        color: PowerProfiles.profile === profileBtn.modelData.profile ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.medium
                    }
                }
            }
        }
    }
}
