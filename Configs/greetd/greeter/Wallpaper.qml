import QtQuick
import Quickshell.Io

// Reads a fixed, root-owned, world-readable snapshot synced by
// `aphotic greeter sync` (commands/cmd_greeter.sh) -- the greeter user has
// no access to any real user's ~/.config/awww/current-wallpaper. Renders a
// flat Colours.background fill if the snapshot hasn't been synced yet
// (fresh install) or fails to load, rather than erroring.
Item {
    id: root

    readonly property string _path: "/etc/aphotic/greeter/wallpaper.png"
    property int _generation: 0

    Image {
        id: img
        anchors.fill: parent
        // Same cache-busting trick as the live shell's Wallpapers.qml --
        // `aphotic greeter sync` overwrites this same path in place, and a
        // literal unchanged source string gives Qt Quick no reason to
        // re-read it from disk once already loaded.
        source: root._generation > 0 ? `file://${root._path}?g=${root._generation}` : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: status === Image.Ready
    }

    Rectangle {
        anchors.fill: parent
        z: -1
        color: Colours.background
    }

    FileView {
        id: watcher
        path: root._path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._generation += 1
    }

    // watchChanges/onFileChanged alone was observed unreliable for this
    // exact "external process rewrites the same path" case on the live
    // shell's own Colours.qml (see that tree's Colours.qml header comment)
    // -- polling sidesteps the same quirk here too.
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: watcher.reload()
    }
}
