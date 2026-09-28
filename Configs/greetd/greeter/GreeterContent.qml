pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Greetd

Item {
    id: root

    required property GreeterAuth auth

    // Signal tones derived from the synced palette snapshot.
    readonly property color glass: Qt.alpha(Qt.tint(Colours.background, Qt.alpha(Colours.textColor, 0.07)), 0.78)
    readonly property color raised: Qt.alpha(Qt.tint(Colours.background, Qt.alpha(Colours.textColor, 0.12)), 0.9)
    readonly property color hairline: Qt.alpha(Colours.mutedTextColor, 0.22)
    readonly property bool typing: root.auth.buffer.length > 0
    readonly property bool askingName: root.auth.phase === GreeterAuth.Phase.Username
    readonly property string who: root.askingName ? root.auth.buffer : root.auth.username

    property real entrance: 0
    property bool unlocking: false
    // greetd's IPC socket is not necessarily connected on the first frame, so
    // the "not running under greetd" banner waits to see whether it settles.
    // Without the delay it appears at startup and then vanishes, which reads
    // as a flash of an error on a correctly launched greeter.
    property bool _greetdChecked: false

    implicitWidth: 440
    implicitHeight: layout.implicitHeight

    Component.onCompleted: entrance = 1

    Behavior on entrance {
        NumberAnimation {
            duration: 900
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.05, 0.7, 0.1, 1, 1, 1]
        }
    }

    // Entrance progress for the i-th block, so clock, card and hint rise in turn.
    function stagger(i: int): real {
        return Math.max(0, Math.min(1, (root.entrance - i * 0.12) / (1 - 3 * 0.12)));
    }

    Timer {
        interval: 1500
        onTriggered: root._greetdChecked = true
    }

    Connections {
        target: root.auth

        function onShake(): void {
            shakeAnim.restart();
            errorFlash.restart();
        }
    }

    Connections {
        target: Greetd

        function onReadyToLaunch(): void {
            root.unlocking = true;
        }
    }

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        width: root.width
        spacing: 28
        opacity: root.unlocking ? 0 : 1
        scale: root.unlocking ? 1.04 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: 250
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 250
            }
        }

        GreeterClock {
            Layout.alignment: Qt.AlignHCenter
            opacity: root.stagger(0)
            transform: Translate {
                y: (1 - root.stagger(0)) * 24
            }
        }

        Rectangle {
            id: card

            Layout.fillWidth: true
            Layout.preferredHeight: cardColumn.implicitHeight + 48
            Layout.topMargin: 24
            radius: 20
            color: root.glass
            border.width: 1
            border.color: root.hairline
            opacity: root.stagger(1)
            transform: Translate {
                y: (1 - root.stagger(1)) * 24
            }

            // Light catching the top edge.
            Rectangle {
                x: card.radius
                width: card.width - card.radius * 2
                height: 1
                color: Qt.alpha(Colours.textColor, 0.1)
            }

            ColumnLayout {
                id: cardColumn

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 24
                spacing: 18

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    Rectangle {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 52
                        radius: 26
                        color: Qt.alpha(Colours.primary, 0.18)
                        border.width: 1
                        border.color: Qt.alpha(Colours.primary, 0.5)

                        Text {
                            anchors.centerIn: parent
                            text: root.who.length > 0 ? root.who[0].toUpperCase() : "?"
                            font.pixelSize: 22
                            font.weight: Font.DemiBold
                            color: Colours.primary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: root.askingName ? qsTr("WELCOME") : qsTr("SIGNING IN AS")
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.6
                            color: Colours.mutedTextColor
                        }

                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.askingName ? qsTr("Who's signing in?") : root.auth.username
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                            color: Colours.textColor
                        }
                    }
                }

                Rectangle {
                    id: field

                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    radius: height / 2
                    color: root.raised
                    border.width: root.typing ? 2 : 1
                    border.color: root.typing ? Qt.alpha(Colours.primary, 0.7) : root.hairline

                    focus: true
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            forceActiveFocus();
                    }
                    Keys.onPressed: event => root.auth.handleKey(event)

                    Behavior on border.color {
                        ColorAnimation {
                            duration: 200
                        }
                    }

                    transform: Translate {
                        id: shakeShift
                    }

                    SequentialAnimation {
                        id: shakeAnim

                        NumberAnimation { target: shakeShift; property: "x"; to: 12; duration: 60 }
                        NumberAnimation { target: shakeShift; property: "x"; to: -10; duration: 60 }
                        NumberAnimation { target: shakeShift; property: "x"; to: 8; duration: 60 }
                        NumberAnimation { target: shakeShift; property: "x"; to: -5; duration: 60 }
                        NumberAnimation { target: shakeShift; property: "x"; to: 2; duration: 60 }
                        NumberAnimation { target: shakeShift; property: "x"; to: 0; duration: 60 }
                    }

                    Rectangle {
                        id: errorRing

                        anchors.fill: parent
                        radius: parent.radius
                        color: "transparent"
                        border.width: 2
                        border.color: Colours.errorColor
                        opacity: 0

                        SequentialAnimation {
                            id: errorFlash

                            NumberAnimation { target: errorRing; property: "opacity"; to: 1; duration: 120 }
                            NumberAnimation { target: errorRing; property: "opacity"; to: 0; duration: 900 }
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 22
                        anchors.rightMargin: 22
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !root.typing || !root.auth.maskInput
                        elide: Text.ElideLeft
                        font.pixelSize: 16
                        text: root.typing ? root.auth.buffer : root.auth.prompt
                        color: root.typing ? Colours.textColor : Colours.mutedTextColor
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 22
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.typing && root.auth.maskInput
                        spacing: 8

                        Repeater {
                            model: root.auth.maskInput ? Math.min(root.auth.buffer.length, 24) : 0

                            Rectangle {
                                width: 9
                                height: 9
                                radius: 4.5
                                color: Colours.textColor
                                scale: 0

                                Component.onCompleted: scale = 1

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 220
                                        easing.type: Easing.OutBack
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.auth.waiting
                        text: "…"
                        font.pixelSize: 20
                        color: Colours.primary
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    text: root.auth.errorText
                    color: Colours.errorColor
                    font.pixelSize: 13
                }

                Text {
                    Layout.fillWidth: true
                    visible: root._greetdChecked && !Greetd.available
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("greetd session not detected — this screen only functions when launched by greetd.")
                    color: Colours.errorColor
                    font.pixelSize: 12
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            opacity: root.stagger(2) * 0.8
            text: qsTr("ENTER TO CONTINUE  ·  ESC TO START OVER")
            font.pixelSize: 11
            font.weight: Font.DemiBold
            font.letterSpacing: 1.6
            color: Colours.mutedTextColor
        }
    }
}
