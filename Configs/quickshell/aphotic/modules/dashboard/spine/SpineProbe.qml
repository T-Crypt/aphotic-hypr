pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.services
import "modules/dashboard/spine" as Spine

// Never maps a window on a live desktop: run with QT_QPA_PLATFORM=offscreen (Quickshell).
// qs resolves `qs.*` imports only from the config root, so a wrapper copies this file to the root.
ShellRoot {
    id: probe

    readonly property int outW: Number(Quickshell.env("SPINE_W") || 1920)
    readonly property int outH: Number(Quickshell.env("SPINE_H") || 1080)
    readonly property int grabAfterMs: Number(Quickshell.env("SPINE_MS") || 4000)
    readonly property int openAfterMs: Number(Quickshell.env("SPINE_OPEN_DELAY") || 0)
    readonly property int motionMs: Number(Quickshell.env("SPINE_MOTION_MS") || 150)
    readonly property string outFile: Quickshell.env("SPINE_OUT") || "/tmp/opencode/spine.png"
    readonly property string wallpaper: Quickshell.env("SPINE_WALLPAPER") || "/tmp/opencode/spine-wallpaper.jpg"

    Component.onCompleted: console.log("PROBE size", probe.outW, "x", probe.outH, "run", probe.grabAfterMs, "ms", "open", probe.openAfterMs, "motion", probe.motionMs)

    FloatingWindow {
        implicitWidth: probe.outW
        implicitHeight: probe.outH
        visible: true
        color: Colours.shadow

        SystemUsageWatch {}
        NetworkUsageWatch {}

        Item {
            id: grabHost

            anchors.fill: parent

            Image {
                anchors.fill: parent
                source: "file://" + probe.wallpaper
                fillMode: Image.PreserveAspectCrop
                asynchronous: false
            }

            Rectangle {
                anchors.fill: parent
                color: Colours.shadow
                opacity: 0.35
            }

            Spine.SpineSurface {
                id: surface

                anchors.fill: parent
                shown: probe.openAfterMs <= 0
            }

            Timer {
                interval: 200
                running: true

                onTriggered: {
                    const count = 48;
                    const cpu = [];
                    const net = [];
                    for (let i = 0; i < count; i++) {
                        const wave = 0.18 + 0.16 * Math.sin(i / 4.5) + 0.08 * Math.sin(i / 1.7);
                        const spike = (i >= 20 && i <= 23) ? 0.5 : 0;
                        cpu.push(Math.min(1, Math.max(0.04, wave + spike)));
                        net.push(Math.max(0, 1024 * (180 + 140 * Math.sin(i / 3.1) + (i >= 33 && i <= 35 ? 900 : 0))));
                    }
                    surface.terrain.seedForProbe(cpu, net);
                    console.log("PROBE seeded terrain");
                }
            }

            Timer {
                id: openTimer

                interval: probe.openAfterMs
                running: probe.openAfterMs > 0

                onTriggered: {
                    surface.shown = true;
                    console.log("PROBE opened");
                }
            }

            Timer {
                interval: probe.openAfterMs > 0 ? probe.openAfterMs + probe.motionMs : probe.grabAfterMs
                running: true

                onTriggered: grabHost.grabToImage(result => {
                    console.log("PROBE saved", probe.outFile, result.saveToFile(probe.outFile));
                    Qt.quit();
                })
            }
        }
    }
}
