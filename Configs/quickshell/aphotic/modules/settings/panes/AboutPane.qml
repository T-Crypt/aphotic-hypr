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

            // Compares the installed VERSION against GitHub's latest
            // tagged Release, the same "curl a JSON endpoint via Process"
            // pattern Weather.qml already uses -- no new HTTP mechanism.
            // "Update now" shells out to the existing `aphotic update`
            // CLI command (git pull --ff-only + cmd_restore.sh --populate
            // + cmd_reload.sh --full, see
            // Configs/.local/lib/aphotic/commands/cmd_update.sh) rather
            // than reimplementing any of that here -- this button is a
            // front end for an already-shipped command, not new update
            // logic. Detached (execDetached), not a plain Process,
            // because cmd_reload.sh's `systemctl --user restart
            // aphotic-shell.service` tears down the very process that
            // would otherwise be waiting on this Process's exit code.
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.spacing.small
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
                            }
                        }
                    }

                    StyledRect {
                        visible: root.updateState === "available"
                        Layout.preferredHeight: 28
                        Layout.preferredWidth: updateLabel.implicitWidth + Tokens.padding.medium * 2
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        StyledText {
                            id: updateLabel
                            anchors.centerIn: parent
                            text: qsTr("Update now")
                            color: Colours.contrastOn(Colours.palette.m3primary)
                            font: Tokens.font.label.small
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Quickshell.execDetached(["aphotic", "update"])
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.updateState !== "idle" && root.updateState !== "checking"
                    text: {
                        if (root.updateState === "current")
                            return qsTr("Up to date (%1)").arg(root.version);
                        if (root.updateState === "available")
                            return qsTr("Update available: %1 (installed: %2)").arg(root.latestVersion).arg(root.version);
                        return qsTr("Couldn't check for updates -- see your network connection, or check manually: %1").arg(root.releasesUrl);
                    }
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
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

    Component.onCompleted: versionProc.running = true
}
