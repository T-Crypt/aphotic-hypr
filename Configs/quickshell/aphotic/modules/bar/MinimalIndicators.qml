pragma ComponentBehavior: Bound

import "components"
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root

    property color colour: Colours.palette.m3primary
    property Item hoveredEntry: null

    implicitWidth: Settings.barHorizontal ? icons.implicitWidth : Settings.barInnerWidth
    implicitHeight: Settings.barHorizontal ? Settings.barInnerWidth : icons.implicitHeight

    HoverPill {
        container: icons
        hoveredEntry: root.hoveredEntry
        thickness: Settings.barHorizontal ? root.height : root.width
    }

    HoverHandler {
        id: rowHover

        onPointChanged: {
            if (!rowHover.hovered)
                return;
            const local = root.mapToItem(icons, rowHover.point.position.x, rowHover.point.position.y);
            root.hoveredEntry = BarHit.nearestAt(icons, local.x, local.y);
        }
        onHoveredChanged: {
            if (!rowHover.hovered)
                root.hoveredEntry = null;
        }
    }

    RowLayout {
        id: icons

        anchors.centerIn: parent
        spacing: Tokens.spacing.small

        // Toggle-type indicators only (things a user turns on/off) -- not
        // continuous status readouts like wifi/battery, those stay in the
        // full StatusIcons cluster. Hidden (opacity 0, but still present/
        // hoverable) when inactive, dimmed on hover, full opacity when
        // active, per the Omarchy reference. DND is the only real toggle
        // this codebase has today; more (night light, screen-recording
        // indicator, ...) can be added here later without redesigning this.
        MinimalIndicatorIcon {
            visible: Settings.minimalShowDnd
            active: Settings.dndEnabled
            icon: "do_not_disturb_on"
            colour: root.colour
            onClicked: Settings.dndEnabled = !Settings.dndEnabled
        }
    }

    component MinimalIndicatorIcon: Item {
        id: item

        required property bool active
        required property string icon
        property color colour: Colours.palette.m3primary
        signal clicked

        implicitWidth: glyph.implicitWidth
        implicitHeight: glyph.implicitHeight

        opacity: item.active ? 1 : (hoverHandler.hovered ? 0.5 : 0)

        Behavior on opacity {
            Anim {}
        }

        HoverHandler {
            id: hoverHandler
        }

        MaterialIcon {
            id: glyph
            text: item.icon
            fill: item.active ? 1 : 0
            color: item.colour
        }

        StateLayer {
            anchors.fill: parent
            radius: Tokens.rounding.full
            onClicked: item.clicked()
        }
    }
}
