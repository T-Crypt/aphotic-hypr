import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    spacing: Tokens.spacing.largeIncreased

    StyledText {
        text: qsTr("Bar")
        font: Tokens.font.title.large
    }

    StyledText {
        text: qsTr("Visibility")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        Repeater {
            model: [
                { value: "always", icon: "push_pin", label: qsTr("Always visible") },
                { value: "autohide", icon: "visibility", label: qsTr("Auto-hide") },
                { value: "hidden", icon: "visibility_off", label: qsTr("Hidden") }
            ]

            StyledRect {
                id: visBtn

                required property var modelData
                readonly property bool active: Settings.barVisibility === visBtn.modelData.value

                Layout.fillWidth: true
                implicitHeight: visCol.implicitHeight + Tokens.padding.medium * 2
                radius: Tokens.rounding.medium
                color: visBtn.active ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer

                ColumnLayout {
                    id: visCol
                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small / 2

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: visBtn.modelData.icon
                        color: visBtn.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: visBtn.modelData.label
                        color: visBtn.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.medium
                    }
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    showHoverBackground: !visBtn.active
                    onClicked: Settings.barVisibility = visBtn.modelData.value
                }
            }
        }
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsToggleRow {
            visible: !Settings.barVertical
            icon: "dock_to_right"
            label: qsTr("Dock bar to right edge")
            checked: Settings.barPositionRight
            onToggled: state => Settings.barPositionRight = state
        }

        SettingsToggleRow {
            visible: Settings.barVertical
            icon: "vertical_align_bottom"
            label: qsTr("Dock bar to bottom edge")
            checked: Settings.barPositionBottom
            onToggled: state => Settings.barPositionBottom = state
        }

        SettingsToggleRow {
            icon: "density_small"
            label: qsTr("Compact bar")
            checked: Settings.barCompact
            onToggled: state => Settings.barCompact = state
        }

        // Roadmap Feature #5 -- a real second orientation (top/bottom
        // dock, full width, entries flowing left-to-right) alongside the
        // left/right-docked, top-to-bottom mode above.
        SettingsToggleRow {
            icon: "swap_horiz"
            label: qsTr("Vertical orientation")
            checked: Settings.barVertical
            onToggled: state => Settings.barVertical = state
        }
    }
}
