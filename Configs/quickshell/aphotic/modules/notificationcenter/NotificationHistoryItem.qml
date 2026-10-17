pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.config
import qs.components
import qs.services
import qs.utils

SignalSurface {
    id: root

    required property var modelData


    function relativeTime(ms: real): string {
        const diff = Date.now() - ms;
        const mins = Math.floor(diff / 60000);
        if (mins < 1)
            return qsTr("just now");
        if (mins < 60)
            return qsTr("%1m ago").arg(mins);
        const hours = Math.floor(mins / 60);
        if (hours < 24)
            return qsTr("%1h ago").arg(hours);
        if (hours < 24 * 7)
            return qsTr("%1d ago").arg(Math.floor(hours / 24));
        return Qt.formatDate(new Date(ms), "MMM d");
    }

    tone: Colours.signalStyle.raised
    radius: Tokens.rounding.medium
    implicitHeight: inner.implicitHeight + Tokens.padding.medium * 2

    // Critical urgency rides the signal line: idle for a normal entry,
    // warn for a critical one.
    SignalLine {
        horizontal: false
        edge: "start"
        level: root.modelData.urgency === NotificationUrgency.Critical ? "warn" : "idle"
    }

    RowLayout {
        id: inner

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        Rectangle {
            Layout.preferredWidth: Tokens.spacing.small
            Layout.preferredHeight: Tokens.spacing.small
            Layout.alignment: Qt.AlignVCenter
            visible: !root.modelData.read
            radius: Tokens.rounding.full
            color: Colours.signal
        }

        Rectangle {
            id: iconChip

            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: Tokens.rounding.full
            color: Qt.alpha(Colours.signal, 0.14)

            AppIcon {
                anchors.centerIn: parent
                name: root.modelData.appIcon
                appClass: root.modelData.appName ?? ""
                fallbackGlyph: Icons.getNotifIcon(root.modelData.summary, root.modelData.urgency)
                size: 20
                fontStyle: Tokens.font.icon.medium
                colour: Colours.signal
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: (root.modelData.appName || root.modelData.summary).toUpperCase()
                font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build()
                color: Colours.inkMuted
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: false
                text: `${root.modelData.summary} · ${root.relativeTime(root.modelData.timestamp)}`
                font: Tokens.font.body.small
                color: Colours.inkMuted
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: root.modelData.summary
                    font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                    color: Colours.ink
                    elide: Text.ElideRight
                }

                StyledText {
                    text: root.relativeTime(root.modelData.timestamp)
                    font: Tokens.font.label.small
                    color: Colours.inkMuted
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.modelData.body
                visible: text.length > 0
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                color: Colours.inkMuted
                font: Tokens.font.body.small
            }
        }

        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: markReadIcon.implicitHeight
            implicitHeight: markReadIcon.implicitHeight
            visible: !root.modelData.read

            Interact {
                radius: Tokens.rounding.full
                onClicked: NotificationHistory.markRead(root.modelData.id)
            }

            MaterialIcon {
                id: markReadIcon
                anchors.centerIn: parent
                text: "close"
                color: Colours.inkMuted
                fontStyle: Tokens.font.icon.small
            }
        }

        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: deleteIcon.implicitHeight
            implicitHeight: deleteIcon.implicitHeight
            opacity: 0.5

            Interact {
                radius: Tokens.rounding.full
                onClicked: NotificationHistory.deleteEntry(root.modelData.id)
            }

            MaterialIcon {
                id: deleteIcon
                anchors.centerIn: parent
                text: "delete"
                color: Colours.inkMuted
                fontStyle: Tokens.font.icon.small
            }
        }
    }
}
