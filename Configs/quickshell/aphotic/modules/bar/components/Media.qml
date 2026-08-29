pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

StyledRect {
    id: root

    readonly property color colour: Colours.palette.m3tertiaryOnSurface

    color: Colours.palette.m3surfaceContainerHigh
    radius: Tokens.rounding.full

    readonly property bool active: Players.active !== null

    clip: true
    implicitWidth: active ? (Settings.barHorizontal ? icon.implicitHeight + Tokens.padding.small * 2 : Settings.barInnerWidth) : 0
    implicitHeight: active ? (Settings.barHorizontal ? Settings.barInnerWidth : icon.implicitHeight + Tokens.padding.small * 2) : 0
    visible: implicitHeight > 0

    Behavior on implicitHeight {
        Anim {}
    }

    // Right click = "open the player" -- same left/right differentiation
    // AgentIndicator.qml already establishes for this bar (left = primary
    // action, right = a secondary one), but deliberately NOT that other
    // component's own "opens a static page" left-click shape: this stays
    // a real app launch/focus, not a persistent panel. Focuses the
    // player's own window if one's already open (matches WindowItem.qml's
    // launcher focus mechanism exactly), falling back to launching it
    // fresh via its real desktop entry (same source the launcher's own
    // app search reads, matched by name -- not a hardcoded per-app
    // command table, so this isn't limited to Spotify specifically; any
    // MPRIS player with a matching .desktop entry works the same way).
    function openPlayer(): void {
        const identity = Players.getIdentity(root.active ? Players.active : null);
        if (!identity)
            return;

        const win = Hypr.toplevels.values.find(t => {
            const cls = (t.lastIpcObject?.class ?? "").toLowerCase();
            return cls.length > 0 && (cls.includes(identity.toLowerCase()) || identity.toLowerCase().includes(cls));
        });
        if (win) {
            Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ address = "${win.address}" })` : `focuswindow address:${win.address}`);
            return;
        }

        const entry = DesktopEntries.applications.values.find(a => a.name.toLowerCase() === identity.toLowerCase() || a.name.toLowerCase().includes(identity.toLowerCase()));
        if (entry) {
            entry.execute();
            return;
        }

        Toaster.toast(qsTr("Couldn't open %1").arg(identity), qsTr("No running window or installed app found"), "error");
    }

    StateLayer {
        radius: root.radius
        disabled: !Players.active?.canTogglePlaying
        onClicked: Players.active?.togglePlaying()
    }

    // StateLayer above only ever accepts its own default LeftButton (see
    // components/StateLayer.qml -- it's a MouseArea with no
    // acceptedButtons override), so right-click reaches nothing today.
    // A separate MouseArea limited to RightButton catches it without
    // touching StateLayer's own left-click ripple/toggle behavior at all.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: root.openPlayer()
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        animate: true
        text: Players.active?.isPlaying ? "pause" : "play_arrow"
        fill: 1
        color: root.colour
    }
}
