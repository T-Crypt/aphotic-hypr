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

StyledRect {
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

    color: Settings.barSignal ? Colours.signalStyle.raised : Colours.tPalette.m3surfaceContainer
    border.width: Settings.barSignal ? 1 : 0
    border.color: Colours.signalStyle.hairline
    radius: Settings.barSignal ? Tokens.rounding.medium : Tokens.rounding.large
    implicitHeight: inner.implicitHeight + Tokens.padding.medium * 2

    Rectangle {
        visible: Settings.barSignal
        x: root.radius
        width: root.width - root.radius * 2
        height: 1
        color: Colours.signalStyle.edgeLight
    }

    // Signal: critical reads as an edge line, not a red-filled card.
    Rectangle {
        visible: Settings.barSignal && root.modelData.urgency === NotificationUrgency.Critical
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: root.radius
        anchors.bottomMargin: root.radius
        width: 2
        color: Colours.palette.m3error
    }

    RowLayout {
        id: inner

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        Rectangle {
            Layout.preferredWidth: 8
            Layout.preferredHeight: 8
            Layout.alignment: Qt.AlignVCenter
            visible: !root.modelData.read
            radius: 4
            color: Colours.palette.m3primary
        }

        Rectangle {
            id: iconChip

            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Settings.barSignal ? 32 : Tokens.sizes.notifs.image
            Layout.preferredHeight: Settings.barSignal ? 32 : Tokens.sizes.notifs.image
            radius: Settings.barSignal ? Tokens.rounding.full : 0
            color: Settings.barSignal ? Qt.alpha(Colours.palette.m3primary, 0.14) : "transparent"

            AppIcon {
                anchors.centerIn: parent
                name: root.modelData.appIcon
                appClass: root.modelData.appName ?? ""
                fallbackGlyph: Icons.getNotifIcon(root.modelData.summary, root.modelData.urgency)
                size: Settings.barSignal ? 20 : Tokens.sizes.notifs.image
                fontStyle: Tokens.font.icon.medium
                colour: Colours.palette.m3primary
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: Settings.barSignal ? (root.modelData.appName || root.modelData.summary).toUpperCase() : (root.modelData.appName || root.modelData.summary)
                font: Settings.barSignal ? Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build() : Tokens.font.body.medium
                color: Settings.barSignal ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: !Settings.barSignal
                text: `${root.modelData.summary} · ${root.relativeTime(root.modelData.timestamp)}`
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
            }

            // Signal: summary leads the line DemiBold, time sits muted at the right.
            RowLayout {
                Layout.fillWidth: true
                visible: Settings.barSignal
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: root.modelData.summary
                    font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                    color: Colours.palette.m3onSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    text: root.relativeTime(root.modelData.timestamp)
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.modelData.body
                visible: text.length > 0
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }
        }

        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: markReadIcon.implicitHeight
            implicitHeight: markReadIcon.implicitHeight
            visible: !root.modelData.read

            StateLayer {
                radius: Tokens.rounding.full
                onClicked: NotificationHistory.markRead(root.modelData.id)
            }

            MaterialIcon {
                id: markReadIcon
                anchors.centerIn: parent
                text: "close"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }
        }

        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: deleteIcon.implicitHeight
            implicitHeight: deleteIcon.implicitHeight
            opacity: 0.5

            StateLayer {
                radius: Tokens.rounding.full
                onClicked: NotificationHistory.deleteEntry(root.modelData.id)
            }

            MaterialIcon {
                id: deleteIcon
                anchors.centerIn: parent
                text: "delete"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }
        }
    }
}
