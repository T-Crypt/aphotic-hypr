pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Deliberately self-contained -- this is a separate qs config (deployed to
// /etc/xdg/quickshell/aphotic-greeter/) run by the unprivileged `greeter`
// system user, which has no HOME/state directory to read the real
// Colours.qml's ~/.local/state/aphotic/palette.json from. Reads a small,
// flat, pre-resolved snapshot synced by `aphotic greeter sync` (see
// commands/cmd_greeter.sh) instead of replicating wallust/matugen engine
// branching here. Falls back to a fixed dark palette if the snapshot is
// missing or unparseable -- this screen must render something sane even
// before the first sync has ever run.
//
// Properties avoid a bare `onXxx` shape (textColor, not onSurface) --
// QML reserves any property identifier starting with "on" + an uppercase
// letter for signal handlers, which is also why the live shell's own
// Colours.qml prefixes these m3onSurface/m3onPrimary rather than bare.
Singleton {
    id: root

    readonly property string _snapshotPath: "/etc/aphotic/greeter/palette.json"

    property color background: "#15151a"
    property color surface: "#1f1f26"
    property color textColor: "#e5e1e9"
    property color mutedTextColor: "#c8c5d0"
    property color primary: "#a9c7ff"
    property color primaryTextColor: "#00325a"
    property color errorColor: "#ffb4ab"

    function _apply(raw: string): void {
        let data;
        try {
            data = JSON.parse(raw);
        } catch (e) {
            return;
        }
        if (!data)
            return;
        if (data.background)
            root.background = data.background;
        if (data.surface)
            root.surface = data.surface;
        if (data.textColor)
            root.textColor = data.textColor;
        if (data.mutedTextColor)
            root.mutedTextColor = data.mutedTextColor;
        if (data.primary)
            root.primary = data.primary;
        if (data.primaryTextColor)
            root.primaryTextColor = data.primaryTextColor;
        if (data.error)
            root.errorColor = data.error;
    }

    FileView {
        id: snapshot
        path: root._snapshotPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._apply(text())
    }
}
