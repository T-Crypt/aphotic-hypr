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
    property string _stamp: ""

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
        // Only a real change to the file advances the generation. The poll
        // below re-reads this same path every second, and treating every one
        // of those reloads as a change re-decoded the full-screen image once
        // a second, which reads as the login screen blinking.
        onLoaded: {
            const bytes = new Uint8Array(watcher.data());
            const mid = bytes.length >> 1;
            const stamp = bytes.length + ":" + Array.prototype.join.call(bytes.subarray(mid, mid + 32), ",");
            if (stamp !== root._stamp) {
                root._stamp = stamp;
                root._generation += 1;
            }
        }
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
