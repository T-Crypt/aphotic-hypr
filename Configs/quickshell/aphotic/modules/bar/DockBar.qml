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
            const match = grouped.find(g => (DesktopEntries.heuristicLookup(g.appClass)?.id ?? "") === id);
            items.push({
                key: id,
                name: entry.name,
                icon: Quickshell.iconPath(entry.icon, "application-x-executable"),
                running: !!match,
                windows: match?.windows ?? [],
                entry
            });
            if (match)
                seenClasses.add(match.appClass);
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
        implicitWidth: Settings.barVertical ? layout.implicitWidth + Tokens.padding.medium * 2 : Tokens.sizes.bar.innerWidth + Tokens.padding.small * 2
        implicitHeight: Settings.barVertical ? Tokens.sizes.bar.innerWidth + Tokens.padding.small * 2 : layout.implicitHeight + Tokens.padding.medium * 2

        radius: Tokens.rounding.full
        color: Colours.tPalette.m3surfaceContainer

        opacity: root.shouldShow ? 1 : 0
        transform: Translate {
            y: root.shouldShow ? 0 : (Settings.barPositionBottom ? pill.height : -pill.height)
            x: Settings.barVertical ? 0 : (Settings.barPositionRight ? pill.width : -pill.width)
        }

        Behavior on opacity {
            Anim { type: Anim.Emphasized }
        }
        Behavior on transform {
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
            flow: Settings.barVertical ? GridLayout.LeftToRight : GridLayout.TopToBottom
            rowSpacing: Tokens.spacing.small
            columnSpacing: Tokens.spacing.small

            Item {
                id: iconRow

                Layout.preferredWidth: iconGrid.implicitWidth
                Layout.preferredHeight: iconGrid.implicitHeight

                readonly property bool magnifying: Settings.dockMagnification && Settings.barVertical && iconHover.hovered

                HoverHandler {
                    id: iconHover
                }

                Grid {
                    id: iconGrid

                    flow: Settings.barVertical ? Grid.LeftToRight : Grid.TopToBottom
                    columns: Settings.barVertical ? root.dockItems.length : 1
                    rows: Settings.barVertical ? 1 : root.dockItems.length
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: root.dockItems

                        DockAppIcon {
                            id: dockIcon
                            required property var modelData
                            item: modelData
                            growOrigin: !Settings.barVertical ? Item.Center : (Settings.barPositionBottom ? Item.Bottom : Item.Top)
                            magnifyScale: iconRow.magnifying ? root.magnifyFalloff(dockIcon.x + dockIcon.width / 2) : 1
                        }
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: Settings.barVertical ? 20 : 1
                Layout.preferredHeight: Settings.barVertical ? 1 : 20
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
