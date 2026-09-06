pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

StyledRect {
    id: root

    required property NotifData modelData
    // Prefers modelData.image (a real, separate freedesktop notification
    // field -- "often something like a profile picture in instant
    // messaging applications", per Quickshell's own docs) over appIcon
    // when the sender provided one, since it's the more specific/richer
    // of the two when both exist. Falls back to appIcon, then the
    // generic keyword-matched glyph.
    readonly property bool hasImage: modelData.image.length > 0
    readonly property int bodyTextFormat: /[<*_`#\[\]]/.test(modelData.body) ? Text.MarkdownText : Text.PlainText
    readonly property bool critical: modelData.urgency === NotificationUrgency.Critical

    color: critical ? Colours.palette.m3error : Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.large

    implicitWidth: Tokens.sizes.notifs.width
    implicitHeight: inner.implicitHeight + Tokens.padding.medium * 2

    // Bioluminescent flash-response on arrival, echoing the deep-sea cue
    // this whole treatment is named for -- decays to nothing rather than
    // looping, so it reads as a one-off reaction to the notification
    // landing, not a persistent highlight.
    BioluminescentGlow {
        id: arrivalGlow

        target: root
        glowColour: root.critical ? Colours.palette.m3error : Colours.palette.m3primary
        glowBlur: 26
        intensity: 0
        breathing: false

        NumberAnimation on intensity {
            id: flashAnim

            running: false
            from: DepthFx.glowIntensity * 1.4
            to: 0
            duration: 900
            easing.type: Easing.OutQuad
        }
    }

    Component.onCompleted: {
        if (DepthFx.enabled)
            flashAnim.start();
    }

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
                    anchors.verticalCenter: parent.verticalCenter
                    width: Tokens.sizes.notifs.image
                    height: Tokens.sizes.notifs.image

                    sourceComponent: root.hasImage ? notifImage : notifAppIcon
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

            // The buttons a sender offered. Every freedesktop notification
            // may carry these and the server has advertised support for
            // them since it was written, but nothing drew them until now,
            // so an application offering "Reply" or "Open" got a popup
            // with no way to take it up. The shell's own notifications
            // (Notifs.notify) use the same list, which is how the release
            // banner offers a way into About.
            //
            // An action carries an optional `icon`, which only the
            // shell's own set. A freedesktop action has no icon field, so
            // that side draws text alone rather than a blank square.
            Item {
                width: 1
                height: Tokens.spacing.extraSmall
                visible: actionRow.visible
            }

            Row {
                id: actionRow

                spacing: Tokens.spacing.small
                visible: root.modelData.actions.length > 0

                Repeater {
                    model: root.modelData.actions

                    StyledRect {
                        id: actionBtn

                        required property var modelData

                        implicitWidth: actionContent.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: 26
                        radius: Tokens.rounding.full
                        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            onClicked: {
                                actionBtn.modelData.invoke();
                                root.modelData.close();
                            }
                        }

                        Row {
                            id: actionContent

                            anchors.centerIn: parent
                            spacing: Tokens.spacing.extraSmall

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: text.length > 0
                                text: actionBtn.modelData.icon ?? ""
                                color: Colours.palette.m3primary
                                fontStyle: Tokens.font.icon.small
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: actionBtn.modelData.text
                                color: Colours.palette.m3onSurface
                                font: Tokens.font.label.small
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: notifImage

        IconImage {
            source: root.modelData.image
            implicitSize: Tokens.sizes.notifs.image
        }
    }

    Component {
        id: notifAppIcon

        AppIcon {
            name: root.modelData.appIcon
            appClass: root.modelData.appName
            fallbackGlyph: Icons.getNotifIcon(root.modelData.summary, root.modelData.urgency)
            size: Tokens.sizes.notifs.image
            fontStyle: Tokens.font.icon.medium
            colour: root.critical ? Colours.palette.m3onSurface : Colours.palette.m3primary
        }
    }
}
