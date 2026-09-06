// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

// Four choices, in the order a person should try them: the narrowest fix
// that the evidence actually supports first, the broadest last. Nothing
// here is applied automatically -- the shell is already down, and a
// recovery screen that acts on its own is one more thing that can be
// wrong.
Item {
    id: root

    property int maxHeight: 720

    implicitHeight: Math.min(root.maxHeight, card.implicitHeight)

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 16
        color: Colours.surface
        border.width: 1
        border.color: Colours.outline

        implicitHeight: layout.implicitHeight + 56

        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: 28
            spacing: 16

            Text {
                text: qsTr("Aphotic recovery")
                color: Colours.textColor
                font.pixelSize: 24
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                text: Diagnosis.failures > 0 ? qsTr("The shell failed to start %1 times in a row, so it has stopped trying.").arg(Diagnosis.failures) : qsTr("The shell is not running.")
                color: Colours.mutedTextColor
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            // What the evidence actually is, stated plainly. A recovery
            // screen that names a culprit without showing why is asking
            // to be trusted on nothing.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: evidence.implicitHeight + 24
                visible: Diagnosis.suspectPlugin.length > 0 || Diagnosis.lastChange.length > 0
                radius: 10
                color: Colours.surfaceRaised

                ColumnLayout {
                    id: evidence
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        visible: Diagnosis.suspectPlugin.length > 0
                        text: qsTr("Suspected plugin: %1").arg(Diagnosis.suspectPlugin)
                        color: Colours.warningColor
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: Diagnosis.suspectPlugin.length > 0
                        text: qsTr("Its files are named in the failure output below.")
                        color: Colours.mutedTextColor
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: Diagnosis.lastChange.length > 0
                        text: qsTr("Last change: %1").arg(Diagnosis.lastChange)
                        color: Colours.mutedTextColor
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Text {
                text: qsTr("Last output")
                color: Colours.mutedTextColor
                font.pixelSize: 12
                visible: Diagnosis.logTail.length > 0
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 90
                Layout.maximumHeight: 180
                visible: Diagnosis.logTail.length > 0
                radius: 10
                color: Colours.background
                clip: true

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 12
                    contentWidth: width
                    contentHeight: logText.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    Text {
                        id: logText
                        width: parent.width
                        text: Diagnosis.logTail
                        color: Colours.mutedTextColor
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 8

                ActionButton {
                    Layout.fillWidth: true
                    primary: Diagnosis.suspectPlugin.length > 0
                    enabledAction: Diagnosis.suspectPlugin.length > 0 && !Diagnosis.applying
                    label: Diagnosis.suspectPlugin.length > 0 ? qsTr("Disable %1 and restart").arg(Diagnosis.suspectPlugin) : qsTr("Disable the suspected plugin")
                    detail: Diagnosis.suspectPlugin.length > 0 ? qsTr("Keeps every other plugin. Re-enable it later from Settings > Plugins.") : qsTr("Nothing in the failure output names a plugin.")
                    onActivated: Diagnosis.apply("disable-suspect")
                }

                ActionButton {
                    Layout.fillWidth: true
                    primary: Diagnosis.suspectPlugin.length === 0
                    enabledAction: !Diagnosis.applying
                    label: qsTr("Start in safe mode")
                    detail: qsTr("Every plugin held back, core shell only. Nothing is uninstalled.")
                    onActivated: Diagnosis.apply("safe-mode")
                }

                ActionButton {
                    Layout.fillWidth: true
                    enabledAction: Diagnosis.latestBackup.length > 0 && !Diagnosis.applying
                    label: qsTr("Restore the last backup")
                    detail: Diagnosis.latestBackup.length > 0 ? qsTr("%1. Your current config is snapshotted first.").arg(Diagnosis.latestBackup) : qsTr("No backup has been taken on this machine.")
                    onActivated: Diagnosis.apply("restore-last")
                }

                ActionButton {
                    Layout.fillWidth: true
                    enabledAction: !Diagnosis.applying
                    label: qsTr("Start normally")
                    detail: qsTr("Change nothing and try again.")
                    onActivated: Diagnosis.apply("continue")
                }
            }

            Text {
                Layout.fillWidth: true
                text: Diagnosis.applying ? qsTr("Applying…") : qsTr("Every option here is also available as 'aphotic recovery' in a terminal.")
                color: Colours.mutedTextColor
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
