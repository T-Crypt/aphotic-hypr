pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property ScreenState screenState

    // Prefix sigils in the search box switch mode, matching the existing
    // convention of one script per Rofi mode (rofi-combi/-clipboard/-emoji/
    // -wallpaper.sh) collapsed into a single searchbox instead of separate
    // launches.
    // "~" alone browses theme folders; "~<theme>/" drills into that
    // theme's own wallpapers -- matching directory-per-theme awww layout
    // (themes/THEME_SPEC.md) instead of a single flat wallpaper list.
    readonly property string wallpaperThemeSlash: {
        const t = search.text;
        if (!t.startsWith("~"))
            return "";
        const slash = t.indexOf("/");
        return slash === -1 ? "" : t.slice(1, slash);
    }
    readonly property var openTheme: wallpaperThemeSlash ? Themes.themeInfo(wallpaperThemeSlash) : null

    // "@" browses git repos under these roots for the project-switcher
    // mode -- falls back to ~/Projects and ~/repos (whichever exist) when
    // the user hasn't configured Settings.projectRoots themselves.
    readonly property var projectRoots: {
        if (Settings.projectRoots.length > 0)
            return Settings.projectRoots;
        const home = Quickshell.env("HOME");
        return [`${home}/Projects`, `${home}/repos`];
    }
    // Detects package.json/Cargo.toml per repo inline in the same find
    // pass instead of a per-delegate fs check, so scrolling the results
    // list doesn't stat the filesystem on every visible row.
    readonly property string projectScanScript: {
        const roots = root.projectRoots.map(r => `"${r}"`).join(" ");
        return `find ${roots} -maxdepth 2 -name .git -type d 2>/dev/null | while IFS= read -r d; do repo=$(dirname "$d"); if [ -f "$repo/package.json" ] || [ -f "$repo/Cargo.toml" ]; then printf 'code\\t%s\\n' "$repo"; else printf 'folder\\t%s\\n' "$repo"; fi; done`;
    }

    readonly property string mode: {
        const t = search.text;
        if (t.startsWith(">"))
            return "clipboard";
        if (t.startsWith(":"))
            return "emoji";
        if (t.startsWith("/"))
            return "windows";
        if (t.startsWith("~"))
            return openTheme ? "wallpaper" : "theme";
        if (t.startsWith("@"))
            return "project";
        if (t.startsWith("?"))
            return "settings";
        if (t.startsWith("!"))
            return "keybinds";
        if (t.startsWith("="))
            return "calculator";
        return "apps";
    }

    // Real recursive-descent parser/evaluator -- deliberately never
    // eval()/Function() on this text, since it's live, untrusted input
    // typed straight into the launcher. Returns a number, or null if the
    // expression doesn't parse/evaluate cleanly (empty result list, not
    // a NaN/broken row). Grammar: expr := term (('+'|'-') term)*,
    // term := power (('*'|'/'|'%') power)*, power := primary ('^' power)?
    // (right-assoc), primary := NUMBER | '(' expr ')', with unary +/-
    // folded into number parsing.
    function _evalMath(expr: string): var {
        const s = expr.replace(/\s+/g, "");
        if (s.length === 0)
            return null;
        let pos = 0;

        function peek() {
            return s[pos];
        }
        function parseNumber() {
            const start = pos;
            if (s[pos] === "+" || s[pos] === "-")
                pos++;
            let sawDigit = false;
            while (pos < s.length && /[0-9]/.test(s[pos])) {
                pos++;
                sawDigit = true;
            }
            if (s[pos] === ".") {
                pos++;
                while (pos < s.length && /[0-9]/.test(s[pos])) {
                    pos++;
                    sawDigit = true;
                }
            }
            if (!sawDigit)
                throw new Error("expected number");
            return parseFloat(s.slice(start, pos));
        }
        function parsePrimary() {
            if (peek() === "(") {
                pos++;
                const v = parseExpr();
                if (peek() !== ")")
                    throw new Error("expected )");
                pos++;
                return v;
            }
            return parseNumber();
        }
        function parsePower() {
            const base = parsePrimary();
            if (peek() === "^") {
                pos++;
                return Math.pow(base, parsePower());
            }
            return base;
        }
        function parseTerm() {
            let v = parsePower();
            while (peek() === "*" || peek() === "/" || peek() === "%") {
                const op = peek();
                pos++;
                const rhs = parsePower();
                v = op === "*" ? v * rhs : op === "/" ? v / rhs : v % rhs;
            }
            return v;
        }
        function parseExpr() {
            let v = parseTerm();
            while (peek() === "+" || peek() === "-") {
                const op = peek();
                pos++;
                v = op === "+" ? v + parseTerm() : v - parseTerm();
            }
            return v;
        }

        try {
            const result = parseExpr();
            if (pos !== s.length || !isFinite(result))
                return null;
            return result;
        } catch (e) {
            return null;
        }
    }
    readonly property string query: {
        const t = search.text;
        if (mode === "wallpaper")
            return t.slice(1 + wallpaperThemeSlash.length + 1).trim().toLowerCase();
        return mode === "apps" ? t.trim().toLowerCase() : t.slice(1).trim().toLowerCase();
    }

    // Rofi-drun-style icon grid, app-search mode only (Settings.launcherStyle
    // === "grid") -- every other prefix mode always renders as the list
    // below regardless of this setting.
    readonly property bool useGrid: mode === "apps" && Settings.launcherStyle === "grid"
    readonly property int gridMaxShown: Tokens.sizes.launcher.gridColumns * Tokens.sizes.launcher.gridRows
    readonly property var appResults: {
        const all = DesktopEntries.applications.values.filter(a => !a.noDisplay);
        const filtered = root.query.length === 0 ? all : all.filter(a => a.name.toLowerCase().includes(root.query));
        // Frequency first, alphabetical as the tiebreak -- there's no
        // fuzzy-match relevance scoring here to begin with (just the
        // substring filter above), so this can't outrank an actual query
        // match, only make ties among already-matched results smarter.
        // Shared by both the list and grid styles so they never drift
        // against each other.
        return filtered.sort((a, b) => (LauncherUsage.countFor(b.id) - LauncherUsage.countFor(a.id)) || a.name.localeCompare(b.name));
    }

    // Rofi-parity sizing: the wallpaper preview strip behind the search
    // bar (matching style.rasi's `inputbar { background-image: url(...) }`)
    // is its own fixed-height band above the results panel, not blended
    // into the same surface.
    readonly property int previewHeight: 140

    implicitWidth: Tokens.sizes.launcher.width
    implicitHeight: previewHeight + (useGrid ? grid.height : list.height) + Tokens.padding.large

    visible: opacity > 0
    opacity: screenState.launcher ? 1 : 0

    Behavior on opacity {
        Anim {}
    }

    onVisibleChanged: {
        if (visible) {
            search.text = root.screenState.launcherPrefill;
            root.screenState.launcherPrefill = "";
            search.forceActiveFocus();
            refreshMode();
        }
    }

    onModeChanged: refreshMode()

    function refreshMode(): void {
        if (mode === "clipboard" && !clipboardProc.running)
            clipboardProc.running = true;
        if (mode === "project")
            projectProc.exec(["sh", "-c", root.projectScanScript]);
    }

    StyledClippingRect {
        anchors.fill: parent
        radius: Tokens.rounding.extraLarge
        color: Colours.palette.m3surfaceContainerHigh
        border.width: Config.border.thickness
        border.color: Colours.palette.m3outlineVariant

        Column {
            anchors.fill: parent
            spacing: 0

            // Wallpaper preview strip -- a real live crop of the current
            // desktop wallpaper (~/.config/awww/current-wallpaper via the
            // Wallpapers service).
            Item {
                id: previewStrip

                width: parent.width
                height: root.previewHeight
                clip: true

                Image {
                    anchors.fill: parent
                    source: Wallpapers.current
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                }

                StyledRect {
                    anchors.fill: parent
                    color: Colours.palette.m3shadow
                    opacity: 0.25
                }

                Item {
                    anchors.centerIn: parent
                    width: parent.width - Tokens.padding.large * 2
                    height: search.implicitHeight

                    StyledRect {
                        anchors.fill: parent
                        anchors.margins: -Tokens.padding.small
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3surfaceContainerHigh

                        Row {
                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.medium

                            MaterialIcon {
                                id: searchIcon

                                anchors.verticalCenter: parent.verticalCenter
                                text: "search"
                                fontStyle: Tokens.font.icon.medium
                                color: Colours.palette.m3onSurfaceVariant
                            }

                            Item {
                                width: parent.width - parent.spacing - searchIcon.width
                                height: search.implicitHeight

                                TextInput {
                                    id: search

                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    clip: true

                                    font: Tokens.font.body.large
                                    color: Colours.palette.m3onSurface

                                    // Grid style (Settings.launcherStyle === "grid",
                                    // apps mode only) swaps the visible results view
                                    // out from under this same search box, but used to
                                    // leave these three handlers hardcoded to `list` --
                                    // Down/Up moved list's currentIndex while the grid
                                    // (the thing actually on screen) stayed frozen on
                                    // its first cell, and Enter read list.currentItem
                                    // regardless of which view the user was looking at.
                                    // moveCurrentIndexUp/Down (not increment/decrement)
                                    // since GridView steps by a full row, not by one
                                    // cell, for correct 2D wrap-around.
                                    Keys.onEscapePressed: root.screenState.launcher = false
                                    Keys.onReturnPressed: {
                                        const activeView = root.useGrid ? grid : list;
                                        if (activeView.currentItem) {
                                            activeView.currentItem.execute();
                                            root.screenState.launcher = false;
                                        }
                                    }
                                    Keys.onDownPressed: root.useGrid ? grid.moveCurrentIndexDown() : list.incrementCurrentIndex()
                                    Keys.onUpPressed: root.useGrid ? grid.moveCurrentIndexUp() : list.decrementCurrentIndex()
                                    Keys.onLeftPressed: event => {
                                        if (root.useGrid)
                                            grid.moveCurrentIndexLeft();
                                        else
                                            event.accepted = false;
                                    }
                                    Keys.onRightPressed: event => {
                                        if (root.useGrid)
                                            grid.moveCurrentIndexRight();
                                        else
                                            event.accepted = false;
                                    }
                                }

                                StyledText {
                                    anchors.left: search.left
                                    anchors.right: search.right
                                    anchors.verticalCenter: search.verticalCenter
                                    elide: Text.ElideRight
                                    text: {
                                        switch (root.mode) {
                                        case "clipboard":
                                            return qsTr("Clipboard history…");
                                        case "emoji":
                                            return qsTr("Search emoji…");
                                        case "windows":
                                            return qsTr("Switch window…");
                                        case "theme":
                                            return qsTr("Choose a theme… (type its name + / to browse wallpapers)");
                                        case "wallpaper":
                                            return qsTr("Choose wallpaper in %1…").arg(root.openTheme?.displayName ?? root.wallpaperThemeSlash);
                                        case "project":
                                            return qsTr("Search projects…");
                                        case "settings":
                                            return qsTr("Search settings…");
                                        case "keybinds":
                                            return qsTr("Search keybinds…");
                                        case "calculator":
                                            return qsTr("Type an expression…");
                                        default:
                                            return qsTr("Search apps… (> clip, : emoji, / windows, ~ themes, @ projects, ? settings, ! keybinds, = calculator)");
                                        }
                                    }
                                    font: search.font
                                    color: Colours.palette.m3onSurfaceVariant
                                    visible: search.text.length === 0
                                }
                            }
                        }
                    }
                }
            }

        ListView {
            id: list

            readonly property int shown: Math.min(Tokens.sizes.launcher.maxShown, count)

            visible: !root.useGrid
            width: parent.width
            height: Tokens.sizes.launcher.itemHeight * shown + Tokens.spacing.small * Math.max(0, shown - 1) + Tokens.padding.large * 2
            topMargin: Tokens.padding.large
            bottomMargin: Tokens.padding.large
            leftMargin: Tokens.padding.large
            rightMargin: Tokens.padding.large
            clip: true
            spacing: Tokens.spacing.small
            currentIndex: 0

            model: ScriptModel {
                values: {
                    switch (root.mode) {
                    case "clipboard": {
                        // Pinned entries always lead the list (and survive
                        // cliphist's rolling history getting trimmed) --
                        // deduped against the live history by raw line so a
                        // still-recent pinned copy doesn't show up twice.
                        const pinned = PinnedSnippets.entries;
                        const rest = clipboardProc.entries.filter(e => !pinned.some(p => p.raw === e.raw));
                        const all = [...pinned, ...rest];
                        return root.query.length === 0 ? all : all.filter(e => e.preview.toLowerCase().includes(root.query));
                    }
                    case "emoji":
                        return (root.query.length === 0 ? EmojiList.entries : EmojiList.entries.filter(e => e.name.toLowerCase().includes(root.query))).slice(0, Tokens.sizes.launcher.maxShown);
                    case "windows": {
                        const all = Hypr.toplevels.values;
                        const filtered = root.query.length === 0 ? all : all.filter(w => (w.title ?? "").toLowerCase().includes(root.query) || (w.lastIpcObject?.class ?? "").toLowerCase().includes(root.query));
                        return filtered.slice(0, Tokens.sizes.launcher.maxShown);
                    }
                    case "theme": {
                        const all = Themes.themes;
                        const filtered = root.query.length === 0 ? all : all.filter(t => t.displayName.toLowerCase().includes(root.query) || t.name.toLowerCase().includes(root.query));
                        return filtered;
                    }
                    case "wallpaper": {
                        const themeName = root.wallpaperThemeSlash;
                        const files = root.openTheme?.wallpapers ?? [];
                        const filtered = root.query.length === 0 ? files : files.filter(f => f.toLowerCase().includes(root.query));
                        return filtered.map(f => ({
                                    theme: themeName,
                                    file: f
                                }));
                    }
                    case "project":
                        return root.query.length === 0 ? projectProc.entries : projectProc.entries.filter(e => e.name.toLowerCase().includes(root.query));
                    case "settings": {
                        // searchIndex, not list: a plugin's settings pane is a
                        // section inside another category's pane rather than a
                        // category of its own, and its entry id
                        // ("<category>/<section>") is the address
                        // SettingsPanel.qml resolves on the way in.
                        const all = SettingsCategories.searchIndex;
                        return root.query.length === 0 ? all : all.filter(c => c.label.toLowerCase().includes(root.query) || c.description.toLowerCase().includes(root.query));
                    }
                    case "keybinds": {
                        const all = HyprKeybinds.entries;
                        return root.query.length === 0 ? all : all.filter(k => k.description.toLowerCase().includes(root.query) || k.combo.toLowerCase().includes(root.query));
                    }
                    case "calculator": {
                        const value = root._evalMath(root.query);
                        return value === null ? [] : [{ expression: root.query, value: value }];
                    }
                    default:
                        // Frequency-first sort, alphabetical tiebreak -- see
                        // root.appResults above. Unsliced -- list.height
                        // stays capped via `shown` below, but the full
                        // result set is in the model so ListView can
                        // scroll to reach entries past the visible window
                        // (same pattern clipboard/project modes already
                        // use), instead of silently truncating.
                        return root.appResults;
                    }
                }
                onValuesChanged: list.currentIndex = 0
            }

            highlight: StyledRect {
                radius: Tokens.rounding.medium
                color: Colours.palette.m3onSurface
                opacity: 0.08
            }
            highlightFollowsCurrentItem: true

            delegate: Loader {
                id: delegateLoader

                required property var modelData
                required property int index

                width: ListView.view?.width ?? 0
                height: Tokens.sizes.launcher.itemHeight

                sourceComponent: {
                    switch (root.mode) {
                    case "clipboard":
                        return clipboardDelegate;
                    case "emoji":
                        return emojiDelegate;
                    case "windows":
                        return windowDelegate;
                    case "theme":
                        return themeDelegate;
                    case "wallpaper":
                        return wallpaperDelegate;
                    case "project":
                        return projectDelegate;
                    case "settings":
                        return settingsDelegate;
                    case "keybinds":
                        return keybindDelegate;
                    case "calculator":
                        return calculatorDelegate;
                    default:
                        return appDelegate;
                    }
                }

                function execute(): void {
                    item?.execute?.();
                }

                Component {
                    id: appDelegate
                    AppItem {
                        modelData: delegateLoader.modelData
                        screenState: root.screenState
                        function execute(): void {
                            LauncherUsage.recordLaunch(modelData.id);
                            modelData.execute();
                        }
                    }
                }
                Component {
                    id: windowDelegate
                    WindowItem {
                        modelData: delegateLoader.modelData
                        screenState: root.screenState
                    }
                }
                Component {
                    id: clipboardDelegate
                    ClipboardItem {
                        modelData: delegateLoader.modelData
                        screenState: root.screenState
                    }
                }
                Component {
                    id: emojiDelegate
                    EmojiItem {
                        modelData: delegateLoader.modelData
                        screenState: root.screenState
                    }
                }
                Component {
                    id: themeDelegate
                    ThemeItem {
                        modelData: delegateLoader.modelData
                        screenState: root.screenState
                    }
                }
                Component {
                    id: wallpaperDelegate
                    WallpaperItem {
                        modelData: delegateLoader.modelData
                        screenState: root.screenState
                    }
                }
                Component {
                    id: projectDelegate
                    ProjectItem {
                        modelData: delegateLoader.modelData
                        screenState: root.screenState
                    }
                }
                Component {
                    id: settingsDelegate
                    SettingsItem {
                        modelData: delegateLoader.modelData
                        screenState: root.screenState
                    }
                }
                Component {
                    id: keybindDelegate
                    KeybindItem {
                        modelData: delegateLoader.modelData
                        screenState: root.screenState
                    }
                }
                Component {
                    id: calculatorDelegate
                    CalculatorItem {
                        modelData: delegateLoader.modelData
                        screenState: root.screenState
                    }
                }
            }
        }

        GridView {
            id: grid

            readonly property int shownCount: Math.min(root.gridMaxShown, count)
            readonly property int shownRows: Math.ceil(shownCount / Tokens.sizes.launcher.gridColumns)

            visible: root.useGrid
            width: parent.width
            height: visible ? shownRows * Tokens.sizes.launcher.gridCellHeight + Tokens.padding.large * 2 : 0
            topMargin: Tokens.padding.large
            bottomMargin: Tokens.padding.large
            leftMargin: Tokens.padding.large
            rightMargin: Tokens.padding.large
            clip: true
            currentIndex: 0
            cellWidth: (width - leftMargin - rightMargin) / Tokens.sizes.launcher.gridColumns
            cellHeight: Tokens.sizes.launcher.gridCellHeight

            model: ScriptModel {
                // Unsliced -- grid.height stays capped to gridMaxShown's
                // worth of rows (see shownRows above), but the full result
                // set is in the model so GridView can scroll to reach
                // entries past the visible window instead of silently
                // truncating (matching the ListView fix above).
                values: root.useGrid ? root.appResults : []
                onValuesChanged: grid.currentIndex = 0
            }

            highlight: StyledRect {
                radius: Tokens.rounding.large
                color: Colours.palette.m3onSurface
                opacity: 0.08
            }
            highlightFollowsCurrentItem: true

            delegate: AppGridItem {
                screenState: root.screenState
            }
        }
        }
    }

    Process {
        id: clipboardProc

        property var entries: []

        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                clipboardProc.entries = text.split("\n").filter(l => l.length > 0).map(l => {
                    const tab = l.indexOf("\t");
                    return {
                        raw: l,
                        preview: tab >= 0 ? l.slice(tab + 1) : l
                    };
                });
            }
        }
    }

    Process {
        id: projectProc

        property var entries: []

        stdout: StdioCollector {
            onStreamFinished: {
                projectProc.entries = text.split("\n").filter(l => l.length > 0).map(l => {
                    const tab = l.indexOf("\t");
                    const path = tab >= 0 ? l.slice(tab + 1) : l;
                    return {
                        icon: tab >= 0 ? l.slice(0, tab) : "folder",
                        path: path,
                        name: path.slice(path.lastIndexOf("/") + 1)
                    };
                });
            }
        }
    }

}
