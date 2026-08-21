import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    spacing: Tokens.spacing.medium

    SettingsToggleRow {
        Layout.fillWidth: true
        Layout.preferredWidth: 300
        icon: "schedule"
        label: qsTr("12-hour clock")
        checked: Settings.twelveHourClock
        onToggled: state => Settings.twelveHourClock = state
    }

    SettingsToggleRow {
        Layout.fillWidth: true
        Layout.preferredWidth: 300
        icon: "calendar_month"
        label: qsTr("Show date in bar clock")
        checked: Settings.showClockDate
        onToggled: state => Settings.showClockDate = state
    }

    SettingsToggleRow {
        Layout.fillWidth: true
        Layout.preferredWidth: 300
        icon: "push_pin"
        label: qsTr("Bar always visible")
        checked: Settings.barPersistent
        onToggled: state => Settings.barPersistent = state
    }

    SettingsToggleRow {
        Layout.fillWidth: true
        Layout.preferredWidth: 300
        icon: "nest_clock_farsight_analog"
        label: qsTr("Desktop clock")
        checked: Settings.desktopClockEnabled
        onToggled: state => Settings.desktopClockEnabled = state
    }

    SettingsToggleRow {
        Layout.fillWidth: true
        Layout.preferredWidth: 300
        icon: "dock_to_right"
        label: qsTr("Dock bar to right edge")
        checked: Settings.barPositionRight
        onToggled: state => Settings.barPositionRight = state
    }

    SettingsToggleRow {
        Layout.fillWidth: true
        Layout.preferredWidth: 300
        icon: "density_small"
        label: qsTr("Compact bar")
        checked: Settings.barCompact
        onToggled: state => Settings.barCompact = state
    }
}
