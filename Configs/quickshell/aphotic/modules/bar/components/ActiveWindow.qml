pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.components.effects
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

    // Room this entry has been granted along the bar's length, handed down
    // by Bar.qml's sizing budget (see Bar.qml's contentExtent). -1 means
    // "unconstrained", for any host that doesn't run a budget.
    //
    // This used to be computed here, by summing every sibling entry's own
    // rendered width/height -- which are outputs of the very layout pass
    // this value feeds, so a long title grew the bar's reported size to
    // make room for itself and pushed every entry after it off the screen.
    // Sizing now flows strictly one way: the bar measures the screen,
    // divides it up, and tells each entry what it got.
    property real maxExtent: -1

    readonly property font titleFont: Tokens.font.body.builders.small.weight(Font.Medium).letterSpacing(1.4).build()

    readonly property real iconExtent: Settings.barHorizontal ? icon.implicitWidth : icon.implicitHeight
    // Everything except the title: the app icon and its padding always
    // survive, however crowded the bar gets.
    readonly property real baseExtent: iconExtent + Tokens.spacing.small + Tokens.padding.small * 2
    // The title at its natural, unelided width, measured by a TextMetrics
    // of its own (see naturalMetrics) rather than off `metrics`: reading
    // any property of `metrics` here would run back into `metrics`'
    // own elideWidth, which is computed FROM this value -- a real binding
    // loop that Qt breaks by freezing `demand` one evaluation short, so
    // the title ended up elided even on a bar with room to spare.
    readonly property real desiredExtent: baseExtent + naturalMetrics.advanceWidth

    property Title current: text1

    clip: true
    implicitWidth: Settings.barHorizontal ? icon.implicitWidth + Tokens.spacing.small + current.implicitWidth + Tokens.padding.small * 2 : Settings.barInnerWidth
    implicitHeight: Settings.barHorizontal ? Settings.barInnerWidth : icon.implicitHeight + current.implicitWidth + current.anchors.topMargin + Tokens.padding.small * 2

    BioluminescentGlow {
        target: background
        intensity: Hypr.activeToplevel ? DepthFx.glowIntensity : 0
    }

    StyledRect {
        id: background

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
        anchors.topMargin: Settings.barHorizontal ? 0 : Tokens.padding.small
        anchors.leftMargin: Settings.barHorizontal ? Tokens.padding.small : 0

        animate: true
        text: Icons.getAppCategoryIcon(Hypr.activeToplevel?.lastIpcObject.class, "desktop_windows")
        color: root.colour

        states: State {
            name: "horizontal"
            when: Settings.barHorizontal

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

    // Measures the title at its natural width only. Kept separate from
    // `metrics` below so that nothing which feeds `metrics.elideWidth` ever
    // reads a property of `metrics` itself.
    TextMetrics {
        id: naturalMetrics

        text: root.windowTitle
        font: root.titleFont
    }

    TextMetrics {
        id: metrics

        text: root.windowTitle
        font: root.titleFont
        elide: Qt.ElideRight
        // No budget in force -- render the title at its natural width
        // rather than eliding against a meaningless target (an elideWidth
        // of 0 elides every string down to a bare ellipsis).
        elideWidth: root.maxExtent < 0 ? naturalMetrics.advanceWidth : Math.max(20, root.maxExtent - root.baseExtent)

        onTextChanged: {
            const next = root.current === text1 ? text2 : text1;
            next.text = elidedText;
            root.current = next;
        }
        onElideWidthChanged: root.current.text = elidedText
    }

    // The along-axis resize animation lives on Bar.qml's EntryWrapper now,
    // which animates the allocation this entry was granted. Animating the
    // implicit size here as well would mean two animations racing to
    // describe the same resize.

    component Title: StyledText {
        id: text

        anchors.horizontalCenter: icon.horizontalCenter
        anchors.top: icon.bottom
        anchors.topMargin: Settings.barHorizontal ? 0 : Tokens.spacing.small
        anchors.leftMargin: Settings.barHorizontal ? Tokens.spacing.small : 0

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
                x: Settings.barHorizontal ? 0 : (root.Config.bar.activeWindow.inverted ? -text.implicitWidth + text.implicitHeight : 0)
            },
            Rotation {
                angle: Settings.barHorizontal ? 0 : (root.Config.bar.activeWindow.inverted ? 270 : 90)
                origin.x: text.implicitHeight / 2
                origin.y: text.implicitHeight / 2
            }
        ]

        width: Settings.barHorizontal ? implicitWidth : implicitHeight
        height: Settings.barHorizontal ? implicitHeight : implicitWidth

        states: State {
            name: "horizontal"
            when: Settings.barHorizontal

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
