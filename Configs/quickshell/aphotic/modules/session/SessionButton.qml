pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property string icon
    required property string label
    required property list<string> command

    signal activated

    function exec(): void {
        Quickshell.execDetached(root.command);
        root.activated();
    }

    implicitWidth: Tokens.sizes.session.button
    implicitHeight: Tokens.sizes.session.button + label_.implicitHeight + Tokens.spacing.small

    activeFocusOnTab: true

    Keys.onEnterPressed: exec()
    Keys.onReturnPressed: exec()

    StyledRect {
        id: bg

        width: Tokens.sizes.session.button
        height: Tokens.sizes.session.button
        radius: root.activeFocus ? Tokens.rounding.extraLarge : Tokens.rounding.largeIncreased
        color: root.activeFocus ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer

        Behavior on radius {
            Anim {}
        }

        StateLayer {
            radius: bg.radius
            onClicked: root.exec()
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: root.icon
            color: root.activeFocus ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
            fontStyle: Tokens.font.icon.builders.large.scale(1.3).build()
        }
    }

    StyledText {
        id: label_

        anchors.top: bg.bottom
        anchors.topMargin: Tokens.spacing.small
        anchors.horizontalCenter: bg.horizontalCenter

        text: root.label
        font: Tokens.font.body.small
        color: Colours.palette.m3onSurfaceVariant
    }
}
