pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.components
import qs.services
import qs.modules.bar.popouts as BarPopouts

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    required property ScreenState screenState
    readonly property BarPopouts.Wrapper popouts: popouts

    readonly property int barWidth: Settings.barInnerWidth + Math.max(Tokens.padding.small, Config.border.thickness) * 2

    WlrLayershell.namespace: "aphotic-bar"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Normal
    // barWrapper.exclusiveZone (not barWidth) -- it already accounts for
    // disabled/hiddenMode (0, e.g. the "hidden" visibility mode or the
    // Dock style, which renders nothing here at all) and autohide's thin
    // collapsed sliver vs. the full reserved width when actually shown.
    // Binding this to the bare barWidth constant instead (as it used to)
    // meant this window kept reserving full-width desktop space in both
    // of those cases even though nothing was drawn there -- a real,
    // pre-existing gap "hidden" mode already had, not something new to
    // the Dock style, just newly noticed because Dock hits it too.
    WlrLayershell.exclusiveZone: barWrapper.exclusiveZone
    color: "transparent"

    // This window is deliberately wider than the visible bar strip (see
    // implicitWidth below) to give popout flyouts room to render. Without a
    // mask, a PanelWindow accepts pointer input across its ENTIRE surface
    // regardless of what's actually drawn there -- so the ~400px of
    // transparent flyout space would silently swallow clicks meant for
    // whatever desktop window sits underneath it, on whichever edge the bar
    // is currently docked to. Masking to just the real bar strip plus the
    // flyout's own (collapses to 0x0 when no popout is open) rect keeps
    // input passthrough everywhere else.
    //
    // In "autohide" mode specifically, masking to barWrapper's own
    // (collapsed) bounds made the hover-to-reveal target a literal couple
    // of physical pixels at the exact screen edge -- technically hittable,
    // practically indistinguishable from never revealing at all. Masking
    // to hoverTarget instead (BarWrapper's always-full-size content Loader,
    // just visually clipped down by BarWrapper's own clip:true while
    // collapsed) gives hover detection the same footprint the bar will
    // actually expand to, which is what "auto-hide" is supposed to feel
    // like. Every other mode keeps masking to barWrapper's own bounds --
    // "always" is already that size anyway, and "hidden" must NOT grab the
    // wider area or it'd swallow clicks meant for whatever's underneath
    // even though the bar itself never shows.
    // flyoutItem/agentFlyoutItem now sit flush against barWrapper with
    // ZERO gap (see popouts/Wrapper.qml) rather than the previous
    // Tokens.spacing.small offset -- matching caelestia-dots/shell's own
    // popouts/ClipWrapper.qml, whose content sits at leftMargin: 0
    // against a bar-flush parent when shown. The old gap was a literal,
    // permanent dead zone in this mask: neither region below covered it,
    // so a pointer crossing it left the layer-shell surface entirely and
    // the compositor treated that pixel strip as click-through to the
    // desktop, with zero hover events delivered while transiting -- the
    // actual mechanism behind "can't reach the popout fast enough."
    // Closing the gap to zero removes the dead zone outright; an earlier
    // attempt to paper over it with a separate bridge Region (bridging a
    // gap that shouldn't have existed) was reverted once this was found.
    mask: Region {
        item: Settings.barVisibility === "autohide" ? barWrapper.hoverTarget : barWrapper

        Region {
            item: popouts.flyoutItem
        }
        Region {
            item: popouts.agentFlyoutItem
        }
    }

    anchors.top: Settings.barHorizontal ? !Settings.barPositionBottom : true
    anchors.bottom: Settings.barHorizontal ? Settings.barPositionBottom : true
    anchors.left: Settings.barHorizontal ? true : !Settings.barPositionRight
    anchors.right: Settings.barHorizontal ? true : Settings.barPositionRight

    // Wider/taller than barWidth to give the popout flyout (drawn on the
    // side of the bar strip facing away from the docked screen edge, see
    // popouts/Wrapper.qml) real surface to paint into -- Wayland
    // layer-shell surfaces clip anything outside their own bounds, a hard
    // boundary no amount of internal QML sizing can exceed. 480 (was 400,
    // then 320 before that -- each bump the same real bug: a popout's
    // real content needed more than the current budget, silently clipping
    // its right edge regardless of the popout's own implicitWidth. 400
    // fit ResourcesPopout; AgentPopout's three-tab provider row plus its
    // title-row close icon didn't fit 400) leaves real headroom for both
    // that and the drop shadow's blur bleed around the flyout's edge.
    // exclusionZone above stays pinned to barWidth so this extra space
    // doesn't reserve desktop area. Both implicit dimensions are set
    // unconditionally to the same expression -- whichever axis has both
    // opposing anchors active (the long axis, spanning the full screen
    // edge) is anchor-driven and silently ignores this value, so only the
    // other (short/thickness) axis actually honours it, in either docking
    // orientation.
    implicitWidth: barWidth + Tokens.spacing.small * 2 + 480
    implicitHeight: barWidth + Tokens.spacing.small * 2 + 480

    BarPopouts.Wrapper {
        id: popouts
        screen: root.screen
        barWidth: root.barWidth
        windowWidth: root.width
        windowHeight: root.height
        screenState: root.screenState
    }

    BarWrapper {
        id: barWrapper

        screen: root.screen
        screenState: root.screenState
        popouts: root.popouts
        fullscreen: false

        // Plain x/y/width/height, not anchors -- BarWrapper.qml's own root
        // already carries a `states: State { name: "visible"; ... }` for
        // its collapse/expand animation. Assigning a SECOND `states:`
        // array here (as this used to do, for docking) replaced that
        // internal one outright instead of merging with it -- QML list
        // properties set at an instantiation site override the
        // component's own default, they don't combine -- silently
        // breaking the auto-hide sizing and leaving barWrapper with no
        // anchors applied at all. Plain bindings avoid a second `states:`
        // entirely; self-referencing implicitWidth/implicitHeight as the
        // "not this axis" fallback is safe here since BarWrapper is a
        // plain Item, not a Layout fighting an external size.
        x: !Settings.barHorizontal && Settings.barPositionRight ? root.width - width : 0
        y: Settings.barHorizontal && Settings.barPositionBottom ? root.height - height : 0
        width: Settings.barHorizontal ? root.width : implicitWidth
        height: Settings.barHorizontal ? implicitHeight : root.height
    }
}
