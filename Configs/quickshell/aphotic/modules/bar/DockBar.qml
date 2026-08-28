pragma ComponentBehavior: Bound

import "components"
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState

    readonly property var dockItems: {
        const pinnedIds = Settings.dockPinnedApps;
        const grouped = WindowList.grouped();
        const items = [];
        const seenClasses = new Set();

        for (const id of pinnedIds) {
            const entry = DesktopEntries.applications.values.find(a => a.id === id);
            if (!entry)
                continue;
            // filter, not find -- an app can spawn windows under more
            // than one distinct wmClass (multi-process/Electron apps are
            // a common real case for DesktopEntries.heuristicLookup's
            // fuzzy matching), so more than one group can resolve to the
            // same pinned id. Merging all of them (and marking all as
            // seen below) avoids the same logical app showing up as two
            // separate dock icons, one per group.
            const matches = grouped.filter(g => (DesktopEntries.heuristicLookup(g.appClass)?.id ?? "") === id);
            items.push({
                key: id,
                name: entry.name,
                icon: Quickshell.iconPath(entry.icon, "application-x-executable"),
                running: matches.length > 0,
                windows: matches.flatMap(g => g.windows),
                entry
            });
            for (const m of matches)
                seenClasses.add(m.appClass);
        }

        for (const g of grouped) {
            if (seenClasses.has(g.appClass))
                continue;
            const entry = DesktopEntries.heuristicLookup(g.appClass);
            items.push({
                key: g.appClass,
                name: entry?.name ?? g.appClass,
                icon: g.windows[0]?.icon ?? Quickshell.iconPath(g.appClass, "application-x-executable"),
                running: true,
                windows: g.windows,
                entry: entry ?? null
            });
        }

        return items;
    }

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

    StyledRect {
        id: pill

        anchors.centerIn: parent
        implicitWidth: Settings.barHorizontal ? layout.implicitWidth + Tokens.padding.medium * 2 : Tokens.sizes.bar.innerWidth + Tokens.padding.small * 2
        implicitHeight: Settings.barHorizontal ? Tokens.sizes.bar.innerWidth + Tokens.padding.small * 2 : layout.implicitHeight + Tokens.padding.medium * 2

        radius: Tokens.rounding.full
        color: Colours.tPalette.m3surfaceContainer

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
            y: root.shouldShow ? 0 : (Settings.barPositionBottom ? pill.height : -pill.height)
            x: Settings.barHorizontal ? 0 : (Settings.barPositionRight ? pill.width : -pill.width)

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

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colours.palette.m3shadow
            shadowOpacity: 0.5
            shadowBlur: 0.5
            shadowVerticalOffset: 2
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
                color: Colours.palette.m3outlineVariant
                opacity: 0.6
            }

            RowLayout {
                Layout.alignment: Qt.AlignCenter
                spacing: Tokens.spacing.small

                DockWorkspaces {
                    screen: root.screen
                }

                Clock {
                    screenState: root.screenState
                }

                Tray {}
            }
        }
    }
}
