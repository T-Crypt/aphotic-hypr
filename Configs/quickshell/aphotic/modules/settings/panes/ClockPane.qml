import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    spacing: Tokens.spacing.largeIncreased

    StyledText {
        text: qsTr("Clock / Date")
        font: Tokens.font.title.large
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsToggleRow {
            icon: "schedule"
            label: qsTr("12-hour clock")
            checked: Settings.twelveHourClock
            onToggled: state => Settings.twelveHourClock = state
        }

        SettingsToggleRow {
            icon: "calendar_month"
            label: qsTr("Show date in bar clock")
            checked: Settings.showClockDate
            onToggled: state => Settings.showClockDate = state
        }

        SettingsToggleRow {
            icon: "nest_clock_farsight_analog"
            label: qsTr("Desktop clock")
            checked: Settings.desktopClockEnabled
            onToggled: state => Settings.desktopClockEnabled = state
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Weather")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsRow {
            icon: "location_on"
            label: qsTr("Location")
            description: Weather.resolvedLocationName.length > 0 ? Weather.resolvedLocationName : qsTr("Auto-detected from IP address")

            StyledRect {
                Layout.preferredWidth: 200
                Layout.preferredHeight: 32
                radius: Tokens.rounding.full
                color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                TextInput {
                    id: locationInput

                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.medium
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                    text: Settings.weatherLocation

                    Keys.onReturnPressed: Settings.weatherLocation = locationInput.text.trim()

                    StyledText {
                        visible: locationInput.text.length === 0
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("City name, or blank for auto")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        SettingsPresetRow {
            icon: "thermostat"
            label: qsTr("Units")
            presets: [{
                    value: "celsius",
                    label: qsTr("Celsius")
                }, {
                    value: "fahrenheit",
                    label: qsTr("Fahrenheit")
                }]
            value: Settings.weatherUnits
            onSelected: value => Settings.weatherUnits = value
        }
    }
}
