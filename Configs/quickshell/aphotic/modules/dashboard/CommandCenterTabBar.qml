pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

RowLayout {
    id: root

    required property string currentTab
    required property var tabs // [{ id, icon, label }]

    readonly property Item activeTab: tabRepeater.count > 0 ? tabRepeater.itemAt(root.tabs.findIndex(t => t.id === root.currentTab)) : null

    signal tabSelected(id: string)

    spacing: Tokens.spacing.small

    Repeater {
        id: tabRepeater

        model: root.tabs

        StyledRect {
            id: tabButton

    property QtObject _sonarTarget: Loader {
        active: Settings.sonarEnabled
        sourceComponent: EchoTarget {
            target: tabButton
            targetId: "core:dashboard/tab-" + tabButton.modelData.id
            label: tabButton.modelData.label
            action: ""
            bindDescription: ""
            plugin: ""
            eligible: true
        }
    }

            required property var modelData
            readonly property bool active: tabButton.modelData.id === root.currentTab

            Layout.preferredHeight: 40
            Layout.preferredWidth: label.implicitWidth + icon.implicitWidth + Tokens.padding.large * 2 + Tokens.spacing.small
            radius: Tokens.rounding.full
            // Signal: no pill fill; the accent underline marks the active tab.
            color: Settings.barSignal ? "transparent" : (tabButton.active ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer)

            Behavior on color {
                CAnim {}
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: Tokens.spacing.small

                MaterialIcon {
                    id: icon
                    text: tabButton.modelData.icon
                    color: Settings.barSignal ? (tabButton.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant) : (tabButton.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant)
                    fontStyle: Tokens.font.icon.small
                    fill: tabButton.active ? 1 : 0
                }

                StyledText {
                    id: label
                    text: tabButton.modelData.label
                    color: Settings.barSignal ? (tabButton.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant) : (tabButton.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant)
                    font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
                }
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
                // Signal: the hover tone lands at full strength; the active
                // tab carries the underline instead of a hover fill.
                stateOpacity: Settings.barSignal ? (containsMouse && !tabButton.active ? 1 : 0) : (containsMouse ? 0.08 : 0)
                color: Settings.barSignal ? Colours.signalStyle.hover : Colours.palette.m3onSurface
                onClicked: root.tabSelected(tabButton.modelData.id)
            }
        }
    }
}
