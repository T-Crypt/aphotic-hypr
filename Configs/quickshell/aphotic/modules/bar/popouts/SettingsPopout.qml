import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root

    // The flyout window this renders inside has a fixed ~400px vertical
    // growth budget (see BarWindow.qml's implicitHeight comment) -- this
    // popout's row count can exceed that (esp. docked along the screen's
    // short edge, where the flyout has even less room below it), so
    // unlike every other (shorter) popout here, this one caps its own
    // height and scrolls instead of asking the flyout to just grow
    // arbitrarily tall and get clipped by the window's hard bound with no
    // way to reach the rows past it.
    readonly property int maxHeight: 340

    implicitWidth: column.implicitWidth
    implicitHeight: Math.min(column.implicitHeight, maxHeight)

    Flickable {
        id: flick

        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: column

            width: flick.width
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
    }

    StyledRect {
        visible: flick.contentHeight > flick.height
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: 4
        radius: Tokens.rounding.full
        color: Colours.palette.m3onSurfaceVariant
        opacity: 0.35

        StyledRect {
            y: flick.visibleArea.yPosition * parent.height
            width: parent.width
            height: flick.visibleArea.heightRatio * parent.height
            radius: parent.radius
            color: Colours.palette.m3onSurface
        }
    }
}
