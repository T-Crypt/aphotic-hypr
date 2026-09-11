pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services

// One searchable list of every plugin, installed or not.
//
// The pane used to stack an "Installed" section above a "Browse
// available" block, each with its own Repeater and the browse block with
// its own nested scroll. A Repeater instantiates every delegate at once,
// so the cost of opening this pane grew with the size of the catalogue,
// and a plugin that was both installed and in the index appeared twice
// in two places that looked like two different things.
//
// Now: one ListView over one merged model, where a plugin's state lives
// on its own row. The list virtualizes, so a 2000-entry catalogue costs
// the same as a 9-entry one, and search rather than scrolling is how you
// find anything in it.
//
// Data comes from PluginRegistry (installed, watched reactively) and
// ~/.local/state/aphotic/plugin-index.json (the catalogue, written and
// cached by the CLI). Neither costs a subprocess to read. The only
// processes this pane starts are the ones a click asks for.
ColumnLayout {
    id: root

    required property ScreenState screenState

    readonly property string repoUrl: "https://github.com/T-Crypt/aphotic-plugins"

    // Matches the CLI's category taxonomy. "all" is local-only: no
    // plugin.toml ever sets it, it just means "don't filter".
    readonly property var categories: [
        { id: "all", icon: "apps", label: qsTr("All") },
        { id: "dev", icon: "code", label: qsTr("Dev") },
        { id: "security", icon: "security", label: qsTr("Security") },
        { id: "mobile", icon: "smartphone", label: qsTr("Mobile") },
        { id: "ai", icon: "smart_toy", label: qsTr("AI") },
        { id: "gaming", icon: "sports_esports", label: qsTr("Gaming") },
        { id: "theming", icon: "palette", label: qsTr("Theming") },
        { id: "productivity", icon: "bolt", label: qsTr("Productivity") }
    ]

    readonly property var layerLabels: ({
        "ai": qsTr("AI layer"),
        "dev": qsTr("Dev layer"),
        "gaming": qsTr("Gaming layer"),
        "security": qsTr("Security layer")
    })

    function layerLabel(layer: string): string {
        return root.layerLabels[layer] ?? layer;
    }

    // ---- state ---------------------------------------------------------

    property var catalogue: []
    property bool catalogueTrusted: false
    property bool catalogueLoaded: false
    property bool refreshing: false

    property string scope: "all"
    property string category: "all"
    // Written by the debounce timer below, not by the field itself, so a
    // held keypress does not rebuild the model per character.
    property string query: ""
    // Only ever one row open. Expanding a second collapses the first,
    // which keeps the list's scroll position meaningful and means only
    // one detail Loader is ever active.
    property string expandedName: ""

    // ---- the model -----------------------------------------------------

    // Installed and catalogue entries merged by name into one row each.
    // A plugin that is both is one row carrying both facts, which is what
    // stops "installed" and "installable" reading as two separate things.
    readonly property var allRows: {
        const byName = ({});
        const rows = [];

        for (const p of PluginRegistry.installedList) {
            const row = {
                name: p.name,
                displayName: p.displayName,
                description: p.description,
                category: p.category,
                version: p.version,
                latestVersion: "",
                capabilities: p.capabilities,
                surfaces: p.surfaces,
                configKeys: p.configKeys,
                externalConfig: p.externalConfig,
                requiresBinaries: p.requiresBinaries,
                requiresLayer: p.requiresLayer,
                installed: true,
                enabled: p.enabled,
                hostVerdict: "ok",
                unhosted: "",
                searchKey: p.searchKey
            };
            byName[p.name] = row;
            rows.push(row);
        }

        for (const entry of root.catalogue) {
            const existing = byName[entry.name];
            if (existing) {
                // The catalogue is where "is there a newer one" comes
                // from; everything else on an installed row stays the
                // installed truth, not the index's description of it.
                existing.latestVersion = entry.version ?? "";
                existing.hostVerdict = entry.host_support?.verdict ?? "ok";
                existing.unhosted = entry.host_support?.unhosted ?? "";
                continue;
            }
            const surfaces = entry.ui?.surfaces ?? [];
            let layer = "";
            for (const s of surfaces) {
                if ((s.requires_layer ?? "").length > 0) {
                    layer = s.requires_layer;
                    break;
                }
            }
            if (!layer)
                layer = entry.profile?.requires_layer ?? "";
            const display = entry.display_name ?? entry.name;
            const description = entry.description ?? "";
            const category = entry.category ?? "";
            rows.push({
                name: entry.name,
                displayName: display,
                description: description,
                category: category,
                version: entry.version ?? "",
                latestVersion: entry.version ?? "",
                capabilities: entry.capabilities ?? [],
                // Catalogue shape, not the registry's resolved shape. The
                // detail view reads both through surfaceLabel() below.
                surfaces: surfaces,
                configKeys: entry.owns?.config_keys ?? [],
                externalConfig: entry.owns?.external_config ?? [],
                requiresBinaries: [],
                requiresLayer: layer,
                installed: false,
                enabled: false,
                hostVerdict: entry.host_support?.verdict ?? "ok",
                unhosted: entry.host_support?.unhosted ?? "",
                searchKey: `${entry.name} ${display} ${description} ${category}`.toLowerCase()
            });
        }

        // Derived once per data change rather than per delegate: a
        // delegate that computes its own state recomputes it on every
        // rebind, which at this list's size is the whole point to avoid.
        for (const row of rows) {
            row.layerOff = !PluginRegistry.layerEnabled(row.requiresLayer);
            row.updatable = row.installed && row.latestVersion.length > 0 && row.latestVersion !== row.version;
            row.unavailable = !row.installed && row.hostVerdict === "inert";
        }

        return rows.sort((a, b) => a.displayName.localeCompare(b.displayName));
    }

    // A catalogue entry whose layer is off is not offered: installing it
    // would install a surface the shell would then refuse to draw. An
    // installed one stays listed whatever its layer, because the user has
    // it and needs to be told why it is inert.
    readonly property var visibleRows: root.allRows.filter(r => r.installed || !r.layerOff)

    readonly property int countInstalled: root.visibleRows.filter(r => r.installed).length
    readonly property int countEnabled: root.visibleRows.filter(r => r.enabled).length
    readonly property int countUpdatable: root.visibleRows.filter(r => r.updatable).length

    readonly property var scopes: [
        { id: "all", label: qsTr("All"), count: root.visibleRows.length },
        { id: "installed", label: qsTr("Installed"), count: root.countInstalled },
        { id: "enabled", label: qsTr("Enabled"), count: root.countEnabled },
        { id: "updates", label: qsTr("Updates"), count: root.countUpdatable }
    ]

    readonly property var model: {
        const q = root.query;
        const scope = root.scope;
        const category = root.category;
        const out = [];
        for (const row of root.visibleRows) {
            if (scope === "installed" && !row.installed)
                continue;
            if (scope === "enabled" && !row.enabled)
                continue;
            if (scope === "updates" && !row.updatable)
                continue;
            if (category !== "all" && row.category !== category)
                continue;
            if (q.length > 0 && !row.searchKey.includes(q))
                continue;
            out.push(row);
        }
        return out;
    }

    // ---- helpers -------------------------------------------------------

    // Catalogue entries carry raw manifest surface objects, installed ones
    // carry PluginRegistry's resolved shape. One reader for both rather
    // than two row types.
    function surfaceKind(surface: var): string {
        return surface.surface ?? "";
    }

    function surfaceLabel(surface: var): string {
        return PluginSurfaces.describe(root.surfaceKind(surface), surface.label ?? "");
    }

    function surfaceIcon(surface: var): string {
        return surface.icon || PluginSurfaces.iconFor(root.surfaceKind(surface));
    }

    // The one line under a plugin's name, assembled here so the delegate
    // holds text rather than a chip Repeater per row. The old row drew a
    // chip per capability and a row per surface, ~35 objects each.
    function metaLine(row: var): string {
        const parts = [];
        if (row.version.length > 0)
            parts.push(row.updatable ? qsTr("v%1 → v%2").arg(row.version).arg(row.latestVersion) : `v${row.version}`);
        if (row.category.length > 0)
            parts.push(row.category);
        for (const cap of row.capabilities)
            parts.push(cap);
        return parts.join("  ·  ");
    }

    function warningFor(row: var): string {
        if (row.installed && row.layerOff)
            return qsTr("Inactive: the %1 is off on this install.").arg(root.layerLabel(row.requiresLayer));
        if (row.hostVerdict === "inert")
            return qsTr("Needs a newer Aphotic. Nothing here hosts its %1.").arg(row.unhosted);
        if (row.hostVerdict === "partial")
            return qsTr("Installs, but this Aphotic has no host for its %1.").arg(row.unhosted);
        // Resolved lazily, so this reads empty until the row has been
        // opened once. A dependency the user cannot see is not a reason to
        // probe every installed plugin's binaries on open.
        const missing = root.missingByName[row.name] ?? [];
        if (row.installed && missing.length > 0)
            return qsTr("Missing dependency: %1").arg(missing.join(", "));
        return "";
    }

    // ---- actions -------------------------------------------------------

    // Optimistic enable/disable for actions still in flight, keyed by
    // name. The toggle reads this ahead of the CLI's answer so a click
    // lands at once. Kept separate from the registry rather than written
    // back into it: the registry is the CLI's to write.
    property var pendingEnabled: ({})

    function isEnabled(row: var): bool {
        const pending = root.pendingEnabled[row.name];
        return pending === undefined ? row.enabled : pending;
    }

    // Quickshell's Process ignores `running = true` on a process that is
    // already running, so a second click while the first command was in
    // flight used to be dropped -- with the optimistic flag already
    // flipped, the row then flipped back and the click looked like it had
    // never happened.
    property var actionQueue: []
    // Tracked here rather than read off actionProc.running, which does not
    // become true until after exec() returns: two clicks in one event-loop
    // frame both saw an idle process and the second replaced the first.
    property bool actionBusy: false

    function runAction(args: var): void {
        if (root.actionBusy) {
            root.actionQueue = [...root.actionQueue, args];
            return;
        }
        root.actionBusy = true;
        actionProc.exec(args);
    }

    Process {
        id: actionProc

        onExited: {
            // Stays busy across the drain, so a click landing between two
            // queued commands still queues rather than pre-empting one.
            if (root.actionQueue.length > 0) {
                actionDrain.start();
                return;
            }
            root.actionBusy = false;
            // PluginRegistry's FileView has already picked the change up
            // by now, so there is nothing to refetch -- just let the real
            // state take over from the optimistic overlay.
            root.pendingEnabled = ({});
        }
    }

    // Launches the next queued action off the event loop rather than from
    // inside onExited, so the process is fully settled before it restarts.
    Timer {
        id: actionDrain

        interval: 0
        onTriggered: {
            const next = root.actionQueue[0];
            root.actionQueue = root.actionQueue.slice(1);
            actionProc.exec(next);
        }
    }

    // ---- catalogue -----------------------------------------------------

    // Serves the cached index (measured at ~50ms) or refetches it when the
    // cache has aged out. The result lands through the FileView below, so
    // this is not on the path to drawing anything -- the list renders from
    // whatever the cache already holds on the first frame.
    Process {
        id: catalogueProc

        command: ["aphotic", "plugin", "list", "--remote", "--json"]
        onExited: root.refreshing = false
    }

    function refreshCatalogue(force: bool): void {
        if (root.refreshing)
            return;
        root.refreshing = true;
        catalogueProc.exec(force ? ["aphotic", "plugin", "list", "--remote", "--json", "--refresh"] : ["aphotic", "plugin", "list", "--remote", "--json"]);
    }

    FileView {
        path: `${Quickshell.env("HOME")}/.local/state/aphotic/plugin-index.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.catalogue = data.plugins ?? [];
                root.catalogueTrusted = data.trusted === true;
            } catch (e) {
                root.catalogue = [];
            }
            root.catalogueLoaded = true;
        }
        onLoadFailed: {
            root.catalogue = [];
            root.catalogueLoaded = true;
        }
    }

    Process {
        id: trustProc

        command: ["aphotic", "plugin", "trust-security-index", "--yes"]
        onExited: root.refreshCatalogue(true)
    }

    // Checked only for the row the user opened, not for every installed
    // plugin on open. Resolving this eagerly meant a `command -v` per
    // declared binary per plugin, which is most of what made listing
    // plugins cost what it did.
    property var missingByName: ({})

    Process {
        id: depProc

        property string forPlugin: ""

        stdout: StdioCollector {
            onStreamFinished: {
                const missing = text.split("\n").filter(l => l.length > 0);
                root.missingByName = Object.assign({}, root.missingByName, {
                    [depProc.forPlugin]: missing
                });
            }
        }
    }

    function checkDependencies(row: var): void {
        if (!row.installed || row.requiresBinaries.length === 0)
            return;
        if (root.missingByName[row.name] !== undefined)
            return;
        depProc.forPlugin = row.name;
        depProc.exec(["sh", "-c", `for b in ${row.requiresBinaries.join(" ")}; do command -v "$b" >/dev/null 2>&1 || echo "$b"; done`]);
    }

    Component.onCompleted: root.refreshCatalogue(false)

    Connections {
        target: root.screenState

        function onSettingsChanged() {
            if (root.screenState.settings)
                root.refreshCatalogue(false);
        }
    }

    // ---- chrome --------------------------------------------------------

    spacing: Tokens.spacing.medium

    RowLayout {
        Layout.fillWidth: true

        StyledText {
            text: qsTr("Plugins")
            font: Tokens.font.title.large
        }

        Item {
            Layout.fillWidth: true
        }

        MaterialIcon {
            text: "refresh"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.small
            opacity: root.refreshing ? 0.4 : 1

            StateLayer {
                anchors.fill: parent
                anchors.margins: -Tokens.padding.small
                radius: Tokens.rounding.full
                onClicked: root.refreshCatalogue(true)
            }
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
        text: qsTr("Plugins add real functionality without touching this repo. Install one to add it, then use the toggle to turn it on or off.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: 36
        radius: Tokens.rounding.full
        color: Colours.layer(Colours.tPalette.m3surfaceContainer, 2)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "search"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            TextInput {
                id: searchInput

                Layout.fillWidth: true
                clip: true
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurface

                Keys.onEscapePressed: searchInput.text = ""
                // Debounced rather than bound straight to root.query:
                // every keystroke otherwise rebuilds the filtered model,
                // and at catalogue size that is the one thing between
                // typing and the list keeping up.
                onTextChanged: queryDebounce.restart()

                StyledText {
                    visible: searchInput.text.length === 0
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Search %1 plugins…").arg(root.visibleRows.length)
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }

            MaterialIcon {
                visible: searchInput.text.length > 0
                text: "close"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small

                StateLayer {
                    anchors.fill: parent
                    anchors.margins: -Tokens.padding.small
                    radius: Tokens.rounding.full
                    onClicked: searchInput.text = ""
                }
            }
        }
    }

    Timer {
        id: queryDebounce

        interval: 120
        onTriggered: root.query = searchInput.text.trim().toLowerCase()
    }

    // Scope and category are two filters, not a navigation rail. The rail
    // this pane used to borrow cost 220px of width and read as a place to
    // go rather than a way to narrow what is already here.
    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        Repeater {
            model: root.scopes

            StyledRect {
                id: scopeChip

                required property var modelData

                readonly property bool current: root.scope === scopeChip.modelData.id

                implicitWidth: scopeLabel.implicitWidth + Tokens.padding.large * 2
                implicitHeight: 30
                radius: Tokens.rounding.full
                color: scopeChip.current ? Colours.palette.m3primary : Colours.layer(Colours.tPalette.m3surfaceContainer, 2)

                StyledText {
                    id: scopeLabel

                    anchors.centerIn: parent
                    text: `${scopeChip.modelData.label}  ${scopeChip.modelData.count}`
                    color: scopeChip.current ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    onClicked: root.scope = scopeChip.modelData.id
                }
            }
        }

        Item {
            Layout.fillWidth: true
        }
    }

    Flow {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        Repeater {
            model: root.categories

            StyledRect {
                id: catChip

                required property var modelData

                readonly property bool current: root.category === catChip.modelData.id

                implicitWidth: catRow.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: 28
                radius: Tokens.rounding.full
                color: catChip.current ? Colours.layer(Colours.tPalette.m3surfaceContainer, 3) : "transparent"
                border.width: 1
                border.color: catChip.current ? Colours.palette.m3primary : Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                RowLayout {
                    id: catRow

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        text: catChip.modelData.icon
                        color: catChip.current ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }

                    StyledText {
                        text: catChip.modelData.label
                        color: catChip.current ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    onClicked: root.category = catChip.modelData.id
                }
            }
        }
    }

    // Security plugins come from a separate, less-vetted index that is not
    // fetched at all until the user trusts it, so an empty security
    // category cannot be reported as "nothing here" the way the others can.
    StyledRect {
        Layout.fillWidth: true
        visible: root.category === "security" && !root.catalogueTrusted
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
                text: qsTr("These come from a separate, less-vetted index and stay hidden until you trust it, the same way the exploit layer asks before it installs anything.")
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
                    onClicked: trustProc.running = true
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.model.length === 0
        wrapMode: Text.Wrap
        text: {
            if (!root.catalogueLoaded)
                return qsTr("Loading plugins…");
            if (root.query.length > 0)
                return qsTr("Nothing matches “%1”.").arg(searchInput.text.trim());
            if (root.scope === "updates")
                return qsTr("Everything installed is up to date.");
            if (root.scope !== "all" && root.countInstalled === 0)
                return qsTr("No plugins installed yet. Switch to All to see what you can add.");
            if (root.visibleRows.length === 0)
                return qsTr("Couldn't reach the plugin index, and nothing is installed yet.");
            return qsTr("Nothing in this category.");
        }
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    // ---- the list ------------------------------------------------------

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        // The list takes the pane's slack rather than growing to its
        // content. The old browse column sized itself off its list's
        // implicitHeight, which forced a full layout pass over every row
        // before the pane could size itself at all -- the binding that
        // made virtualizing impossible.
        Layout.minimumHeight: 320
        visible: root.model.length > 0

        ListView {
            id: list

            anchors.fill: parent
            anchors.rightMargin: scrollBar.implicitWidth + Tokens.spacing.extraSmall
            clip: true
            spacing: 0
            boundsBehavior: Flickable.StopAtBounds
            model: root.model
            // Delegates are recycled rather than destroyed and rebuilt as
            // the list scrolls. Every binding in the delegate below is on
            // modelData, so a reused delegate re-evaluates into its new
            // row with nothing to reset by hand.
            reuseItems: true
            cacheBuffer: 800

            delegate: PluginRow {}

            // A JS-array model resets contentY to 0 whenever it is
            // reassigned, and enabling a plugin reassigns it: the registry
            // changes, the model rebuilds, and the list jumps to the top
            // under whatever row was just clicked. Restored only when the
            // row count is unchanged, which separates "the data moved"
            // from "the user filtered" -- a filter should land at the top.
            Connections {
                target: root

                function onModelChanged() {
                    const y = list.contentY;
                    const n = list.count;
                    Qt.callLater(() => {
                        if (list.count !== n)
                            return;
                        list.contentY = Math.max(0, Math.min(y, list.contentHeight - list.height));
                    });
                }
            }
        }

        FlickScrollBar {
            id: scrollBar

            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            flickable: list
        }
    }

    // ---- the row -------------------------------------------------------

    component PluginRow: StyledRect {
        id: pluginRow

        required property var modelData
        required property int index

        readonly property bool expanded: root.expandedName === pluginRow.modelData.name
        readonly property bool on: root.isEnabled(pluginRow.modelData)
        readonly property string warning: root.warningFor(pluginRow.modelData)
        readonly property bool actionable: !pluginRow.modelData.installed && !pluginRow.modelData.unavailable

        width: ListView.view?.width ?? 0
        implicitHeight: rowCol.implicitHeight + Tokens.padding.medium * 2

        color: pluginRow.expanded ? Colours.layer(Colours.tPalette.m3surfaceContainer, 3) : Colours.layer(Colours.tPalette.m3surfaceContainer, 2)

        // Rounded as one card: the group's ends round, everything between
        // them stays square. SettingsGroup does this by stamping its static
        // children, which a virtualized list has none of.
        topLeftRadius: pluginRow.index === 0 ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
        topRightRadius: pluginRow.topLeftRadius
        bottomLeftRadius: pluginRow.index === root.model.length - 1 ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
        bottomRightRadius: pluginRow.bottomLeftRadius

        ColumnLayout {
            id: rowCol

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    Layout.alignment: Qt.AlignVCenter
                    text: "extension"
                    color: pluginRow.modelData.installed ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: pluginRow.modelData.displayName
                        elide: Text.ElideRight
                        font: Tokens.font.body.medium
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.metaLine(pluginRow.modelData)
                        elide: Text.ElideRight
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }

                // Collapsed rows still show that something is wrong, just
                // not what: the detail says that. A warning that only
                // appears once expanded is a warning nobody reads.
                MaterialIcon {
                    visible: pluginRow.warning.length > 0
                    Layout.alignment: Qt.AlignVCenter
                    text: pluginRow.modelData.unavailable || pluginRow.modelData.layerOff ? "error" : "warning"
                    color: pluginRow.modelData.unavailable || pluginRow.modelData.layerOff ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                    fill: 1
                }

                MaterialIcon {
                    visible: pluginRow.modelData.installed
                    Layout.alignment: Qt.AlignVCenter
                    text: pluginRow.on ? "toggle_on" : "toggle_off"
                    fill: 1
                    color: pluginRow.on ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium

                    StateLayer {
                        anchors.fill: parent
                        anchors.margins: -Tokens.padding.small
                        radius: Tokens.rounding.full
                        onClicked: {
                            const name = pluginRow.modelData.name;
                            const shouldEnable = !pluginRow.on;
                            root.pendingEnabled = Object.assign({}, root.pendingEnabled, {
                                [name]: shouldEnable
                            });
                            root.runAction(["aphotic", "plugin", shouldEnable ? "enable" : "disable", name]);
                        }
                    }
                }

                StyledRect {
                    visible: !pluginRow.modelData.installed
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: installLabel.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: 30
                    radius: Tokens.rounding.full
                    color: pluginRow.actionable ? Colours.palette.m3primary : Colours.layer(Colours.tPalette.m3surfaceContainer, 3)

                    StyledText {
                        id: installLabel

                        anchors.centerIn: parent
                        text: pluginRow.modelData.unavailable ? qsTr("Unavailable") : qsTr("Install")
                        color: pluginRow.actionable ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: parent.radius
                        disabled: !pluginRow.actionable
                        // Install runs in a real terminal rather than
                        // silently through a tracked Process. It clones or
                        // pulls the plugins repo, which can fail in ways
                        // worth reading; routing it to a window the user
                        // can see beats reimplementing progress and error
                        // display in QML. --hold keeps that window up
                        // after the command exits.
                        onClicked: Quickshell.execDetached(["kitty", "--hold", "-T", qsTr("Installing %1").arg(pluginRow.modelData.displayName), "aphotic", "plugin", "install", pluginRow.modelData.name])
                    }
                }

                MaterialIcon {
                    Layout.alignment: Qt.AlignVCenter
                    text: pluginRow.expanded ? "expand_less" : "expand_more"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small

                    StateLayer {
                        anchors.fill: parent
                        anchors.margins: -Tokens.padding.small
                        radius: Tokens.rounding.full
                        onClicked: {
                            if (pluginRow.expanded) {
                                root.expandedName = "";
                                return;
                            }
                            root.expandedName = pluginRow.modelData.name;
                            root.checkDependencies(pluginRow.modelData);
                        }
                    }
                }
            }

            // Inactive until the row is opened, so a collapsed row costs
            // nothing for detail nobody is looking at. This is what the
            // old row drew inline for every plugin at once.
            Loader {
                Layout.fillWidth: true
                active: pluginRow.expanded
                visible: active
                sourceComponent: PluginDetail {
                    row: pluginRow.modelData
                    warning: pluginRow.warning
                }
            }
        }
    }

    component PluginDetail: ColumnLayout {
        id: detail

        required property var row
        required property string warning

        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.fillWidth: true
            visible: detail.row.description.length > 0
            text: detail.row.description
            wrapMode: Text.Wrap
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
        }

        StyledText {
            Layout.fillWidth: true
            visible: detail.warning.length > 0
            text: detail.warning
            wrapMode: Text.Wrap
            color: detail.row.unavailable || detail.row.layerOff ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }

        Repeater {
            model: detail.row.surfaces

            RowLayout {
                id: surfaceRow

                required property var modelData

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                MaterialIcon {
                    text: root.surfaceIcon(surfaceRow.modelData)
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.surfaceLabel(surfaceRow.modelData)
                    elide: Text.ElideRight
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: detail.row.configKeys.length > 0
            text: qsTr("Uses settings: %1").arg(detail.row.configKeys.join(", "))
            wrapMode: Text.Wrap
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }

        StyledText {
            Layout.fillWidth: true
            visible: detail.row.externalConfig.length > 0
            text: qsTr("Wires: %1").arg(detail.row.externalConfig.join(", "))
            wrapMode: Text.Wrap
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }

        RowLayout {
            Layout.topMargin: Tokens.spacing.extraSmall
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            Repeater {
                model: detail.row.enabled ? PluginSurfaces.jumpsFor(detail.row.name) : []

                RowLayout {
                    id: jump

                    required property var modelData

                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        text: jump.modelData.icon
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.small
                    }

                    StyledText {
                        text: jump.modelData.label
                        color: Colours.palette.m3primary
                        font: Tokens.font.label.small
                    }

                    StateLayer {
                        anchors.fill: parent
                        anchors.margins: -Tokens.padding.small
                        radius: Tokens.rounding.full
                        onClicked: PluginSurfaces.navigate(root.screenState, jump.modelData)
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                visible: detail.row.updatable
                text: qsTr("Update")
                color: Colours.palette.m3primary
                font: Tokens.font.label.small

                StateLayer {
                    anchors.fill: parent
                    anchors.margins: -Tokens.padding.small
                    radius: Tokens.rounding.full
                    onClicked: Quickshell.execDetached(["kitty", "--hold", "-T", qsTr("Updating %1").arg(detail.row.displayName), "aphotic", "plugin", "update", detail.row.name])
                }
            }

            StyledText {
                visible: detail.row.installed
                text: qsTr("Remove")
                color: Colours.palette.m3error
                font: Tokens.font.label.small

                StateLayer {
                    anchors.fill: parent
                    anchors.margins: -Tokens.padding.small
                    radius: Tokens.rounding.full
                    onClicked: {
                        root.expandedName = "";
                        root.runAction(["aphotic", "plugin", "remove", detail.row.name]);
                    }
                }
            }
        }
    }
}
