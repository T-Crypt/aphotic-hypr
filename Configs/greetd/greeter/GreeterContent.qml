pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Greetd

Item {
    id: root

    required property GreeterAuth auth

    implicitWidth: 420
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        width: root.width
        spacing: 24

        AphoticMark {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 72
            Layout.preferredHeight: 72
        }

        GreeterClock {
            Layout.alignment: Qt.AlignHCenter
        }

        Rectangle {
            id: field

            Layout.fillWidth: true
            Layout.preferredHeight: 56
            Layout.topMargin: 16
            radius: height / 2
            color: Qt.alpha(Colours.surface, 0.92)
            border.width: 1
            border.color: Qt.alpha(Colours.mutedTextColor, 0.3)

            focus: true
            onActiveFocusChanged: {
                if (!activeFocus)
                    forceActiveFocus();
            }
            Keys.onPressed: event => root.auth.handleKey(event)

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideLeft
                font.pixelSize: 16
                text: {
                    if (root.auth.buffer.length > 0)
                        return root.auth.maskInput ? "•".repeat(root.auth.buffer.length) : root.auth.buffer;
                    return root.auth.prompt;
                }
                color: root.auth.buffer.length > 0 ? Colours.textColor : Colours.mutedTextColor
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: root.width
            visible: text.length > 0
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            text: root.auth.errorText
            color: Colours.errorColor
            font.pixelSize: 13
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: root.width
            visible: !Greetd.available
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("greetd session not detected — this screen only functions when launched by greetd.")
            color: Colours.errorColor
            font.pixelSize: 12
        }
    }
}
