import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    readonly property string repoUrl: "https://github.com/T-Crypt/Noctis-Hypr"
    property string version: "…"

    spacing: Tokens.spacing.medium

    StyledText {
        text: "Noctis-Hypr"
        color: Colours.palette.m3onSurface
        font: Tokens.font.headline.medium
    }

    StyledText {
        text: qsTr("Version %1").arg(root.version)
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.medium
    }

    StyledText {
        textFormat: Text.RichText
        text: `<a href="${root.repoUrl}">${root.repoUrl}</a>`
        color: Colours.legibleAccent(Colours.palette.m3primary, Colours.tPalette.m3surfaceContainer)
        font: Tokens.font.body.medium
        onLinkActivated: link => Qt.openUrlExternally(link)

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.NoButton
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.medium
        text: qsTr("Wallpaper art credits")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.builders.medium.weight(Font.Medium).build()
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("All shipped theme wallpapers are original, hand-authored art created for this project — see themes/THEME_SPEC.md.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    Process {
        id: versionProc
        command: ["cat", `${Quickshell.env("NOCTIS_DOTS_DIR") || `${Quickshell.env("HOME")}/Noctis-Hypr`}/VERSION`]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    root.version = text.trim();
            }
        }
    }

    Component.onCompleted: versionProc.running = true
}
