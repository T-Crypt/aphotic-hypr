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

    // Icon + label for each known `capabilities` tag (manifest v3, see
    // docs/archive/PLUGIN_SYSTEM.md §7.1). An unrecognized tag (a future
    // capability, or a third-party plugin's own) falls back to a generic
    // icon and the raw string rather than needing this map updated --
    // same "no dead UI, no silent gap" spirit `[owns]` was built for.
    readonly property var capabilityMetaMap: ({
        "theme-hook": { icon: "palette", label: qsTr("Theme Hook") },
        "project-hook": { icon: "folder_open", label: qsTr("Project Hook") },
        "workspace-hook": { icon: "work", label: qsTr("Workspace Hook") },
        "ui-surface": { icon: "dashboard", label: qsTr("UI Surface") },
        "harness-hook": { icon: "smart_toy", label: qsTr("Harness Hook") }
    })

    function capabilityMeta(cap: string): var {
        return root.capabilityMetaMap[cap] ?? { icon: "extension", label: cap };
    }

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

    // Install now runs in a detached kitty terminal (see the Install
    // button below) rather than a tracked Process, so there's no
    // onExited to hook a refresh onto -- poll instead, same "cheap and
    // self-correcting" convention as Themes.qml/Colours.qml's own state-
    // file polling. 2s is frequent enough that "Install" flipping to
    // "Installed" reads as prompt without re-running `aphotic plugin
    // list` (two subprocess spawns) fast enough to matter.
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    function installedNames(): var {
        return root.installed.map(p => p.name);
    }

    // Small pill, same idiom as the "Installed"/"Install"/GitHub-link
    // pills already in this file (StyledRect, radius.full, sized to
    // content) rather than CategoryRail's larger nav-icon chip -- that
    // shape belongs to the category filter, not a per-row badge.
    component CapabilityChip: StyledRect {
        id: chip

        required property string capability

        readonly property var meta: root.capabilityMeta(chip.capability)

        implicitWidth: chipRow.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: chipRow.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.full
        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: Tokens.spacing.extraSmall

            MaterialIcon {
                text: chip.meta.icon
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                text: chip.meta.label
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }
        }
    }

    // SettingsRow's own single-line description leaves no room for
    // capability chips / a dashboard-tab disclosure / an owns-config-keys
    // line, and it exposes no slot for extra content below the
    // description -- so plugin rows use this local lookalike instead of
    // extending the shared component (docs/archive/PLUGIN_SYSTEM.md
    // §7.1 keeps this pass scoped to PluginsPane.qml). Same chrome
    // (SettingsGroup stamps first/last on any child exposing those
    // properties, duck-typed by name, so this still chains into one
    // connected card exactly like a real SettingsRow would).
    component PluginRow: StyledRect {
        id: pluginRow

        required property string icon
        required property string label
        property string description: ""
        property var capabilities: []
        property var dashboardTab: null
        property var configKeys: []
        property var externalConfig: []
        property string hostVerdict: "ok"
        property string unhosted: ""

        property bool first: true
        property bool last: true

        default property alias trailing: trailingSlot.data

        Layout.fillWidth: true
        implicitHeight: rowLayout.implicitHeight + Tokens.padding.large * 2

        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)
        topLeftRadius: pluginRow.first ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
        topRightRadius: pluginRow.first ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
        bottomLeftRadius: pluginRow.last ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
        bottomRightRadius: pluginRow.last ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall

        Behavior on topLeftRadius {
            Anim { type: Anim.DefaultEffects }
        }
        Behavior on topRightRadius {
            Anim { type: Anim.DefaultEffects }
        }
        Behavior on bottomLeftRadius {
            Anim { type: Anim.DefaultEffects }
        }
        Behavior on bottomRightRadius {
            Anim { type: Anim.DefaultEffects }
        }

        RowLayout {
            id: rowLayout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            StyledRect {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                Layout.alignment: Qt.AlignTop
                radius: Tokens.rounding.medium
                color: Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: pluginRow.icon
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    Layout.fillWidth: true
                    text: pluginRow.label
                    elide: Text.ElideRight
                    font: Tokens.font.body.medium
                }

                StyledText {
                    visible: pluginRow.description.length > 0
                    Layout.fillWidth: true
                    text: pluginRow.description
                    elide: Text.ElideRight
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.extraSmall
                    visible: pluginRow.capabilities.length > 0
                    spacing: Tokens.spacing.extraSmall

                    Repeater {
                        model: pluginRow.capabilities

                        CapabilityChip {
                            required property string modelData
                            capability: modelData
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.extraSmall
                    visible: pluginRow.dashboardTab !== null
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        text: pluginRow.dashboardTab?.icon ?? "dashboard"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: qsTr("Adds a Dashboard tab: %1").arg(pluginRow.dashboardTab?.label ?? "")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }

                StyledText {
                    visible: pluginRow.configKeys.length > 0
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: qsTr("Uses settings: %1").arg(pluginRow.configKeys.join(", "))
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }

                StyledText {
                    visible: pluginRow.externalConfig.length > 0
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: qsTr("Wires: %1").arg(pluginRow.externalConfig.join(", "))
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.extraSmall
                    visible: pluginRow.hostVerdict !== "ok"
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        text: pluginRow.hostVerdict === "inert" ? "error" : "warning"
                        color: pluginRow.hostVerdict === "inert" ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                        fill: 1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: pluginRow.hostVerdict === "inert" ? qsTr("Needs a newer Aphotic — no host here for its %1").arg(pluginRow.unhosted) : qsTr("Installs, but this Aphotic has no host for its %1").arg(pluginRow.unhosted)
                        color: pluginRow.hostVerdict === "inert" ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }

            Item {
                id: trailingSlot

                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: childrenRect.width
                Layout.preferredHeight: childrenRect.height
            }
        }
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

            PluginRow {
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
                capabilities: installedRow.modelData.capabilities ?? []
                dashboardTab: installedRow.modelData.ui?.dashboard_tab ?? null
                configKeys: installedRow.modelData.owns?.config_keys ?? []
                externalConfig: installedRow.modelData.owns?.external_config ?? []

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
            // Was 300, same fixed height as the browse column next to it --
            // but with the search box gone (showSearch: false below) and 7
            // real categories at ~60px/row with no inner spacing, 300 still
            // clipped the list into its own inner scroll for no reason this
            // box needs one. 400 fits all 7 without scrolling and keeps
            // this column and the browse column matched (see below).
            Layout.preferredHeight: 400
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            CategoryRail {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                showSearch: false
                currentCategory: root.selectedCategory
                categories: root.categories
                onCategorySelected: id => root.selectedCategory = id
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 400
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

                        PluginRow {
                            id: availableRow

                            required property var modelData
                            readonly property bool isInstalled: root.installedNames().includes(availableRow.modelData.name)
                            readonly property bool isUnhosted: availableRow.hostVerdict === "inert"

                            icon: "extension"
                            label: `${availableRow.modelData.display_name}  ·  v${availableRow.modelData.version}`
                            description: availableRow.modelData.description
                            capabilities: availableRow.modelData.capabilities ?? []
                            dashboardTab: availableRow.modelData.ui?.dashboard_tab ?? null
                            // Absent reads as "ok": an older CLI's --json
                            // carries no host_support at all, and defaulting
                            // the other way would mark every plugin
                            // unavailable rather than none.
                            hostVerdict: availableRow.modelData.host_support?.verdict ?? "ok"
                            unhosted: availableRow.modelData.host_support?.unhosted ?? ""

                            StyledRect {
                                id: installButton

                                readonly property bool actionable: !availableRow.isInstalled && !availableRow.isUnhosted

                                implicitWidth: installLabel.implicitWidth + Tokens.padding.large * 2
                                implicitHeight: 32
                                radius: Tokens.rounding.full
                                color: installButton.actionable ? Colours.palette.m3primary : Colours.layer(Colours.tPalette.m3surfaceContainer, 2)

                                StyledText {
                                    id: installLabel
                                    anchors.centerIn: parent
                                    text: availableRow.isInstalled ? qsTr("Installed") : availableRow.isUnhosted ? qsTr("Unavailable") : qsTr("Install")
                                    color: installButton.actionable ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.label.small
                                }

                                StateLayer {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    disabled: !installButton.actionable
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: installButton.actionable
                                    cursorShape: installButton.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        // Install used to run silently through
                                        // actionProc (no stdout/stderr capture at
                                        // all) -- on a machine with no local
                                        // aphotic-plugins checkout yet, the real
                                        // CLI failure (see cmd_plugin.sh) was
                                        // discarded with zero UI feedback: the
                                        // button just sat there. Routing through
                                        // a real, visible terminal instead of
                                        // trying to reimplement progress/error
                                        // display in QML -- same CLI command
                                        // either way (`aphotic plugin install`,
                                        // now self-sufficient: clones/pulls the
                                        // plugins repo itself, see
                                        // _aphotic_plugin_sync_repo), just with
                                        // real output the user can actually read,
                                        // including the git clone/pull step.
                                        // `--hold` keeps the window open after
                                        // the command exits instead of it
                                        // vanishing the instant install finishes
                                        // (or fails). No windowrule floats
                                        // kitty, so this tiles normally.
                                        Quickshell.execDetached(["kitty", "--hold", "-T", `Installing ${availableRow.modelData.display_name}`, "aphotic", "plugin", "install", availableRow.modelData.name]);
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
