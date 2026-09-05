pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property var item
    // Externally computed by DockBar's icon row (distance-based falloff
    // from the hovered pointer position) -- kept as a plain input here
    // rather than each icon owning its own hover detection, since the
    // falloff needs every icon's position relative to ONE shared cursor
    // position at once.
    property real magnifyScale: 1
    // Which edge a magnified icon should grow away from -- Item.Bottom
    // for a bottom-anchored dock (icons grow upward, matching macOS),
    // Item.Top for top-anchored, Item.Center for a side placement.
    property int growOrigin: Item.Center
    // Off when the dock row is showing its shared gliding HoverPill
    // instead: that pill is the same circle at the same opacity as this
    // icon's own hover layer, so leaving both on would double the tint
    // and hide the glide entirely.
    property bool showHover: true

    implicitWidth: Settings.barInnerWidth
    implicitHeight: Settings.barInnerWidth

    scale: magnifyScale
    transformOrigin: growOrigin
    z: Math.round(magnifyScale * 100)

    Behavior on scale {
        Anim { type: Anim.StandardSmall }
    }

    StateLayer {
        anchors.fill: parent
        radius: Tokens.rounding.full
        stateOpacity: root.showHover && containsMouse ? 0.08 : 0
        onClicked: {
            if (root.item.windows.length > 0)
                WindowList.focus(root.item.windows[0].address);
            else
                root.item.entry?.execute();
        }
    }

    AppIcon {
        anchors.centerIn: parent
        name: root.item.iconName
        appClass: root.item.iconKeys
        size: parent.width * 0.6
        fontStyle: Tokens.font.icon.large
        colour: Colours.palette.m3onSurface
    }

    Rectangle {
        visible: root.item.running
        width: 5
        height: 5
        radius: 2.5
        color: Colours.palette.m3primary
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
    }
}
