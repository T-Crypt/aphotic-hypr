pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Directory-per-theme wallpaper sets following themes/THEME_SPEC.md:
// ~/.config/awww/<theme>/theme.toml + wallpapers alongside it. The
// filesystem is the theme registry (no separate index file) -- adding a
// theme is just making a new folder. State (which theme, which wallpaper
// within it) persists to ~/.local/state/aphotic/theme.json so SUPER+W-style
// rotation resumes where it left off instead of always restarting at
// wallpaper #1, and re-entering a theme doesn't lose your place in it.
Singleton {
    id: root

    readonly property string awwwDir: `${Quickshell.env("HOME")}/.config/awww`
    readonly property string statePath: `${Quickshell.env("HOME")}/.local/state/aphotic/theme.json`

    // Each entry: { name, displayName, description, engineName, scheme, contrast,
    // backend, palette, colorscheme, style, papirusColor, defaultWallpaper,
    // wallpapers: [...] }
    property list<var> themes: []
    property string activeTheme: ""
    property string activeWallpaper: ""
    readonly property var activeThemeInfo: themes.find(t => t.name === activeTheme) ?? null
    readonly property list<string> wallpapersInActiveTheme: activeThemeInfo?.wallpapers ?? []
    readonly property bool ready: _scanned && _stateLoaded

    property bool _scanned: false
    property bool _stateLoaded: false
    property bool _writePending: false

    function themeInfo(themeName: string): var {
        return themes.find(t => t.name === themeName) ?? null;
    }

    // Deliberately minimal: themes/THEME_SPEC.md's theme.toml is flat
    // ([section] headers, key = "value"/bool/number pairs, no arrays-of-
    // tables or multi-line strings), so a purpose-built line parser here
    // avoids pulling in a real TOML library for a handful of fields.
    function _parseFlatToml(text: string): var {
        const result = {};
        let section = "";
        for (const rawLine of text.split("\n")) {
            const line = rawLine.trim();
            if (!line || line.startsWith("#"))
                continue;
            const sectionMatch = line.match(/^\[([\w.]+)\]$/);
            if (sectionMatch) {
                section = sectionMatch[1];
                if (!result[section])
                    result[section] = {};
                continue;
            }
            const kvMatch = line.match(/^([\w-]+)\s*=\s*(.+)$/);
            if (!kvMatch)
                continue;
            const key = kvMatch[1];
            let value = kvMatch[2].trim();
            if (value.startsWith('"') && value.endsWith('"'))
                value = value.slice(1, -1);
            else if (value === "true")
                value = true;
            else if (value === "false")
                value = false;
            else if (/^-?\d+(\.\d+)?$/.test(value))
                value = parseFloat(value);

            if (section)
                result[section][key] = value;
            else
                result[key] = value;
        }
        return result;
    }

    // The actual apply (wallust + awww, see Wallpapers.setWallpaper) ends
    // with Colours.qml getting rewritten -- and Quickshell hot-reloads its
    // *entire* scene graph on any watched QML file changing, Colours.qml
    // included (see cmd_reload.sh's own comment on this). That reload is
    // the expensive, visible part, well past what a debounce inside
    // Wallpapers.qml alone can smooth over. Picking themes in quick
    // succession -- clicking through the grid, or holding next/prev --
    // used to kick off one full reload per click, and a second click
    // landing mid-reload is exactly the "glitchy" symptom reported.
    // Debouncing the heavy half here means N rapid picks collapse into
    // one reload for whichever theme the user actually settles on --
    // activeTheme/activeWallpaper (and so the grid's own highlight) still
    // update immediately below, every time, so clicking itself never
    // feels delayed.
    property var _pendingApply: null

    function setTheme(themeName: string, wallpaperFile: string): void {
        const info = themeInfo(themeName);
        if (!info || info.wallpapers.length === 0)
            return;

        const file = wallpaperFile && info.wallpapers.includes(wallpaperFile) ? wallpaperFile : (info.defaultWallpaper ?? info.wallpapers[0]);
        root.activeTheme = themeName;
        root.activeWallpaper = file;
        root._saveState();

        root._pendingApply = {
            themeName: themeName,
            file: file,
            info: info
        };
        applyDebounce.restart();
    }

    Timer {
        id: applyDebounce
        interval: 200
        onTriggered: {
            const p = root._pendingApply;
            if (!p)
                return;
            root._pendingApply = null;
            const fullPath = `${root.awwwDir}/${p.themeName}/${p.file}`;
            Wallpapers.setWallpaper(fullPath, p.info.backend ?? "", p.info.palette ?? "", p.info.colorscheme ?? "", p.info.style ?? "", p.info.papirusColor ?? "", p.info.iconTheme ?? "", p.info.cursorTheme ?? "", p.info.gtkTheme ?? "", p.info.engineName ?? "", p.info.scheme ?? "", p.info.contrast ?? "");
        }
    }

    function setWallpaperInActiveTheme(file: string): void {
        setTheme(root.activeTheme, file);
    }

    function _stepWallpaper(direction: int): void {
        const wallpapers = root.wallpapersInActiveTheme;
        if (wallpapers.length === 0)
            return;
        const idx = wallpapers.indexOf(root.activeWallpaper);
        const next = (idx === -1 ? 0 : (idx + direction + wallpapers.length) % wallpapers.length);
        setWallpaperInActiveTheme(wallpapers[next]);
    }

    function nextWallpaper(): void {
        _stepWallpaper(1);
    }

    function previousWallpaper(): void {
        _stepWallpaper(-1);
    }

    function randomWallpaper(): void {
        const wallpapers = root.wallpapersInActiveTheme;
        if (wallpapers.length === 0)
            return;
        const idx = Math.floor(Math.random() * wallpapers.length);
        setWallpaperInActiveTheme(wallpapers[idx]);
    }

    function _saveState(): void {
        root._writePending = true;
        stateWriter.setText(JSON.stringify({
            theme: root.activeTheme,
            wallpaper: root.activeWallpaper
        }, null, 2));
    }

    function _applyLoadedState(): void {
        if (!root._scanned)
            return;
        if (root.themes.length === 0) {
            root._stateLoaded = true;
            return;
        }

        let theme = root.activeTheme;
        let wallpaper = root.activeWallpaper;
        if (!theme || !root.themes.some(t => t.name === theme)) {
            theme = root.themes[0].name;
            wallpaper = "";
        }

        const info = themeInfo(theme);
        root.activeTheme = theme;
        root.activeWallpaper = (info && info.wallpapers.includes(wallpaper)) ? wallpaper : (info?.defaultWallpaper ?? info?.wallpapers[0] ?? "");
        root._stateLoaded = true;
    }

    FileView {
        id: stateFile

        path: root.statePath
        watchChanges: true
        onLoaded: {
            if (root._writePending) {
                root._writePending = false;
                return;
            }
            try {
                const data = JSON.parse(text());
                root.activeTheme = data.theme ?? "";
                root.activeWallpaper = data.wallpaper ?? "";
            } catch (e) {
                // No state file yet, or malformed -- fall back to the
                // first scanned theme once scanning finishes.
            }
            root._applyLoadedState();
        }
        onLoadFailed: error => {
            root._applyLoadedState();
        }
    }

    // watchChanges above relies on an OS-level file watch that does not
    // reliably survive this path being replaced out from under it -- the
    // CLI (`aphotic theme`/`aphotic wallpaper -f`, see cmd_theme.sh's
    // _aphotic_theme_write_state) always writes via a temp file + atomic
    // rename onto this exact path, and after the first such rename the
    // watch stops firing for any later one, so a second `aphotic
    // wallpaper -f` in the same shell session silently stopped updating
    // activeTheme/activeWallpaper (and so the Settings panel) until the
    // whole shell was restarted. Polling is the only mechanism this repo
    // controls that survives repeated external rewrites of the same
    // path -- the file is a few bytes, so re-reading it every second is
    // free, and reload() on unchanged content is a no-op (same values
    // back into the same properties).
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: stateFile.reload()
    }

    FileView {
        id: stateWriter

        path: root.statePath
        printErrors: false
    }

    Process {
        id: mkStateDir
        command: ["mkdir", "-p", `${Quickshell.env("HOME")}/.local/state/aphotic`]
        onExited: stateFile.reload()
    }

    // Two-pass scan: first list every theme directory, then read each
    // one's wallpapers + theme.toml. Kept as one shell pipeline (rather
    // than N separate Process objects, one per theme) since the theme
    // count is small and static per-scan.
    Process {
        id: scanProc

        command: ["sh", "-c", `for d in "${root.awwwDir}"/*/; do name=$(basename "$d"); printf 'THEME\\t%s\\n' "$name"; find "$d" -maxdepth 1 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' -o -iname '*.webp' \\) -printf 'WALL\\t%f\\n'; if [ -f "$d/theme.toml" ]; then printf 'TOML_BEGIN\\n'; cat "$d/theme.toml"; printf 'TOML_END\\n'; fi; done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const themeList = [];
                let current = null;
                let tomlLines = null;

                for (const line of text.split("\n")) {
                    if (tomlLines !== null) {
                        if (line === "TOML_END") {
                            if (current)
                                current._tomlText = tomlLines.join("\n");
                            tomlLines = null;
                        } else {
                            tomlLines.push(line);
                        }
                        continue;
                    }

                    if (line === "TOML_BEGIN") {
                        tomlLines = [];
                        continue;
                    }

                    const tab = line.indexOf("\t");
                    if (tab === -1)
                        continue;
                    const tag = line.slice(0, tab);
                    const value = line.slice(tab + 1);

                    if (tag === "THEME") {
                        current = {
                            name: value,
                            wallpapers: [],
                            _tomlText: ""
                        };
                        themeList.push(current);
                    } else if (tag === "WALL" && current) {
                        current.wallpapers.push(value);
                    }
                }

                root.themes = themeList.map(t => {
                    const toml = t._tomlText ? root._parseFlatToml(t._tomlText) : {};
                    return {
                        name: t.name,
                        displayName: toml.theme?.display_name ?? t.name,
                        description: toml.theme?.description ?? "",
                        engineName: toml.engine?.name ?? "",
                        scheme: toml.engine?.scheme ?? "",
                        contrast: toml.engine?.contrast ?? "",
                        backend: toml.engine?.backend ?? "",
                        palette: toml.engine?.palette ?? "",
                        colorscheme: toml.engine?.colorscheme ?? "",
                        style: toml.engine?.style ?? "",
                        papirusColor: toml.icons?.papirus_color ?? "",
                        iconTheme: toml.icons?.icon_theme ?? "",
                        cursorTheme: toml.icons?.cursor_theme ?? "",
                        gtkTheme: toml.gtk?.theme ?? "",
                        defaultWallpaper: toml.wallpaper?.default ?? (t.wallpapers[0] ?? ""),
                        wallpapers: t.wallpapers.sort()
                    };
                }).filter(t => t.wallpapers.length > 0).sort((a, b) => a.name.localeCompare(b.name));

                root._scanned = true;
                root._applyLoadedState();
            }
        }
    }

    Component.onCompleted: {
        mkStateDir.running = true;
        scanProc.running = true;
    }
}
