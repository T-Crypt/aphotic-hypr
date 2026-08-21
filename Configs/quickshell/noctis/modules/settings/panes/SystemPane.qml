import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    property string doctorOutput: qsTr("Running noctis doctor…")

    spacing: Tokens.spacing.medium

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        StyledText {
            Layout.fillWidth: true
            text: qsTr("System")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
        }

        StyledRect {
            Layout.preferredHeight: 28
            Layout.preferredWidth: refreshLabel.implicitWidth + Tokens.padding.medium * 2
            radius: Tokens.rounding.full
            color: Colours.tPalette.m3surfaceContainer

            StyledText {
                id: refreshLabel
                anchors.centerIn: parent
                text: qsTr("Refresh")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
            }

            MouseArea {
                anchors.fill: parent
                onClicked: doctorProc.running = true
            }
        }
    }

    StyledRect {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        StyledText {
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            font: Tokens.font.mono.small
            color: Colours.palette.m3onSurface
            text: root.doctorOutput
        }
    }

    Process {
        id: doctorProc
        command: ["noctis", "doctor"]
        stdout: StdioCollector {
            onStreamFinished: root.doctorOutput = text.trim()
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    root.doctorOutput = text.trim();
            }
        }
    }

    Component.onCompleted: doctorProc.running = true
}
