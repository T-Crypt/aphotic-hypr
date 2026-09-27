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

    property int tintIndex: 0
    property bool destructive: false
    property real reveal: 1

    signal activated

    readonly property bool signalSkin: Settings.barSignal
    readonly property color tint: root.destructive ? Colours.palette.m3error : Colours.signalStyle.tint(root.tintIndex)
    readonly property bool hot: root.activeFocus || state.containsMouse

    function exec(): void {
        Quickshell.execDetached(root.command);
        root.activated();
    }

    implicitWidth: Tokens.sizes.session.button
    implicitHeight: Tokens.sizes.session.button + label_.implicitHeight + Tokens.spacing.small

    activeFocusOnTab: true
    opacity: root.reveal
    transform: Translate {
        y: (1 - root.reveal) * Tokens.spacing.large
    }

    Keys.onEnterPressed: exec()
    Keys.onReturnPressed: exec()

    StyledRect {
        id: bg

        width: root.signalSkin ? root.width : Tokens.sizes.session.button
        height: root.signalSkin ? root.height : Tokens.sizes.session.button
        radius: root.signalSkin ? Tokens.rounding.large
               : (root.activeFocus ? Tokens.rounding.extraLarge : Tokens.rounding.largeIncreased)
        border.width: root.signalSkin ? 1 : 0
        border.color: root.signalSkin ? (root.hot ? root.tint : Colours.signalStyle.hairline) : "transparent"
        color: root.signalSkin ? (root.hot ? Qt.alpha(root.tint, 0.14) : Colours.signalStyle.glass)
             : (root.activeFocus ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer)

        Behavior on radius {
            Anim {}
        }

        StateLayer {
            id: state

            radius: bg.radius
            opacity: root.signalSkin ? 0 : 1
            onClicked: root.exec()
        }

        // Signal: 48px icon chip; the tile holds chip + label.
        StyledRect {
            id: chip

            x: (Tokens.sizes.session.button - 48) / 2
            y: (Tokens.sizes.session.button - 48) / 2
            width: 48
            height: 48
            radius: Tokens.rounding.medium
            visible: root.signalSkin
            color: Qt.alpha(root.tint, 0.18)
        }

        MaterialIcon {
            x: root.signalSkin ? chip.x + (chip.width - implicitWidth) / 2 : (bg.width - implicitWidth) / 2
            y: root.signalSkin ? chip.y + (chip.height - implicitHeight) / 2 : (bg.height - implicitHeight) / 2
            text: root.icon
            color: root.signalSkin ? Colours.legibleAccent(root.tint, Colours.signalStyle.surface)
                 : (root.activeFocus ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface)
            fontStyle: root.signalSkin ? Tokens.font.icon.builders.medium.build()
                          : Tokens.font.icon.builders.large.scale(1.3).build()
        }
    }

    StyledText {
        id: label_

        x: (bg.width - implicitWidth) / 2
        y: root.signalSkin ? chip.y + chip.height + Tokens.spacing.small : bg.height + Tokens.spacing.small

        text: root.signalSkin ? root.label.toUpperCase() : root.label
        font: root.signalSkin ? Tokens.font.label.builders.small.letterSpacing(1).build() : Tokens.font.body.small
        color: Colours.palette.m3onSurfaceVariant
    }
}
