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
    readonly property string mode: {
        const t = search.text;
        if (t.startsWith(">"))
            return "clipboard";
        if (t.startsWith(":"))
            return "emoji";
        if (t.startsWith("/"))
            return "windows";
        if (t.startsWith("~"))
            return "wallpaper";
        return "apps";
    }
    readonly property string query: {
        const t = search.text;
        return mode === "apps" ? t.trim().toLowerCase() : t.slice(1).trim().toLowerCase();
    }

    implicitWidth: Tokens.sizes.launcher.width
    implicitHeight: search.implicitHeight + Tokens.padding.large * 3 + list.height

    visible: opacity > 0
    opacity: screenState.launcher ? 1 : 0

    Behavior on opacity {
        Anim {}
    }

    onVisibleChanged: {
        if (visible) {
            search.text = "";
            search.forceActiveFocus();
            refreshMode();
        }
    }

    onModeChanged: refreshMode()

    function refreshMode(): void {
        if (mode === "clipboard" && !clipboardProc.running)
            clipboardProc.running = true;
        else if (mode === "wallpaper" && !wallpaperProc.running)
            wallpaperProc.running = true;
    }

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainerHigh
    }

    Column {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.padding.large

        Item {
            width: parent.width
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
                anchors.verticalCenter: search.verticalCenter
                text: {
                    switch (root.mode) {
                    case "clipboard":
                        return qsTr("Clipboard history…");
                    case "emoji":
                        return qsTr("Search emoji…");
                    case "windows":
                        return qsTr("Switch window…");
                    case "wallpaper":
                        return qsTr("Choose wallpaper…");
                    default:
                        return qsTr("Search apps… (> clip, : emoji, / windows, ~ wallpaper)");
                    }
                }
                font: search.font
                color: Colours.palette.m3onSurfaceVariant
                visible: search.text.length === 0
            }
        }

        ListView {
            id: list

            readonly property int shown: Math.min(Tokens.sizes.launcher.maxShown, count)

            width: parent.width
            height: Tokens.sizes.launcher.itemHeight * shown + Tokens.spacing.small * Math.max(0, shown - 1)
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
                    case "wallpaper":
                        return root.query.length === 0 ? wallpaperProc.entries : wallpaperProc.entries.filter(e => e.name.toLowerCase().includes(root.query));
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
                    id: wallpaperDelegate
                    WallpaperItem {
                        modelData: delegateLoader.modelData
                        screenState: root.screenState
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

    Process {
        id: wallpaperProc

        property var entries: []

        command: ["find", Config.launcher.wallpaperDir, "-maxdepth", "1", "-type", "f", "(", "-iname", "*.png", "-o", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.gif", "-o", "-iname", "*.webp", ")"]
        stdout: StdioCollector {
            onStreamFinished: {
                wallpaperProc.entries = text.split("\n").filter(l => l.length > 0).map(l => ({
                            path: l,
                            name: l.slice(l.lastIndexOf("/") + 1)
                        })).sort((a, b) => a.name.localeCompare(b.name));
            }
        }
    }
}
