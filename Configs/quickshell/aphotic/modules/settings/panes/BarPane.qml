import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.modules.settings

ColumnLayout {
    id: root

    spacing: Tokens.spacing.largeIncreased

    StyledText {
        text: qsTr("Bar")
        font: Tokens.font.title.large
    }

    StyledText {
        text: qsTr("Style")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        BarStylePreviewCard {
            Layout.fillWidth: true
            styleName: "full"
            label: qsTr("Full")
        }
        BarStylePreviewCard {
            Layout.fillWidth: true
            styleName: "dock"
            label: qsTr("Dock")
        }
        BarStylePreviewCard {
            Layout.fillWidth: true
            styleName: "taskbar"
            label: qsTr("Taskbar")
        }
        BarStylePreviewCard {
            Layout.fillWidth: true
            styleName: "minimal"
            label: qsTr("Minimal")
        }
    }

    // None of the three new styles have a real vertical/side-dock layout
    // (Dock's pill, Taskbar's task list, and Minimal's strip are all
    // built horizontal-first) -- a side placement isn't blocked, but per
    // the spec, a combination that's likely to look broken gets flagged
    // rather than silently allowed with no warning.
    StyledRect {
        Layout.fillWidth: true
        visible: Settings.barStyle !== "full" && !Settings.barHorizontal
        implicitHeight: warningRow.implicitHeight + Tokens.padding.medium * 2
        radius: Tokens.rounding.medium
        color: Colours.palette.m3error

        RowLayout {
            id: warningRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "warning"
                color: Colours.palette.m3onError
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: qsTr("This style is designed for top/bottom placement -- side placement may look broken.")
                color: Colours.palette.m3onError
                font: Tokens.font.body.small
            }
        }
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
            visible: !Settings.barHorizontal
            icon: "dock_to_right"
            label: qsTr("Dock bar to right edge")
            checked: Settings.barPositionRight
            onToggled: state => Settings.barPositionRight = state
        }

        SettingsToggleRow {
            visible: Settings.barHorizontal
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
            label: qsTr("Horizontal orientation")
            checked: Settings.barHorizontal
            onToggled: state => Settings.barHorizontal = state
        }

        SettingsPresetRow {
            visible: Settings.barStyle === "full"
            icon: "style"
            label: qsTr("Full style background")
            presets: [
                { value: "pill", label: qsTr("Pill") },
                { value: "square", label: qsTr("Square") }
            ]
            value: Settings.barSkin
            onSelected: value => Settings.barSkin = value
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: Settings.barStyle === "dock"
        spacing: Tokens.spacing.small

        StyledText {
            text: qsTr("Dock")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsToggleRow {
                icon: "visibility_off"
                label: qsTr("Auto-hide when a window is focused")
                checked: Settings.dockAutoHide
                onToggled: state => Settings.dockAutoHide = state
            }

            SettingsToggleRow {
                icon: "zoom_in"
                label: qsTr("Icon magnification on hover")
                checked: Settings.dockMagnification
                onToggled: state => Settings.dockMagnification = state
            }
        }

        StyledText {
            text: qsTr("Pinned apps")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Repeater {
                model: Settings.dockPinnedApps

                StyledRect {
                    id: pinChip

                    required property string modelData
                    readonly property var entry: DesktopEntries.applications.values.find(a => a.id === pinChip.modelData)

                    implicitWidth: chipRow.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: chipRow.implicitHeight + Tokens.padding.small * 2
                    radius: Tokens.rounding.full
                    color: Colours.tPalette.m3surfaceContainerHigh

                    RowLayout {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: Tokens.spacing.small

                        StyledText {
                            text: pinChip.entry?.name ?? pinChip.modelData
                            font: Tokens.font.body.small
                        }

                        MaterialIcon {
                            text: "close"
                            fontStyle: Tokens.font.icon.small

                            StateLayer {
                                anchors.fill: parent
                                anchors.margins: -Tokens.padding.extraSmall
                                radius: Tokens.rounding.full
                                onClicked: Settings.dockPinnedApps = Settings.dockPinnedApps.filter(id => id !== pinChip.modelData)
                            }
                        }
                    }
                }
            }

            StyledRect {
                id: addChip

                property bool expanded: false

                implicitWidth: addLabel.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: addLabel.implicitHeight + Tokens.padding.small * 2
                radius: Tokens.rounding.full
                color: "transparent"
                border.width: 1
                border.color: Colours.palette.m3outlineVariant

                StyledText {
                    id: addLabel
                    anchors.centerIn: parent
                    text: qsTr("+ Add app")
                    font: Tokens.font.body.small
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    onClicked: addChip.expanded = !addChip.expanded
                }
            }
        }

        Loader {
            Layout.fillWidth: true
            Layout.preferredHeight: 200
            active: addChip.expanded

            sourceComponent: StyledRect {
                radius: Tokens.rounding.medium
                color: Colours.tPalette.m3surfaceContainer

                ListView {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    clip: true
                    model: DesktopEntries.applications.values.filter(a => !a.noDisplay && !Settings.dockPinnedApps.includes(a.id))

                    delegate: StyledRect {
                        required property var modelData

                        width: ListView.view.width
                        implicitHeight: rowLabel.implicitHeight + Tokens.padding.small * 2
                        color: "transparent"

                        StyledText {
                            id: rowLabel
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.padding.small
                            text: parent.modelData.name
                            elide: Text.ElideRight
                        }

                        StateLayer {
                            anchors.fill: parent
                            onClicked: {
                                Settings.dockPinnedApps = [...Settings.dockPinnedApps, parent.modelData.id];
                                addChip.expanded = false;
                            }
                        }
                    }
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: Settings.barStyle === "taskbar"
        spacing: Tokens.spacing.small

        StyledText {
            text: qsTr("Taskbar")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsToggleRow {
                icon: "layers"
                label: qsTr("Group windows by app")
                checked: Settings.taskbarGrouping
                onToggled: state => Settings.taskbarGrouping = state
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: Settings.barStyle === "minimal"
        spacing: Tokens.spacing.small

        StyledText {
            text: qsTr("Minimal")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.medium
        }

        SettingsGroup {
            Layout.fillWidth: true

            SettingsToggleRow {
                icon: "do_not_disturb_on"
                label: qsTr("Show Do Not Disturb indicator")
                checked: Settings.minimalShowDnd
                onToggled: state => Settings.minimalShowDnd = state
            }
        }
    }
}
