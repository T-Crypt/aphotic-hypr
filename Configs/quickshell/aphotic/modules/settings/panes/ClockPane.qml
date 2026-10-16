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

    StyledText {
        Layout.bottomMargin: -Tokens.spacing.small
        Layout.leftMargin: Tokens.padding.small
        text: qsTr("Clock")
        color: Colours.inkMuted
        font: Tokens.font.label.builders.medium.weight(Font.DemiBold).build()
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsToggleRow {
            searchId: "twelveHourClock"
            icon: "schedule"
            label: qsTr("12-hour clock")
            checked: Settings.twelveHourClock
            onToggled: state => Settings.twelveHourClock = state
        }

        SettingsToggleRow {
            searchId: "barClockDate"
            icon: "calendar_month"
            label: qsTr("Show date in bar clock")
            checked: Settings.showClockDate
            onToggled: state => Settings.showClockDate = state
        }

        SettingsToggleRow {
            searchId: "desktopClock"
            icon: "nest_clock_farsight_analog"
            label: qsTr("Desktop clock")
            checked: Settings.desktopClockEnabled
            onToggled: state => Settings.desktopClockEnabled = state
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        Layout.bottomMargin: -Tokens.spacing.small
        Layout.leftMargin: Tokens.padding.small
        text: qsTr("Weather")
        color: Colours.inkMuted
        font: Tokens.font.label.builders.medium.weight(Font.DemiBold).build()
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsRow {
            searchId: "weatherLocation"
            icon: "location_on"
            label: qsTr("Location")
            description: Weather.resolvedLocationName.length > 0 ? Weather.resolvedLocationName : qsTr("Auto-detected from IP address")

            StyledRect {
                Layout.preferredWidth: 200
                Layout.preferredHeight: 32
                radius: Tokens.rounding.full
                color: Colours.layer(Colours.surface, 3)

                TextInput {
                    id: locationInput

                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.medium
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    font: Tokens.font.label.small
                    color: Colours.ink
                    text: Settings.weatherLocation

                    Keys.onReturnPressed: Settings.weatherLocation = locationInput.text.trim()

                    StyledText {
                        visible: locationInput.text.length === 0
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("City name, or blank for auto")
                        color: Colours.inkMuted
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        SettingsPresetRow {
            searchId: "weatherUnits"
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
