pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services
import qs.modules.settings

// See docs/PLUGIN_SYSTEM.md. All actual
// plugin logic (install/enable/disable/remove, remote index fetch,
// category filter, security-index trust) lives in the `aphotic plugin`
// CLI (Configs/.local/lib/aphotic/commands/cmd_plugin.sh) -- this pane
// is a thin view over it via Process + --json, same "shell out, don't
// reimplement" convention as every other Settings pane that touches
// system state.
ColumnLayout {
    id: root

    readonly property string repoUrl: "https://github.com/T-Crypt/aphotic-plugins"

    property var installed: []
    property var available: []
    property bool refreshing: false
    property bool securityIndexTrusted: false
    property string selectedCategory: "all"

    // Matches CLAUDE.md's category taxonomy. "all" is a local-only
    // pseudo-category (no plugin.toml ever sets category: "all") that
    // just means "don't filter".
    readonly property var categories: [
        { id: "all", icon: "apps", label: qsTr("All") },
        { id: "dev", icon: "code", label: qsTr("Dev Tools") },
        { id: "security", icon: "security", label: qsTr("Security Tools") },
        { id: "mobile", icon: "smartphone", label: qsTr("Mobile Bridge") },
        { id: "ai", icon: "smart_toy", label: qsTr("AI Dev") },
        { id: "theming", icon: "palette", label: qsTr("Theming") },
        { id: "productivity", icon: "bolt", label: qsTr("Productivity") }
    ]

    readonly property var filteredAvailable: root.selectedCategory === "all" ? root.available : root.available.filter(p => p.category === root.selectedCategory)

    function refresh(): void {
        root.refreshing = true;
        installedProc.running = true;
        availableProc.running = true;
        securityStatusProc.running = true;
    }

    Process {
        id: installedProc
        command: ["aphotic", "plugin", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.installed = JSON.parse(text);
                } catch (e) {
                    root.installed = [];
                }
                root.refreshing = false;
            }
        }
    }

    Process {
        id: availableProc
        command: ["aphotic", "plugin", "list", "--remote", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.available = JSON.parse(text);
                } catch (e) {
                    root.available = [];
                }
            }
        }
    }

    // Queried separately from availableProc rather than inferred from
    // whether any security-category entries happen to be present in the
    // fetched list -- that heuristic can't tell "untrusted" apart from
    // "trusted, but the security index currently has zero entries".
    Process {
        id: securityStatusProc
        command: ["aphotic", "plugin", "security-index-status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.securityIndexTrusted = JSON.parse(text).trusted === true;
                } catch (e) {
                    root.securityIndexTrusted = false;
                }
            }
        }
    }

    Process {
        id: actionProc
        onExited: root.refresh()
    }

    function installedNames(): var {
        return root.installed.map(p => p.name);
    }

    Component.onCompleted: root.refresh()

    spacing: Tokens.spacing.largeIncreased

    RowLayout {
        Layout.fillWidth: true

        StyledText {
            text: qsTr("Plugins")
            font: Tokens.font.title.large
        }

        Item {
            Layout.fillWidth: true
        }

        StyledRect {
            implicitWidth: ghLabel.implicitWidth + Tokens.padding.large * 2
            implicitHeight: 32
            radius: Tokens.rounding.full
            color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)

            RowLayout {
                anchors.centerIn: parent
                spacing: Tokens.spacing.extraSmall

                MaterialIcon {
                    text: "code"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    id: ghLabel
                    text: qsTr("aphotic-plugins on GitHub")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Qt.openUrlExternally(root.repoUrl)
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Plugins add real functionality (like syncing the active theme to RGB PC lighting) without touching this repo. See docs/PLUGIN_SYSTEM.md for how they work.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    StyledText {
        text: qsTr("Installed")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    StyledText {
        visible: !root.refreshing && root.installed.length === 0
        text: qsTr("No plugins installed yet — browse available ones below.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    SettingsGroup {
        Layout.fillWidth: true
        visible: root.installed.length > 0

        Repeater {
            model: root.installed

            SettingsRow {
                id: installedRow

                required property var modelData

                icon: "extension"
                label: installedRow.modelData.display_name
                description: {
                    const missing = installedRow.modelData.missing_binaries ?? [];
                    if (missing.length > 0)
                        return qsTr("Missing dependency: %1").arg(missing.join(", "));
                    return installedRow.modelData.description;
                }

                RowLayout {
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: installedRow.modelData.enabled ? "toggle_on" : "toggle_off"
                        fill: 1
                        color: installedRow.modelData.enabled ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium

                        StateLayer {
                            anchors.fill: parent
                            anchors.margins: -Tokens.padding.small
                            radius: Tokens.rounding.full
                            onClicked: {
                                actionProc.command = ["aphotic", "plugin", installedRow.modelData.enabled ? "disable" : "enable", installedRow.modelData.name];
                                actionProc.running = true;
                            }
                        }
                    }

                    MaterialIcon {
                        text: "delete"
                        color: Colours.palette.m3error
                        fontStyle: Tokens.font.icon.small

                        StateLayer {
                            anchors.fill: parent
                            anchors.margins: -Tokens.padding.small
                            radius: Tokens.rounding.full
                            onClicked: {
                                actionProc.command = ["aphotic", "plugin", "remove", installedRow.modelData.name];
                                actionProc.running = true;
                            }
                        }
                    }
                }
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Browse available")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    StyledText {
        visible: root.available.length === 0
        text: qsTr("Couldn't reach the aphotic-plugins index (offline, or the repo isn't public yet).")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.available.length > 0
        spacing: Tokens.spacing.medium

        StyledRect {
            Layout.preferredWidth: 220
            Layout.preferredHeight: 300
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            CategoryRail {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                currentCategory: root.selectedCategory
                categories: root.categories
                onCategorySelected: id => root.selectedCategory = id
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 300
            spacing: Tokens.spacing.small

            // Security is the one category that can be legitimately
            // empty for a reason other than "the index has nothing in
            // it" -- untrusted, it was never even fetched (see
            // securityStatusProc above and _aphotic_plugin_list_remote_json
            // in cmd_plugin.sh). Show the trust prompt instead of a bare
            // "no plugins" message in that specific case.
            StyledRect {
                Layout.fillWidth: true
                visible: root.selectedCategory === "security" && !root.securityIndexTrusted
                implicitHeight: securityPromptCol.implicitHeight + Tokens.padding.large * 2
                radius: Tokens.rounding.medium
                color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)

                ColumnLayout {
                    id: securityPromptCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.small

                    RowLayout {
                        spacing: Tokens.spacing.small

                        MaterialIcon {
                            text: "security"
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        StyledText {
                            text: qsTr("Security-category plugins are hidden")
                            font: Tokens.font.body.medium
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: qsTr("These come from a separate, less-vetted index and aren't shown until you explicitly trust it -- same idea as the exploit layer's BlackArch confirmation.")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                    }

                    StyledRect {
                        Layout.alignment: Qt.AlignLeft
                        implicitWidth: trustLabel.implicitWidth + Tokens.padding.large * 2
                        implicitHeight: 32
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        StyledText {
                            id: trustLabel
                            anchors.centerIn: parent
                            text: qsTr("Trust the security plugin index")
                            color: Colours.contrastOn(Colours.palette.m3primary)
                            font: Tokens.font.label.small
                        }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                trustProc.running = true;
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: root.selectedCategory !== "security" && root.filteredAvailable.length === 0
                text: qsTr("No plugins in this category.")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.filteredAvailable.length > 0
                contentWidth: width
                contentHeight: browseList.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                SettingsGroup {
                    id: browseList
                    width: parent.width

                    Repeater {
                        model: root.filteredAvailable

                        SettingsRow {
                            id: availableRow

                            required property var modelData
                            readonly property bool isInstalled: root.installedNames().includes(availableRow.modelData.name)

                            icon: "extension"
                            label: `${availableRow.modelData.display_name}  ·  v${availableRow.modelData.version}`
                            description: availableRow.modelData.description

                            StyledRect {
                                implicitWidth: installLabel.implicitWidth + Tokens.padding.large * 2
                                implicitHeight: 32
                                radius: Tokens.rounding.full
                                color: availableRow.isInstalled ? Colours.layer(Colours.tPalette.m3surfaceContainer, 2) : Colours.palette.m3primary

                                StyledText {
                                    id: installLabel
                                    anchors.centerIn: parent
                                    text: availableRow.isInstalled ? qsTr("Installed") : qsTr("Install")
                                    color: availableRow.isInstalled ? Colours.palette.m3onSurfaceVariant : Colours.contrastOn(Colours.palette.m3primary)
                                    font: Tokens.font.label.small
                                }

                                StateLayer {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    disabled: availableRow.isInstalled
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !availableRow.isInstalled
                                    cursorShape: availableRow.isInstalled ? Qt.ArrowCursor : Qt.PointingHandCursor
                                    onClicked: {
                                        actionProc.command = ["aphotic", "plugin", "install", availableRow.modelData.name];
                                        actionProc.running = true;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Process {
        id: trustProc
        command: ["aphotic", "plugin", "trust-security-index", "--yes"]
        onExited: root.refresh()
    }
}
