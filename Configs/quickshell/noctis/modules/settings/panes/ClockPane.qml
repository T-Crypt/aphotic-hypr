import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    spacing: Tokens.spacing.medium

    SettingsToggleRow {
        Layout.fillWidth: true
        icon: "schedule"
        label: qsTr("12-hour clock")
        checked: Settings.twelveHourClock
        onToggled: state => Settings.twelveHourClock = state
    }

    SettingsToggleRow {
        Layout.fillWidth: true
        icon: "calendar_month"
        label: qsTr("Show date in bar clock")
        checked: Settings.showClockDate
        onToggled: state => Settings.showClockDate = state
    }

    SettingsToggleRow {
        Layout.fillWidth: true
        icon: "nest_clock_farsight_analog"
        label: qsTr("Desktop clock")
        checked: Settings.desktopClockEnabled
        onToggled: state => Settings.desktopClockEnabled = state
    }
}
