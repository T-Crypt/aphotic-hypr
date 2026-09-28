pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property var lock
    required property var pam

    property bool unlocking: false

    implicitWidth: Tokens.sizes.lock.width
    implicitHeight: layout.implicitHeight + Tokens.padding.extraLarge * 2
    transformOrigin: Item.Center

    // Drives the entrance of the children below; renders nothing itself.
    SurfaceReveal {
        id: reveal
        visible: false
        Component.onCompleted: shown = true
    }

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        width: parent.width - Tokens.padding.extraLarge * 2
        spacing: Tokens.spacing.large

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Time.format("hh:mm")
            font: Settings.barSignal ? Tokens.font.headline.builders.large.scale(4).weight(Font.DemiBold).letterSpacing(-2).build() : Tokens.font.headline.builders.large.scale(2).build()
            color: Colours.palette.m3onSurface
            opacity: reveal.staggered(0)
            transform: Translate {
                y: (1 - reveal.staggered(0)) * Tokens.spacing.large
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Settings.barSignal ? Time.format("dddd, MMMM d").toUpperCase() : Time.format("dddd, MMMM d")
            font: Settings.barSignal ? Tokens.font.label.builders.medium.weight(Font.DemiBold).letterSpacing(3).build() : Tokens.font.body.large
            color: Colours.palette.m3onSurfaceVariant
            opacity: reveal.staggered(1)
            transform: Translate {
                y: (1 - reveal.staggered(1)) * Tokens.spacing.large
            }
        }

        Item {
            id: fieldContainer

            Layout.fillWidth: true
            readonly property real cardPad: Settings.barSignal ? Tokens.padding.large : 0
            readonly property real userRowHeight: Settings.barSignal ? 44 + Tokens.spacing.large : 0

            Layout.preferredHeight: Tokens.sizes.lock.fieldHeight + userRowHeight + cardPad * 2
            Layout.topMargin: Tokens.spacing.large
            opacity: reveal.staggered(2)
            transform: Translate {
                id: fieldShift
                y: (1 - reveal.staggered(2)) * Tokens.spacing.large
            }

            SequentialAnimation {
                id: shakeAnim

                NumberAnimation { target: fieldShift; property: "x"; to: 12; duration: Tokens.anim.durations.normal / 6; easing: Tokens.anim.standard }
                NumberAnimation { target: fieldShift; property: "x"; to: -10; duration: Tokens.anim.durations.normal / 6; easing: Tokens.anim.standard }
                NumberAnimation { target: fieldShift; property: "x"; to: 8; duration: Tokens.anim.durations.normal / 6; easing: Tokens.anim.standard }
                NumberAnimation { target: fieldShift; property: "x"; to: -5; duration: Tokens.anim.durations.normal / 6; easing: Tokens.anim.standard }
                NumberAnimation { target: fieldShift; property: "x"; to: 2; duration: Tokens.anim.durations.normal / 6; easing: Tokens.anim.standard }
                NumberAnimation { target: fieldShift; property: "x"; to: 0; duration: Tokens.anim.durations.normal / 6; easing: Tokens.anim.standard }
            }

            // Signal: the field sits in a glass card with the user above it,
            // the same card the login greeter shows.
            StyledRect {
                visible: Settings.barSignal
                anchors.fill: parent
                radius: Tokens.rounding.large
                color: Colours.signalStyle.glass
                border.width: 1
                border.color: Colours.signalStyle.hairline

                Rectangle {
                    x: parent.radius
                    width: parent.width - parent.radius * 2
                    height: 1
                    color: Colours.signalStyle.edgeLight
                }

                RowLayout {
                    x: fieldContainer.cardPad
                    y: fieldContainer.cardPad
                    width: parent.width - fieldContainer.cardPad * 2
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        radius: 22
                        color: Qt.alpha(Colours.palette.m3primary, 0.18)
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3primary, 0.5)

                        StyledText {
                            anchors.centerIn: parent
                            text: (Quickshell.env("USER") ?? "?").charAt(0).toUpperCase()
                            font: Tokens.font.title.builders.large.weight(Font.DemiBold).build()
                            color: Colours.palette.m3primaryOnSurface
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            text: qsTr("LOCKED")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.builders.small.weight(Font.DemiBold).letterSpacing(1.4).build()
                        }

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: Quickshell.env("USER") ?? ""
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.title.builders.medium.weight(Font.DemiBold).build()
                        }
                    }
                }
            }

            StyledRect {
                id: field

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: fieldContainer.cardPad
                height: Tokens.sizes.lock.fieldHeight
                radius: Tokens.rounding.full
                color: Settings.barSignal ? Colours.signalStyle.raised : Colours.tPalette.m3surfaceContainer

                readonly property bool typing: root.pam.buffer.length > 0 && root.pam.state === Pam.None
                border.width: typing ? 2 : Settings.barSignal ? 1 : 0
                border.color: typing ? Qt.alpha(Colours.palette.m3primary, 0.6) : Settings.barSignal ? Colours.signalStyle.hairline : "transparent"
                Behavior on border.color {
                    CAnim {}
                }

                focus: true
                onActiveFocusChanged: {
                    if (!activeFocus)
                        forceActiveFocus();
                }

                Keys.onPressed: event => root.pam.handleKey(event)

                Rectangle {
                    id: errorRing

                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: 2
                    border.color: Colours.palette.m3error
                    opacity: 0

                    SequentialAnimation {
                        id: flashAnim
                        Anim { target: errorRing; property: "opacity"; to: 1; type: Anim.StandardSmall }
                        Anim { target: errorRing; property: "opacity"; to: 0; type: Anim.StandardLarge }
                    }
                }

                MaterialIcon {
                    id: icon

                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.padding.large
                    anchors.verticalCenter: parent.verticalCenter

                    text: root.pam.state === Pam.MaxTries ? "lock_clock" : root.pam.state !== Pam.None ? "error" : "lock"
                    color: {
                        if (root.pam.state !== Pam.None)
                            return Colours.palette.m3error;
                        if (root.pam.buffer.length > 0)
                            return Colours.palette.m3primary;
                        return Colours.palette.m3onSurfaceVariant;
                    }
                    Behavior on color {
                        CAnim {}
                    }
                    fontStyle: Tokens.font.icon.medium
                }

                Row {
                    anchors.left: icon.right
                    anchors.leftMargin: Tokens.spacing.medium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: root.pam.buffer.length

                        Rectangle {
                            id: dot

                            property bool shown: false

                            width: Tokens.padding.small
                            height: Tokens.padding.small
                            radius: height / 2
                            color: Colours.palette.m3onSurface
                            scale: 0
                            transformOrigin: Item.Center

                            Component.onCompleted: shown = true

                            states: State {
                                name: "shown"
                                when: dot.shown
                                PropertyChanges { dot.scale: 1 }
                            }
                            transitions: Transition {
                                to: "shown"
                                Anim { property: "scale"; type: Anim.FastSpatial }
                            }
                        }
                    }

                    StyledText {
                        text: root.pam.buffer.length === 0 ? qsTr("Enter password…") : ""
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.medium
                    }
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            visible: text.length > 0
            text: {
                if (root.pam.state === Pam.MaxTries)
                    return qsTr("Too many attempts — locked out temporarily");
                if (root.pam.state === Pam.Error)
                    return qsTr("Authentication error");
                if (root.pam.state === Pam.Failed)
                    return qsTr("Incorrect password");
                return "";
            }
            color: Colours.palette.m3error
            font: Tokens.font.body.small
            opacity: (text.length > 0 ? 1 : 0) * reveal.staggered(3)
            transform: Translate {
                y: (1 - reveal.staggered(3)) * Tokens.spacing.large
            }
        }
    }

    states: State {
        name: "unlocking"
        when: root.unlocking
        PropertyChanges { root.scale: 1.04; root.opacity: 0 }
    }
    transitions: Transition {
        to: "unlocking"
        ParallelAnimation {
            Anim { property: "scale"; type: Anim.FastEffects }
            Anim { property: "opacity"; type: Anim.FastEffects }
        }
    }

    Connections {
        target: root.pam

        function onStateChanged(): void {
            if (root.pam.state === Pam.Failed) {
                shakeAnim.restart();
                flashAnim.restart();
            }
        }

        function onFlashMsg(): void {
            shakeAnim.restart();
            flashAnim.restart();
        }

        function onUnlockSuccess(): void {
            root.unlocking = true;
        }
    }
}
