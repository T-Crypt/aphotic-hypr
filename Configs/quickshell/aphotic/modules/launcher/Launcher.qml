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
        return "apps";
    }
    readonly property string query: {
        const t = search.text;
        if (mode === "wallpaper")
            return t.slice(1 + wallpaperThemeSlash.length + 1).trim().toLowerCase();
        return mode === "apps" ? t.trim().toLowerCase() : t.slice(1).trim().toLowerCase();
    }

    // Rofi-parity sizing: the wallpaper preview strip behind the search
    // bar (matching style.rasi's `inputbar { background-image: url(...) }`)
    // is its own fixed-height band above the results panel, not blended
    // into the same surface.
    readonly property int previewHeight: 140

    implicitWidth: Tokens.sizes.launcher.width
    implicitHeight: previewHeight + list.height + Tokens.padding.large

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
            // desktop wallpaper, the same source Rofi's inputbar reads
            // (~/.config/awww/wallpaper.rofi via the Wallpapers service).
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

                                    Keys.onEscapePressed: root.screenState.launcher = false
                                    Keys.onReturnPressed: {
                                        if (list.currentItem) {
                                            list.currentItem.execute();
                                            root.screenState.launcher = false;
                                        }
                                    }
                                    Keys.onDownPressed: list.incrementCurrentIndex()
                                    Keys.onUpPressed: list.decrementCurrentIndex()
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
                                        default:
                                            return qsTr("Search apps… (> clip, : emoji, / windows, ~ themes)");
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
                    case "clipboard":
                        return root.query.length === 0 ? clipboardProc.entries : clipboardProc.entries.filter(e => e.preview.toLowerCase().includes(root.query));
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
                    default: {
                        const all = DesktopEntries.applications.values.filter(a => !a.noDisplay);
                        const filtered = root.query.length === 0 ? all : all.filter(a => a.name.toLowerCase().includes(root.query));
                        return filtered.sort((a, b) => a.name.localeCompare(b.name)).slice(0, Tokens.sizes.launcher.maxShown);
                    }
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

}
