import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    readonly property string repoUrl: "https://github.com/T-Crypt/Aphotic-Hypr"
    property string version: "…"

    spacing: Tokens.spacing.medium

    // Same fillHeight-spacer centering LauncherPane.qml uses -- About is
    // the sparsest pane in the panel (a logo + three short text lines),
    // and got visibly more top-heavy once SettingsPanel.qml's fixed
    // height grew from 560 to 720.
    Item {
        Layout.fillHeight: true
    }

    Logo {
        implicitWidth: 96
        implicitHeight: 96
    }

    StyledText {
        Layout.topMargin: -Tokens.spacing.extraSmall
        text: "Aphotic-Hypr"
        color: Colours.palette.m3onSurface
        font: Tokens.font.headline.large
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

    Process {
        id: versionProc
        command: ["cat", `${Quickshell.env("APHOTIC_DOTS_DIR") || `${Quickshell.env("HOME")}/Aphotic-Hypr`}/VERSION`]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    root.version = text.trim();
            }
        }
    }

    Component.onCompleted: versionProc.running = true
}
