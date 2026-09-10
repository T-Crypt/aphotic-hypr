// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors
//
// Disk-backed thumbnail and poster cache for the wallpaper pickers.

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Every picker used to point a plain Image at the full-resolution source and
// lean on sourceSize to downscale at decode time. That decode still reads and
// parses the whole file, so a theme of 4K wallpapers cost hundreds of
// megabytes of decode work to draw a grid of 120px tiles, and scrolling a
// large library stuttered on cold tiles.
//
// This hands out paths into ~/.cache/aphotic/wallpaper-thumbs instead, and
// generates what is missing in batches. Posters are the same idea for a
// different reason: a video wallpaper has no still for wallust to read a
// palette from or for `awww img` to display, so one extracted frame stands in
// for it everywhere the rest of the shell expects an image.
Singleton {
    id: root

    readonly property string script: {
        const dotsDir = Quickshell.env("APHOTIC_DOTS_DIR") || `${Quickshell.env("HOME")}/Aphotic-Hypr`;
        return `${dotsDir}/Configs/.local/lib/aphotic/wallpaper_thumbs.py`;
    }

    // Bumped whenever a batch lands. thumbFor()/posterFor() read it so that
    // a binding written as `source: WallpaperThumbs.thumbFor(path)`
    // re-evaluates once the file it asked for actually exists -- a plain JS
    // map lookup is invisible to the binding engine on its own.
    property int generation: 0

    signal posterReady(string source, string poster)

    property var _thumbs: ({})
    property var _posters: ({})
    // Paths handed to a running process, so a second request for the same
    // path mid-flight doesn't queue a duplicate ffmpeg run.
    property var _inFlight: ({})
    property var _thumbQueue: []
    property var _posterQueue: []

    function _queue(path: string, poster: bool): void {
        if (!path)
            return;
        const key = (poster ? "p:" : "t:") + path;
        if (root._inFlight[key])
            return;
        root._inFlight[key] = true;
        if (poster)
            root._posterQueue.push(path);
        else
            root._thumbQueue.push(path);
        flush.restart();
    }

    // Returns a file:// URL for path's thumbnail, or "" while it is still
    // being generated. Callers bind straight to this and fall back to the
    // source image for the first frame or two.
    function thumbFor(path: string): string {
        if (!path)
            return "";
        root.generation;
        const hit = root._thumbs[path];
        if (hit)
            return `file://${hit}`;
        root._queue(path, false);
        return "";
    }

    // The still image standing in for path. For an image that is the image
    // itself, so this is safe to call unconditionally.
    function posterFor(path: string): string {
        if (!path)
            return "";
        root.generation;
        const hit = root._posters[path];
        if (hit)
            return hit;
        root._queue(path, true);
        return "";
    }

    function hasPoster(path: string): bool {
        return !!root._posters[path];
    }

    // Ask for a poster and get told when it lands. setTheme() needs the real
    // path before it can run the colour engine, so it waits on this rather
    // than applying an empty source.
    function ensurePoster(path: string): void {
        if (root._posters[path])
            root.posterReady(path, root._posters[path]);
        else
            root._queue(path, true);
    }

    function _absolute(path: string): string {
        return path.startsWith("file://") ? path.slice(7) : path;
    }

    // One tick of coalescing. A grid binding two hundred delegates at once
    // would otherwise start two hundred processes; this collects the whole
    // first paint into a single run.
    Timer {
        id: flush

        interval: 16
        onTriggered: {
            if (root._thumbQueue.length > 0 && !thumbProc.running) {
                thumbProc.batch = root._thumbQueue;
                root._thumbQueue = [];
                thumbProc.command = ["python3", root.script].concat(thumbProc.batch.map(root._absolute));
                thumbProc.running = true;
            }
            if (root._posterQueue.length > 0 && !posterProc.running) {
                posterProc.batch = root._posterQueue;
                root._posterQueue = [];
                posterProc.command = ["python3", root.script, "--poster"].concat(posterProc.batch.map(root._absolute));
                posterProc.running = true;
            }
            // Anything queued while a process was already running waits for
            // the next tick rather than being dropped.
            if (root._thumbQueue.length > 0 || root._posterQueue.length > 0)
                flush.restart();
        }
    }

    Process {
        id: thumbProc

        property var batch: []

        stdout: StdioCollector {
            onStreamFinished: {
                let map = {};
                try {
                    map = JSON.parse(text);
                } catch (e) {
                    // A failed run leaves every path in the batch unresolved;
                    // the picker keeps showing full-resolution sources.
                }
                for (const src of thumbProc.batch)
                    delete root._inFlight["t:" + src];
                for (const src in map)
                    root._thumbs[src] = map[src];
                root.generation++;
            }
        }
    }

    Process {
        id: posterProc

        property var batch: []

        stdout: StdioCollector {
            onStreamFinished: {
                let map = {};
                try {
                    map = JSON.parse(text);
                } catch (e) {
                }
                for (const src of posterProc.batch)
                    delete root._inFlight["p:" + src];
                for (const src in map)
                    root._posters[src] = map[src];
                root.generation++;
                for (const src in map)
                    root.posterReady(src, map[src]);
            }
        }
    }
}
