pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.services
import qs.utils

Item {
    id: root

    required property var bar
    required property Brightness.Monitor monitor
    property color colour: Colours.palette.m3primaryOnSurface

    readonly property string windowTitle: {
        const title = Hypr.activeToplevel?.title;
        if (!title)
            return qsTr("Desktop");
        if (Config.bar.activeWindow.compact) {
            // " - " (standard hyphen), " — " (em dash), " – " (en dash)
            const parts = title.split(/\s+[\-\u2013\u2014]\s+/);
            if (parts.length > 1)
                return parts[parts.length - 1].trim();
        }
        return title;
    }

    // How much room is left for this entry along the bar's length, once
    // every sibling entry's own along-axis extent is subtracted out.
    readonly property int maxExtent: {
        const otherModules = bar.children.filter(c => c.entryId && c.item !== this && c.entryId !== "spacer");
        const otherSize = otherModules.reduce((acc, curr) => acc + (Settings.barVertical ? (curr.item.nonAnimWidth ?? curr.width) : (curr.item.nonAnimHeight ?? curr.height)), 0);
        const barSize = Settings.barVertical ? bar.width : bar.height;
        // Length - 2 cause repeater counts as a child
        return barSize - otherSize - bar.spacing * (bar.children.length - 1) - bar.vPadding * 2;
    }
    property Title current: text1

    clip: true
    implicitWidth: Settings.barVertical ? icon.implicitWidth + Tokens.spacing.small + current.implicitWidth + Tokens.padding.small * 2 : Settings.barInnerWidth
    implicitHeight: Settings.barVertical ? Settings.barInnerWidth : icon.implicitHeight + current.implicitWidth + current.anchors.topMargin + Tokens.padding.small * 2

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.full
        color: Colours.palette.m3surfaceContainerHigh
    }

    Loader {
        asynchronous: true
        anchors.fill: parent
        active: !Config.bar.activeWindow.showOnHover

        sourceComponent: MouseArea {
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onPositionChanged: {
                const popouts = root.bar.popouts;
                if (popouts.hasCurrent && popouts.currentName !== "activewindow")
                    popouts.hasCurrent = false;
            }
            onClicked: {
                const popouts = root.bar.popouts;
                if (popouts.hasCurrent) {
                    popouts.hasCurrent = false;
                } else {
                    popouts.currentName = "activewindow";
                    popouts.currentCenter = root.bar.centerAlong(root);
                    popouts.hasCurrent = true;
                }
            }
        }
    }

    MaterialIcon {
        id: icon

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Settings.barVertical ? 0 : Tokens.padding.small
        anchors.leftMargin: Settings.barVertical ? Tokens.padding.small : 0

        animate: true
        text: Icons.getAppCategoryIcon(Hypr.activeToplevel?.lastIpcObject.class, "desktop_windows")
        color: root.colour

        states: State {
            name: "horizontal"
            when: Settings.barVertical

            AnchorChanges {
                target: icon
                anchors.horizontalCenter: undefined
                anchors.top: undefined
                anchors.left: icon.parent.left
                anchors.verticalCenter: icon.parent.verticalCenter
            }
        }
    }

    Title {
        id: text1
    }

    Title {
        id: text2
    }

    TextMetrics {
        id: metrics

        text: root.windowTitle
        font: root.Tokens.font.body.builders.small.weight(Font.Medium).letterSpacing(1.4).build()
        elide: Qt.ElideRight
        elideWidth: Settings.barVertical ? root.maxExtent - icon.width : root.maxExtent - icon.height

        onTextChanged: {
            const next = root.current === text1 ? text2 : text1;
            next.text = elidedText;
            root.current = next;
        }
        onElideWidthChanged: root.current.text = elidedText
    }

    Behavior on implicitHeight {
        Anim {}
    }

    Behavior on implicitWidth {
        Anim {}
    }

    component Title: StyledText {
        id: text

        anchors.horizontalCenter: icon.horizontalCenter
        anchors.top: icon.bottom
        anchors.topMargin: Settings.barVertical ? 0 : Tokens.spacing.small
        anchors.leftMargin: Settings.barVertical ? Tokens.spacing.small : 0

        font: metrics.font
        color: root.colour
        opacity: root.current === this ? 1 : 0
        horizontalAlignment: Text.AlignLeft

        // Horizontal mode never rotates the marquee text -- it already
        // reads left-to-right naturally, so `inverted` (which only ever
        // flipped the vertical marquee's reading direction) has nothing
        // to invert, and both transforms below collapse to identity (0
        // translate, 0 rotation). QML object literals can't live inside
        // a ternary, so the list itself is unconditional and only the
        // angle/offset are gated.
        transform: [
            Translate {
                x: Settings.barVertical ? 0 : (root.Config.bar.activeWindow.inverted ? -text.implicitWidth + text.implicitHeight : 0)
            },
            Rotation {
                angle: Settings.barVertical ? 0 : (root.Config.bar.activeWindow.inverted ? 270 : 90)
                origin.x: text.implicitHeight / 2
                origin.y: text.implicitHeight / 2
            }
        ]

        width: Settings.barVertical ? implicitWidth : implicitHeight
        height: Settings.barVertical ? implicitHeight : implicitWidth

        states: State {
            name: "horizontal"
            when: Settings.barVertical

            AnchorChanges {
                target: text
                anchors.horizontalCenter: undefined
                anchors.top: undefined
                anchors.left: icon.right
                anchors.verticalCenter: icon.verticalCenter
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
