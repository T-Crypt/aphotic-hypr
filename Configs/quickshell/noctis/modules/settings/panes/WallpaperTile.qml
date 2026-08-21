pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.services

StyledClippingRect {
    id: root

    required property var modelData // { theme, file }
    readonly property bool active: root.modelData.theme === Themes.activeTheme && root.modelData.file === Themes.activeWallpaper

    implicitWidth: 120
    implicitHeight: 120
    radius: Tokens.rounding.largeIncreased
    color: Colours.tPalette.m3surfaceContainer
    border.width: root.active ? 3 : 0
    border.color: Colours.palette.m3primary

    Image {
        id: thumb

        anchors.fill: parent
        source: `file://${Themes.awwwDir}/${root.modelData.theme}/${root.modelData.file}`
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize.width: 240
        sourceSize.height: 240
        opacity: status === Image.Ready ? 1 : 0

        Behavior on opacity {
            Anim { type: Anim.DefaultEffects }
        }
    }

    StyledRect {
        anchors.fill: parent
        visible: thumb.status !== Image.Ready
        color: Colours.tPalette.m3surfaceContainer

        MaterialIcon {
            anchors.centerIn: parent
            text: "image"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.large
        }
    }

    StyledRect {
        id: labelScrim

        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        height: label.implicitHeight + Tokens.padding.small * 2
        color: Qt.alpha(Colours.palette.m3shadow, 0.55)

        StyledText {
            id: label
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Tokens.padding.small
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            text: root.modelData.theme
            color: Colours.contrastOn(labelScrim.color)
            font: Tokens.font.label.small
        }
    }

    MaterialIcon {
        visible: root.active
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Tokens.padding.small
        text: "check_circle"
        fill: 1
        color: Colours.palette.m3primary
        fontStyle: Tokens.font.icon.small

        StyledRect {
            z: -1
            anchors.centerIn: parent
            width: parent.implicitWidth + 4
            height: parent.implicitHeight + 4
            radius: Tokens.rounding.full
            color: Colours.contrastOn(Colours.palette.m3primary)
        }
    }

    StateLayer {
        anchors.fill: parent
        radius: root.radius
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (!root.active)
                Themes.setTheme(root.modelData.theme, root.modelData.file);
        }
    }
}
