pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.services
import "modules/dashboard/concept" as Concept

// Offscreen render probe for the dashboard concept. Never maps a window
// on a live desktop: run it with QT_QPA_PLATFORM=offscreen, e.g.
//
//   QT_QPA_PLATFORM=offscreen \
//     CONCEPT_W=1920 CONCEPT_H=1080 CONCEPT_MS=14000 \
//     CONCEPT_OUT=/tmp/opencode/concept-1920x1080.png \
//     qs -p ConceptProbeRun.qml
//
// qs resolves `qs.*` imports only from the config root, so a wrapper
// copies this file to the root (as ConceptProbeRun.qml) before running
// and deletes it afterwards. See README.md in this directory.
//
// The run stages a throwaway HOME (CONCEPT_HOME, default
// /tmp/opencode/concept-home) holding COPIES of the operator's
// palette.json, settings.json and current-wallpaper, so Colours
// resolves the live dark palette and the weather leaf reads a neutral
// location, all without touching the real files. Set HOME to that
// directory for the run. CONCEPT_WALLPAPER points at the wallpaper
// copy drawn under the dim layer.
ShellRoot {
    id: probe

    readonly property int outW: Number(Quickshell.env("CONCEPT_W") || 1920)
    readonly property int outH: Number(Quickshell.env("CONCEPT_H") || 1080)
    // How long the surface stays open before the grab. The CPU ridge
    // grows one sample per service poll while it is open, so a longer
    // run draws more terrain.
    readonly property int runMs: Number(Quickshell.env("CONCEPT_MS") || 4000)
    // When set, the surface opens this many ms after startup, and the
    // grab lands CONCEPT_MOTION_MS into that open transition, showing
    // the entrance mid-flight.
    readonly property int openDelay: Number(Quickshell.env("CONCEPT_OPEN_DELAY") || 0)
    readonly property int motionMs: Number(Quickshell.env("CONCEPT_MOTION_MS") || 150)
    readonly property string outFile: Quickshell.env("CONCEPT_OUT") || "/tmp/opencode/concept.png"
    readonly property string wallpaper: Quickshell.env("CONCEPT_WALLPAPER") || "/tmp/opencode/concept-wallpaper.jpg"

    Component.onCompleted: console.log("PROBE size", probe.outW, "x", probe.outH, "run", probe.runMs, "ms", "open", probe.openDelay, "motion", probe.motionMs)

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

            // The wallpaper and the dim layer the real dashboard window
            // sits over, so translucency reads true in the render. The
            // real compositor also frosts this; a still render of the
            // dimmed wallpaper is the honest stand-in.
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

            Concept.ConceptPulse {
                id: surface

                anchors.fill: parent
                shown: probe.openDelay <= 0
            }

            // Seeded terrain: a gentle load waveform with one spike,
            // drawn at the exact capacity the surface holds, so the
            // render shows a filled ridge without minutes of polling
            // first. The readouts and the clock still show the live
            // service values.
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
                    surface.terrain.seed(cpu, net);
                    console.log("PROBE seeded terrain");
                }
            }

            // Flip the open state so the SurfaceReveal transition runs
            // for the mid-motion frame.
            Timer {
                id: openTimer

                interval: probe.openDelay
                running: probe.openDelay > 0

                onTriggered: {
                    surface.shown = true;
                    console.log("PROBE opened");
                }
            }

            Timer {
                interval: probe.openDelay > 0 ? probe.openDelay + probe.motionMs : probe.runMs
                running: true

                onTriggered: grabHost.grabToImage(result => {
                    console.log("PROBE saved", probe.outFile, result.saveToFile(probe.outFile));
                    Qt.quit();
                })
            }
        }
    }
}
