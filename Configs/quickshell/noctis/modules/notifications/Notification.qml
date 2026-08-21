pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.config
import qs.components
import qs.services
import qs.utils

StyledRect {
    id: root

    required property NotifData modelData
    readonly property bool hasAppIcon: modelData.appIcon.length > 0
    readonly property int bodyTextFormat: /[<*_`#\[\]]/.test(modelData.body) ? Text.MarkdownText : Text.PlainText
    readonly property bool critical: modelData.urgency === NotificationUrgency.Critical

    color: critical ? Colours.palette.m3error : Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.large

    implicitWidth: Tokens.sizes.notifs.width
    implicitHeight: inner.implicitHeight + Tokens.padding.medium * 2

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.modelData.timer.stop()
        onExited: root.modelData.timer.start()

        Column {
            id: inner

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.extraSmall

            Row {
                width: parent.width
                spacing: Tokens.spacing.medium

                Loader {
                    id: icon

                    asynchronous: true
                    active: root.hasAppIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: Tokens.sizes.notifs.image
                    height: Tokens.sizes.notifs.image

                    sourceComponent: IconImage {
                        source: Quickshell.iconPath(root.modelData.appIcon, "image-missing")
                        implicitSize: Tokens.sizes.notifs.image
                    }
                }

                Loader {
                    active: !root.hasAppIcon
                    anchors.verticalCenter: parent.verticalCenter

                    sourceComponent: MaterialIcon {
                        text: Icons.getNotifIcon(root.modelData.summary, root.modelData.urgency)
                        color: root.critical ? Colours.palette.m3onSurface : Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.medium
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - icon.width - parent.spacing - closeBtn.width - Tokens.spacing.medium

                    StyledText {
                        text: root.modelData.appName || root.modelData.summary
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    StyledText {
                        text: root.modelData.appName ? root.modelData.summary : ""
                        visible: text.length > 0
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }

                Item {
                    id: closeBtn

                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: closeIcon.implicitHeight
                    implicitHeight: closeIcon.implicitHeight

                    StateLayer {
                        radius: Tokens.rounding.full
                        onClicked: root.modelData.close()
                    }

                    MaterialIcon {
                        id: closeIcon
                        anchors.centerIn: parent
                        text: "close"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }
                }
            }

            StyledText {
                text: root.modelData.body
                textFormat: root.bodyTextFormat
                visible: text.length > 0
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                width: parent.width
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small

                onLinkActivated: link => Qt.openUrlExternally(link)
            }
        }
    }
}
