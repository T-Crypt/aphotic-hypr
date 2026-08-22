// Picker.qml -- drag-to-select region, captured via grim (no native plugin needed)
pragma ComponentBehavior: Bound

import qs.components
import qs.config
import qs.services
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects

MouseArea {
    id: root

    required property var loader
    required property ShellScreen screen

    property bool onClient

    // Real caelestia snaps to the focused client's own border/rounding
    // (Hypr.options["general:border_size"]/["decoration:rounding"]) --
    // this repo's vendored Hypr.qml never exposed that live-options API,
    // so these are just reasonable fixed values instead.
    readonly property real realBorderWidth: 2
    readonly property real realRounding: 0

    property real ssx
    property real ssy

    property real sx: 0
    property real sy: 0
    property real ex: screen.width
    property real ey: screen.height

    property real rsx: Math.min(sx, ex)
    property real rsy: Math.min(sy, ey)
    property real sw: Math.abs(sx - ex)
    property real sh: Math.abs(sy - ey)

    property list<HyprlandToplevel> clients: {
        const mon = Hypr.monitorFor(screen);
        if (!mon)
            return [];

        const special = mon.lastIpcObject.specialWorkspace;
        const wsId = special.name ? special.id : mon.activeWorkspace.id;

        return Hypr.toplevels.values.filter(c => c.workspace?.id === wsId).sort((a, b) => {
            const ac = a.lastIpcObject;
            const bc = b.lastIpcObject;
            return (bc.pinned - ac.pinned) || ((bc.fullscreen !== 0) - (ac.fullscreen !== 0)) || (bc.floating - ac.floating);
        });
    }

    function checkClientRects(x: real, y: real): void {
        for (const client of clients) {
            if (!client)
                continue;

            const ipc = client.lastIpcObject;
            let cx = ipc.at[0] - screen.x;
            let cy = ipc.at[1] - screen.y;
            const cw = ipc.size[0];
            const ch = ipc.size[1];
            if (cx <= x && cy <= y && cx + cw >= x && cy + ch >= y) {
                onClient = true;
                sx = cx;
                sy = cy;
                ex = cx + cw;
                ey = cy + ch;
                break;
            }
        }
    }

    function save(): void {
        const gx = Math.round(root.screen.x + root.rsx);
        const gy = Math.round(root.screen.y + root.rsy);
        const gw = Math.round(root.sw);
        const gh = Math.round(root.sh);

        if (gw > 0 && gh > 0) {
            grimProc.outPath = `/tmp/aphotic-picker-${Date.now()}.png`;
            grimProc.clipboardOnly = root.loader.clipboardOnly;
            grimProc.command = ["grim", "-g", `${gx},${gy} ${gw}x${gh}`, grimProc.outPath];
            grimProc.running = true;
        }
        closeAnim.start();
    }

    Process {
        id: grimProc

        property string outPath
        property bool clipboardOnly

        onExited: exitCode => {
            if (exitCode !== 0)
                return;
            if (clipboardOnly) {
                Quickshell.execDetached(["sh", "-c", `wl-copy --type image/png < ${outPath}`]);
                Quickshell.execDetached(["notify-send", "-a", "aphotic", "-i", outPath, "Screenshot taken", "Screenshot copied to clipboard"]);
            } else {
                Quickshell.execDetached(["swappy", "-f", outPath]);
            }
        }
    }

    onClientsChanged: checkClientRects(mouseX, mouseY)

    anchors.fill: parent
    opacity: 0
    hoverEnabled: true
    cursorShape: Qt.CrossCursor

    Component.onCompleted: {
        // Break binding if frozen
        if (loader.freeze)
            clients = clients;

        opacity = 1;

        const c = clients[0];
        if (c) {
            const cx = c.lastIpcObject.at[0] - screen.x;
            const cy = c.lastIpcObject.at[1] - screen.y;
            onClient = true;
            sx = cx;
            sy = cy;
            ex = cx + c.lastIpcObject.size[0];
            ey = cy + c.lastIpcObject.size[1];
        } else {
            sx = screen.width / 2 - 100;
            sy = screen.height / 2 - 100;
            ex = screen.width / 2 + 100;
            ey = screen.height / 2 + 100;
        }
    }

    onPressed: event => {
        ssx = event.x;
        ssy = event.y;
    }

    onReleased: {
        if (closeAnim.running)
            return;

        if (root.loader.freeze) {
            save();
        } else {
            overlay.visible = border.visible = false;
            screencopy.visible = false;
            screencopy.active = true;
        }
    }

    onPositionChanged: event => {
        const x = event.x;
        const y = event.y;

        if (pressed) {
            onClient = false;
            sx = ssx;
            sy = ssy;
            ex = x;
            ey = y;
        } else {
            checkClientRects(x, y);
        }
    }

    focus: true
    Keys.onEscapePressed: closeAnim.start()

    SequentialAnimation {
        id: closeAnim

        PropertyAction {
            target: root.loader
            property: "closing"
            value: true
        }
        ParallelAnimation {
            Anim {
                target: root
                property: "opacity"
                to: 0
                duration: Tokens.anim.durations.large
            }
            ExAnim {
                target: root
                properties: "rsx,rsy"
                to: 0
            }
            ExAnim {
                target: root
                property: "sw"
                to: root.screen.width
            }
            ExAnim {
                target: root
                property: "sh"
                to: root.screen.height
            }
        }
        PropertyAction {
            target: root.loader
            property: "active"
            value: false
        }
    }

    Loader {
        id: screencopy

        anchors.fill: parent

        active: root.loader.freeze

        sourceComponent: ScreencopyView {
            captureSource: root.screen

            onHasContentChanged: {
                if (hasContent && !root.loader.freeze) {
                    overlay.visible = border.visible = true;
                    root.save();
                }
            }
        }
    }

    StyledRect {
        id: overlay

        anchors.fill: parent
        color: Colours.palette.m3secondary
        opacity: 0.3

        layer.enabled: true
        layer.effect: MultiEffect {
            maskSource: selectionWrapper
            maskEnabled: true
            maskInverted: true
            maskSpreadAtMin: 1
            maskThresholdMin: 0.5
        }
    }

    Item {
        id: selectionWrapper

        anchors.fill: parent
        layer.enabled: true
        visible: false

        Rectangle {
            id: selectionRect

            radius: root.realRounding
            x: root.rsx
            y: root.rsy
            implicitWidth: root.sw
            implicitHeight: root.sh
        }
    }

    Rectangle {
        id: border

        color: "transparent"
        radius: root.realRounding > 0 ? root.realRounding + root.realBorderWidth : 0
        border.width: root.realBorderWidth
        border.color: Colours.palette.m3primary

        x: selectionRect.x - root.realBorderWidth
        y: selectionRect.y - root.realBorderWidth
        implicitWidth: selectionRect.implicitWidth + root.realBorderWidth * 2
        implicitHeight: selectionRect.implicitHeight + root.realBorderWidth * 2

        Behavior on border.color {
            CAnim {}
        }
    }

    Behavior on opacity {
        Anim {
            duration: Tokens.anim.durations.large
        }
    }

    Behavior on rsx {
        enabled: !root.pressed

        ExAnim {}
    }

    Behavior on rsy {
        enabled: !root.pressed

        ExAnim {}
    }

    Behavior on sw {
        enabled: !root.pressed

        ExAnim {}
    }

    Behavior on sh {
        enabled: !root.pressed

        ExAnim {}
    }

    component ExAnim: Anim {
        duration: Tokens.anim.durations.expressiveDefaultSpatial
        easing: Tokens.anim.expressiveDefaultSpatial
    }
}
