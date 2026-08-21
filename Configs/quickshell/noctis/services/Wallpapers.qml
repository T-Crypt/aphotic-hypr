pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Real convention already used by every wallpaper-setting script in this
// repo (rofi-wallpaper.sh, thunar_wall.py, wallswitcher.py): they all copy
// the chosen image to ~/.config/awww/wallpaper.rofi as the "current
// wallpaper" marker -- not a text file, an actual copy of the image
// itself.
Singleton {
    id: root

    readonly property string path: `${Quickshell.env("HOME")}/.config/awww/wallpaper.rofi`
    // Query-string cache-bust: an Image with a `source` URL that never
    // changes won't notice the file's bytes changed underneath it
    // (wallpaper.rofi is the same path every time, just re-copied).
    // Bumping this on every FileView change forces a real reload.
    property int generation: 0
    readonly property string current: generation >= 0 ? `file://${path}?g=${generation}` : ""

    FileView {
        path: root.path
        watchChanges: true
        onFileChanged: root.generation++
    }

    function setWallpaper(path: string): void {
        Quickshell.execDetached(["awww", "img", path, "--transition-type", "wipe", "--transition-angle", "30", "--transition-step", "90"]);
        Quickshell.execDetached(["cp", path, root.path]);
    }
}
