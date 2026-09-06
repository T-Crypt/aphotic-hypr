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
    readonly property string releasesUrl: "https://github.com/T-Crypt/Aphotic-Hypr/releases"
    readonly property string licenseUrl: "https://github.com/T-Crypt/Aphotic-Hypr/blob/main/LICENSE"
    property string version: "…"

    // "idle" | "checking" | "current" | "available" | "error"
    property string updateState: "idle"
    property string latestVersion: ""

    // Filled by `aphotic sync --check --json`, which runs alongside the
    // release check rather than after it: the two answer different
    // questions and neither blocks the other. A release being current
    // does not mean the packages it wants are installed, which is exactly
    // the half-updated state this pane exists to surface.
    property var missingPackages: []
    property var outdatedPlugins: []

    // Read back from ~/.local/state/aphotic/last-sync.json. A sync
    // restarts the shell, so this pane cannot watch one finish -- it
    // reads the result the next time it is opened.
    property var lastSync: null

    readonly property string releaseUrl: root.latestVersion.length > 0 ? `${root.releasesUrl}/tag/${root.latestVersion}` : root.releasesUrl
    readonly property bool syncWorthwhile: root.updateState === "available" || root.outdatedPlugins.length > 0

    spacing: Tokens.spacing.medium

    // Symmetric top/bottom fillHeight spacers -- previously only the top
    // one existed (matching LauncherPane.qml's centering trick), so once
    // SettingsPanel.qml's fixed height grew from 560 to 720 the sparsest
    // pane in the panel accumulated every bit of that extra height above
    // its content and sat pinned to the bottom edge instead of centred.
    // Paired with `card`'s own Qt.AlignHCenter below, which fixes the
    // other half of the same complaint: no child here ever set
    // horizontal alignment, so the whole block also hugged the left edge
    // once the column stretched to the panel's full width.
    Item {
        Layout.fillHeight: true
    }

    StyledRect {
        id: card

        Layout.alignment: Qt.AlignHCenter
        implicitWidth: content.implicitWidth + Tokens.padding.large * 4
        implicitHeight: content.implicitHeight + Tokens.padding.large * 3
        radius: Tokens.rounding.extraLarge
        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)

        DepthGradient {
            anchors.fill: parent
            radius: parent.radius
            baseColour: card.color
        }

        ColumnLayout {
            id: content

            anchors.centerIn: parent
            spacing: Tokens.spacing.medium

            Logo {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 96
                implicitHeight: 96
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: -Tokens.spacing.extraSmall
                text: "Aphotic-Hypr"
                color: Colours.palette.m3onSurface
                font: Tokens.font.headline.large
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Version %1").arg(root.version)
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
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

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.spacing.small
                spacing: Tokens.spacing.medium

                StyledText {
                    textFormat: Text.RichText
                    text: `<a href="${root.releasesUrl}">${qsTr("Release notes")}</a>`
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
                    text: "·"
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                }

                StyledText {
                    textFormat: Text.RichText
                    text: `<a href="${root.licenseUrl}">${qsTr("GPL-3.0 license")}</a>`
                    color: Colours.legibleAccent(Colours.palette.m3primary, Colours.tPalette.m3surfaceContainer)
                    font: Tokens.font.body.medium
                    onLinkActivated: link => Qt.openUrlExternally(link)

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.NoButton
                    }
                }
            }

            // Two questions, asked together and answered separately. The
            // release check compares the installed VERSION against
            // GitHub's latest tagged Release, the same "curl a JSON
            // endpoint via Process" pattern Weather.qml uses. The sync
            // check runs `aphotic sync --check --json`, which says which
            // packages the installed profile asks for and pacman does not
            // have, and which plugins the local plugins repo has a newer
            // version of.
            //
            // Both matter because they fail apart: a release can be
            // current while the packages it added are missing, which is a
            // half-updated desktop where the config landed and the feature
            // needing the new package silently does nothing. That is the
            // state this pane exists to name.
            //
            // The button runs `aphotic sync` -- config sync plus a plugin
            // refresh, no package installs, because those need sudo and a
            // resolved profile and belong to install.sh. Detached
            // (execDetached), not a plain Process, because the config sync
            // restarts aphotic-shell.service and tears down the very
            // process that would be waiting on the exit code. Which is
            // also why the result is read back off a file below rather
            // than a pipe.
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.spacing.small
                Layout.maximumWidth: 460
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        Layout.preferredHeight: 28
                        Layout.preferredWidth: checkLabel.implicitWidth + Tokens.padding.medium * 2
                        radius: Tokens.rounding.full
                        color: Colours.tPalette.m3surfaceContainer
                        opacity: root.updateState === "checking" ? 0.5 : 1

                        StyledText {
                            id: checkLabel
                            anchors.centerIn: parent
                            text: root.updateState === "checking" ? qsTr("Checking…") : qsTr("Check for updates")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            disabled: root.updateState === "checking"
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.updateState !== "checking"
                            onClicked: {
                                root.updateState = "checking";
                                updateCheckProc.running = true;
                                syncCheckProc.running = true;
                            }
                        }
                    }

                    StyledRect {
                        visible: root.syncWorthwhile
                        Layout.preferredHeight: 28
                        Layout.preferredWidth: updateLabel.implicitWidth + Tokens.padding.medium * 2
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        StyledText {
                            id: updateLabel
                            anchors.centerIn: parent
                            text: qsTr("Sync update")
                            color: Colours.contrastOn(Colours.palette.m3primary)
                            font: Tokens.font.label.small
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Quickshell.execDetached(["aphotic", "sync"])
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: root.updateState !== "idle" && root.updateState !== "checking"
                    textFormat: Text.RichText
                    text: {
                        if (root.updateState === "current")
                            return qsTr("Up to date (%1)").arg(root.version);
                        if (root.updateState === "available")
                            return qsTr("Update available: %1 (installed: %2). <a href=\"%3\">What changed</a>").arg(root.latestVersion).arg(root.version).arg(root.releaseUrl);
                        return qsTr("Couldn't check for updates -- see your network connection, or check manually: %1").arg(root.releasesUrl);
                    }
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                    onLinkActivated: link => Qt.openUrlExternally(link)
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: root.outdatedPlugins.length > 0
                    text: qsTr("Plugin updates: %1").arg(root.outdatedPlugins.map(p => `${p.name} ${p.from} → ${p.to}`).join(", "))
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }

                // Only ever a warning. Nothing here installs a package.
                StyledRect {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.extraSmall
                    visible: root.missingPackages.length > 0
                    implicitHeight: missingCol.implicitHeight + Tokens.padding.medium * 2
                    radius: Tokens.rounding.medium
                    color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                    ColumnLayout {
                        id: missingCol

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.padding.medium
                        spacing: Tokens.spacing.extraSmall

                        RowLayout {
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                text: "inventory_2"
                                color: Colours.palette.m3error
                                fontStyle: Tokens.font.icon.small
                            }

                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: qsTr("%1 package(s) this profile asks for are not installed").arg(root.missingPackages.length)
                                color: Colours.palette.m3onSurface
                                font: Tokens.font.label.medium
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: root.missingPackages.join(", ")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: qsTr("A sync deploys the config but installs nothing. Run ./install.sh from the Aphotic repo to add these.")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: root.syncWorthwhile
                    text: qsTr("Syncing re-deploys the config and refreshes plugins. It restarts the shell, so the bar and every panel disappear for a moment.")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }

                // What the last sync did, read back after the restart it
                // caused. Absent until one has run.
                StyledRect {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.extraSmall
                    visible: root.lastSync !== null
                    implicitHeight: lastCol.implicitHeight + Tokens.padding.medium * 2
                    radius: Tokens.rounding.medium
                    color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                    ColumnLayout {
                        id: lastCol

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.padding.medium
                        spacing: Tokens.spacing.extraSmall

                        RowLayout {
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                text: root.lastSync?.result === "ok" ? "check_circle" : "error"
                                color: root.lastSync?.result === "ok" ? Colours.palette.m3primary : Colours.palette.m3error
                                fontStyle: Tokens.font.icon.small
                            }

                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: root.lastSync?.result === "ok" ? qsTr("Last sync finished") : qsTr("Last sync did not finish")
                                color: Colours.palette.m3onSurface
                                font: Tokens.font.label.medium
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: qsTr("Full output: ~/.local/state/aphotic/last-sync.log")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }
                    }
                }
            }
        }
    }

    Item {
        Layout.fillHeight: true
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

    Process {
        id: updateCheckProc
        command: ["curl", "-s", "-m", "10", "https://api.github.com/repos/T-Crypt/aphotic-hypr/releases/latest"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    const tag = (data.tag_name || "").replace(/^v/, "");
                    if (!tag)
                        throw new Error("no tag_name in response");
                    root.latestVersion = data.tag_name;
                    root.updateState = tag === root.version ? "current" : "available";
                } catch (e) {
                    root.updateState = "error";
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (root.updateState === "checking")
                    root.updateState = "error";
            }
        }
    }

    // Read-only: `--check` pulls nothing, deploys nothing and restarts
    // nothing, so this is safe to run on a plain button press and safe to
    // run again while the release check is still in flight.
    Process {
        id: syncCheckProc

        command: ["aphotic", "sync", "--check", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.missingPackages = data.missingPackages ?? [];
                    root.outdatedPlugins = data.outdatedPlugins ?? [];
                } catch (e) {
                    root.missingPackages = [];
                    root.outdatedPlugins = [];
                }
            }
        }
    }

    // Absent until a sync has run, which is the normal state on a fresh
    // install -- so a failed read clears the card rather than showing an
    // error for a file nobody was owed.
    FileView {
        path: `${Quickshell.env("HOME")}/.local/state/aphotic/last-sync.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.lastSync = JSON.parse(text());
            } catch (e) {
                root.lastSync = null;
            }
        }
        onLoadFailed: root.lastSync = null
    }

    Component.onCompleted: {
        versionProc.running = true;
        syncCheckProc.running = true;
    }
}
