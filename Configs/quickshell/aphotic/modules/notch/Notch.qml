pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.config
import qs.components
import qs.services

StyledRect {
    id: root

    // Which edge the bar is docked to, and which way this has to open to
    // get away from it. Supplied by NotchWindow, which anchors the layer
    // surface to the same edge.
    property bool dockHorizontal: true
    property bool growsPositive: true

    // Processes is the base shell's tile and is the only one this file
    // knows the name of: the notch ships with the base layer, so a plain
    // install has exactly one tile and no switcher at all (see
    // `switchable`). Every other tile is a plugin's notch surface,
    // supplied by PluginRegistry and gated by that plugin's own manifest
    // -- its profile layer enabled AND the plugin installed and enabled.
    // Neither condition met means the tile is absent, not present and
    // empty. Adding, removing or rotating a tile is a plugin install,
    // with no edit here. See docs/PLUGIN_LAYER_MODEL.md.
    readonly property var pluginTiles: PluginRegistry.surfacesFor("notch")

    readonly property var tiles: [
        {
            plugin: "",
            id: "processes",
            icon: "monitoring",
            label: qsTr("Processes"),
            componentUrl: ""
        }
    ].concat(root.pluginTiles)

    // A base install has one tile, so there is nothing to switch between:
    // the name stops being a button and the switcher strip is gone
    // entirely rather than sitting there as a single dead segment.
    readonly property bool switchable: root.tiles.length > 1

    readonly property var activeTile: root.tiles.find(t => t.id === root.shownTileId) ?? null

    onTilesChanged: {
        if (!root.tiles.some(t => t.id === root.shownTileId))
            root.shownTileId = "processes";
        if (root.tileId !== "" && !root.tiles.some(t => t.id === root.tileId))
            root.tileId = "processes";
    }
    readonly property bool processesLive: root.expanded && root.shownTileId === "processes"

    // A plugin tile may expose `property bool attention` to say it has
    // something the user needs to act on. NotchBody reads that duck-typed
    // off whichever tiles happen to be loaded, so the collapsed strip can
    // show that a tile is asking for attention without this file knowing
    // what any of them are about.
    readonly property var attentionIds: body.attentionIds
    readonly property bool attention: root.attentionIds.length > 0

    property string tileId: ""
    readonly property bool expanded: root.tileId !== ""

    // Which tile the expanded body is BUILT for, kept latched past a
    // collapse so the body still reports a real implicitHeight while the
    // close animation plays -- reading it off `tileId` instead would
    // collapse the target to zero on the first frame and cut the
    // animation short. Same reasoning as popouts/Wrapper.qml's
    // showContent.
    property string shownTileId: "processes"

    readonly property real contentWidth: Config.notch.expandedWidth - Tokens.padding.large * 2

    function cycle(): void {
        if (root.expanded && !root.switchable)
            return;
        const i = root.tiles.findIndex(t => t.id === root.tileId);
        root.tileId = root.tiles[(i + 1) % root.tiles.length].id;
    }

    function collapse(): void {
        root.tileId = "";
    }

    onTileIdChanged: {
        if (root.tileId !== "")
            root.shownTileId = root.tileId;
    }

    // ---- Geometry -------------------------------------------------------
    //
    // Everything is expressed against the docked edge: `along` runs beside
    // it, `grow` away from it. The open panel is the same rectangle in all
    // four orientations, so only which of the two axes carries which
    // progress changes.
    readonly property real collapsedAlong: Config.notch.collapsedWidth
    readonly property real collapsedThick: Config.notch.collapsedHeight
    readonly property real collapsedW: root.dockHorizontal ? root.collapsedAlong : root.collapsedThick
    readonly property real collapsedH: root.dockHorizontal ? root.collapsedThick : root.collapsedAlong

    // Springs to the shown tile's size, so switching tiles settles into
    // the new height instead of stepping to it. Bound to the body, which
    // lays out at a constant contentWidth -- nothing here feeds back into
    // the enclosing PanelWindow's geometry.
    property real panelHeight: Math.min(body.implicitHeight + Tokens.padding.large * 2, Config.notch.maxHeight)

    Behavior on panelHeight {
        SpringAnimation {
            spring: 4
            damping: 0.7
            mass: 0.9
            epsilon: 0.25
        }
    }

    // One spring drives the whole open: the surface's growth, the reveal
    // of the body behind the clip, and the body's settle offset. There is
    // no dwell timer and no reveal delay on this path -- content arrives
    // when the geometry has made room for it, which is a fact about the
    // spring rather than a countdown running beside it.
    property real openProgress: root.expanded ? 1 : 0

    Behavior on openProgress {
        SpringAnimation {
            spring: 4
            damping: 0.62
            mass: 0.9
            // Unit-range property, so the pixel-scale epsilon the capsule
            // uses would stop this a quarter of the way from its target.
            epsilon: 0.005
        }
    }

    // The growth axis keeps the spring's overshoot -- that bounce out from
    // the edge is the motion. The along axis is clamped: a sideways bounce
    // is noise, and it is the axis with the tightest room inside the
    // static surface.
    readonly property real growT: Math.max(0, root.openProgress)
    readonly property real alongT: Math.min(1, root.growT)
    readonly property real reveal: Math.max(0, Math.min(1, (root.alongT - 0.35) / 0.45))

    width: root.collapsedW + (Config.notch.expandedWidth - root.collapsedW) * (root.dockHorizontal ? root.alongT : root.growT)
    height: root.collapsedH + (root.panelHeight - root.collapsedH) * (root.dockHorizontal ? root.growT : root.alongT)

    // Interpolated rather than animated: NOT Tokens.rounding.full for the
    // collapsed strip, because that is 999999, and animating it down to a
    // real radius keeps the value above width/2 (where every value renders
    // identically) until the last few frames, then drops through the whole
    // visible range at once.
    radius: root.collapsedThick / 2 + (Tokens.rounding.extraLarge - root.collapsedThick / 2) * root.alongT
    color: Colours.tPalette.m3surfaceContainer

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Colours.palette.m3shadow
        shadowOpacity: 0.5
        shadowBlur: 0.5
        shadowVerticalOffset: 2
    }

    LazyLoader {
        active: root.processesLive

        ProcessUsageWatch {}
    }

    // Gated here rather than mounted inside NotchProcessTile: the tile
    // outlives a collapse (shownTileId latches so the body still reports a
    // height through the shrink), so a watch owned by the tile would keep
    // polling for as long as Processes was the last tile visited. Both
    // watches hang off the same gate for that reason.
    LazyLoader {
        active: root.processesLive

        SystemUsageWatch {
            fast: true
        }
    }

    // Faded rather than flipped straight to invisible: the click that
    // opens the notch starts a ripple that runs 600ms, longer than the
    // open, so hiding this the instant `expanded` flips cut the ripple off
    // mid-sweep and read as a flash under the growing surface.
    StateLayer {
        radius: root.radius
        disabled: root.expanded
        visible: opacity > 0
        opacity: root.expanded ? 0 : 1
        onClicked: root.cycle()

        Behavior on opacity {
            Anim { type: Anim.FastEffects }
        }
    }

    Item {
        anchors.fill: parent
        // Hard guarantee, not decoration: the window masks input to this
        // item's bounds, so anything a child renders outside them is both
        // visually loose and dead to the pointer. Clipping turns that
        // class of bug into a visible truncation instead of content
        // sliding off-screen, and it is what wipes the body out from the
        // docked edge as the surface grows.
        clip: true

        DepthGradient {
            anchors.fill: parent
            radius: root.radius
            baseColour: root.color
            strength: 0.05
        }

        // The collapsed strip's own footprint, pinned at the docked edge
        // so the idle content stays put while the surface grows past it.
        Item {
            width: root.dockHorizontal ? parent.width : root.collapsedThick
            height: root.dockHorizontal ? root.collapsedThick : parent.height
            x: root.dockHorizontal ? 0 : (root.growsPositive ? 0 : parent.width - width)
            y: root.dockHorizontal ? (root.growsPositive ? 0 : parent.height - height) : 0

            NotchIdleStrip {
                anchors.centerIn: parent
                stacked: !root.dockHorizontal
                attention: root.attention
                visible: opacity > 0
                opacity: 1 - Math.min(1, root.alongT / 0.3)
            }
        }

        NotchBody {
            id: body

            width: root.contentWidth
            height: implicitHeight

            // Along the docked edge the body is centred, so the surface
            // reads as opening around it. Away from the edge it is pinned,
            // so the clip wipes it out from under the bar rather than
            // sliding it in from off-screen; the remaining travel is a
            // short settle, not an entrance.
            readonly property real enter: (1 - root.reveal) * Tokens.spacing.medium
            readonly property real pad: Tokens.padding.large

            x: root.dockHorizontal ? (parent.width - width) / 2 : (root.growsPositive ? pad + enter : parent.width - width - pad - enter)
            y: root.dockHorizontal ? (root.growsPositive ? pad + enter : parent.height - height - pad - enter) : (parent.height - height) / 2

            tiles: root.tiles
            pluginTiles: root.pluginTiles
            switchable: root.switchable
            expanded: root.expanded
            shownTileId: root.shownTileId
            activeTile: root.activeTile

            visible: opacity > 0
            opacity: root.reveal

            onCycled: root.cycle()
            onDismissed: root.collapse()
            onPicked: id => root.tileId = id
        }

        // Last child, so it draws over the depth gradient rather than
        // under it: a hairline is all that separates an opaque surface
        // from an opaque backdrop of nearly the same tone.
        StyledRect {
            anchors.fill: parent
            radius: root.radius
            color: "transparent"
            border.width: 1
            border.color: Colours.palette.m3outlineVariant
        }
    }
}
