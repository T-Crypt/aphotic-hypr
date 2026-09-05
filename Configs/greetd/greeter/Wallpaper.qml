import QtQuick

// Reads a fixed, root-owned, world-readable snapshot synced by
// `aphotic greeter sync` (commands/cmd_greeter.sh) -- the greeter user has
// no access to any real user's ~/.config/awww/current-wallpaper. Renders a
// flat Colours.background fill if the snapshot hasn't been synced yet
// (fresh install) or fails to load, rather than erroring.
Item {
    id: root

    Image {
        id: img
        anchors.fill: parent
        source: "file:///etc/aphotic/greeter/wallpaper.png"
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
}
