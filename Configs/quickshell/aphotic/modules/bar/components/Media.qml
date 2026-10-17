pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

StyledRect {
    id: root

    property QtObject _sonarTarget: Loader {
        active: Settings.sonarEnabled
        sourceComponent: EchoTarget {
            target: root
            targetId: "core:bar/media"
            label: qsTr("Media")
            action: ""
            bindDescription: ""
            plugin: ""
            eligible: true
        }
    }

    readonly property color colour: Colours.signalTertiaryOnSurface

    color: "transparent"
    radius: Tokens.rounding.full

    readonly property bool active: Players.active !== null

    clip: true
    implicitWidth: active ? (Settings.barHorizontal ? icon.implicitHeight + Tokens.padding.small * 2 : Settings.barInnerWidth) : 0
    implicitHeight: active ? (Settings.barHorizontal ? Settings.barInnerWidth : icon.implicitHeight + Tokens.padding.small * 2) : 0
    visible: implicitHeight > 0

    Behavior on implicitHeight {
        Anim {}
    }

    // Right click = "open the player". Focuses the player's own window if
    // one is open (same mechanism WindowItem.qml's launcher focus uses),
    // otherwise launches it fresh via its real desktop entry, matched by
    // name from the same source the launcher's own app search reads. Not
    // a hardcoded per-app command table, so any MPRIS player with a
    // matching entry works the same way.
    function openPlayer(): void {
        const identity = Players.getIdentity(root.active ? Players.active : null);
        if (!identity)
            return;

        const win = Hypr.toplevels.values.find(t => {
            const cls = (t.lastIpcObject?.class ?? "").toLowerCase();
            return cls.length > 0 && (cls.includes(identity.toLowerCase()) || identity.toLowerCase().includes(cls));
        });
        if (win) {
            WindowList.focus(win.address);
            return;
        }

        const entry = DesktopEntries.applications.values.find(a => a.name.toLowerCase() === identity.toLowerCase() || a.name.toLowerCase().includes(identity.toLowerCase()));
        if (entry) {
            entry.execute();
            return;
        }

        Toaster.toast(qsTr("Couldn't open %1").arg(identity), qsTr("No running window or installed app found"), "error");
    }

    Interact {
        radius: root.radius
        disabled: !Players.active?.canTogglePlaying
        onClicked: Players.active?.togglePlaying()
    }

    // Interact above only ever accepts its own default LeftButton (see
    // components/Interact.qml -- it's a MouseArea with no
    // acceptedButtons override), so right-click reaches nothing today.
    // A separate MouseArea limited to RightButton catches it without
    // touching Interact's own left-click toggle behavior at all.
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
