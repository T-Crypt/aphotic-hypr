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
    readonly property bool hasAppIcon: !hasImage && modelData.appIcon.length > 0
    // Quickshell.iconPath()'s two-arg (icon, fallback) overload only
    // resolves ICON-THEME NAMES via QIcon::fromTheme() -- confirmed by
    // reading quickshell-mirror/quickshell's own
    // src/core/iconimageprovider.cpp: the two-arg call never sets the
    // separate `path=` parameter its own file-path fallback branch
    // (`icon = QPixmap(path)`) depends on. The freedesktop notification
    // spec explicitly allows app_icon to be EITHER a themed icon name OR
    // a file:// URI/absolute path -- when a sending app uses the latter
    // (common for Electron apps, some game launchers), the theme lookup
    // fails silently and falls through to the "image-missing" fallback
    // glyph, which is what "icons not properly rendering for certain
    // notifications" actually was. Detecting the path/URI case and
    // sourcing it directly (Image accepts a plain absolute path or
    // file:// URI natively) fixes exactly that class of notification.
    readonly property bool appIconIsPath: modelData.appIcon.startsWith("/") || modelData.appIcon.startsWith("file://")
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
                    active: root.hasImage || root.hasAppIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: Tokens.sizes.notifs.image
                    height: Tokens.sizes.notifs.image

                    sourceComponent: IconImage {
                        // hasImage/hasAppIcon are mutually exclusive (see
                        // their definitions above), and appIconIsPath
                        // sources the raw path/URI directly instead of
                        // routing it through Quickshell.iconPath()'s
                        // theme-name-only resolver, which silently fails
                        // for that case -- see the property comments above
                        // for the full reasoning.
                        source: root.hasImage ? root.modelData.image : (root.appIconIsPath ? root.modelData.appIcon : Quickshell.iconPath(root.modelData.appIcon, "image-missing"))
                        implicitSize: Tokens.sizes.notifs.image
                    }
                }

                Loader {
                    active: !root.hasImage && !root.hasAppIcon
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
