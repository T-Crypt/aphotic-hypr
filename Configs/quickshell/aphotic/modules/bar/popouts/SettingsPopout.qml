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

    SettingsPresetRow {
        Layout.fillWidth: true
        Layout.preferredWidth: 300
        icon: "push_pin"
        label: qsTr("Bar visibility")
        presets: [
            { value: "always", label: qsTr("Always") },
            { value: "autohide", label: qsTr("Auto-hide") },
            { value: "hidden", label: qsTr("Hidden") }
        ]
        value: Settings.barVisibility
        onSelected: v => Settings.barVisibility = v
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
        visible: !Settings.barVertical
        icon: "dock_to_right"
        label: qsTr("Dock bar to right edge")
        checked: Settings.barPositionRight
        onToggled: state => Settings.barPositionRight = state
    }

    SettingsToggleRow {
        Layout.fillWidth: true
        Layout.preferredWidth: 300
        visible: Settings.barVertical
        icon: "vertical_align_bottom"
        label: qsTr("Dock bar to bottom edge")
        checked: Settings.barPositionBottom
        onToggled: state => Settings.barPositionBottom = state
    }

    SettingsToggleRow {
        Layout.fillWidth: true
        Layout.preferredWidth: 300
        icon: "density_small"
        label: qsTr("Compact bar")
        checked: Settings.barCompact
        onToggled: state => Settings.barCompact = state
    }

    SettingsToggleRow {
        Layout.fillWidth: true
        Layout.preferredWidth: 300
        icon: "swap_horiz"
        label: qsTr("Vertical orientation")
        checked: Settings.barVertical
        onToggled: state => Settings.barVertical = state
    }
}
