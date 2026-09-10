pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.services

// The half of the picker that has nothing to do with how it looks: what the
// list is, which entry is being previewed, and what commit and cancel mean.
//
// All three layouts need exactly this and none of them should own a second
// copy of it -- the deferred-preview rule in particular is subtle enough to
// get wrong. Themes.setTheme() queues wallust, which rewrites Colours.qml,
// which hot-reloads the entire Quickshell scene graph. Firing that per
// scrolled-past entry is what made the strip stutter, so previews wait for
// the layout to come to rest and _commit() flushes whatever is still pending.
Item {
    id: root

    // Coverflow and dock browse within the active theme, because moving
    // between themes mid-scroll would apply a whole theme switch per step.
    // The grid sets this and browses everything.
    property bool allThemes: false

    property bool open: false

    readonly property var entries: {
        const result = [];
        if (root.allThemes) {
            for (const theme of Themes.themes) {
                for (const file of theme.wallpapers ?? [])
                    result.push(root._entry(theme.name, file));
            }
        } else {
            for (const file of Themes.wallpapersInActiveTheme)
                result.push(root._entry(Themes.activeTheme, file));
        }
        return result;
    }

    readonly property int count: root.entries.length

    readonly property int activeIndex: root.entries.findIndex(e => e.theme === Themes.activeTheme && e.file === Themes.activeWallpaper)

    signal closeRequested

    function _entry(theme: string, file: string): var {
        return {
            theme: theme,
            file: file,
            path: `${Themes.awwwDir}/${theme}/${file}`,
            isVideo: Themes.isVideo(file)
        };
    }

    // What a layout should point an Image at: the cached thumbnail once it
    // exists, the source image meanwhile. A video has no decodable source,
    // so it waits for the thumbnail rather than being handed a file Image
    // cannot read.
    function previewFor(index: int): string {
        const entry = root.entries[index];
        if (!entry)
            return "";
        const thumb = WallpaperThumbs.thumbFor(entry.path);
        if (thumb)
            return thumb;
        return entry.isVideo ? "" : `file://${entry.path}`;
    }

    // The full-resolution original, for the backdrop. Never the thumbnail --
    // the whole point of the lossless backdrop is that it is not the
    // downscaled copy the cards are drawn from.
    function fullSizeFor(index: int): string {
        const entry = root.entries[index];
        if (!entry)
            return "";
        if (entry.isVideo) {
            const poster = WallpaperThumbs.posterFor(entry.path);
            return poster ? `file://${poster}` : "";
        }
        return `file://${entry.path}`;
    }

    property string _originalTheme: ""
    property string _originalWallpaper: ""
    property int _previewIndex: -1

    // Captured on open so Escape can put back exactly what was there,
    // including which theme it belonged to.
    function begin(): void {
        root.cancelPreview();
        root._originalTheme = Themes.activeTheme;
        root._originalWallpaper = Themes.activeWallpaper;
    }

    function queuePreview(index: int): void {
        root._previewIndex = index;
        previewDelay.restart();
    }

    function cancelPreview(): void {
        previewDelay.stop();
        root._previewIndex = -1;
    }

    function applyPreview(): void {
        previewDelay.stop();
        const index = root._previewIndex;
        root._previewIndex = -1;
        root._apply(index);
    }

    function _apply(index: int): void {
        const entry = root.entries[index];
        if (!entry)
            return;
        if (entry.theme === Themes.activeTheme && entry.file === Themes.activeWallpaper)
            return;
        Themes.setTheme(entry.theme, entry.file);
    }

    // The entry being chosen is whatever the layout is heading for, which is
    // not necessarily _previewIndex: a layout clears that while it is still
    // moving. Layouts pass their own focused index in rather than letting
    // this read a stale one.
    function commit(index: int): void {
        previewDelay.stop();
        root._previewIndex = -1;
        root._apply(index);
        root.closeRequested();
    }

    // Closing without having moved used to re-apply the wallpaper that was
    // already active, spending a full wallust + awww + sddm-sync run to
    // arrive back where it started.
    function revertAndClose(): void {
        root.cancelPreview();
        if (root._originalWallpaper && (root._originalTheme !== Themes.activeTheme || root._originalWallpaper !== Themes.activeWallpaper))
            Themes.setTheme(root._originalTheme, root._originalWallpaper);
        root.closeRequested();
    }

    Timer {
        id: previewDelay

        interval: Tokens.anim.durations.expressiveSlowEffects
        onTriggered: root.applyPreview()
    }
}
