pragma ComponentBehavior: Bound

import "components"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services
import "../../services/BarLayout.js" as BarLayout

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState

    readonly property var dockItems: WindowList.dockItems(Settings.dockPinnedApps,"",true)

    // Icon-proximity magnification falloff (macOS-style), quadratic so it
    // reads as a smooth "wave" rather than a hard-edged linear ramp.
    // Horizontal placement only -- see Settings.dockMagnification.
    function magnifyFalloff(centerPos: real): real {
        const radius = 90;
        const maxExtra = 0.6;
        const dist = Math.abs(centerPos - iconHover.point.position.x);
        if (dist >= radius)
            return 1;
        const t = 1 - dist / radius;
        return 1 + maxExtra * t * t;
    }

    // Auto-hide is content-transform-only (translate + opacity below),
    // never a window re-anchor/re-mask -- matches this repo's shared
    // popout/bar animation discipline. "No window focused" is a rough
    // proxy for "nothing to get out of the way of"; a real per-window
    // occlusion check isn't available cheaply via Hyprland's IPC.
    readonly property bool shouldShow: !Settings.dockAutoHide || !Hypr.activeToplevel || hoverHandler.hovered

    // Was entirely absent -- Dock silently lost scroll-to-volume that
    // every other bar style has (Full/Taskbar/Minimal all define this
    // identically). Real feature gap, not a design choice like Minimal's
    // deliberately sparse icon set -- fixed to match.
    function handleWheel(pos: real, angleDelta: point): void {
        if (angleDelta.y > 0)
            Audio.incrementVolume();
        else if (angleDelta.y < 0)
            Audio.decrementVolume();
    }

    implicitWidth: pill.width
    implicitHeight: pill.height
    width: Math.max(implicitWidth, hoverTarget.width)
    height: Math.max(implicitHeight, hoverTarget.height)

    // Fixed-size hover target the same footprint as the fully-shown pill,
    // always present (even while auto-hide has visually collapsed the
    // pill away) so proximity can actually reveal it again.
    Item {
        id: hoverTarget
        width: pill.implicitWidth
        height: pill.implicitHeight
    }

    HoverHandler {
        id: hoverHandler
        target: hoverTarget
    }

    // Which docked app's icon the Signal line's accent sits under: the one
    // holding the focused window, if any.
    readonly property int focusedDockIndex: root.dockItems.findIndex(d => d.windows && d.windows.some(w => w.focused))

    SignalSurface {
        id: pill

        anchors.centerIn: parent
        implicitWidth: Settings.barHorizontal ? layout.implicitWidth + Tokens.padding.medium * 2 : Settings.barInnerWidth + Tokens.padding.small * 2
        implicitHeight: Settings.barHorizontal ? Settings.barInnerWidth + Tokens.padding.small * 2 : layout.implicitHeight + Tokens.padding.medium * 2

        radius: BarLayout.cornerRadius(Settings.barCorners, Settings.barHorizontal ? pill.implicitHeight : pill.implicitWidth)

        opacity: root.shouldShow ? 1 : 0
        // Behaviors go on the Translate's own x/y, not on `transform`
        // itself -- `transform` never actually changes identity here (it's
        // always the same Translate instance, just its x/y sub-properties
        // being reassigned), so a `Behavior on transform` never fires: QML
        // only animates a property when the property's OWN value changes,
        // and from the outside this list-valued property's value (the
        // Translate object reference) never does. Real bug this caused:
        // the auto-hide reveal/hide slide had no animation at all -- the
        // pill just snapped instantly to shown/hidden every time, the
        // literal "SNAP-to" behavior reported, and inconsistent with every
        // other bar style's Emphasized-eased motion.
        transform: Translate {
            y: Settings.barHorizontal && !root.shouldShow ? (Settings.barPositionBottom ? pill.height : -pill.height) : 0
            x: !Settings.barHorizontal && !root.shouldShow ? (Settings.barPositionRight ? pill.width : -pill.width) : 0

            Behavior on y {
                Anim { type: Anim.Emphasized }
            }
            Behavior on x {
                Anim { type: Anim.Emphasized }
            }
        }

        Behavior on opacity {
            Anim { type: Anim.Emphasized }
        }

        GridLayout {
            id: layout

            anchors.centerIn: parent
            flow: Settings.barHorizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
            rowSpacing: Tokens.spacing.small
            columnSpacing: Tokens.spacing.small

            Item {
                id: iconRow

                Layout.preferredWidth: iconGrid.implicitWidth
                Layout.preferredHeight: iconGrid.implicitHeight

                readonly property bool magnifies: Settings.dockMagnification && Settings.barHorizontal
                readonly property bool magnifying: magnifies && iconHover.hovered
                property Item hoveredEntry: null

                HoverHandler {
                    id: iconHover

                    onPointChanged: {
                        if (!iconHover.hovered)
                            return;
                        const local = iconRow.mapToItem(iconGrid, iconHover.point.position.x, iconHover.point.position.y);
                        iconRow.hoveredEntry = BarHit.nearestAt(iconGrid, local.x, local.y);
                    }
                    onHoveredChanged: {
                        if (!iconHover.hovered)
                            iconRow.hoveredEntry = null;
                    }
                }

                // Magnification already answers "which icon is the pointer
                // on" by growing it, and a highlight gliding under icons
                // that are themselves swelling reads as two effects
                // fighting -- so the dock shows one or the other, never
                // both. DockAppIcon's own StateLayer hover takes over
                // whenever this pill is off.
                HoverPill {
                    container: iconGrid
                    hoveredEntry: iconRow.magnifies ? null : iconRow.hoveredEntry
                    thickness: Settings.barHorizontal ? iconRow.height : iconRow.width
                }

                Grid {
                    id: iconGrid

                    flow: Settings.barHorizontal ? Grid.LeftToRight : Grid.TopToBottom
                    columns: Settings.barHorizontal ? root.dockItems.length : 1
                    rows: Settings.barHorizontal ? 1 : root.dockItems.length
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: root.dockItems

                        DockAppIcon {
                            id: dockIcon
                            property QtObject _sonarTarget: Loader {
                                active: Settings.sonarEnabled
                                sourceComponent: EchoTarget {
                                    target: dockIcon
                                    targetId: "core:dock/" + dockIcon.modelData.key
                                    label: dockIcon.modelData.name
                                }
                            }
                            required property var modelData
                            item: modelData
                            growOrigin: !Settings.barHorizontal ? Item.Center : (Settings.barPositionBottom ? Item.Bottom : Item.Top)
                            magnifyScale: iconRow.magnifying ? root.magnifyFalloff(dockIcon.x + dockIcon.width / 2) : 1
                            showHover: iconRow.magnifies
                        }
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: Settings.barHorizontal ? 20 : 1
                Layout.preferredHeight: Settings.barHorizontal ? 1 : 20
                Layout.alignment: Qt.AlignCenter
                visible: root.dockItems.length > 0
                color: Colours.signalStyle.hairline
                opacity: 0.6
            }

            DockWorkspaces {
                Layout.alignment: Qt.AlignCenter
                screen: root.screen
            }

            // Was entirely absent -- Dock silently dropped battery/
            // network/bluetooth/VPN visibility with no design rationale
            // documented anywhere (unlike Minimal, whose sparse icon set
            // is a deliberate, commented design choice). Hover popouts
            // for these icons don't work here yet (Dock has no
            // checkPopout/popout-positioning support at all -- a
            // separate, larger feature gap, already tracked in
            // docs/ROADMAP.md's Bar section), but the icons themselves
            // showing real status is the actual "silently lost
            // information" gap being fixed here.
            StatusIcons {
                Layout.alignment: Qt.AlignCenter
                screenState: root.screenState
            }

            Clock {
                Layout.alignment: Qt.AlignCenter
                screenState: root.screenState
            }

            Tray {
                Layout.alignment: Qt.AlignCenter
            }
        }

        // The screen-facing edge of the dock: the edge the window docks to
        // is the pill's start edge (top or left) or end edge (bottom or
        // right), so the line mirrors which one that is. The accent
        // segments span the focused app's icon, read out of the grid (the
        // Repeater keeps one child per dock item, in model order).
        SignalLine {
            id: dockSignalLine

            readonly property int idx: root.focusedDockIndex
            readonly property Item focusedIcon: idx >= 0 && idx < iconGrid.children.length ? iconGrid.children[idx] : null

            horizontal: Settings.barHorizontal
            edge: (Settings.barHorizontal ? !Settings.barPositionBottom : !Settings.barPositionRight) ? "start" : "end"
            level: "active"
            activeStart: {
                // Read icon.x/icon.y for the dependency: mapToItem alone
                // would leave this binding stale after a grid reflow.
                const icon = dockSignalLine.focusedIcon;
                if (!icon)
                    return 0;
                const x = icon.x, y = icon.y;
                const p = icon.mapToItem(pill, 0, 0);
                return Settings.barHorizontal ? p.x : p.y;
            }
            activeLength: {
                const icon = dockSignalLine.focusedIcon;
                if (!icon)
                    return 0;
                return Settings.barHorizontal ? icon.width : icon.height;
            }
        }
    }
}
