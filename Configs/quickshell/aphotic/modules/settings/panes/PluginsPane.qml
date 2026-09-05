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
    property bool hasFetchedAvailable: false
    // Raw JSON text from the last successful parse, so the 2s poll below
    // (see Timer) can skip reassigning `installed`/`available` when
    // nothing actually changed.
    property string _lastInstalledRaw: ""
    property string _lastAvailableRaw: ""

    // Matches CLAUDE.md's category taxonomy. "all" is a local-only
    // pseudo-category (no plugin.toml ever sets category: "all") that
    // just means "don't filter".
    readonly property var categories: [
        { id: "all", icon: "apps", label: qsTr("All") },
        { id: "dev", icon: "code", label: qsTr("Dev Tools") },
        { id: "security", icon: "security", label: qsTr("Security Tools") },
        { id: "mobile", icon: "smartphone", label: qsTr("Mobile Bridge") },
        { id: "ai", icon: "smart_toy", label: qsTr("AI Dev") },
        { id: "gaming", icon: "sports_esports", label: qsTr("Gaming") },
        { id: "theming", icon: "palette", label: qsTr("Theming") },
        { id: "productivity", icon: "bolt", label: qsTr("Productivity") }
    ]

    // A catalogue entry never states its layer at the top level -- the
    // requirement lives on whichever surface or profile it declares, which
    // is the same place PluginRegistry reads it from once the plugin is
    // installed. Deriving it here rather than adding a top-level field
    // keeps one source of truth for "what does this need".
    readonly property var layerLabels: ({
        "ai": qsTr("AI layer"),
        "dev": qsTr("Dev layer"),
        "gaming": qsTr("Gaming layer"),
        "security": qsTr("Security layer")
    })

    readonly property var layerOrder: ["ai", "dev", "gaming", "security", ""]

    function requiredLayer(entry: var): string {
        for (const surface of entry.ui?.surfaces ?? []) {
            const layer = surface.requires_layer ?? "";
            if (layer.length > 0)
                return layer;
        }
        return entry.profile?.requires_layer ?? "";
    }

    function layerLabel(layer: string): string {
        return root.layerLabels[layer] ?? layer;
    }

    // Same vocabulary and same fail-closed rule as PluginRegistry's own
    // gate: an unrecognised token is a plugin built against a newer
    // contract, and offering it here would be offering an install whose
    // surface the shell would then refuse to draw.
    function layerEnabled(layer: string): bool {
        if (!layer)
            return true;
        if (layer === "ai")
            return InstallProfile.aiEnabled;
        if (layer === "dev")
            return InstallProfile.devEnabled;
        if (layer === "gaming")
            return InstallProfile.gamingEnabled;
        if (layer === "security")
            return InstallProfile.securityEnabled;
        return false;
    }

    readonly property var categoryAvailable: root.selectedCategory === "all" ? root.available : root.available.filter(p => p.category === root.selectedCategory)
    readonly property var unlockedAvailable: root.available.filter(p => root.layerEnabled(root.requiredLayer(p)))
    readonly property var filteredAvailable: root.categoryAvailable.filter(p => root.layerEnabled(root.requiredLayer(p)))

    readonly property var availableGroups: {
        const groups = [];
        for (const layer of root.layerOrder) {
            const plugins = root.filteredAvailable.filter(p => root.requiredLayer(p) === layer);
            if (plugins.length === 0)
                continue;
            groups.push({
                layer: layer,
                label: layer.length > 0 ? root.layerLabel(layer) : qsTr("Works on any install"),
                plugins: plugins
            });
        }
        return groups;
    }

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
                // Skip the reassignment entirely when the text is
                // byte-identical to last time -- see availableProc below,
                // same reasoning, same fix for the same class of glitch.
                if (text !== root._lastInstalledRaw) {
                    root._lastInstalledRaw = text;
                    try {
                        root.installed = JSON.parse(text);
                    } catch (e) {
                        root.installed = [];
                    }
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
                // The 2s poll below re-runs this on every tick regardless
                // of whether the remote index actually changed, and used
                // to reassign `root.available` to a brand-new array
                // object every single time even when its contents were
                // identical. That flowed through availableGroups into the
                // Repeater below as a fresh model reference, so the
                // Repeater destroyed and recreated every delegate instead
                // of diffing them -- a transient dip in browseList's
                // implicitHeight (bound straight to the Flickable's
                // contentHeight) that StopAtBounds clamps contentY back
                // toward on every tick. Reported as "scrolling glitches
                // and snaps back to the top shortly after you start."
                // Comparing the raw text first means an unchanged index
                // (the common case) never touches `root.available` at
                // all, so the Repeater's delegates -- and the user's
                // scroll position -- are left alone.
                if (text === root._lastAvailableRaw) {
                    root.hasFetchedAvailable = true;
                    return;
                }
                root._lastAvailableRaw = text;
                try {
                    root.available = JSON.parse(text);
                } catch (e) {
                    root.available = [];
                }
                root.hasFetchedAvailable = true;
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
        property var surfaces: []
        property var configKeys: []
        property var externalConfig: []
        property string inactiveLayer: ""
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

                Repeater {
                    model: pluginRow.surfaces

                    RowLayout {
                        id: surfaceRow

                        required property var modelData

                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.spacing.extraSmall
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: surfaceRow.modelData.icon || (surfaceRow.modelData.surface === "notch" ? "expand_more" : "dashboard")
                            color: Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: surfaceRow.modelData.surface === "notch" ? qsTr("Adds a notch tile: %1").arg(surfaceRow.modelData.label ?? "") : qsTr("Adds a Dashboard tab: %1").arg(surfaceRow.modelData.label ?? "")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }

                        StyledText {
                            visible: (surfaceRow.modelData.requires_layer ?? "") !== ""
                            elide: Text.ElideRight
                            text: qsTr("needs the %1 layer").arg(surfaceRow.modelData.requires_layer ?? "")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }
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

                StyledText {
                    visible: pluginRow.inactiveLayer.length > 0
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: qsTr("Inactive: the %1 is off on this install.").arg(pluginRow.inactiveLayer)
                    color: Colours.palette.m3error
                    font: Tokens.font.label.small
                }

                // Distinct from inactiveLayer above, and both can show at
                // once: a layer being off is a state the user can change,
                // while an unhosted surface means this shell build has no
                // host for it at all.
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
                readonly property string gateLayer: root.requiredLayer(installedRow.modelData)

                icon: "extension"
                label: installedRow.modelData.display_name
                description: {
                    const missing = installedRow.modelData.missing_binaries ?? [];
                    if (missing.length > 0)
                        return qsTr("Missing dependency: %1").arg(missing.join(", "));
                    return installedRow.modelData.description;
                }
                capabilities: installedRow.modelData.capabilities ?? []
                surfaces: installedRow.modelData.ui?.surfaces ?? []
                configKeys: installedRow.modelData.owns?.config_keys ?? []
                externalConfig: installedRow.modelData.owns?.external_config ?? []
                inactiveLayer: root.layerEnabled(installedRow.gateLayer) ? "" : root.layerLabel(installedRow.gateLayer)

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
        // Gated on hasFetchedAvailable, not just an empty list -- on tab
        // open, `available` reads empty for however long the remote
        // fetch takes (a real network round-trip), and this used to
        // flash "couldn't reach the index" during that entirely normal
        // wait before flipping to real content, reading as part of the
        // reported opening-stall glitchiness.
        visible: root.hasFetchedAvailable && root.available.length === 0
        text: qsTr("Couldn't reach the aphotic-plugins index (offline, or the repo isn't public yet).")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    StyledText {
        visible: !root.hasFetchedAvailable
        text: qsTr("Loading available plugins…")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.available.length > 0 && root.unlockedAvailable.length === 0
        wrapMode: Text.Wrap
        text: qsTr("Nothing to browse: every plugin in the index belongs to a layer this install doesn't have. Enabling a layer is what reveals its plugins.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    // Still shown with nothing unlocked when the security index is
    // untrusted: that index was never fetched, so "no plugins for your
    // layers" can't be the whole story yet, and the trust prompt inside
    // this row is the only way to find out.
    RowLayout {
        Layout.fillWidth: true
        visible: root.available.length > 0 && (root.unlockedAvailable.length > 0 || !root.securityIndexTrusted)
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
                Layout.fillWidth: true
                visible: root.selectedCategory !== "security" && root.unlockedAvailable.length > 0 && root.filteredAvailable.length === 0
                wrapMode: Text.Wrap
                text: root.categoryAvailable.length > 0 ? qsTr("The plugins in this category need a layer this install doesn't have.") : qsTr("No plugins in this category.")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }

            Flickable {
                id: browseFlick

                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.availableGroups.length > 0
                contentWidth: width
                contentHeight: browseList.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                // Trims the drag/scroll travel so the thumb below stays a
                // true position indicator instead of racing ahead of it.
                rightMargin: 16

                ColumnLayout {
                    id: browseList
                    width: parent.width
                    spacing: Tokens.spacing.medium

                    Repeater {
                        model: root.availableGroups

                        ColumnLayout {
                            id: layerGroup

                            required property var modelData

                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            StyledText {
                                text: layerGroup.modelData.label
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.label.medium
                            }

                            SettingsGroup {
                                Layout.fillWidth: true

                                Repeater {
                                    model: layerGroup.modelData.plugins

                                    PluginRow {
                                        id: availableRow

                                        required property var modelData
                                        readonly property bool isInstalled: root.installedNames().includes(availableRow.modelData.name)
                                        readonly property bool isUnhosted: availableRow.hostVerdict === "inert"

                                        icon: "extension"
                                        label: `${availableRow.modelData.display_name}  ·  v${availableRow.modelData.version}`
                                        description: availableRow.modelData.description
                                        capabilities: availableRow.modelData.capabilities ?? []
                                        surfaces: availableRow.modelData.ui?.surfaces ?? []
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
            }

            // Real draggable scrollbar, not a wheel-only Flickable -- see
            // docs/ideas.md UX-04. 12px press band / 28px thumb floor,
            // the project's stated standard (SettingsPanel.qml's own
            // scrollThumb predates it at 8px/24px; not copied here).
            StyledRect {
                id: browseScrollThumb

                visible: browseFlick.contentHeight > browseFlick.height
                x: browseFlick.x + browseFlick.width - width
                y: browseFlick.y + browseFlick.visibleArea.yPosition * browseFlick.height
                width: 12
                height: Math.max(28, browseFlick.visibleArea.heightRatio * browseFlick.height)
                radius: Tokens.rounding.full
                color: Colours.palette.m3onSurfaceVariant
                opacity: browseDragArea.pressed ? 0.7 : browseDragArea.containsMouse ? 0.55 : 0.35

                Behavior on opacity {
                    Anim { type: Anim.StandardSmall }
                }

                MouseArea {
                    id: browseDragArea

                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true

                    property real pressY: 0
                    property real pressContentY: 0

                    onPressed: mouse => {
                        pressY = mapToItem(browseFlick, mouse.x, mouse.y).y;
                        pressContentY = browseFlick.contentY;
                    }
                    onPositionChanged: mouse => {
                        if (!pressed)
                            return;
                        const trackHeight = browseFlick.height - browseScrollThumb.height;
                        if (trackHeight <= 0)
                            return;
                        const scrollable = browseFlick.contentHeight - browseFlick.height;
                        const deltaY = mapToItem(browseFlick, mouse.x, mouse.y).y - pressY;
                        const deltaContent = deltaY / trackHeight * scrollable;
                        browseFlick.contentY = Math.max(0, Math.min(scrollable, pressContentY + deltaContent));
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
